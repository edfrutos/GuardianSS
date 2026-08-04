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

    func check() {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil

        guard let ghPath = Self.resolveGHExecutable() else {
            isChecking = false
            errorMessage = "No se encontró 'gh' (GitHub CLI). Instálalo con Homebrew para comprobar actualizaciones."
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
                        self.errorMessage = "No se pudo comprobar actualizaciones (¿hay alguna release publicada en el repositorio?)."
                        return
                    }
                    guard let info = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else {
                        self.errorMessage = "Respuesta de GitHub con formato inesperado."
                        return
                    }
                    self.latestVersion = info.tagName.hasPrefix("v") ? String(info.tagName.dropFirst()) : info.tagName
                    self.releaseURL = URL(string: info.url)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isChecking = false
                    self.errorMessage = "Error al ejecutar 'gh': \(error.localizedDescription)"
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
