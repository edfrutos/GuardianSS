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
    init() {
        // Ventana única de utilidad: la barra de pestañas nativa no aporta aquí.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, idealWidth: 1100, maxWidth: 1600, minHeight: 600, idealHeight: 750, maxHeight: 1200)
        }
    }
}
