import Foundation
import Combine

struct ScanResult: Codable, Identifiable, Hashable {
    var id: String { archivo }
    let archivo: String
    let alertas: [Alerta]
    let movido_a: String?
    let copiado: Bool?
}

struct Alerta: Codable, Hashable {
    let tipo: String
    let detalle: String?
    let linea: Int?
    let muestra: String?
}

struct FileMetadata: Codable {
    let timestamp: String
    let original_path: String
    let modo: String?
    let reasons: [Alerta]
}

struct RestoreResult: Codable {
    let restaurado: Bool
    let origen: String
    let destino: String?
    let error: String?
}

class ScannerManager: ObservableObject {
    @Published var results: [ScanResult] = []
    @Published var isScanning = false
    @Published var quarantineActive = false
    @Published var copyInsteadOfMove = false
    @Published var customQuarantineDir: String? = nil
    @Published var hasCompletedScan = false
    @Published var errorMessage: String? = nil
    @Published var lastScannedPath: String = ""
    @Published var isRestoring = false

    /// Argumentos CLI para la acción de cuarentena, según el modo (copiar/mover) y
    /// el directorio raíz elegido (por defecto, la carpeta `quarantine/` junto al script).
    func quarantineArgs() -> [String] {
        var args = [copyInsteadOfMove ? "--copy" : "--move"]
        if let dir = customQuarantineDir, !dir.isEmpty {
            args.append("--move-to")
            args.append(dir)
        }
        return args
    }

