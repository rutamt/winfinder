import AppKit
import CoreGraphics
import os

enum KeyCode {
    static let returnKey: CGKeyCode = 36
    static let delete: CGKeyCode = 51          // Backspace
    static let forwardDelete: CGKeyCode = 117
    static let f2: CGKeyCode = 120
    static let downArrow: CGKeyCode = 125
    static let n: CGKeyCode = 45
    static let t: CGKeyCode = 17
}

/// Builds and posts keyboard events tagged so our own tap ignores them.
enum KeySynthesizer {
    /// Written to `eventSourceUserData` on every event WinFinder creates ("WINFNDR").
    static let marker: Int64 = 0x57_49_4E_46_4E_44_52

    private static let source = CGEventSource(stateID: .privateState)

    /// Creates a tagged key event. The unicode string is derived from the key code
    /// and current layout, so menu key equivalents in Finder match correctly.
    static func makeEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return nil
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    /// Posts a full key press (down + up) into the HID stream.
    static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        makeEvent(keyCode: keyCode, keyDown: true, flags: flags)?.post(tap: .cghidEventTap)
        makeEvent(keyCode: keyCode, keyDown: false, flags: flags)?.post(tap: .cghidEventTap)
    }
}

/// Owns the CGEventTap that rewrites Finder keystrokes. The tap runs on its own
/// thread so slow work on the main thread (AppleScript, menus) can never time it out.
final class EventTapManager {

    static let finderBundleID = "com.apple.finder"

    private enum Action {
        case remap(keyCode: CGKeyCode, flags: CGEventFlags)
        case newTextDocument
    }

    private struct SharedState {
        var enabled = true
        var finderIsFrontmost = false
    }

    private let state = OSAllocatedUnfairLock(initialState: SharedState())

    // Accessed only from the tap thread.
    private var eventTap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    /// Key codes whose keyDown we rewrote, so the matching keyUp is rewritten the same way.
    private var activeActions: [CGKeyCode: Action] = [:]

    private var activationObserver: NSObjectProtocol?

    var isEnabled: Bool {
        get { state.withLock { $0.enabled } }
        set { state.withLock { $0.enabled = newValue } }
    }

    var isRunning: Bool { thread != nil }

    // MARK: - Lifecycle

    /// Starts the tap. Returns false if the tap could not be created (usually missing permissions).
    @discardableResult
    func start() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard thread == nil else { return true }

        observeFrontmostApplication()

        let ready = DispatchSemaphore(value: 0)
        var created = false
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            created = self.installTap()
            ready.signal()
            if created { CFRunLoopRun() }
        }
        thread.name = "WinFinder.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        if created {
            self.thread = thread
            NSLog("WinFinder: event tap active")
        } else {
            NSLog("WinFinder: failed to create event tap — is Accessibility permission granted?")
        }
        return created
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        eventTap = nil
        runLoop = nil
        thread = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    // MARK: - Setup

    /// Caches whether Finder is frontmost so the tap callback never touches AppKit off-main.
    private func observeFrontmostApplication() {
        let update: (NSRunningApplication?) -> Void = { [weak self] app in
            self?.state.withLock { $0.finderIsFrontmost = app?.bundleIdentifier == Self.finderBundleID }
        }
        update(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            update(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoop = loop
        return true
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            NSLog("WinFinder: event tap was disabled (%d), re-enabling", type.rawValue)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passThrough
        case .keyDown, .keyUp:
            break
        default:
            return passThrough
        }

        // Never touch events we synthesized ourselves.
        if event.getIntegerValueField(.eventSourceUserData) == KeySynthesizer.marker {
            return passThrough
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyUp {
            // Rewrite the keyUp only if we rewrote its keyDown, keeping down/up pairs consistent.
            guard let action = activeActions.removeValue(forKey: keyCode) else { return passThrough }
            return emit(action, keyDown: false)
        }

        let (enabled, finderIsFrontmost) = state.withLock { ($0.enabled, $0.finderIsFrontmost) }
        guard enabled, finderIsFrontmost else { return passThrough }

        guard let action = action(for: keyCode, flags: event.flags) else { return passThrough }

        // Only now pay for the AX round-trip: leave typing and dialogs alone.
        if AccessibilityHelper.shouldBypassRemapping() {
            return passThrough
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            // Holding Delete/Return shouldn't trash or open things repeatedly.
            return nil
        }

        activeActions[keyCode] = action
        return emit(action, keyDown: true)
    }

    private func action(for keyCode: CGKeyCode, flags: CGEventFlags) -> Action? {
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let noModifiers = !hasCmd && !hasCtrl && !hasOpt && !hasShift

        switch keyCode {
        case KeyCode.returnKey where noModifiers:
            // Cmd+Down opens files and navigates into folders, and is keyboard-layout independent.
            return .remap(keyCode: KeyCode.downArrow, flags: [.maskCommand, .maskSecondaryFn, .maskNumericPad])
        case KeyCode.f2 where noModifiers:
            return .remap(keyCode: KeyCode.returnKey, flags: [])
        case KeyCode.delete where noModifiers, KeyCode.forwardDelete where noModifiers:
            return .remap(keyCode: KeyCode.delete, flags: .maskCommand)
        case KeyCode.n where hasCtrl && hasShift && !hasCmd && !hasOpt,
             KeyCode.t where hasCmd && hasShift && !hasCtrl && !hasOpt:
            return .newTextDocument
        default:
            return nil
        }
    }

    private func emit(_ action: Action, keyDown: Bool) -> Unmanaged<CGEvent>? {
        switch action {
        case let .remap(keyCode, flags):
            guard let newEvent = KeySynthesizer.makeEvent(keyCode: keyCode, keyDown: keyDown, flags: flags) else {
                return nil
            }
            // The event system releases the returned event, so hand over a +1 reference.
            return Unmanaged.passRetained(newEvent)
        case .newTextDocument:
            if keyDown {
                DispatchQueue.main.async { FinderBridge.createNewTextDocument() }
            }
            return nil // swallow the shortcut
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handle(type: type, event: event)
}
