import QtQuick
import Quickshell
import Quickshell.Io
import "Game.js" as Game
import "Theme.js" as Theme

// vim-sudoku — Quickshell window (FloatingWindow), integrated with Omarchy.
// Live theme via FileView with a smooth crossfade.
// Font: JetBrainsMono Nerd Font.
//
// Runs both standalone (shell.qml) and as an omarchy-shell panel plugin
// (SudokuPanel.qml). In embedded mode the window starts hidden and is shown by
// the plugin host, and quitting asks the host to close the panel instead of
// ending the process.

FloatingWindow {
    id: root

    // Embedded mode: hosted by the omarchy-shell panel plugin (SudokuPanel.qml).
    property bool embedded: false
    signal quitRequested()

    visible: !root.embedded
    implicitWidth: 580
    implicitHeight: 900
    minimumSize: Qt.size(540, 850)
    title: "vim-sudoku"
    color: tBackground

    // ---- Live theme: every color is a property with a crossfade Behavior ----
    property color tBackground: Theme.defaults().background
    property color tForeground: Theme.defaults().foreground
    property color tBright: Theme.defaults().bright
    property color tMuted: Theme.defaults().muted
    property color tSelection: Theme.defaults().selection
    property color tAccent: Theme.defaults().accent
    property color tGreen: Theme.defaults().green
    property color tBlue: Theme.defaults().blue
    property color tYellow: Theme.defaults().yellow
    property color tRed: Theme.defaults().red
    property bool tIsLight: false
    property string tName: ""
    property string lastTheme: ""

    Behavior on tBackground { ColorAnimation { duration: 400 } }
    Behavior on tForeground { ColorAnimation { duration: 400 } }
    Behavior on tBright { ColorAnimation { duration: 400 } }
    Behavior on tMuted { ColorAnimation { duration: 400 } }
    Behavior on tSelection { ColorAnimation { duration: 400 } }
    Behavior on tAccent { ColorAnimation { duration: 400 } }
    Behavior on tGreen { ColorAnimation { duration: 400 } }
    Behavior on tBlue { ColorAnimation { duration: 400 } }
    Behavior on tYellow { ColorAnimation { duration: 400 } }
    Behavior on tRed { ColorAnimation { duration: 400 } }

    function onAccent() {
        return tIsLight ? tForeground : tBackground;
    }

    property string themePath: Quickshell.env("VIM_SUDOKU_THEME")
        || (Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml")

    property FileView themeFile: FileView {
        path: root.themePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyTheme(Theme.parseColors(text()))
        onFileChanged: reload()
    }

    property FileView themeNameFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onLoaded: root.applyName(String(text()).trim())
        onFileChanged: reload()
    }

    function applyName(n) {
        if (n && tName !== n) {
            if (tName !== "") {
                game.message = "theme updated: " + n;
                lastTheme = n;
                refresh();
            }
            tName = n;
        }
    }

    function reloadThemeNow() {
        themeFile.reload();
        themeNameFile.reload();
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            themeFile.reload();
            themeNameFile.reload();
        }
    }

    function applyTheme(t) {
        tBackground = t.background;
        tForeground = t.foreground;
        tBright = t.bright;
        tMuted = t.muted;
        tSelection = t.selection;
        tAccent = t.accent;
        tGreen = t.green;
        tBlue = t.blue;
        tYellow = t.yellow;
        tRed = t.red;
        tIsLight = t.isLight;
    }

    // ---- Clock: runs while focused, pauses when unfocused or hidden ----
    property int clock: 0
    readonly property bool appFocused: visible && Qt.application.state === Qt.ApplicationActive
    onAppFocusedChanged: {
        // Lost focus with Space held: the release went to another window
        // — don't leave INSERT stuck.
        if (!appFocused) {
            spaceHeld = false;
            if (game.mode === "insert")
                Game.enterNormal(game);
        } else {
            keyboard.forceActiveFocus();
        }
        refresh();
    }

    function gameElapsed() {
        var t = game.elapsedMs;
        if (game.runningSince > 0)
            t += Math.max(0, Date.now() - game.runningSince);
        return t;
    }

    function syncClock() {
        var live = game && !game.won && !game.gameover;
        if (live && appFocused) {
            if (!game.runningSince)
                game.runningSince = Date.now();
        } else if (game.runningSince) {
            game.elapsedMs += Math.max(0, Date.now() - game.runningSince);
            game.runningSince = 0;
        }
    }

    function pauseGame() {
        if (game.runningSince) {
            game.elapsedMs += Math.max(0, Date.now() - game.runningSince);
            game.runningSince = 0;
        }
    }

    function quitGame() {
        pauseGame();
        persistSlots();
        try {
            saveFile.waitForJob();
        } catch (e) {}
        // The host decides what quitting means: the standalone shell exits, the
        // omarchy-shell plugin closes its panel.
        quitRequested();
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        property int n: 0
        onTriggered: {
            n++;
            var was = game.runningSince;
            syncClock();
            if ((was && !game.runningSince) || (game.runningSince && n % 60 === 0))
                persistSlots();
            clock++;
        }
    }

    // ---- Save: JSON at ~/.local/state/vim-sudoku/slots.json ----
    property string savePath: Quickshell.env("HOME") + "/.local/state/vim-sudoku/slots.json"
    property FileView corruptSaveFile: FileView {
        watchChanges: false
        printErrors: false
        atomicWrites: true
        onSaved: root.bootFresh()
        onSaveFailed: {
            root.game.message = "save damaged; could not create backup";
            root.rev++;
        }
    }
    property var saveFile: FileView {
        path: root.savePath
        watchChanges: false
        printErrors: false
        atomicWrites: true
        onLoaded: root.loadLibrary(text())
        onLoadFailed: root.bootFresh()
    }

    function loadLibrary(raw) {
        try {
            bootFromLibrary(JSON.parse(raw));
        } catch (e) {
            // Keep the damaged save before starting a new library.
            try {
                corruptSaveFile.path = savePath + ".corrupt-" + Date.now();
                corruptSaveFile.setText(raw);
            } catch (backupError) {
                game.message = "save damaged; could not create backup";
                rev++;
            }
        }
    }

    property var game: Game.newState()
    property int rev: 0
    property int hoverCell: -1
    property string monoFont: "JetBrainsMono Nerd Font"
    property var library: ({active: null, order: [], games: ({})})
    property bool libraryReady: false
    property bool gamesOpen: false
    property int panelIndex: 0
    property bool spaceHeld: false // Space held = momentary INSERT

    function refresh() {
        rev++;
        syncClock();
        if (game.won) {
            if (game.id && library.games[game.id]) {
                delete library.games[game.id];
                library.order = library.order.filter(function (id) { return id !== game.id; });
                if (library.active === game.id)
                    library.active = null;
            }
        } else if (game.id) {
            library.games[game.id] = Game.serialize(game);
        }
        persistSlots();
    }

    function persistSlots() {
        if (!libraryReady)
            return;
        try {
            var dump = {
                active: library.active,
                order: library.order,
                games: library.games,
                lastTheme: lastTheme,
                lastDifficulty: library.lastDifficulty || "medium"
            };
            saveFile.setText(JSON.stringify(dump));
        } catch (e) {}
    }

    function bootFromLibrary(lib) {
        try {
            if (lib && Array.isArray(lib.order) && lib.games) {
                var order = [];
                for (var i = 0; i < lib.order.length; i++) {
                    var id = lib.order[i];
                    if (lib.games[id] && Game.deserialize(lib.games[id]))
                        order.push(id);
                }
                library = {active: lib.active, order: order, games: lib.games};
                lastTheme = lib.lastTheme || "";
                library.lastDifficulty = validDiff(lib.lastDifficulty);
                if (library.active && library.games[library.active]) {
                    var st = Game.deserialize(library.games[library.active]);
                    if (st) {
                        game = st;
                        game.message = "welcome back! (g = switch game)";
                        themeFile.reload();
                        libraryReady = true;
                        refresh();
                        return;
                    }
                    library.active = null;
                }
            }
        } catch (e) {}
        bootFresh();
    }

    function bootFresh() {
        library = {active: null, order: [], games: ({})};
        libraryReady = true;
        newGameSlot();
    }

    function nextGameName() {
        var max = 0;
        for (var i = 0; i < library.order.length; i++) {
            var nm = String((library.games[library.order[i]] || {}).name || "");
            var m = /(?:Jogo|Game) (\d+)/.exec(nm);
            if (m && +m[1] > max)
                max = +m[1];
        }
        return "Game " + (max + 1);
    }

    function difficultyLabel(diff) {
        return diff === "easy" ? "easy" : (diff === "hard" ? "hard" : "medium");
    }

    function validDiff(diff) {
        return diff === "easy" || diff === "hard" ? diff : "medium";
    }

    function newGameSlot(diff) {
        diff = validDiff(diff || library.lastDifficulty);
        library.lastDifficulty = diff;
        pauseGame();
        if (game.id)
            library.games[game.id] = Game.serialize(game);
        var st = Game.newState(undefined, undefined, diff);
        st.id = "g" + Date.now();
        st.name = nextGameName();
        st.createdAt = Date.now();
        st.message = "new " + difficultyLabel(diff) + " game! good luck";
        library.games[st.id] = Game.serialize(st);
        library.order.push(st.id);
        library.active = st.id;
        game = st;
        gamesOpen = false;
        refresh();
    }

    function switchSlot(id) {
        if (!library.games[id])
            return;
        pauseGame();
        if (game.id)
            library.games[game.id] = Game.serialize(game);
        library.active = id;
        var st = Game.deserialize(library.games[id]);
        if (st) {
            game = st;
            game.message = "back to " + (st.name || "game");
        }
        gamesOpen = false;
        refresh();
    }

    function deleteSlot(id) {
        delete library.games[id];
        library.order = library.order.filter(function (k) { return k !== id; });
        if (library.active === id) {
            library.active = null;
            if (library.order.length > 0)
                switchSlot(library.order[library.order.length - 1]);
            else
                newGameSlot();
        } else {
            if (panelIndex >= library.order.length)
                panelIndex = Math.max(0, library.order.length - 1);
            persistSlots();
            refresh();
        }
    }

    function openGames() {
        panelIndex = Math.max(0, library.order.indexOf(library.active));
        gamesOpen = true;
        refresh();
    }

    function slotRows(r) {
        if (r < 0)
            return [];
        var rows = [];
        for (var i = 0; i < library.order.length; i++) {
            var id = library.order[i];
            var st = Game.deserialize(library.games[id]);
            if (!st)
                continue;
            var p = Game.progress(st);
            rows.push({
                id: id,
                name: st.name || ("Game " + (i + 1)),
                diff: difficultyLabel(st.difficulty),
                time: Game.formatElapsed(st.elapsedMs),
                pct: Math.round(100 * p.done / p.total),
                mistakes: st.mistakes,
                active: id === library.active
            });
        }
        return rows;
    }

    function rowOf(i) { return Math.floor(i / 9); }
    function colOf(i) { return i % 9; }

    function isCursor(i, r) {
        if (r < 0)
            return false;
        return rowOf(i) === game.cy && colOf(i) === game.cx;
    }

    function cursorValue(r) {
        if (r < 0) return 0;
        var c = game.grid[game.cy][game.cx];
        return c.value;
    }

    function cellBg(i, r) {
        if (r < 0)
            return "transparent";
        var y = rowOf(i), x = colOf(i);
        var c = game.grid[y][x];

        // Main cursor: fill in the color of the active mode (the floating
        // frame sits on top, so keep this subdued)
        if (x === game.cx && y === game.cy) {
            var mc = root.modeColor(r);
            return Qt.rgba(mc.r, mc.g, mc.b, 0.25);
        }

        // Cells holding the same number as the cursor: soft shading in tSelection
        var cv = cursorValue(r);
        if (c.value !== 0 && cv !== 0 && c.value === cv)
            return Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.85);

        // Same row, same column or same 3x3 box: soft crosshair
        var sameBox = Math.floor(x / 3) === Math.floor(game.cx / 3) &&
                      Math.floor(y / 3) === Math.floor(game.cy / 3);
        if (x === game.cx || y === game.cy || sameBox)
            return Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.35);

        // Base board look: alternating 3x3 boxes get a faint tint
        var evenBox = (Math.floor(x / 3) + Math.floor(y / 3)) % 2 === 0;
        return evenBox ? Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.07) : "transparent";
    }

    function cellBorderColor(i, r) {
        return "transparent";
    }

    function cellBorderWidth(i, r) {
        return 0;
    }

    function valueColor(i, r) {
        if (r < 0)
            return tForeground;
        var y = rowOf(i), x = colOf(i);
        var c = game.grid[y][x];
        if (Game.isWrong(game, x, y))
            return onAccent();
        // Active cursor cell: maximum contrast against tBright
        if (x === game.cx && y === game.cy)
            return tBright;
        // Cells with the same number: subtle emphasis in tAccent
        var cv = cursorValue(r);
        if (c.value !== 0 && cv !== 0 && c.value === cv)
            return tAccent;
        if (c.given)
            return tBright;
        return tGreen;
    }

    function valueBold(i, r) {
        if (r < 0)
            return false;
        var y = rowOf(i), x = colOf(i);
        var c = game.grid[y][x];
        if (c.given || Game.isWrong(game, x, y))
            return true;
        var cv = cursorValue(r);
        return c.value !== 0 && cv !== 0 && c.value === cv;
    }

    function cellWrong(i, r) {
        if (r < 0)
            return false;
        return Game.isWrong(game, colOf(i), rowOf(i));
    }

    function isNormal(r) {
        return r >= 0 && game.mode === "normal";
    }

    function modeColor(r) {
        return isNormal(r) ? tBlue : tGreen;
    }

    function modeLabel(r) {
        if (r < 0)
            return "NORMAL";
        return isNormal(r) ? "NORMAL" : "INSERT";
    }

    function isWon(r) {
        return r >= 0 && game.won;
    }

    function isGameover(r) {
        return r >= 0 && game.gameover;
    }

    function wonStats(r) {
        if (r < 0)
            return "";
        root.clock;
        return game.moves + " moves · " + game.mistakes + "/3 mistakes · time: " + Game.formatElapsed(gameElapsed());
    }

    function overStats(r) {
        if (r < 0)
            return "";
        root.clock;
        return "3 mistakes made · " + game.moves + " moves · time: " + Game.formatElapsed(gameElapsed());
    }

    function helpText(r) {
        if (r < 0)
            return "";
        return isNormal(r)
            ? "NORMAL: h j k l move · 1-9 notes · x/d clears · u/r undo/redo · hold Space to insert"
            : "INSERT: 1-9 fills · x/d/0 erases · Ctrl+R redoes · release Space for normal";
    }

    function palLabel(r) {
        if (r < 0)
            return "";
        return isNormal(r) ? "click a number to take NOTES (pencil)" : "click a number to FILL the cell";
    }

    function cellHasValue(i, r) {
        if (r < 0)
            return false;
        return game.grid[rowOf(i)][colOf(i)].value !== 0;
    }

    function cellValueText(i, r) {
        if (r < 0)
            return "";
        return String(game.grid[rowOf(i)][colOf(i)].value);
    }

    function cellHasNotes(i, r) {
        if (r < 0)
            return false;
        var c = game.grid[rowOf(i)][colOf(i)];
        return c.value === 0 && Game.notesString(c) !== "";
    }

    function noteText(cellI, n, r) {
        if (r < 0)
            return "";
        var c = game.grid[rowOf(cellI)][colOf(cellI)];
        return c.notes[n] ? String(n + 1) : "";
    }

    function noteColor(cellI, n, r) {
        if (r < 0)
            return tMuted;
        var y = rowOf(cellI), x = colOf(cellI);
        if (!Game.noteValid(game, x, y, n + 1))
            return tRed;
        var cv = cursorValue(r);
        if (cv > 0 && (n + 1) === cv)
            return tAccent;
        return tMuted;
    }

    function noteValidAt(cellI, n, r) {
        if (r < 0)
            return true;
        return Game.noteValid(game, colOf(cellI), rowOf(cellI), n + 1);
    }

    function remainingText(n, r) {
        if (r < 0)
            return "";
        return String(Game.remainingCounts(game)[n]);
    }

    function remainingColor(n, r) {
        if (r < 0)
            return tMuted;
        var count = Game.remainingCounts(game)[n];
        return count === 0 ? tGreen : (count <= 2 ? tYellow : tMuted);
    }

    function selectCell(i) {
        game.cx = colOf(i);
        game.cy = rowOf(i);
        refresh();
    }

    function playNumber(n) {
        if (game.mode === "normal")
            Game.toggleNote(game, n);
        else
            Game.tryPlace(game, n);
        refresh();
    }

    function statusText(r) {
        if (r < 0)
            return "";
        root.clock;
        var c = game.grid[game.cy][game.cx];
        var n = Game.notesString(c);
        return "r" + (game.cy + 1) + " c" + (game.cx + 1)
            + "  |  " + Game.formatElapsed(gameElapsed())
            + "  |  " + difficultyLabel(game.difficulty)
            + "  |  notes: " + (n === "" ? "-" : n)
            + "  |  moves: " + game.moves + "  mistakes: " + game.mistakes + "/3"
            + "  |  " + game.message;
    }

    function statusMessage(r) {
        if (r < 0)
            return "";
        var c = game.grid[game.cy][game.cx];
        var n = Game.notesString(c);
        if (n !== "")
            return "notes: " + n + (game.message ? "  ·  " + game.message : "");
        return game.message || "ready";
    }

    function statusProgress(r) {
        if (r < 0)
            return "";
        var p = Game.progress(game);
        return p.done + "/81 (" + Math.round(100 * p.done / p.total) + "%)";
    }

    function progressRatio(r) {
        if (r < 0)
            return 0;
        var p = Game.progress(game);
        return p.total > 0 ? p.done / p.total : 0;
    }

    Component.onCompleted: {
        Qt.callLater(function () { if (root.visible) keyboard.forceActiveFocus(); });
    }

    // =========================================================================
    // MAIN LAYOUT (centered and harmonious)
    // =========================================================================
    Column {
        width: 512
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // 1. TOP HEADER — brand on the left, live stats on the right
        Item {
            width: parent.width
            height: 42

            // Brand: logo badge + title + current theme
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    width: 42
                    height: 42
                    radius: 11
                    color: Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.16)
                    border.color: Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.5)
                    border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        text: "\ue7c5"
                        font.family: root.monoFont
                        font.pixelSize: 21
                        font.bold: true
                        color: tAccent
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "S U D O K U"
                        font.family: root.monoFont
                        font.bold: true
                        font.pixelSize: 14
                        font.letterSpacing: 1.5
                        color: tBright
                    }
                    Text {
                        text: root.tName !== "" ? "theme: " + root.tName : "vim motions"
                        font.family: root.monoFont
                        font.pixelSize: 9
                        color: tMuted
                    }
                }
            }

            // Stats cluster, right aligned
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Difficulty level
                Rectangle {
                    width: 66
                    height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: diffMouse.containsMouse ? tSelection : Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.3)
                    border.color: diffMouse.containsMouse ? tForeground : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: root.difficultyLabel(game.difficulty)
                        font.family: root.monoFont
                        font.bold: true
                        font.pixelSize: 11
                        color: tForeground
                    }
                    MouseArea {
                        id: diffMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.openGames()
                    }
                }

                // Clock with a paused state
                Rectangle {
                    width: 90
                    height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.3)
                    border.color: root.appFocused ? Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.3) : Qt.rgba(tYellow.r, tYellow.g, tYellow.b, 0.5)
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            text: root.appFocused ? "⏱" : "⏸"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: root.appFocused ? tAccent : tYellow
                        }
                        Text {
                            text: {
                                root.clock;
                                return Game.formatElapsed(root.gameElapsed());
                            }
                            font.family: root.monoFont
                            font.bold: true
                            font.pixelSize: 12
                            color: root.appFocused ? tBright : tMuted
                        }
                    }
                }

                // Mistake / life indicator
                Rectangle {
                    width: 58
                    height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.3)
                    border.color: { root.rev; return game.mistakes > 0 ? Qt.rgba(tRed.r, tRed.g, tRed.b, 0.5) : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.3); }
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: 3
                            Text {
                                text: { root.rev; return model.index < game.mistakes ? "✕" : "♥"; }
                                font.family: root.monoFont
                                font.pixelSize: 10
                                color: { root.rev; return model.index < game.mistakes ? tRed : (game.mistakes === 0 ? tGreen : tMuted); }
                            }
                        }
                    }
                }

                // Game library button (g)
                Rectangle {
                    width: 72
                    height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: gamesMouse.containsMouse ? tSelection : "transparent"
                    border.color: gamesMouse.containsMouse ? tAccent : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.4)
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "games g"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: gamesMouse.containsMouse ? tBright : tForeground
                    }
                    MouseArea {
                        id: gamesMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.openGames()
                    }
                }
            }
        }

        // 2. SUDOKU BOARD — card floating on a soft drop shadow
        Item {
            width: 512
            height: 512
            anchors.horizontalCenter: parent.horizontalCenter

            // Soft drop shadow under the card
            Rectangle {
                x: -3
                y: 7
                width: 518
                height: 512
                radius: 15
                color: Qt.rgba(0, 0, 0, tIsLight ? 0.15 : 0.35)
            }

            Rectangle {
                id: boardCard
                width: 512
                height: 512
                radius: 14
                color: Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.22)
                border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                border.width: 1

                Grid {
                    id: cellGrid
                    anchors.centerIn: parent
                    columns: 9
                    rows: 9

                    Repeater {
                        model: 81
                        delegate: Item {
                            id: cell
                            width: 56
                            height: 56
                            property int cellIndex: index
                            property int cx: colOf(index)
                            property int cy: rowOf(index)
                            property bool ready: false
                            Component.onCompleted: ready = true

                            // Cell background (box tint, crosshair, same value or cursor)
                            Rectangle {
                                anchors.fill: parent
                                color: root.cellBg(cellIndex, root.rev)
                            }

                            // Highlight ring for other cells with the same number (not the cursor)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 40
                                height: 40
                                radius: 20
                                visible: {
                                    if (root.isCursor(cellIndex, root.rev)) return false;
                                    var cv = root.cursorValue(root.rev);
                                    var val = root.game.grid[cy][cx].value;
                                    return cv !== 0 && val !== 0 && val === cv;
                                }
                                color: Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.12)
                                border.color: Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.45)
                                border.width: 1
                            }

                            // Cell with a mistake: red chip
                            Rectangle {
                                anchors.centerIn: parent
                                width: 44
                                height: 44
                                radius: 10
                                visible: root.cellWrong(cellIndex, root.rev)
                                color: root.tRed
                            }

                            // Value placed in the cell (pops in with a scale bounce)
                            Text {
                                id: valText
                                anchors.centerIn: parent
                                visible: root.cellHasValue(cellIndex, root.rev)
                                text: root.cellValueText(cellIndex, root.rev)
                                font.family: root.monoFont
                                font.pixelSize: 25
                                font.bold: root.valueBold(cellIndex, root.rev)
                                color: root.valueColor(cellIndex, root.rev)
                                onTextChanged: {
                                    if (ready && valText.text !== "")
                                        popAnim.restart();
                                }
                            }

                            // Pop-in when a number lands on the cell
                            SequentialAnimation {
                                id: popAnim
                                NumberAnimation { target: valText; property: "scale"; from: 0.4; to: 1.18; duration: 110; easing.type: Easing.OutCubic }
                                NumberAnimation { target: valText; property: "scale"; to: 1.0; duration: 130; easing.type: Easing.InOutQuad }
                            }

                            // Notes laid out in a tidy 3x3 grid
                            Grid {
                                anchors.centerIn: parent
                                columns: 3
                                rows: 3
                                visible: root.cellHasNotes(cellIndex, root.rev)
                                Repeater {
                                    model: 9
                                    Item {
                                        width: 17
                                        height: 15
                                        property bool hasNote: root.noteText(cellIndex, model.index, root.rev) !== ""
                                        property bool badNote: hasNote && !root.noteValidAt(cellIndex, model.index, root.rev)

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 15
                                            height: 13
                                            radius: 3
                                            visible: parent.badNote
                                            color: Qt.rgba(tRed.r, tRed.g, tRed.b, 0.25)
                                            border.color: Qt.rgba(tRed.r, tRed.g, tRed.b, 0.6)
                                            border.width: 1
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.noteText(cellIndex, model.index, root.rev)
                                            font.family: root.monoFont
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: parent.badNote ? tRed : root.noteColor(cellIndex, model.index, root.rev)
                                        }
                                    }
                                }
                            }

                            // Subtle mouse hover
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.color: Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.4)
                                border.width: 1.5
                                radius: 4
                                visible: root.hoverCell === cellIndex && !root.isCursor(cellIndex, root.rev)
                            }

                            // Inner vertical separator (thick on the 3x3 box, thin elsewhere)
                            Rectangle {
                                anchors.right: parent.right
                                visible: cx < 8
                                width: (cx === 2 || cx === 5) ? 2.5 : 1
                                height: parent.height
                                color: (cx === 2 || cx === 5)
                                    ? Qt.rgba(tForeground.r, tForeground.g, tForeground.b, 0.45)
                                    : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.22)
                            }

                            // Inner horizontal separator (thick on the 3x3 box, thin elsewhere)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                visible: cy < 8
                                height: (cy === 2 || cy === 5) ? 2.5 : 1
                                width: parent.width
                                color: (cy === 2 || cy === 5)
                                    ? Qt.rgba(tForeground.r, tForeground.g, tForeground.b, 0.45)
                                    : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.22)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onEntered: root.hoverCell = cellIndex
                                onExited: root.hoverCell = -1
                                onClicked: (mouse) => {
                                    root.selectCell(cellIndex);
                                    if (mouse.button === Qt.RightButton)
                                        Game.clearCell(game);
                                    root.refresh();
                                }
                                onDoubleClicked: {
                                    Game.enterInsert(game, false);
                                    root.refresh();
                                }
                            }
                        }
                    }
                }

                // Vim cursor: one floating frame that slides between cells
                Item {
                    id: cursorLayer
                    z: 20
                    width: 56
                    height: 56
                    property int cellX: { root.rev; return game.cx * 56; }
                    property int cellY: { root.rev; return game.cy * 56; }
                    x: cellGrid.x + cellX
                    y: cellGrid.y + cellY

                    Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                    // Soft glow behind the frame
                    Rectangle {
                        anchors.centerIn: parent
                        width: 66
                        height: 66
                        radius: 10
                        color: {
                            var mc = root.modeColor(root.rev);
                            return Qt.rgba(mc.r, mc.g, mc.b, 0.16);
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "transparent"
                        border.color: root.modeColor(root.rev)
                        border.width: 3
                    }
                }
            }
        }

        // 3. VIM-STYLE STATUS BAR (Lualine / Neovim) with progress line
        Rectangle {
            width: parent.width
            height: 38
            radius: 9
            color: Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.5)
            border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.25)
            border.width: 1
            clip: true

            // Completion progress along the bottom edge
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: 3
                width: parent.width * root.progressRatio(root.rev)
                color: root.modeColor(root.rev)
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 5
                anchors.rightMargin: 10
                anchors.bottomMargin: 3
                spacing: 8

                // Mode pill (Normal/Insert)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: 86
                    radius: 6
                    color: root.modeColor(root.rev)
                    Text {
                        anchors.centerIn: parent
                        text: root.modeLabel(root.rev)
                        font.family: root.monoFont
                        font.bold: true
                        font.pixelSize: 11
                        color: onAccent()
                    }
                }

                // Cursor coordinates rX:cY
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: 58
                    radius: 6
                    color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.35)
                    Text {
                        anchors.centerIn: parent
                        text: { root.rev; return "r" + (game.cy + 1) + ":c" + (game.cx + 1); }
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: tForeground
                    }
                }

                // Contextual message / feedback
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 264
                    elide: Text.ElideRight
                    text: root.statusMessage(root.rev)
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: tBright
                }

                // Fill progress
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: 96
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.statusProgress(root.rev)
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: tMuted
                    }
                }
            }
        }

        // 4. NUMBER PALETTE AND COUNTERS (1 to 9) — keycap style
        Column {
            width: parent.width
            spacing: 8

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.modeColor(root.rev)
                }
                Text {
                    text: root.isNormal(root.rev) ? "NOTES (1-9)" : "PLAY NUMBER (1-9)"
                    font.family: root.monoFont
                    font.bold: true
                    font.pixelSize: 11
                    color: root.modeColor(root.rev)
                }
                Text {
                    text: "·"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: tMuted
                }
                Text {
                    text: root.isNormal(root.rev) ? "click to note (pencil)" : "click to fill the cell"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: tMuted
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                Repeater {
                    model: 9
                    Rectangle {
                        id: numKey
                        property int num: model.index + 1
                        property int rem: { root.rev; return Game.remainingCounts(game)[model.index]; }
                        property bool isDone: rem === 0
                        property bool isMatchingCursor: cursorValue(root.rev) === num

                        width: 50
                        height: 58
                        radius: 10
                        color: numMouse.containsMouse
                            ? tSelection
                            : (isDone
                                ? Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.15)
                                : (isMatchingCursor
                                    ? Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.2)
                                    : Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.32)))
                        border.color: isMatchingCursor
                            ? tAccent
                            : (isDone
                                ? Qt.rgba(tGreen.r, tGreen.g, tGreen.b, 0.35)
                                : (numMouse.containsMouse ? tForeground : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)))
                        border.width: isMatchingCursor ? 2 : 1

                        // Keycap depth
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            anchors.bottomMargin: 3
                            height: 3
                            radius: 1.5
                            color: Qt.rgba(0, 0, 0, 0.22)
                            visible: !numKey.isDone
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String(numKey.num)
                                font.family: root.monoFont
                                font.pixelSize: 20
                                font.bold: true
                                color: numKey.isDone ? tMuted : (numKey.isMatchingCursor ? tAccent : tBright)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: numKey.isDone ? "✓" : String(numKey.rem)
                                font.family: root.monoFont
                                font.pixelSize: 10
                                font.bold: numKey.isDone
                                color: numKey.isDone ? tGreen : (numKey.rem <= 2 ? tYellow : tMuted)
                            }
                        }

                        MouseArea {
                            id: numMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.playNumber(numKey.num)
                        }
                    }
                }
            }
        }

        // 5. QUICK ACTION BUTTONS — keycap ghost style
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Clear
            Rectangle {
                width: 96
                height: 38
                radius: 9
                color: actMouseX.containsMouse ? tSelection : Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.28)
                border.color: actMouseX.containsMouse ? tForeground : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                border.width: 1
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 5
                        color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.45)
                        border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "x"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.bold: true
                            color: tForeground
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "clear"
                        font.family: root.monoFont
                        font.pixelSize: 12
                        color: tForeground
                    }
                }
                MouseArea {
                    id: actMouseX
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { Game.clearCell(game); root.refresh(); }
                }
            }

            // Undo
            Rectangle {
                width: 108
                height: 38
                radius: 9
                property bool canUndo: { root.rev; return game.undo && game.undo.length > 0; }
                opacity: canUndo ? 1.0 : 0.45
                color: actMouseU.containsMouse ? tSelection : Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.28)
                border.color: actMouseU.containsMouse ? tForeground : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                border.width: 1
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 5
                        color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.45)
                        border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "u"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.bold: true
                            color: tForeground
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "undo"
                        font.family: root.monoFont
                        font.pixelSize: 12
                        color: tForeground
                    }
                }
                MouseArea {
                    id: actMouseU
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { Game.doUndo(game); root.refresh(); }
                }
            }

            // Redo
            Rectangle {
                width: 104
                height: 38
                radius: 9
                property bool canRedo: { root.rev; return game.redo && game.redo.length > 0; }
                opacity: canRedo ? 1.0 : 0.45
                color: actMouseR.containsMouse ? tSelection : Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.28)
                border.color: actMouseR.containsMouse ? tForeground : Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                border.width: 1
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 5
                        color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.45)
                        border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "r"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.bold: true
                            color: tForeground
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "redo"
                        font.family: root.monoFont
                        font.pixelSize: 12
                        color: tForeground
                    }
                }
                MouseArea {
                    id: actMouseR
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { Game.doRedo(game); root.refresh(); }
                }
            }

            // Mode indicator: INSERT is momentary (Space held)
            Rectangle {
                width: 176
                height: 38
                radius: 9
                color: root.modeColor(root.rev)
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        height: 20
                        radius: 5
                        color: Qt.rgba(0, 0, 0, 0.25)
                        Text {
                            anchors.centerIn: parent
                            text: "Space"
                            font.family: root.monoFont
                            font.bold: true
                            font.pixelSize: 10
                            color: onAccent()
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isNormal(root.rev) ? "hold → INSERT" : "release → NORMAL"
                        font.family: root.monoFont
                        font.bold: true
                        font.pixelSize: 11
                        color: onAccent()
                    }
                }
            }
        }

        // 6. KEY CHEATSHEET (keycap footer)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
                model: [
                    { key: "hjkl", desc: "move" },
                    { key: "Space", desc: "insert" },
                    { key: "1-9", desc: "note/play" },
                    { key: "u", desc: "undo" },
                    { key: "r", desc: "redo" },
                    { key: "g", desc: "games" },
                    { key: "q", desc: "quit" }
                ]
                Row {
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 19
                        width: keyText.implicitWidth + 10
                        radius: 4
                        color: Qt.rgba(tSelection.r, tSelection.g, tSelection.b, 0.45)
                        border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.35)
                        border.width: 1
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            height: 2
                            radius: 1
                            color: Qt.rgba(0, 0, 0, 0.25)
                        }
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -1
                            text: modelData.key
                            font.family: root.monoFont
                            font.pixelSize: 10
                            font.bold: true
                            color: tForeground
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.desc
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: tMuted
                    }
                }
            }
        }
    }

    // =========================================================================
    // OVERLAYS / MODALS
    // =========================================================================

    // Victory overlay
    Rectangle {
        anchors.fill: parent
        visible: root.isWon(root.rev)
        color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.88)

        // Drop shadow
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            width: 452
            height: 278
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.35)
        }

        Rectangle {
            anchors.centerIn: parent
            width: 452
            height: 278
            radius: 18
            color: tSelection
            border.color: Qt.rgba(tGreen.r, tGreen.g, tGreen.b, 0.55)
            border.width: 1.5

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "🏆"
                    font.family: root.monoFont
                    font.pixelSize: 34
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Puzzle complete!"
                    font.family: root.monoFont
                    font.bold: true
                    font.pixelSize: 21
                    color: tGreen
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.wonStats(root.rev)
                    font.family: root.monoFont
                    font.pixelSize: 12
                    color: tForeground
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Rectangle {
                        width: 152
                        height: 38
                        radius: 9
                        color: tAccent
                        Text {
                            anchors.centerIn: parent
                            text: "new game (n)"
                            font.family: root.monoFont
                            font.bold: true
                            font.pixelSize: 13
                            color: onAccent()
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.newGameSlot()
                        }
                    }
                    Rectangle {
                        width: 116
                        height: 38
                        radius: 9
                        color: "transparent"
                        border.color: tMuted
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "quit (q)"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            color: tForeground
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.quitGame()
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "n — new game    ·    q — quit"
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: tMuted
                }
            }
        }
    }

    // Game over overlay (3 mistakes)
    Rectangle {
        anchors.fill: parent
        visible: root.isGameover(root.rev)
        color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.88)

        // Drop shadow
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            width: 464
            height: 282
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.35)
        }

        Rectangle {
            anchors.centerIn: parent
            width: 464
            height: 282
            radius: 18
            color: tSelection
            border.color: Qt.rgba(tRed.r, tRed.g, tRed.b, 0.55)
            border.width: 1.5

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "💀"
                    font.family: root.monoFont
                    font.pixelSize: 34
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Game over"
                    font.family: root.monoFont
                    font.bold: true
                    font.pixelSize: 21
                    color: tRed
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.overStats(root.rev)
                    font.family: root.monoFont
                    font.pixelSize: 12
                    color: tForeground
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Rectangle {
                        width: 150
                        height: 38
                        radius: 9
                        color: tAccent
                        Text {
                            anchors.centerIn: parent
                            text: "try again"
                            font.family: root.monoFont
                            font.bold: true
                            font.pixelSize: 13
                            color: onAccent()
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { Game.retryPuzzle(game); root.refresh(); }
                        }
                    }
                    Rectangle {
                        width: 130
                        height: 38
                        radius: 9
                        color: "transparent"
                        border.color: tMuted
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "new game"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            color: tForeground
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.newGameSlot()
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Enter retries · n new · g others · q quits"
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: tMuted
                }
            }
        }
    }

    // Game library panel (g)
    Rectangle {
        anchors.fill: parent
        visible: gamesOpen
        color: Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.9)

        // Drop shadow
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            width: libPanel.width
            height: libPanel.height
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.35)
        }

        Rectangle {
            id: libPanel
            anchors.centerIn: parent
            width: 500
            height: Math.min(560, parent.height - 40)
            radius: 16
            color: tSelection
            border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.4)
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Item {
                    width: parent.width
                    height: 20
                    Text {
                        anchors.left: parent.left
                        text: "GAME LIBRARY"
                        font.family: root.monoFont
                        font.bold: true
                        font.pixelSize: 15
                        font.letterSpacing: 2
                        color: tBright
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: { root.rev; return String(library.order.length) + " saved"; }
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: tMuted
                    }
                }
                Text {
                    text: "j/k navigates · Enter opens · d deletes · n new · 1/2/3 difficulty · Esc closes"
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: tMuted
                }

                Item {
                    width: parent.width
                    height: 236
                    ListView {
                        anchors.fill: parent
                        clip: true
                        model: root.slotRows(root.rev)
                        spacing: 5
                        delegate: Row {
                            width: parent.width
                            spacing: 6
                            property string rowId: modelData.id
                            property int rowIdx: index

                            Rectangle {
                                width: parent.width - 46
                                height: 42
                                radius: 8
                                color: rowIdx === root.panelIndex ? Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.16) : Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.5)
                                border.color: modelData.active ? Qt.rgba(tAccent.r, tAccent.g, tAccent.b, 0.8) : "transparent"
                                border.width: modelData.active ? 1 : 0

                                // Selection marker on the left edge
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 20
                                    radius: 1.5
                                    color: tAccent
                                    visible: rowIdx === root.panelIndex
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.active ? "▶" : " "
                                        font.family: root.monoFont
                                        font.pixelSize: 10
                                        color: tAccent
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name
                                        font.family: root.monoFont
                                        font.bold: true
                                        font.pixelSize: 13
                                        color: tBright
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 20
                                        width: 56
                                        radius: 5
                                        color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.2)
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.diff
                                            font.family: root.monoFont
                                            font.pixelSize: 10
                                            color: tForeground
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.pct + "%"
                                        font.family: root.monoFont
                                        font.pixelSize: 11
                                        font.bold: modelData.pct >= 80
                                        color: tGreen
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.time
                                        font.family: root.monoFont
                                        font.pixelSize: 11
                                        color: tMuted
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.panelIndex = rowIdx
                                    onClicked: root.switchSlot(rowId)
                                }
                            }

                            Rectangle {
                                width: 40
                                height: 42
                                radius: 8
                                color: delMouse.containsMouse ? Qt.rgba(tRed.r, tRed.g, tRed.b, 0.18) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    font.family: root.monoFont
                                    font.pixelSize: 13
                                    color: delMouse.containsMouse ? tRed : tMuted
                                }
                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.deleteSlot(rowId)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 38
                    radius: 9
                    color: tAccent
                    Text {
                        anchors.centerIn: parent
                        text: "+ new game   (n)"
                        font.family: root.monoFont
                        font.bold: true
                        font.pixelSize: 13
                        color: onAccent()
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.newGameSlot()
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Repeater {
                        model: [
                            {key: "easy", label: "easy (1)"},
                            {key: "medium", label: "medium (2)"},
                            {key: "hard", label: "hard (3)"}
                        ]
                        Rectangle {
                            width: 132
                            height: 34
                            radius: 8
                            color: difMouse.containsMouse ? tSelection : Qt.rgba(tBackground.r, tBackground.g, tBackground.b, 0.4)
                            border.color: Qt.rgba(tMuted.r, tMuted.g, tMuted.b, 0.4)
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: root.monoFont
                                font.pixelSize: 11
                                color: tForeground
                            }
                            MouseArea {
                                id: difMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.newGameSlot(modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // KEYBOARD (vim navigation and modes)
    // =========================================================================
    Item {
        id: keyboard
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            var g = game;
            var ctrl = (event.modifiers & Qt.ControlModifier);
            if (ctrl && (event.key === Qt.Key_Q || event.key === Qt.Key_C)) {
                root.quitGame();
                return;
            }
            if (ctrl && event.key === Qt.Key_R) {
                Game.doRedo(g);
                refresh();
                return;
            }

            // Momentary INSERT: hold Space to insert, release for NORMAL.
            // i/a no longer switch modes — the mode only exists while Space is held.
            // (Space auto-repeat is consumed here without re-entering the mode)
            if (event.key === Qt.Key_Space) {
                if (!event.isAutoRepeat) {
                    spaceHeld = true;
                    if (!gamesOpen && !g.gameover)
                        Game.enterInsert(g, false);
                }
                refresh();
                event.accepted = true;
                return;
            }

            if (gamesOpen) {
                switch (event.key) {
                case Qt.Key_Escape:
                    gamesOpen = false;
                    break;
                case Qt.Key_Q: root.quitGame(); break;
                case Qt.Key_J: case Qt.Key_Down:
                    panelIndex = Math.min(library.order.length - 1, panelIndex + 1);
                    break;
                case Qt.Key_K: case Qt.Key_Up:
                    panelIndex = Math.max(0, panelIndex - 1);
                    break;
                case Qt.Key_Return: case Qt.Key_Enter:
                    if (library.order[panelIndex])
                        switchSlot(library.order[panelIndex]);
                    break;
                case Qt.Key_D: case Qt.Key_X: case Qt.Key_Delete:
                    if (library.order[panelIndex])
                        deleteSlot(library.order[panelIndex]);
                    break;
                case Qt.Key_N:
                    newGameSlot();
                    break;
                case Qt.Key_1: newGameSlot("easy"); break;
                case Qt.Key_2: newGameSlot("medium"); break;
                case Qt.Key_3: newGameSlot("hard"); break;
                }
                refresh();
                event.accepted = true;
                return;
            }

            if (g.gameover) {
                switch (event.key) {
                case Qt.Key_Q: root.quitGame(); break;
                case Qt.Key_G: openGames(); return;
                case Qt.Key_N: newGameSlot(); return;
                case Qt.Key_Return: case Qt.Key_Enter:
                    Game.retryPuzzle(g);
                    break;
                }
                refresh();
                event.accepted = true;
                return;
            }

            // Re-assert INSERT on any key while Space is held —
            // covers desyncs (e.g. Esc pressed without releasing Space).
            if (spaceHeld && g.mode !== "insert")
                Game.enterInsert(g, false);

            if (g.mode === "normal") {
                switch (event.key) {
                case Qt.Key_Q: case Qt.Key_Escape: root.quitGame(); break;
                case Qt.Key_H: case Qt.Key_Left: Game.moveCursor(g, -1, 0); break;
                case Qt.Key_J: case Qt.Key_Down: Game.moveCursor(g, 0, 1); break;
                case Qt.Key_K: case Qt.Key_Up: Game.moveCursor(g, 0, -1); break;
                case Qt.Key_L: case Qt.Key_Right: Game.moveCursor(g, 1, 0); break;
                case Qt.Key_X: case Qt.Key_D: Game.clearCell(g); break;
                case Qt.Key_U: Game.doUndo(g); break;
                case Qt.Key_R: Game.doRedo(g); break;
                case Qt.Key_G: openGames(); break;
                case Qt.Key_1: case Qt.Key_2: case Qt.Key_3:
                case Qt.Key_4: case Qt.Key_5: case Qt.Key_6:
                case Qt.Key_7: case Qt.Key_8: case Qt.Key_9:
                    Game.toggleNote(g, event.key - Qt.Key_0);
                    break;
                }
            } else {
                switch (event.key) {
                case Qt.Key_Escape: Game.enterNormal(g); break;
                case Qt.Key_G: openGames(); break;
                case Qt.Key_H: case Qt.Key_Left: Game.moveCursor(g, -1, 0); break;
                case Qt.Key_J: case Qt.Key_Down: Game.moveCursor(g, 0, 1); break;
                case Qt.Key_K: case Qt.Key_Up: Game.moveCursor(g, 0, -1); break;
                case Qt.Key_L: case Qt.Key_Right: Game.moveCursor(g, 1, 0); break;
                case Qt.Key_X: case Qt.Key_D: case Qt.Key_0:
                case Qt.Key_Backspace: case Qt.Key_Delete:
                    Game.clearCell(g);
                    break;
                case Qt.Key_1: case Qt.Key_2: case Qt.Key_3:
                case Qt.Key_4: case Qt.Key_5: case Qt.Key_6:
                case Qt.Key_7: case Qt.Key_8: case Qt.Key_9:
                    Game.tryPlace(g, event.key - Qt.Key_0);
                    break;
                }
            }
            refresh();
            event.accepted = true;
        }

        // Released Space → back to NORMAL (INSERT only exists while Space is held).
        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Space && !event.isAutoRepeat) {
                spaceHeld = false;
                if (game.mode === "insert") {
                    Game.enterNormal(game);
                    refresh();
                }
                event.accepted = true;
            }
        }
    }
}
