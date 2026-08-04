import Foundation
import Combine

/// Respuesta de `gh release view --json tagName,url,name`.
private struct GitHubReleaseInfo: Decodable {
    let tagName: String
    let url: String
    let name: String?
}

/// Comprueba si hay una release más reciente en GitHub que la versión instalada.
///
/// El repositorio es privado, así que la API de GitHub no se puede consultar de forma
/// anónima por HTTP; en vez de embeber un token en el binario, se invoca `gh` CLI, que
/// reutiliza la sesión ya autenticada en esta máquina (requiere `gh` instalado y logueado).
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var isChecking = false
    @Published var errorMessage: String?
    /// Mensaje a mostrar en una alerta tras una comprobación manual (no silenciosa) que no
    /// encontró actualización, o que falló. En comprobaciones automáticas al abrir se deja
    /// a nil para no molestar si todo está en orden.
    @Published var manualCheckNotice: String?
    /// Fuente de verdad para `.alert(isPresented:)`, enlazada directamente desde la vista
    /// vía `$updateChecker.showManualCheckAlert` (evita derivarla con `.onChange`, frágil
    /// cuando el valor observado es una propiedad de un ObservableObject externo).
    @Published var showManualCheckAlert = false

    private static let repo = "edfrutos/GuardianSS"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isVersion(latest, newerThan: currentVersion)
    }

    private static func resolveGHExecutable() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// - Parameter silent: `false` para comprobaciones lanzadas explícitamente por el usuario
    ///   (menú/botón), que rellenan `manualCheckNotice` con el resultado aunque no haya
    ///   actualización. `true` (por defecto) para la comprobación automática al abrir la app.
    func check(silent: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        manualCheckNotice = nil

        guard let ghPath = Self.resolveGHExecutable() else {
            isChecking = false
            let message = "No se encontró 'gh' (GitHub CLI). Instálalo con Homebrew para comprobar actualizaciones."
            errorMessage = message
            if !silent { manualCheckNotice = message; showManualCheckAlert = true }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["release", "view", "--repo", Self.repo, "--json", "tagName,url,name"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        DispatchQueue.global(qos: .utility).async {
            do {
                try process.run()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    self.isChecking = false

                    guard process.terminationStatus == 0 else {
                        let message = "No se pudo comprobar actualizaciones (¿hay alguna release publicada en el repositorio?)."
                        self.errorMessage = message
                        if !silent { self.manualCheckNotice = message; self.showManualCheckAlert = true }
                        return
                    }
                    guard let info = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else {
                        let message = "Respuesta de GitHub con formato inesperado."
                        self.errorMessage = message
                        if !silent { self.manualCheckNotice = message; self.showManualCheckAlert = true }
                        return
                    }

                    self.latestVersion = info.tagName.hasPrefix("v") ? String(info.tagName.dropFirst()) : info.tagName
                    self.releaseURL = URL(string: info.url)

                    if !silent && !self.updateAvailable {
                        self.manualCheckNotice = "Ya tienes la última versión (\(self.currentVersion))."
                        self.showManualCheckAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isChecking = false
                    let message = "Error al ejecutar 'gh': \(error.localizedDescription)"
                    self.errorMessage = message
                    if !silent { self.manualCheckNotice = message; self.showManualCheckAlert = true }
                }
            }
        }
    }

    /// Compara versiones "X.Y.Z" numéricamente (sin asumir el mismo número de componentes).
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").map { Int($0) ?? 0 }
        let partsB = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }
}
