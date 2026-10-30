import AppKit

/// The status bar item and its menu.
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let tapManager: EventTapManager

    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let tapStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private static let hideIconDefaultsKey = "HideMenuBarIcon"

    init(tapManager: EventTapManager) {
        self.tapManager = tapManager
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "WinFinder")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "WinFinder"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "WinFinder", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        enabledItem.target = self
        menu.addItem(enabledItem)

        permissionItem.target = self
        menu.addItem(permissionItem)

        tapStatusItem.isEnabled = false
        menu.addItem(tapStatusItem)

        menu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "")
        hideItem.target = self
        hideItem.toolTip = "Open WinFinder again (e.g. from Spotlight) to show the icon."
        menu.addItem(hideItem)

        let quitItem = NSMenuItem(title: "Quit WinFinder", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.isVisible = !UserDefaults.standard.bool(forKey: Self.hideIconDefaultsKey)
        refresh()
    }

    /// Shows or hides the status bar icon and remembers the choice across launches.
    func setIconVisible(_ visible: Bool) {
        statusItem.isVisible = visible
        UserDefaults.standard.set(!visible, forKey: Self.hideIconDefaultsKey)
        NSLog("WinFinder: menu bar icon %@", visible ? "shown" : "hidden")
    }

    func refresh() {
        enabledItem.state = tapManager.isEnabled ? .on : .off

        let trusted = AccessibilityHelper.isTrusted(prompt: false)
        permissionItem.title = trusted
            ? "Accessibility: Granted ✓"
            : "Accessibility: Not Granted — Open Settings…"
        permissionItem.isEnabled = !trusted

        tapStatusItem.title = tapManager.isRunning ? "Key remapping: Active" : "Key remapping: Waiting for permission"

        statusItem.button?.appearsDisabled = !(tapManager.isEnabled && tapManager.isRunning)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        tapManager.isEnabled.toggle()
        NSLog("WinFinder: remapping %@", tapManager.isEnabled ? "enabled" : "disabled")
        refresh()
    }

    @objc private func hideIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the WinFinder menu bar icon?"
        alert.informativeText = "WinFinder keeps running in the background. To show the icon again, open WinFinder again from Applications, Spotlight or Launchpad."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setIconVisible(false)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityHelper.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
