import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = NSApplication.shared.windows.first else { return }
            window.backgroundColor = NSColor.black
            window.isMovableByWindowBackground = false
            window.collectionBehavior = [.fullScreenPrimary, .managed]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
