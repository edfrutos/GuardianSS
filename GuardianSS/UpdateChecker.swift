import Foundation
import Combine

/// Respuesta de `GET /repos/{repo}/releases/latest`.
private struct GitHubReleaseInfo: Decodable {
    let tagName: String
    let htmlURL: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
    }
}

/// Comprueba si hay una release más reciente en GitHub que la versión instalada.
///
/// El repositorio es público, así que la API de GitHub se consulta de forma anónima
/// por HTTP; no hace falta token ni depender de que `gh` CLI esté instalado y logueado
/// en la máquina que ejecuta la app.
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
    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isVersion(latest, newerThan: currentVersion)
    }

    /// - Parameter silent: `false` para comprobaciones lanzadas explícitamente por el usuario
    ///   (menú/botón), que rellenan `manualCheckNotice` con el resultado aunque no haya
    ///   actualización. `true` (por defecto) para la comprobación automática al abrir la app.
    func check(silent: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        manualCheckNotice = nil

        var request = URLRequest(url: Self.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GuardianSS-UpdateChecker", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isChecking = false

                if let error = error {
                    let message = "Error al comprobar actualizaciones: \(error.localizedDescription)"
                    self.errorMessage = message
                    if !silent { self.manualCheckNotice = message; self.showManualCheckAlert = true }
                    return
                }

                guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
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
                self.releaseURL = URL(string: info.htmlURL)

                if !silent && !self.updateAvailable {
                    self.manualCheckNotice = "Ya tienes la última versión (\(self.currentVersion))."
                    self.showManualCheckAlert = true
                }
            }
        }.resume()
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