    /// Aísla, de la salida cruda del subproceso, el JSON de resultados descartando
    /// las líneas de log tipo "[*] Escaneando..." que `scan_sensitive.py` mezcla en stdout.
    static func extractJSONPayload(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let jsonLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[*]") }
        return jsonLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ruta al motor Python. Se puede sobreescribir con la variable de entorno
    /// GUARDIANSS_SCAN_SCRIPT para no depender de esta ruta fija de desarrollo.
    private static var scriptPath: String {
        ProcessInfo.processInfo.environment["GUARDIANSS_SCAN_SCRIPT"]
            ?? "/Volumes/BACKUPS_PROYECTOS/__01.-Github_Repositories/secret-scanner-tool/scan_sensitive.py"
    }

    /// Busca el ejecutable de Python 3 más adecuado para evitar stubs bloqueantes de macOS.
    private static func resolvePythonExecutable() -> String {
        let candidates = [
            "/opt/homebrew/bin/python3", // Homebrew en Apple Silicon
            "/usr/local/bin/python3",    // Homebrew en Intel o instaladores oficiales
            "/usr/bin/python3"           // Fallback del sistema
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/usr/bin/python3"
    }

    func runScan(targetPath: String) {
        self.isScanning = true
        self.results = []
        self.hasCompletedScan = false
        self.errorMessage = nil
        self.lastScannedPath = targetPath

        let scriptPath = Self.scriptPath

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            self.isScanning = false
            self.hasCompletedScan = true
            self.errorMessage = "No se encontró el motor de escaneo en \(scriptPath). Define GUARDIANSS_SCAN_SCRIPT con la ruta correcta."
            return
        }

        let process = Process()
        let pipe = Pipe()
        let selectedPythonPath = Self.resolvePythonExecutable()
        process.executableURL = URL(fileURLWithPath: selectedPythonPath)

        var args = [scriptPath, targetPath, "--json-only"]
        if quarantineActive {
            args.append(contentsOf: quarantineArgs())
        }

        process.arguments = args
        process.standardOutput = pipe

        print("[DEBUG] Iniciando escaneo...")
        print("[DEBUG] Python ejecutable: \(selectedPythonPath)")
        print("[DEBUG] Script: \(scriptPath)")
        print("[DEBUG] Target: \(targetPath)")
        print("[DEBUG] Argumentos: \(args)")

        // Evitar el deadlock leyendo en un hilo de fondo (background thread) de forma asíncrona.
        // Esto previene que el buffer de la tubería (normalmente de 64KB) se llene y bloquee al proceso secundario.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                
                // readDataToEndOfFile() leerá continuamente hasta que el proceso finalice y cierre el pipe,
                // asegurando que el buffer no se sature.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                print("[DEBUG] Proceso finalizado. Código de salida: \(process.terminationStatus)")
                
                if let outputString = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Salida cruda del proceso: \(outputString)")
                    
                    let jsonString = Self.extractJSONPayload(from: outputString)

                    if !jsonString.isEmpty {
                        if let jsonData = jsonString.data(using: .utf8),
                           let decoded = try? JSONDecoder().decode([ScanResult].self, from: jsonData) {
                            print("[DEBUG] Decodificación JSON exitosa. Se encontraron \(decoded.count) resultados.")
                            DispatchQueue.main.async {
                                self.results = decoded
                                self.isScanning = false
                                self.hasCompletedScan = true
                            }
                            return
                        } else {
                            print("[DEBUG] Error de decodificación JSON en la sección extraída: \(jsonString)")
                            DispatchQueue.main.async {
                                self.isScanning = false
                                self.hasCompletedScan = true
                                self.errorMessage = "La respuesta del escáner no tiene un formato válido."
                            }
                            return
                        }
                    } else {
                        print("[DEBUG] La salida filtrada de JSON está vacía.")
                        DispatchQueue.main.async {
                            self.isScanning = false
                            self.hasCompletedScan = true
                            self.errorMessage = "El escáner no devolvió datos de resultados."
                        }
                        return
                    }
                } else {
                    print("[DEBUG] No se pudo convertir el búfer de salida del proceso a un String UTF-8.")
                    DispatchQueue.main.async {
                        self.isScanning = false
                        self.hasCompletedScan = true
                        self.errorMessage = "Error al leer los datos de salida del proceso."
                    }
                    return
                }
            } catch {
                print("[DEBUG] Falla al ejecutar el proceso: \(error)")
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.hasCompletedScan = true
                    self.errorMessage = "Error al iniciar el motor de escaneo de Python: \(error.localizedDescription)"
                }
            }
        }
    }

    func quarantineFile(archivo: String) {
        self.isScanning = true
        self.errorMessage = nil
        
        let scriptPath = Self.scriptPath

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            self.isScanning = false
            self.errorMessage = "No se encontró el motor de escaneo en \(scriptPath). Define GUARDIANSS_SCAN_SCRIPT con la ruta correcta."
            return
        }

        let process = Process()
        let pipe = Pipe()
        let selectedPythonPath = Self.resolvePythonExecutable()
        process.executableURL = URL(fileURLWithPath: selectedPythonPath)

        // Ejecutar el script para escanear y aislar (copiar o mover) solo este archivo
        let args = [scriptPath, archivo, "--json-only"] + quarantineArgs()
        process.arguments = args
        process.standardOutput = pipe
        
        print("[DEBUG] Moviendo archivo individual a cuarentena...")
        print("[DEBUG] Ejecutable: \(selectedPythonPath) \(args)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                print("[DEBUG] Proceso de cuarentena individual finalizado. Código de salida: \(process.terminationStatus)")
                
                if let outputString = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Salida cruda de cuarentena individual: \(outputString)")
                    
                    let jsonString = Self.extractJSONPayload(from: outputString)

                    if !jsonString.isEmpty,
                       let jsonData = jsonString.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([ScanResult].self, from: jsonData),
                       !decoded.isEmpty {

                        let newResult = decoded[0]
                        print("[DEBUG] Archivo movido con éxito. Nueva ruta: \(String(describing: newResult.movido_a))")
                        
                        DispatchQueue.main.async {
                            // Reemplazar el resultado antiguo en la lista por el nuevo resultado (que contiene movido_a)
                            if let index = self.results.firstIndex(where: { $0.archivo == archivo }) {
                                self.results[index] = newResult
                            }
                            self.isScanning = false
                        }
                        return
                    }
                }
                
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.errorMessage = "No se pudo completar el traslado del archivo a cuarentena."
                }
            } catch {
                print("[DEBUG] Falla de proceso individual: \(error)")
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.errorMessage = "Error de ejecución en cuarentena individual: \(error.localizedDescription)"
                }
            }
        }
    }

    func quarantineFiles(archivos: [String]) {
        self.isScanning = true
        self.errorMessage = nil

        // Ejecutar de forma secuencial en segundo plano para evitar colisiones de ejecución del proceso
        DispatchQueue.global(qos: .userInitiated).async {
            var fallos: [String] = []
            for archivo in archivos {
                if !self.quarantineFileSync(archivo: archivo) {
                    fallos.append((archivo as NSString).lastPathComponent)
                }
            }

            DispatchQueue.main.async {
                self.isScanning = false
                if !fallos.isEmpty {
                    self.errorMessage = "No se pudo poner en cuarentena: \(fallos.joined(separator: ", "))"
                }
            }
        }
    }

    @discardableResult
    private func quarantineFileSync(archivo: String) -> Bool {
        let scriptPath = Self.scriptPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("[DEBUG] Motor de escaneo no encontrado en \(scriptPath)")
            return false
        }

        let process = Process()
        let pipe = Pipe()
        let selectedPythonPath = Self.resolvePythonExecutable()
        process.executableURL = URL(fileURLWithPath: selectedPythonPath)
        let args = [scriptPath, archivo, "--json-only"] + quarantineArgs()
        process.arguments = args
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let outputString = String(data: data, encoding: .utf8) {
                let jsonString = Self.extractJSONPayload(from: outputString)

                if !jsonString.isEmpty,
                   let jsonData = jsonString.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([ScanResult].self, from: jsonData),
                   !decoded.isEmpty {

                    let newResult = decoded[0]
                    DispatchQueue.main.async {
                        if let index = self.results.firstIndex(where: { $0.archivo == archivo }) {
                            self.results[index] = newResult
                        }
                    }
                    return newResult.movido_a != nil
                }
            }
            return false
        } catch {
            print("[DEBUG] Falla en traslado síncrono: \(error)")
            return false
        }
    }

    /// Restaura un único archivo desde cuarentena a la ruta de origen guardada en su
    /// `.metadata.json` (la misma carpeta de la que se aisló al escanear o poner en
    /// cuarentena manualmente). Al terminar, elimina el resultado de la lista actual
    /// si la restauración tuvo éxito, ya que el archivo ha dejado de estar en cuarentena.
    func restoreFile(quarantinePath: String, completion: ((Bool, String?) -> Void)? = nil) {
        self.isRestoring = true
        self.errorMessage = nil

        let scriptPath = Self.scriptPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            self.isRestoring = false
            let mensaje = "No se encontró el motor de escaneo en \(scriptPath). Define GUARDIANSS_SCAN_SCRIPT con la ruta correcta."
            self.errorMessage = mensaje
            completion?(false, mensaje)
            return
        }

        let process = Process()
        let pipe = Pipe()
        let selectedPythonPath = Self.resolvePythonExecutable()
        process.executableURL = URL(fileURLWithPath: selectedPythonPath)
        process.arguments = [scriptPath, "--restore", quarantinePath, "--json-only"]
        process.standardOutput = pipe

        print("[DEBUG] Restaurando desde cuarentena: \(quarantinePath)")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if let outputString = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Salida cruda de restauración: \(outputString)")
                    let jsonString = Self.extractJSONPayload(from: outputString)

                    if !jsonString.isEmpty,
                       let jsonData = jsonString.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(RestoreResult.self, from: jsonData) {
                        DispatchQueue.main.async {
                            self.isRestoring = false
                            if decoded.restaurado {
                                self.results.removeAll { $0.movido_a == quarantinePath }
                                completion?(true, nil)
                            } else {
                                self.errorMessage = decoded.error ?? "No se pudo restaurar el archivo."
                                completion?(false, self.errorMessage)
                            }
                        }
                        return
                    }
                }

                DispatchQueue.main.async {
                    self.isRestoring = false
                    let mensaje = "No se pudo completar la restauración del archivo."
                    self.errorMessage = mensaje
                    completion?(false, mensaje)
                }
            } catch {
                print("[DEBUG] Falla al restaurar: \(error)")
                DispatchQueue.main.async {
                    self.isRestoring = false
                    let mensaje = "Error de ejecución al restaurar: \(error.localizedDescription)"
                    self.errorMessage = mensaje
                    completion?(false, mensaje)
                }
            }
        }
    }

    /// Restaura varios archivos en cuarentena de forma secuencial, cada uno a su
    /// carpeta de origen. Los que fallen (por ejemplo, porque ya existe un archivo
    /// en el destino) se reportan agrupados en `errorMessage`.
    func restoreFiles(quarantinePaths: [String]) {
        self.isRestoring = true
        self.errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var fallos: [String] = []
            var restaurados: [String] = []

            for path in quarantinePaths {
                if self.restoreFileSync(quarantinePath: path) {
                    restaurados.append(path)
                } else {
                    fallos.append((path as NSString).lastPathComponent)
                }
            }

            DispatchQueue.main.async {
                self.results.removeAll { restaurados.contains($0.movido_a ?? "") }
                self.isRestoring = false
                if !fallos.isEmpty {
                    self.errorMessage = "No se pudo restaurar: \(fallos.joined(separator: ", "))"
                }
            }
        }
    }

    @discardableResult
    private func restoreFileSync(quarantinePath: String) -> Bool {
        let scriptPath = Self.scriptPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("[DEBUG] Motor de escaneo no encontrado en \(scriptPath)")
            return false
        }

        let process = Process()
        let pipe = Pipe()
        let selectedPythonPath = Self.resolvePythonExecutable()
        process.executableURL = URL(fileURLWithPath: selectedPythonPath)
        process.arguments = [scriptPath, "--restore", quarantinePath, "--json-only"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let outputString = String(data: data, encoding: .utf8) {
                let jsonString = Self.extractJSONPayload(from: outputString)
                if !jsonString.isEmpty,
                   let jsonData = jsonString.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(RestoreResult.self, from: jsonData) {
                    return decoded.restaurado
                }
            }
            return false
        } catch {
            print("[DEBUG] Falla en restauración síncrona: \(error)")
            return false
        }
    }
}
