//
//  Sphaira_ConnectApp.swift
//  Sphaira Connect
//
//  Created by Marvbuster on 25.07.26.
//

import SwiftUI
import AppKit

@main
struct Sphaira_ConnectApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "Über Sphaira Connect")) { showAboutPanel() }
            }
        }
    }

    /// Über-Fenster mit den Angaben zu fremden Bestandteilen.
    ///
    /// Die Grafik des App-Symbols steht unter CC BY 3.0. Diese Lizenz verlangt,
    /// dass die Namensnennung für alle erreichbar ist, die das Werk benutzen —
    /// ein Hinweis nur im Quelltext-Repository genügt dafür nicht, weil die App
    /// auch als fertiges Programm weitergegeben wird.
    private func showAboutPanel() {
        let credits = NSMutableAttributedString()

        func line(_ text: String, size: CGFloat = 11, color: NSColor = .secondaryLabelColor) {
            credits.append(NSAttributedString(
                string: text + "\n",
                attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
            ))
        }

        line(String(localized: "Überträgt Titelpakete per USB an Sphaira auf der Nintendo Switch."),
             size: 11, color: .labelColor)
        line("")
        line(String(localized: "Symbolgrafik: „nintendo switch“ von Mikicon, Noun Project (CC BY 3.0)"))
        line(String(localized: "USB-Anbindung: libusb (LGPL-2.1-or-later)"))
        line(String(localized: "Protokoll abgeleitet aus usb_install.py von Sphaira (GPL-3.0)"))
        line("")
        line(String(localized: "Nicht mit Nintendo verbunden."))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Sphaira Connect",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "GPL-3.0",
        ])
        NSApplication.shared.activate()
    }
}
