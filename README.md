# WinFinder

Windows-style keyboard shortcuts for the macOS Finder. WinFinder is a small menu bar app that remaps a few keys only while Finder is frontmost.

| Key | In Finder with WinFinder | Finder's default |
| --- | --- | --- |
| **Return** | Open the selected file or folder | Rename |
| **F2** | Rename the selection | — |
| **Delete** / **Forward Delete** | Move to Trash | Nothing (needs ⌘⌫) |
| **Ctrl+Shift+N** or **⌘⇧T** | Create `New Text Document.txt` in the current folder and start renaming it | — |

WinFinder leaves your keys alone when you're typing: renaming a file, using the search field or Go to Folder, or working in a dialog such as "Empty Trash?". Holding Delete or Return down doesn't repeat the action.

## Install

1. Download `WinFinder-<version>.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **WinFinder** into **Applications**.
3. Open WinFinder from Applications. The app isn't notarized, so macOS blocks it the first time. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
4. Grant the permissions below.

### Permissions

- **Accessibility** (required): lets WinFinder see and remap key presses. Turn on WinFinder in **System Settings → Privacy & Security → Accessibility**. WinFinder starts working within a couple of seconds, with no relaunch needed.
- **Automation → Finder**: needed only for creating new text documents. macOS asks the first time you press Ctrl+Shift+N or ⌘⇧T.

To start WinFinder automatically, add it under **System Settings → General → Login Items**.

## Menu bar

Click the folder icon in the menu bar to:

- turn remapping on or off (**Enabled**)
- check whether Accessibility permission has been granted
- **Hide Menu Bar Icon**: WinFinder keeps running with no icon. To show the icon again, open WinFinder again from Applications, Spotlight or Launchpad.
- quit

## Building from source

You need macOS 13 or later and Xcode or the Swift command line tools (Swift 5.10 or later).

```sh
./bundle.sh      # builds build/WinFinder.app
./make_dmg.sh    # builds the app, then packages build/WinFinder-<version>.dmg
```

Optional environment variables:

- `VERSION`: version string written into the app and the DMG name (default `1.0.0`)
- `SIGN_IDENTITY`: code-signing identity. Without it the app is signed ad hoc, and macOS may ask for permissions again after each rebuild.
- `BUNDLE_ID`: bundle identifier (default `com.winfinder.WinFinder`)

Example: `VERSION=1.1.0 ./make_dmg.sh`

## How it works

- `EventTapManager`: a `CGEventTap`, running on its own thread, that rewrites key events while Finder is the active app.
- `AccessibilityHelper`: checks the focused UI element so that text fields and dialogs are skipped.
- `FinderBridge`: uses AppleScript to find the front Finder window's folder, create the text file, select it and start renaming.
- `MenuBarController`: the status bar menu.
