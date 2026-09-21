import QtQuick
import "qml"

// vim-sudoku as an omarchy-shell panel plugin.
//
// The shell discovers manifest.json, loads this file as a `panel` entry point,
// and injects `shell` and `manifest` when the properties exist. It then drives
// the panel through this contract:
//
//   open(payloadJson)  summon/show the panel
//   close()            hide it (host-initiated)
//   requestClose()     the panel asks the host to hide it (user-initiated)
//   opened             read-only flag the host polls for toggle()
//
// Summon it with:
//   omarchy-shell shell toggle bcosta19.vim-sudoku
//
// The game itself lives in qml/SudokuWindow.qml and runs in embedded mode:
// it starts hidden, never calls Qt.quit(), and asks this wrapper to close
// instead. See README.md for install and keybinding instructions.

Item {
    id: root

    // ---- host injections ---------------------------------------------------
    property var shell: null
    property var manifest: null

    readonly property string pluginId: (manifest && manifest.id)
        ? String(manifest.id) : "bcosta19.vim-sudoku"

    // True while the panel is showing; the host reads this for isPluginOpen().
    readonly property bool opened: sudokuWindow.visible

    property bool closingFromHost: false

    function hideOnHost() {
        if (shell && typeof shell.hide === "function")
            shell.hide(root.pluginId)
        else
            sudokuWindow.visible = false
    }

    // Host-initiated show.
    function open(payloadJson) {
        closingFromHost = false
        sudokuWindow.visible = true
        sudokuWindow.reloadThemeNow();
    }

    // Host-initiated hide.
    function close() {
        closingFromHost = true
        sudokuWindow.visible = false
        closingFromHost = false
    }

    // User-initiated close (q / Esc / the window close button).
    function requestClose() {
        root.hideOnHost()
    }

    SudokuWindow {
        id: sudokuWindow
        embedded: true

        // The user closed the window; keep the host's open-panel set in sync.
        onVisibleChanged: {
            if (!visible && !root.closingFromHost)
                root.hideOnHost()
        }

        onQuitRequested: root.requestClose()
    }
}
