import SwiftUI

struct ContentView: View {
    @StateObject var scanner = ScannerManager()
    @State private var selectedResults: Set<String> = [] // Múltiple selección de IDs (Rutas de archivos)
    
    var body: some View {
        NavigationSplitView {
            VStack {
                if scanner.results.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: scanner.hasCompletedScan ? "checkmark.shield.fill" : "exclamationmark.shield")
                            .foregroundColor(scanner.hasCompletedScan ? .green : .secondary)
                            .font(.system(size: 32))
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
                } else {
                    List(scanner.results, selection: $selectedResults) { result in
                        HStack(spacing: 10) {
                            Image(systemName: result.movido_a != nil ? "shield.fill" : "lock.open.fill")
                                .foregroundColor(result.movido_a != nil ? .green : .red)
                                .font(.system(size: 14))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: result.archivo).lastPathComponent)
                                    .fontWeight(.medium)
                                Text(result.archivo)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Resultados")
            .safeAreaInset(edge: .bottom) {
                // Control de Cuarentena en la barra lateral
                VStack(spacing: 10) {
                    Divider()
                        .padding(.horizontal, -16)
                        .padding(.bottom, 4)
                    
                    Toggle("Mover a Cuarentena", isOn: $scanner.quarantineActive)
                        .toggleStyle(.switch)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            
        } detail: {
            if scanner.isScanning {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analizando directorio en busca de secretos...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else if let error = scanner.errorMessage {
                ErrorView(message: error, onRetry: selectFolderAndScan)
            } else if selectedResults.count > 1 {
                MultiDetailView(selectedPaths: selectedResults, scanner: scanner)
            } else if selectedResults.count == 1,
                      let selectedID = selectedResults.first,
                      let result = scanner.results.first(where: { $0.archivo == selectedID }) {
                DetailView(result: result, scanner: scanner)
            } else if scanner.hasCompletedScan {
                if scanner.results.isEmpty {
                    CleanView(path: scanner.lastScannedPath, onScanAgain: selectFolderAndScan)
                } else {
                    ThreatsFoundView(count: scanner.results.count)
                }
            } else {
                WelcomeView(onScan: selectFolderAndScan)
            }
        }
        .toolbar {
            // Panel de Control en la barra superior nativa de macOS
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
                scanner.runScan(targetPath: url.path)
            }
        }
    }
}

struct DetailView: View {
    let result: ScanResult
    @ObservedObject var scanner: ScannerManager
    @State private var metadata: FileMetadata?

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
    }
    
    var header: some View {
        HStack {
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
                }
            }
            Spacer()
            
            HStack(spacing: 12) {
                if result.movido_a == nil {
                    Button(action: {
                        scanner.quarantineFile(archivo: result.archivo)
                    }) {
                        Label("Aislar archivo", systemImage: "shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                
                // Etiqueta de Estado Semántica
                Text(result.movido_a != nil ? "Aislado" : "Comprometido")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(result.movido_a != nil ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundColor(result.movido_a != nil ? .green : .red)
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    func quarantineInfoBox(path: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                Text("ESTADO: PROTEGIDO EN CUARENTENA")
                    .font(.headline)
                    .foregroundColor(.green)
                    .fontWeight(.bold)
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
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
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
                    .foregroundColor(.red)
                
                Text(alerta.tipo)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let linea = alerta.linea {
                    Text("Línea \(linea)")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
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
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct WelcomeView: View {
    let onScan: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 8)
                
            VStack(spacing: 8) {
                Text("Guardian v2.0")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Auditoría de secretos con trazabilidad cronológica.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Divider()
                .frame(maxWidth: 200)
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "folder.badge.gearshape", title: "Análisis Inteligente", description: "Escanea directorios buscando claves de API, contraseñas y certificados expuestos.")
                FeatureRow(icon: "lock.shield", title: "Cuarentena Autónoma", description: "Aísla de forma segura archivos compromised, impidiendo su fuga o commits accidentales.")
                FeatureRow(icon: "clock.arrow.circlepath", title: "Historial de Acciones", description: "Almacena logs cronológicos y metadatos detallados para cada acción de contención.")
            }
            .frame(maxWidth: 360)
            
            Button(action: onScan) {
                Label("Escanear Carpeta", systemImage: "magnifyingglass")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24, alignment: .center)
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
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)
                .symbolRenderingMode(.hierarchical)
            
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
                .controlSize(.large)
                .padding(.top, 10)
        }
        .padding()
    }
}

struct CleanView: View {
    let path: String
    let onScanAgain: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 8)
            
            VStack(spacing: 8) {
                Text("¡Carpeta Segura!")
                    .font(.title)
                    .fontWeight(.bold)
                Text("No se detectaron secretos expuestos ni archivos comprometidos.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Divider()
                .frame(maxWidth: 200)
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ruta analizada:").bold()
                        .foregroundColor(.secondary)
                    Text(path)
                        .italic()
                        .lineLimit(1)
                }
                .font(.caption)
                
                HStack {
                    Text("Resultado:").bold()
                        .foregroundColor(.secondary)
                    Text("Limpio (0 amenazas)")
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
                .font(.caption)
            }
            .padding(16)
            .background(Color.green.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
            )
            
            Button(action: onScanAgain) {
                Label("Escanear otra carpeta", systemImage: "magnifyingglass")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 16)
        }
        .padding()
    }
}

struct ThreatsFoundView: View {
    let count: Int
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 8)
            
            VStack(spacing: 8) {
                Text("¡Se encontraron \(count) archivos comprometidos!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                Text("Se han detectado claves de API, secretos o credenciales expuestas en la carpeta analizada.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Divider()
                .frame(maxWidth: 200)
                .padding(.vertical, 8)
            
            Text("Selecciona cualquier archivo de la barra lateral izquierda para ver el detalle de las amenazas y los fragmentos de código afectados.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .padding()
    }
}

struct MultiDetailView: View {
    let selectedPaths: Set<String>
    @ObservedObject var scanner: ScannerManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 8)
            
            VStack(spacing: 8) {
                Text("Selección Múltiple: \(selectedPaths.count) Archivos")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Has seleccionado varios archivos con secretos o credenciales comprometidas.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Divider()
                .frame(maxWidth: 200)
                .padding(.vertical, 8)
            
            // Contar cuántos de los seleccionados no están aislados
            let unisolatedCount = selectedPaths.filter { path in
                scanner.results.first(where: { $0.archivo == path })?.movido_a == nil
            }.count
            
            if unisolatedCount > 0 {
                Button(action: {
                    let unisolatedPaths = selectedPaths.filter { path in
                        scanner.results.first(where: { $0.archivo == path })?.movido_a == nil
                    }
                    scanner.quarantineFiles(archivos: Array(unisolatedPaths))
                }) {
                    Label("Aislar \(unisolatedCount) seleccionados", systemImage: "shield.fill")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Todos los archivos seleccionados están protegidos en cuarentena.")
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Listado de rutas seleccionadas
            VStack(alignment: .leading, spacing: 6) {
                Text("ARCHIVOS SELECCIONADOS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(selectedPaths), id: \.self) { path in
                            HStack {
                                Image(systemName: scanner.results.first(where: { $0.archivo == path })?.movido_a != nil ? "shield.fill" : "lock.open.fill")
                                    .foregroundColor(scanner.results.first(where: { $0.archivo == path })?.movido_a != nil ? .green : .red)
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(path)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .padding(.horizontal, 48)
        }
        .padding()
    }
}
