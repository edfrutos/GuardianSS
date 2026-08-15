import Foundation
import AppKit

/// Carpeta donde vive (o debe vivir) el bundle de la app, elegida por el
/// usuario en el primer lanzamiento y persistida en UserDefaults. Tanto la
/// configuración inicial como el auto-actualizador (`UpdateChecker`) la usan
/// como destino estable, en vez de fiarse de dónde se esté ejecutando en
/// cada momento (podría ser DerivedData, Descargas, un DMG montado...).
enum InstallLocation {
    static let defaultDirectory = "/Applications"
    private static let directoryKey = "GuardianSS.installDirectory"
    private static let firstLaunchDoneKey = "GuardianSS.hasCompletedInstallSetup"

    static var directory: String {
        get { UserDefaults.standard.string(forKey: directoryKey) ?? defaultDirectory }
        set { UserDefaults.standard.set(newValue, forKey: directoryKey) }
    }

    static var hasCompletedFirstLaunchSetup: Bool {
        get { UserDefaults.standard.bool(forKey: firstLaunchDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: firstLaunchDoneKey) }
    }

    static var appPath: String {
        "\(directory)/\(Bundle.main.bundleURL.lastPathComponent)"
    }
}

/// Sustituye el bundle en ejecución por otro y relanza. Se apoya en un script
/// auxiliar independiente porque una app no puede sustituir de forma fiable
/// su propio bundle mientras sigue corriendo: el script espera a que este
/// proceso termine, hace el intercambio, y se autoborra. `move: false` usa
/// `cp -R` en vez de `mv`, necesario cuando el origen puede estar en un
/// volumen de solo lectura (p. ej. un DMG montado en el primer lanzamiento).
enum RelaunchHelper {
    static func swapAndRelaunch(from sourcePath: String, to targetPath: String, move: Bool) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardianss-swap-\(UUID().uuidString).sh")
        let copyOrMove = move ? "mv" : "cp -R"
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(targetPath)"
        \(copyOrMove) "\(sourcePath)" "\(targetPath)"
        xattr -cr "\(targetPath)"
        open "\(targetPath)"
        rm -f "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        // Deliberadamente sin esperar: el script debe sobrevivir a que esta
        // app termine, para poder sustituir su propio bundle y relanzarla.
        try process.run()

        NSApplication.shared.terminate(nil)
    }
}

/// Gestiona el primer lanzamiento: pregunta dónde debe vivir la app de forma
/// estable (por defecto `/Applications`) para que las futuras actualizaciones
/// automáticas tengan siempre el mismo destino, con opción de elegir otra
/// carpeta ahí mismo o más tarde desde el ajuste del sidebar.
final class InstallSetupManager: ObservableObject {
    @Published var directory = InstallLocation.directory
    @Published var showFirstLaunchPrompt = false
    @Published var errorMessage: String?

    /// En builds de Debug (ejecutadas desde Xcode/DerivedData durante
    /// desarrollo) no se ofrece relocalizar nada — solo aplica a releases.
    func checkFirstLaunch() {
        #if DEBUG
        return
        #else
        guard !InstallLocation.hasCompletedFirstLaunchSetup else { return }
        showFirstLaunchPrompt = true
        #endif
    }

    func confirmDefaultDestination() {
        confirm(directory: InstallLocation.defaultDirectory)
    }

    func chooseCustomDirectoryAndConfirm() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.message = "Elige la carpeta donde debe vivir GuardianSS."

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.confirm(directory: url.path)
        }
    }

    /// Solo relevante en el primer lanzamiento: pospone la decisión sin
    /// marcarla como completada, así que se vuelve a preguntar la próxima vez.
    func deferFirstLaunchPrompt() {
        showFirstLaunchPrompt = false
    }

    private func confirm(directory newDirectory: String) {
        InstallLocation.directory = newDirectory
        InstallLocation.hasCompletedFirstLaunchSetup = true
        directory = newDirectory
        showFirstLaunchPrompt = false

        let target = InstallLocation.appPath
        guard target != Bundle.main.bundlePath else { return } // ya está donde debe
        do {
            try RelaunchHelper.swapAndRelaunch(from: Bundle.main.bundlePath, to: target, move: false)
        } catch {
            errorMessage = "No se pudo mover la app a la carpeta elegida."
        }
    }
}
