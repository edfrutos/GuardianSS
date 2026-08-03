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

class ScannerManager: ObservableObject {
    @Published var results: [ScanResult] = []
    @Published var isScanning = false
    @Published var quarantineActive = false
    @Published var copyInsteadOfMove = false
    @Published var customQuarantineDir: String? = nil
    @Published var hasCompletedScan = false
    @Published var errorMessage: String? = nil
    @Published var lastScannedPath: String = ""

    /// Argumentos CLI para la acción de cuarentena, según el modo (copiar/mover) y
    /// el directorio raíz elegido (por defecto, la carpeta `quarantine/` junto al script).
    private func quarantineArgs() -> [String] {
        var args = [copyInsteadOfMove ? "--copy" : "--move"]
        if let dir = customQuarantineDir, !dir.isEmpty {
            args.append("--move-to")
            args.append(dir)
        }
        return args
    }

    /// Ruta al motor Python. Se puede sobreescribir con la variable de entorno
    /// GUARDIANSS_SCAN_SCRIPT para no depender de esta ruta fija de desarrollo.
    private static var scriptPath: String {
        ProcessInfo.processInfo.environment["GUARDIANSS_SCAN_SCRIPT"]
            ?? "/Volumes/BACKUPS_PROYECTOS/secret-scanner-tool/scan_sensitive.py"
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
                    
                    // Filtrar las líneas de logs (como "[*] Escaneando...") para dejar solo el JSON
                    let lines = outputString.components(separatedBy: .newlines)
                    let jsonLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[*]") }
                    let jsonString = jsonLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    
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
                    
                    let lines = outputString.components(separatedBy: .newlines)
                    let jsonLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[*]") }
                    let jsonString = jsonLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    
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
            for archivo in archivos {
                self.quarantineFileSync(archivo: archivo)
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
            }
        }
    }

    private func quarantineFileSync(archivo: String) {
        let scriptPath = Self.scriptPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("[DEBUG] Motor de escaneo no encontrado en \(scriptPath)")
            return
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
                let lines = outputString.components(separatedBy: .newlines)
                let jsonLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[*]") }
                let jsonString = jsonLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                
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
                }
            }
        } catch {
            print("[DEBUG] Falla en traslado síncrono: \(error)")
        }
    }
}
