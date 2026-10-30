import AppKit
import ApplicationServices

/// Thin wrappers around the macOS Accessibility (AX) API.
enum AccessibilityHelper {

    /// Roles (and subroles) that accept typed text. If one of these is focused,
    /// Return/Backspace must reach Finder untouched.
    private static let textInputRoles: Set<String> = [
        kAXTextFieldRole as String,   // inline rename field, Go to Folder field
        kAXTextAreaRole as String,
        "AXSearchField",              // Finder toolbar search
        kAXComboBoxRole as String,    // Go to Folder on newer macOS versions
    ]

    /// Windows where Return/Delete mean "press the default button" or similar,
    /// not "open/trash the selection".
    private static let dialogRoles: Set<String> = [
        kAXSheetRole as String,
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String,
    ]

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // Never let a hung app stall the event tap for long.
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }()

    // MARK: - Trust

    /// Checks Accessibility trust, optionally showing the system prompt.
    @discardableResult
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Focus inspection

    /// True when the focused UI element is a text input (renaming, search, Go to Folder…).
    static func isTextInputFocused() -> Bool {
        guard let focused = focusedElement() else { return false }
        if let role = stringAttribute(focused, kAXRoleAttribute), textInputRoles.contains(role) {
            return true
        }
        if let subrole = stringAttribute(focused, kAXSubroleAttribute), textInputRoles.contains(subrole) {
            return true
        }
        return false
    }

    /// True when focus is inside a sheet or dialog (e.g. "Empty Trash?" confirmation),
    /// where Return should press the default button rather than open a file.
    static func isDialogFocused() -> Bool {
        guard let focused = focusedElement() else { return false }
        if let role = stringAttribute(focused, kAXRoleAttribute), dialogRoles.contains(role) {
            return true
        }
        guard let window = elementAttribute(focused, kAXWindowAttribute) else { return false }
        if let role = stringAttribute(window, kAXRoleAttribute), dialogRoles.contains(role) {
            return true
        }
        if let subrole = stringAttribute(window, kAXSubroleAttribute), dialogRoles.contains(subrole) {
            return true
        }
        return false
    }

    /// Returns true if remapping should be skipped because the user is typing
    /// or interacting with a dialog.
    static func shouldBypassRemapping() -> Bool {
        isTextInputFocused() || isDialogFocused()
    }

    // MARK: - Private

    private static func focusedElement() -> AXUIElement? {
        elementAttribute(systemWide, kAXFocusedUIElementAttribute)
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
