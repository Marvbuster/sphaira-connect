import SwiftUI
import AppKit

struct WindowStyleConfigurator: NSViewRepresentable {
    /// Jede Wertänderung passt das Fenster animiert an die ideale
    /// Inhaltsgröße an (so klein wie möglich, so groß wie nötig).
    var sizeKey: AnyHashable = false

    func makeNSView(context: Context) -> NSView {
        return ConfigView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfigView)?.refitIfNeeded(key: sizeKey)
    }

    private final class ConfigView: NSView {
        private var lastKey: AnyHashable?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            applyTransparentTitlebar(window)
            // AppKit stellt beim Start den zuletzt gesicherten Rahmen wieder her —
            // Persistenz abschalten und einmal an den Inhalt anpassen.
            window.setFrameAutosaveName("")
            window.isRestorable = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.fitWindowToContent()
            }
        }

        func refitIfNeeded(key: AnyHashable) {
            guard let previous = lastKey else {
                lastKey = key
                return
            }
            guard previous != key else { return }
            lastKey = key
            // Erst SwiftUI das neue Layout festschreiben lassen, dann anpassen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.fitWindowToContent()
            }
        }

        private func fitWindowToContent() {
            guard let window = self.window, let content = window.contentView else { return }
            // NSHostingView meldet die SwiftUI-Idealgröße über intrinsicContentSize;
            // fittingSize kann stillschweigend Null liefern.
            var fitting = content.intrinsicContentSize
            if fitting.width <= 100 || fitting.height <= 100 {
                fitting = content.fittingSize
            }
            guard fitting.width > 100, fitting.height > 100 else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: fitting))
            let old = window.frame
            frame.origin = NSPoint(x: old.origin.x, y: old.maxY - frame.height) // obere linke Ecke halten
            window.setFrame(frame, display: true, animate: true)
        }

        private func applyTransparentTitlebar(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            // Ampelknöpfe bleiben sichtbar
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
        }
    }
}
