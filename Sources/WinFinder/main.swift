import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let tapManager = EventTapManager()
    private var menuBar: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(tapManager: tapManager)

        if AccessibilityHelper.isTrusted(prompt: true) {
            startTap()
        } else {
            printPermissionInstructions()
            waitForPermission()
        }
    }

    /// Opening the app again while it's running (Finder, Spotlight, `open -a`) brings back a hidden icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.setIconVisible(true)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapManager.stop()
    }

    private func startTap() {
        tapManager.start()
        menuBar?.refresh()
    }

    /// Polls every 2 seconds until Accessibility is granted, then starts the tap.
    private func waitForPermission() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard AccessibilityHelper.isTrusted(prompt: false) else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            print("WinFinder: Accessibility permission granted — starting event tap.")
            self?.startTap()
        }
    }

    private func printPermissionInstructions() {
        let executable = Bundle.main.bundleURL.path
        print("""

        ┌────────────────────────────────────────────────────────────────┐
        │ WinFinder needs Accessibility permission to remap Finder keys. │
        └────────────────────────────────────────────────────────────────┘
          1. Open System Settings → Privacy & Security → Accessibility
          2. Enable the entry for WinFinder (or your terminal app if you
             launched the raw binary from a shell)
               \(executable)
          3. Leave WinFinder running — it checks again every 2 seconds and
             starts automatically once permission is granted.

        Creating new text documents also needs Automation access to Finder;
        macOS will ask the first time you press Ctrl+Shift+N / Cmd+Shift+T.

        """)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
