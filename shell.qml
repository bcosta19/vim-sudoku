import QtQuick
import Quickshell
import Quickshell.Io
import "qml"

// vim-sudoku as a standalone Quickshell app — the same runtime as the
// Omarchy shell (qs -p). FloatingWindow + FileView, like the dev-gallery.
//
// Live theme: `omarchy theme set` swaps colors.toml by rename (new inode),
// so watchChanges by inode does not fire — the shell itself solves this by
// pushing over IPC. Here it is the same: the hook in
// ~/.config/omarchy/hooks/theme-set.d/ calls `qs ipc call sudoku
// applyTheme`, which re-reads the files and applies a crossfade. A 1s
// Timer covers any other theme-change path.
//
// The same game also ships as an omarchy-shell plugin — see SudokuPanel.qml
// and README.md. This file is only the standalone development entry point.

ShellRoot {
  SudokuWindow {
    id: sudokuWindow
    onQuitRequested: Qt.quit()
  }

  IpcHandler {
    target: "sudoku"

    function applyTheme(): string {
      sudokuWindow.reloadThemeNow();
      return "ok";
    }

    function quit(): string {
      sudokuWindow.quitGame();
      return "ok";
    }
  }

  // Closing the window saves the clock and ends the app (the qs process).
  Connections {
    target: Quickshell
    function onLastWindowClosed() { sudokuWindow.quitGame() }
  }
}
