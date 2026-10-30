import AppKit

/// Talks to Finder over Apple Events and performs file-system work.
/// All methods must be called on the main thread (NSAppleScript requirement).
enum FinderBridge {

    static let baseName = "New Text Document"
    static let fileExtension = "txt"

    /// Creates "New Text Document.txt" in the active Finder folder, selects it,
    /// and puts Finder into inline rename mode.
    static func createNewTextDocument() {
        dispatchPrecondition(condition: .onQueue(.main))

        let folder = currentFolderURL()
        let fileURL: URL
        do {
            fileURL = try createUniqueFile(in: folder)
        } catch {
            NSLog("WinFinder: failed to create file in %@: %@", folder.path, error.localizedDescription)
            NSSound.beep()
            return
        }
        NSLog("WinFinder: created %@", fileURL.path)

        guard selectInFinder(fileURL) else { return }

        // Give Finder a moment to settle the selection, then send a bare Return to start renaming.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            KeySynthesizer.post(keyCode: KeyCode.returnKey, flags: [])
        }
    }

    // MARK: - Folder discovery

    /// The target folder of the front Finder window, or ~/Desktop if there is none
    /// (or the window shows something that isn't a real folder, like Recents).
    static func currentFolderURL() -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)

        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            try
                return POSIX path of (target of front Finder window as alias)
            on error
                return ""
            end try
        end tell
        """
        guard let path = runAppleScript(source)?.stringValue, !path.isEmpty else {
            return desktop
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return desktop
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - File creation

    /// Creates an empty UTF-8 file, auto-incrementing the name on collisions:
    /// "New Text Document.txt", "New Text Document (2).txt", ...
    static func createUniqueFile(in folder: URL) throws -> URL {
        let fm = FileManager.default
        var index = 1
        while true {
            let name = index == 1 ? "\(baseName).\(fileExtension)" : "\(baseName) (\(index)).\(fileExtension)"
            let url = folder.appendingPathComponent(name, isDirectory: false)
            if !fm.fileExists(atPath: url.path) {
                // `.withoutOverwriting` makes the existence check race-free.
                do {
                    try Data().write(to: url, options: .withoutOverwriting)
                    return url
                } catch CocoaError.fileWriteFileExists {
                    // Someone created it between the check and the write; try the next name.
                }
            }
            index += 1
        }
    }

    // MARK: - Selection

    @discardableResult
    static func selectInFinder(_ fileURL: URL) -> Bool {
        let filePath = appleScriptEscape(fileURL.path)
        let folderPath = appleScriptEscape(fileURL.deletingLastPathComponent().path)
        let source = """
        tell application "Finder"
            activate
            try
                update (POSIX file "\(folderPath)" as alias)
            end try
            set theFile to (POSIX file "\(filePath)" as alias)
            reveal theFile
            select theFile
        end tell
        """
        return runAppleScript(source) != nil
    }

    // MARK: - AppleScript

    @discardableResult
    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
            NSLog("WinFinder: AppleScript error %d: %@", code, message)
            if code == -1743 {
                NSLog("WinFinder: Automation permission denied. Enable WinFinder → Finder in System Settings → Privacy & Security → Automation.")
            }
            return nil
        }
        return result
    }

    private static func appleScriptEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
