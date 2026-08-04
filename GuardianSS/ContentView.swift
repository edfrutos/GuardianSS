import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var scanner = ScannerManager()
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var selectedResults: Set<String> = [] // Múltiple selección de IDs (Rutas de archivos)
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar { toolbarContent }
        .task { updateChecker.check() }
        .alert("Actualizaciones", isPresented: $updateChecker.showManualCheckAlert) {
            Button("OK") { updateChecker.manualCheckNotice = nil }
        } message: {
            Text(updateChecker.manualCheckNotice ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    // MARK: - Arrastrar y soltar carpeta

    private var dropOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            RoundedRectangle(cornerRadius: GuardianTheme.radiusLarge, style: .continuous)
                .strokeBorder(GuardianTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .padding(20)
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(GuardianTheme.accent)
                Text("Suelta la carpeta para escanearla")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GuardianTheme.radiusMedium, style: .continuous))
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            switch item {
            case let data as Data:
                url = URL(dataRepresentation: data, relativeTo: nil)
            case let directURL as URL:
                url = directURL
            case let nsurl as NSURL:
                url = nsurl as URL
            default:
                url = nil
            }
            guard let droppedURL = url else { return }

            DispatchQueue.main.async {
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: droppedURL.path, isDirectory: &isDirectory)
                guard exists, isDirectory.boolValue else {
                    scanner.errorMessage = "Solo se pueden analizar carpetas. Arrastra un directorio, no un archivo suelto."
                    scanner.hasCompletedScan = true
                    return
                }
                withAnimation(GuardianTheme.spring) {
                    scanner.runScan(targetPath: droppedURL.path)
                }
            }
        }
        return true
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if updateChecker.updateAvailable {
                UpdateBanner(checker: updateChecker)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            if scanner.results.isEmpty {
                emptySidebarState
            } else {
                List(scanner.results, selection: $selectedResults) { result in
                    ResultRow(result: result)
                        .padding(.vertical, 3)
                }
                .listStyle(.sidebar)
                .animation(GuardianTheme.spring, value: scanner.results)
            }
        }
        .animation(GuardianTheme.spring, value: updateChecker.updateAvailable)
        .navigationTitle("Resultados")
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        .safeAreaInset(edge: .bottom) {
            QuarantineSettingsCard(scanner: scanner)
                .padding(12)
                .background(.bar)
        }
    }

    private var emptySidebarState: some View {
        VStack(spacing: 10) {
            Spacer()
            GlowBadge(
                systemImage: scanner.hasCompletedScan ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                tint: scanner.hasCompletedScan ? GuardianTheme.success : .secondary,
                size: 60
            )
            Text(scanner.hasCompletedScan ? "Sin Amenazas" : "Listo")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(scanner.hasCompletedScan ? "La carpeta analizada está libre de secretos expuestos." : "Inicia un escaneo para buscar credenciales en riesgo.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if scanner.isScanning {
            VStack(spacing: 20) {
                GlowBadge(systemImage: "magnifyingglass", tint: GuardianTheme.accent, size: 84)
                    .overlay(
                        Circle()
                            .stroke(GuardianTheme.accent.opacity(0.5), lineWidth: 2)
                            .frame(width: 100, height: 100)
                            .scaleEffect(1.15)
                            .opacity(0.6)
                    )
                Text("Analizando directorio en busca de secretos...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .guardianAppear()
        } else if let error = scanner.errorMessage {
            ErrorView(message: error, onRetry: selectFolderAndScan)
                .guardianAppear()
        } else if selectedResults.count > 1 {
            MultiDetailView(selectedPaths: selectedResults, scanner: scanner)
                .guardianAppear()
        } else if selectedResults.count == 1,
                  let selectedID = selectedResults.first,
                  let result = scanner.results.first(where: { $0.archivo == selectedID }) {
            DetailView(result: result, scanner: scanner)
                .guardianAppear()
        } else if scanner.hasCompletedScan {
            if scanner.results.isEmpty {
                CleanView(path: scanner.lastScannedPath, onScanAgain: selectFolderAndScan)
                    .guardianAppear()
            } else {
                ThreatsFoundView(count: scanner.results.count)
                    .guardianAppear()
            }
        } else {
            WelcomeView(onScan: selectFolderAndScan)
                .guardianAppear()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button(action: { updateChecker.check(silent: false) }) {
                if updateChecker.isChecking {
                    ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(updateChecker.isChecking)
            .help("Buscar actualizaciones")
        }

        ToolbarItem(placement: .primaryAction) {
            if scanner.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                    Text("Escaneando...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: selectFolderAndScan) {
                    Label("Escanear Carpeta", systemImage: "folder.badge.plus")
                }
                .help("Selecciona una carpeta para iniciar la búsqueda de secretos")
            }
        }
    }

    func selectFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        // begin(completionHandler:) es asíncrono y no bloquea el hilo principal,
        // evitando bloqueos de interfaz y cuelgues si el diálogo queda abierto.
        panel.begin { response in
            if response == .OK, let url = panel.url {
                withAnimation(GuardianTheme.spring) {
                    scanner.runScan(targetPath: url.path)
                }
            }
        }
    }
}

// MARK: - Fila de resultado en el sidebar

struct ResultRow: View {
    let result: ScanResult

    private var isQuarantined: Bool { result.movido_a != nil }
    private var statusTint: Color { isQuarantined ? GuardianTheme.success : GuardianTheme.danger }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusTint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: result.archivo).lastPathComponent)
                    .fontWeight(.medium)
                Text(result.archivo)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            if !result.alertas.isEmpty {
                Text("\(result.alertas.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Image(systemName: isQuarantined ? (result.copiado == true ? "doc.on.doc.fill" : "shield.fill") : "lock.open.fill")
                .foregroundColor(statusTint)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Aviso de actualización disponible

struct UpdateBanner: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(GuardianTheme.glow)

            VStack(alignment: .leading, spacing: 1) {
                Text("Versión \(checker.latestVersion ?? "") disponible")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Tienes la \(checker.currentVersion) instalada")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            Button("Ver") {
                if let url = checker.releaseURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(GuardianTheme.glow)
            .controlSize(.small)
        }
        .guardianCard(padding: 10, radius: GuardianTheme.radiusSmall)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Ajustes de cuarentena (tarjeta inferior del sidebar)

struct QuarantineSettingsCard: View {
    @ObservedObject var scanner: ScannerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconLabelRow(
                icon: "shield.lefthalf.filled",
                title: "Cuarentena al escanear",
                tint: GuardianTheme.accent
            ) {
                Toggle("", isOn: $scanner.quarantineActive.animation(GuardianTheme.spring))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            Divider().opacity(0.5)

            // Se aplican tanto al aislamiento automático al escanear como al botón
            // manual "Aislar archivo" / "Copiar a cuarentena" del detalle de archivo.
            IconLabelRow(
                icon: "doc.on.doc",
                title: "Copiar en vez de mover",
                subtitle: scanner.copyInsteadOfMove ? "El original permanece en su sitio" : "El original se elimina al aislar",
                tint: GuardianTheme.glow
            ) {
                Toggle("", isOn: $scanner.copyInsteadOfMove)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            QuarantineDirectoryRow(customDir: $scanner.customQuarantineDir)
        }
        .guardianCard()
        .animation(GuardianTheme.spring, value: scanner.quarantineActive)
    }
}

struct QuarantineDirectoryRow: View {
    @Binding var customDir: String?

    var body: some View {
        IconLabelRow(
            icon: "folder",
            title: "Directorio de cuarentena",
            subtitle: customDir ?? "Por defecto (quarantine/)",
            tint: .secondary
        ) {
            HStack(spacing: 2) {
                Button(action: chooseFolder) {
                    Image(systemName: "folder.badge.gearshape")
                }
                .buttonStyle(.borderless)
                .help("Elegir directorio raíz de cuarentena")

                if customDir != nil {
                    Button(action: { withAnimation(GuardianTheme.spring) { customDir = nil } }) {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Volver al directorio por defecto")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                withAnimation(GuardianTheme.spring) { customDir = url.path }
            }
        }
    }
}

// MARK: - Detalle de archivo

struct DetailView: View {
    let result: ScanResult
    @ObservedObject var scanner: ScannerManager
    @State private var metadata: FileMetadata?

    private var isQuarantined: Bool { result.movido_a != nil }
    private var statusTint: Color { isQuarantined ? GuardianTheme.success : GuardianTheme.danger }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let movido = result.movido_a {
                        quarantineInfoBox(path: movido)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Alertas de Seguridad")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        ForEach(result.alertas, id: \.self) { alerta in
                            AlertCard(alerta: alerta)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(
            LinearGradient(
                colors: [statusTint.opacity(0.10), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        )
    }

    var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: isQuarantined ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: result.archivo).lastPathComponent)
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text(result.archivo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()

            HStack(spacing: 12) {
                if !isQuarantined {
                    Button(action: {
                        withAnimation(GuardianTheme.spring) {
                            scanner.quarantineFile(archivo: result.archivo)
                        }
                    }) {
                        Label(scanner.copyInsteadOfMove ? "Copiar a cuarentena" : "Aislar archivo", systemImage: "shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GuardianTheme.success)
                }

                SeverityChip(
                    text: isQuarantined ? (result.copiado == true ? "Copiado" : "Aislado") : "Comprometido",
                    color: statusTint
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    func quarantineInfoBox(path: String) -> some View {
        let esCopia = result.copiado == true
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .foregroundColor(GuardianTheme.success)
                    .font(.title3)
                Text(esCopia ? "ESTADO: COPIADO A CUARENTENA" : "ESTADO: PROTEGIDO EN CUARENTENA")
                    .font(.headline)
                    .foregroundColor(GuardianTheme.success)
                    .fontWeight(.bold)
            }

            if esCopia {
                Text("El archivo original permanece en su ubicación; esta es una copia.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
            }

            if let meta = metadata {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text("Fecha Acción:").bold()
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Text(formatDate(meta.timestamp))
                            .font(.caption)
                    }
                    HStack(alignment: .top) {
                        Text("Origen:").bold()
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Text(meta.original_path)
                            .font(.caption)
                            .italic()
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianTheme.success.opacity(0.08))
        .cornerRadius(GuardianTheme.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: GuardianTheme.radiusMedium)
                .stroke(GuardianTheme.success.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .onAppear(perform: loadMetadata)
    }

    func loadMetadata() {
        guard let movido = result.movido_a else { return }
        let metaPath = movido + ".metadata.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
           let decoded = try? JSONDecoder().decode(FileMetadata.self, from: data) {
            self.metadata = decoded
        }
    }

    func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return iso
    }
}

struct AlertCard: View {
    let alerta: Alerta

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(GuardianTheme.danger)

                Text(alerta.tipo)
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                if let linea = alerta.linea {
                    SeverityChip(text: "Línea \(linea)", color: GuardianTheme.danger)
                }
            }

            if let detalle = alerta.detalle, !detalle.isEmpty {
                Text(detalle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let muestra = alerta.muestra, !muestra.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("FRAGMENTO DE CÓDIGO DETECTADO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(muestra)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.25))
                .cornerRadius(GuardianTheme.radiusSmall)
                .overlay(
                    RoundedRectangle(cornerRadius: GuardianTheme.radiusSmall)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .guardianCard(radius: GuardianTheme.radiusMedium)
    }
}

struct WelcomeView: View {
    let onScan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GlowBadge(systemImage: "shield.lefthalf.filled", tint: GuardianTheme.accent, size: 96)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    Text("Guardian v2.0")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("Auditoría de secretos con trazabilidad cronológica.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "folder.badge.gearshape", tint: GuardianTheme.accent, title: "Análisis Inteligente", description: "Escanea directorios buscando claves de API, contraseñas y certificados expuestos.")
                    FeatureRow(icon: "lock.shield", tint: GuardianTheme.success, title: "Cuarentena Autónoma", description: "Aísla de forma segura archivos comprometidos, copiando o moviendo, impidiendo su fuga o commits accidentales.")
                    FeatureRow(icon: "clock.arrow.circlepath", tint: GuardianTheme.glow, title: "Historial de Acciones", description: "Almacena logs cronológicos y metadatos detallados para cada acción de contención.")
                }
                .frame(maxWidth: 360)
                .guardianCard(padding: 18)

                Button(action: onScan) {
                    Label("Escanear Carpeta", systemImage: "magnifyingglass")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(GuardianTheme.accent)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    var tint: Color = GuardianTheme.accent
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlowBadge(systemImage: "exclamationmark.shield.fill", tint: GuardianTheme.danger, size: 84)

                Text("Error en el Escaneo")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Intentar de nuevo", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(GuardianTheme.danger)
                    .controlSize(.large)
                    .padding(.top, 10)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

struct CleanView: View {
    let path: String
    let onScanAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GlowBadge(systemImage: "checkmark.shield.fill", tint: GuardianTheme.success, size: 100)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    Text("¡Carpeta Segura!")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("No se detectaron secretos expuestos ni archivos comprometidos.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ruta analizada:").bold()
                            .foregroundColor(.secondary)
                        Text(path)
                            .italic()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)

                    HStack {
                        Text("Resultado:").bold()
                            .foregroundColor(.secondary)
                        Text("Limpio (0 amenazas)")
                            .foregroundColor(GuardianTheme.success)
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: 320, alignment: .leading)
                .guardianCard()

                Button(action: onScanAgain) {
                    Label("Escanear otra carpeta", systemImage: "magnifyingglass")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(GuardianTheme.success)
                .controlSize(.large)
                .padding(.top, 16)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

struct ThreatsFoundView: View {
    let count: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GlowBadge(systemImage: "exclamationmark.shield.fill", tint: GuardianTheme.danger, size: 100)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    Text("¡Se encontraron \(count) archivos comprometidos!")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(GuardianTheme.danger)
                    Text("Se han detectado claves de API, secretos o credenciales expuestas en la carpeta analizada.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Text("Selecciona cualquier archivo de la barra lateral izquierda para ver el detalle de las amenazas y los fragmentos de código afectados.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

struct MultiDetailView: View {
    let selectedPaths: Set<String>
    @ObservedObject var scanner: ScannerManager

    private var relevantResults: [ScanResult] {
        scanner.results.filter { selectedPaths.contains($0.archivo) }
    }
    private var unisolatedPaths: [String] {
        relevantResults.filter { $0.movido_a == nil }.map(\.archivo)
    }

    var body: some View {
        VStack(spacing: 24) {
            GlowBadge(systemImage: "exclamationmark.shield.fill", tint: GuardianTheme.danger, size: 100)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text("Selección Múltiple: \(selectedPaths.count) Archivos")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                Text("Has seleccionado varios archivos con secretos o credenciales comprometidas.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            if !unisolatedPaths.isEmpty {
                Button(action: {
                    withAnimation(GuardianTheme.spring) {
                        scanner.quarantineFiles(archivos: unisolatedPaths)
                    }
                }) {
                    Label(scanner.copyInsteadOfMove ? "Copiar \(unisolatedPaths.count) seleccionados" : "Aislar \(unisolatedPaths.count) seleccionados", systemImage: "shield.fill")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(GuardianTheme.success)
                .controlSize(.large)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(GuardianTheme.success)
                    Text("Todos los archivos seleccionados están protegidos en cuarentena.")
                        .foregroundColor(GuardianTheme.success)
                        .fontWeight(.semibold)
                }
                .padding(12)
                .background(GuardianTheme.success.opacity(0.1), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ARCHIVOS SELECCIONADOS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(relevantResults) { result in
                            HStack {
                                Image(systemName: result.movido_a != nil ? "shield.fill" : "lock.open.fill")
                                    .foregroundColor(result.movido_a != nil ? GuardianTheme.success : GuardianTheme.danger)
                                Text(URL(fileURLWithPath: result.archivo).lastPathComponent)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(result.archivo)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .guardianCard()
        }
        .padding()
    }
}
