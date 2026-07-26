import SwiftUI
import AppKit

struct WindowStyleConfigurator: NSViewRepresentable {
    /// Every change of this value animates the window to its ideal content size
    /// (as small as possible, as large as necessary).
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
            // On launch AppKit restores the last saved frame — turn that
            // persistence off and fit to the content once.
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
            // Let SwiftUI commit the new layout first, then resize.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.fitWindowToContent()
            }
        }

        private func fitWindowToContent() {
            guard let window = self.window, let content = window.contentView else { return }
            // NSHostingView reports the SwiftUI ideal size via intrinsicContentSize;
            // fittingSize can silently return zero.
            var fitting = content.intrinsicContentSize
            if fitting.width <= 100 || fitting.height <= 100 {
                fitting = content.fittingSize
            }
            guard fitting.width > 100, fitting.height > 100 else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: fitting))
            let old = window.frame
            frame.origin = NSPoint(x: old.origin.x, y: old.maxY - frame.height) // keep the top-left corner fixed
            window.setFrame(frame, display: true, animate: true)
        }

        private func applyTransparentTitlebar(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            // Traffic-light buttons stay visible
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
        }
    }
}
