//
//  GuardianSSApp.swift
//  GuardianSS
//
//  Created by Eugenio de Frutos Sanchez on 01/08/2026.
//

import SwiftUI
import AppKit

@main
struct GuardianSSApp: App {
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var installSetup = InstallSetupManager()

    init() {
        // Ventana única de utilidad: la barra de pestañas nativa no aporta aquí.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updateChecker)
                .environmentObject(installSetup)
                .frame(minWidth: 900, idealWidth: 1100, maxWidth: 1600, minHeight: 600, idealHeight: 750, maxHeight: 1200)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Buscar actualizaciones...") {
                    updateChecker.check(silent: false)
                }
                .disabled(updateChecker.isChecking)
            }
        }
    }
}
