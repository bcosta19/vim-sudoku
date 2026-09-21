# Vim Sudoku

A Sudoku you play with vim motions, built for the [Omarchy](https://omarchy.org/)
desktop — it runs as a plugin inside `omarchy-shell` and also works as a
standalone [Quickshell](https://quickshell.org/) app.

`hjkl` moves the cursor, holding <kbd>Space</kbd> is momentary INSERT mode,
`1-9` toggles pencil notes in NORMAL mode and plays a number in INSERT mode,
`u`/`r` undo and redo. The colors follow the live Omarchy theme, including the
crossfade when you switch themes.

> **Preview:** drop a `preview.png` at the repo root (a screenshot of the
> board) before listing the plugin in a marketplace.

## Features

- **Two modes, one key.** Hold <kbd>Space</kbd> to insert, release it to go
  back to NORMAL — no mode to get stuck in.
- **Mistakes stay on the board.** A wrong number is placed (in red) so you can
  reason on top of it; **3 mistakes** end the game.
- **Pencil notes.** `1-9` toggles notes; notes that conflict with a placed
  digit are painted red, and placing a number clears that note from all its
  peers (row, column, 3x3 box).
- **Unique-solution generator.** Every puzzle is generated locally with
  backtracking plus a uniqueness test; easy/medium/hard control how many cells
  are removed (36 / 44 / 52 holes).
- **Game library.** Keep several games at once, each with its own board,
  clock, score and undo history; `g` opens the library.
- **Live theme.** Background, foreground, accent and error colors all come
  from the current Omarchy theme, with a 400 ms crossfade.
- **Auto-save.** The clock, board, notes and undo/redo stack are saved to
  `~/.local/state/vim-sudoku/slots.json`; the clock pauses whenever the game
  loses focus or the panel is hidden.

## Requirements

- Omarchy 4.x for the plugin mode (`omarchy-shell` plus the `omarchy plugin`
  commands). Any Quickshell runtime can run the standalone app with `qs -p`.
- `JetBrainsMono Nerd Font` for the glyphs. It ships with Omarchy; the font
  family is set in `qml/SudokuWindow.qml` (`monoFont`).
- Qt 6.11 only if you want to run the tests (`qmltestrunner`).

## Install as an omarchy-shell plugin

Once the repo is pushed to a public git host:

```bash
omarchy plugin add https://github.com/bcosta19/vim-sudoku.git --enable
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + G", "Vim Sudoku", "omarchy-shell shell toggle bcosta19.vim-sudoku")
```

Without a keybinding you can always move it from a terminal — `toggle` closes
the panel if it is already open:

```bash
omarchy-shell shell toggle bcosta19.vim-sudoku
omarchy-shell shell hide   bcosta19.vim-sudoku
```

The plugin registers as `kinds: ["panel"]` with `keepLoaded: true`, so the
shell mounts it once and keeps the board, clock and undo history alive between
summons. `q` (or <kbd>Esc</kbd> in NORMAL mode) closes the panel without
touching the rest of the shell.

### Local development (no publishing)

Install the working copy as a symlinked plugin and let the shell hot-reload it:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/bcosta19.vim-sudoku
omarchy-shell shell rescanPlugins
omarchy plugin enable bcosta19.vim-sudoku
```

Saving a file under the plugin directory reloads it automatically. To undo:

```bash
omarchy plugin disable bcosta19.vim-sudoku
rm ~/.config/omarchy/plugins/bcosta19.vim-sudoku
```

`make install` does the symlink + rescan for you.

## Run standalone

For a normal floating window without installing the plugin:

```bash
./vim-sudoku
```

`vim-sudoku.desktop` is a launcher for that mode (adjust its `Exec=` path to
your checkout). Standalone and plugin mode share the same save file, so you can
switch between them freely — just don't run both at once.

### Live theme hook (standalone only)

`omarchy theme set` swaps `colors.toml` by rename (new inode), so an inode
watch alone does not fire. The app re-reads the theme on a 1s timer as a
fallback, but for an instant crossfade install a hook:

```sh
# ~/.config/omarchy/hooks/theme-set.d/vim-sudoku.sh
#!/bin/sh
pgrep -f "qs -p /path/to/vim-sudoku" >/dev/null 2>&1 || exit 0
qs ipc -p /path/to/vim-sudoku call sudoku applyTheme >/dev/null 2>&1 || true
```

The plugin mode does not need this hook: it lives inside `omarchy-shell`, which
already re-reads the theme.

## Keys

| Key | NORMAL | INSERT (hold <kbd>Space</kbd>) |
| --- | --- | --- |
| `h` `j` `k` `l` / arrows | move the cursor | move the cursor |
| `1-9` | toggle a pencil note | play the number |
| `x` `d` `0` `Del` | clear the cell | clear the cell |
| `u` | undo | — |
| `r` | redo | — |
| `Ctrl+r` | redo | redo |
| `g` | open the game library | open the game library |
| `o` | toggle the agents pill | — |
| `q` / `Ctrl+q` / `Ctrl+c` | quit (closes the panel) | quit |
| <kbd>Esc</kbd> | quit | back to NORMAL |

In the game library: `j`/`k` navigate, <kbd>Enter</kbd> opens, `d`/`x`/`Del`
deletes, `n` starts a new game, `1`/`2`/`3` pick easy/medium/hard, and
<kbd>Esc</kbd> closes. Right-clicking a cell clears it; double-clicking enters
INSERT mode.

## Rules and scoring

- A wrong number goes to the board in red and counts as a mistake; **3
  mistakes** end the game. From the game-over screen, <kbd>Enter</kbd> retries
  the same board from scratch or `n` starts a new one.
- The number palette shows how many of each digit are still missing, in yellow
  when only one or two remain and with a green `✓` when the digit is complete.
- The clock only runs while the game is focused and visible.

## Save file

`~/.local/state/vim-sudoku/slots.json` (v2 format) stores every game:

```json
{
  "active": "g1726000000000",
  "order": ["g1726000000000"],
  "games": { "g1726000000000": { "v": 2, "name": "Game 1", "...": "..." } },
  "lastTheme": "tokyo-night",
  "agentsPill": true,
  "lastDifficulty": "medium"
}
```

Finished games are not restored (they are dropped when you win). Deleting the
file simply starts a fresh library.

## Agents pill (optional)

The header can show a pill with the state of background coding agents, read
from `~/.local/state/vim-sudoku/agents.json`:

```json
{
  "updated_at": 1726000000000,
  "agents": [
    { "label": "pi", "state": "working" },
    { "label": "reviewer", "state": "error" }
  ]
}
```

It only appears when the file is fresh (less than 2 minutes old) and something
is working or has failed; `state: "error"` wins only when nothing is working.
Press `o` to turn the pill off entirely — the choice is persisted. Point the app
at a different file with the `VIM_SUDOKU_AGENTS` environment variable. This is a
personal integration and is entirely optional.

## Development

```bash
make test       # game logic tests (18 cases)
make lint       # qmllint
make validate   # omarchy plugin validate .
make run        # standalone window
make install    # symlink the working copy into ~/.config/omarchy/plugins/
```

The test runner in `PATH` may be the Qt5 build, which fails silently; the
Makefile defaults to `/usr/lib/qt6/bin/qmltestrunner` (override with
`QMLTESTRUNNER=...`). Tests need `QT_QPA_PLATFORM=offscreen` on a headless
machine and cover: notes on/off, givens, correct/wrong plays, game over and
retry, clear/undo/redo, cursor clamping, insert shift, note validity, win
detection, the generator's uniqueness, difficulty handling, the clock format,
remaining counts, and save/load round-trips.

### Layout

```
manifest.json          Omarchy plugin manifest (kind: panel)
SudokuPanel.qml        omarchy-shell plugin entry point (host contract)
shell.qml              standalone Quickshell entry point (ShellRoot)
vim-sudoku             standalone launcher script
vim-sudoku.desktop     standalone desktop entry
qml/SudokuWindow.qml   the game window: board, status bar, overlays, key handling
qml/Game.js            pure game logic (no UI)
qml/Theme.js           colors.toml parser + fallbacks
tests/tst_game.qml     game logic tests
```

## Before publishing

- `manifest.json` uses the `bcosta19.vim-sudoku` id and `Bruno Costa` as the
  author — change both if you fork the repo or move it to another account. The
  id also names the plugin directory and the value passed to
  `omarchy-shell shell toggle`.
- Add a `preview.png` and pick a license you are happy with.
- `omarchy plugin validate .` must exit 0.

## License

MIT — see [LICENSE](LICENSE).
