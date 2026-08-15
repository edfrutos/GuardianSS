import Foundation
import Combine
import AppKit

/// Respuesta de `GET /repos/{repo}/releases/latest`.
private struct GitHubReleaseInfo: Decodable {
    let tagName: String
    let htmlURL: String
    let name: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
        case assets
    }
}

/// Progreso de la descarga, verificación e instalación de una actualización ya
/// detectada. La descarga y verificación arrancan solas en cuanto `check()`
/// encuentra una versión más reciente; `.readyToInstall` requiere que el
/// usuario confirme desde la UI (`installAndRelaunch()`), ya que sustituye la
/// app en ejecución y la cierra.
enum UpdateInstallStage: Equatable {
    case idle
    case downloading(progress: Double)
    case verifying
    case readyToInstall
    case failed(String)
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
    /// Estado de la descarga/verificación/instalación de la actualización detectada.
    @Published var installStage: UpdateInstallStage = .idle
    /// `true` tras pulsar "Más tarde" en el aviso de instalación lista; oculta el
    /// banner sin cancelar la actualización ya descargada y verificada.
    @Published var installBannerDismissed = false

    private static let repo = "edfrutos/GuardianSS"
    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    /// Team ID de firma esperado (`DEVELOPMENT_TEAM` en project.pbxproj). Una
    /// actualización descargada que no esté firmada por este equipo se rechaza.
    private static let expectedTeamID = "V29BTBRY6G"
    private static let appName = "GuardianSS"

    private var dmgDownloadURL: URL?
    private var stagedAppURL: URL?
    private var progressObservation: NSKeyValueObservation?

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
                self.dmgDownloadURL = info.assets
                    .first { $0.name.hasSuffix(".dmg") }
                    .flatMap { URL(string: $0.browserDownloadURL) }

                if !silent && !self.updateAvailable {
                    self.manualCheckNotice = "Ya tienes la última versión (\(self.currentVersion))."
                    self.showManualCheckAlert = true
                }

                if self.updateAvailable {
                    self.beginDownloadIfNeeded()
                }
            }
        }.resume()
    }

    // MARK: - Descarga, verificación e instalación

    /// Arranca la descarga en segundo plano si no hay ya una descarga, verificación
    /// o instalación lista en curso. Se llama sola al detectar una versión nueva;
    /// tras un fallo, la siguiente comprobación (automática o manual) reintenta.
    private func beginDownloadIfNeeded() {
        switch installStage {
        case .idle, .failed:
            break
        default:
            return
        }
        guard let dmgURL = dmgDownloadURL else {
            installStage = .failed("La release no tiene un DMG adjunto para descargar.")
            return
        }

        installBannerDismissed = false
        installStage = .downloading(progress: 0)

        let task = URLSession.shared.downloadTask(with: dmgURL) { [weak self] tempURL, _, error in
            guard let self else { return }
            guard let tempURL, error == nil else {
                DispatchQueue.main.async { self.installStage = .failed("No se pudo descargar la actualización.") }
                return
            }

            let dmgDest = FileManager.default.temporaryDirectory
                .appendingPathComponent("GuardianSS-update-\(UUID().uuidString).dmg")
            do {
                try FileManager.default.moveItem(at: tempURL, to: dmgDest)
            } catch {
                DispatchQueue.main.async { self.installStage = .failed("No se pudo guardar la actualización descargada.") }
                return
            }
            self.verifyAndStage(dmgPath: dmgDest)
        }

        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard case .downloading = self?.installStage else { return }
                self?.installStage = .downloading(progress: progress.fractionCompleted)
            }
        }
        task.resume()
    }

    /// Monta el DMG descargado, comprueba que la app dentro está firmada y notarizada
    /// (`codesign --verify`, `spctl --assess`) y que el equipo de firma coincide con
    /// `expectedTeamID`, y si todo es correcto la copia a un lugar temporal lista para
    /// instalar. Corre fuera del hilo principal porque encadena varios `Process`
    /// síncronos (montar, verificar, copiar, desmontar).
    private func verifyAndStage(dmgPath: URL) {
        DispatchQueue.main.async { self.installStage = .verifying }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let mountPoint = FileManager.default.temporaryDirectory
                .appendingPathComponent("GuardianSS-mount-\(UUID().uuidString)")
            var didMount = false
            defer {
                if didMount {
                    _ = self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
                }
                try? FileManager.default.removeItem(at: mountPoint)
                try? FileManager.default.removeItem(at: dmgPath)
            }

            do {
                try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            } catch {
                self.fail("No se pudo preparar la verificación de la actualización.")
                return
            }

            guard self.run("/usr/bin/hdiutil", [
                "attach", dmgPath.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mountPoint.path,
            ]) else {
                self.fail("No se pudo montar la actualización descargada.")
                return
            }
            didMount = true

            let appPath = mountPoint.appendingPathComponent("\(Self.appName).app")
            guard FileManager.default.fileExists(atPath: appPath.path) else {
                self.fail("La actualización descargada no contiene \(Self.appName).app.")
                return
            }

            guard self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appPath.path]) else {
                self.fail("La firma de la actualización descargada no es válida.")
                return
            }

            guard self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", appPath.path]) else {
                self.fail("La actualización descargada no supera la comprobación de Gatekeeper.")
                return
            }

            guard let teamID = self.signingTeamIdentifier(of: appPath), teamID == Self.expectedTeamID else {
                self.fail("La actualización descargada no está firmada por el equipo de desarrollo esperado.")
                return
            }

            let stagedPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(Self.appName)-staged-\(UUID().uuidString).app")
            do {
                try FileManager.default.copyItem(at: appPath, to: stagedPath)
            } catch {
                self.fail("No se pudo preparar la actualización verificada.")
                return
            }

            DispatchQueue.main.async {
                self.stagedAppURL = stagedPath
                self.installStage = .readyToInstall
            }
        }
    }

    /// Sustituye la app en ejecución por la actualización ya verificada y la
    /// relanza. Se apoya en un script auxiliar independiente porque una app no
    /// puede sustituir de forma fiable su propio bundle mientras sigue corriendo;
    /// el script espera a que este proceso termine, hace el intercambio, y se
    /// autoborra.
    func installAndRelaunch() {
        guard case .readyToInstall = installStage, let stagedAppURL else { return }

        let targetPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardianss-update-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(targetPath)"
        mv "\(stagedAppURL.path)" "\(targetPath)"
        xattr -cr "\(targetPath)"
        open "\(targetPath)"
        rm -f "$0"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            installStage = .failed("No se pudo preparar el instalador de la actualización.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        // Deliberadamente sin esperar: el script debe sobrevivir a que esta app
        // termine, para poder sustituir su propio bundle y relanzarla.
        try? process.run()

        NSApplication.shared.terminate(nil)
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { self.installStage = .failed(message) }
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func signingTeamIdentifier(of appPath: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", appPath.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { return nil }
            for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
            return nil
        } catch {
            return nil
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
