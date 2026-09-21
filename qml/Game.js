.pragma library

// Pure vim-sudoku game logic (no UI dependency).
// Used by SudokuWindow.qml and covered by tst_game.qml.
//
// Mistake rule: a wrong move DOES go to the board (in red) so you can
// reason on top of it. 3 mistakes end the game (game over).

var MAX_MISTAKES = 3;

// Holes per difficulty level (always with a guaranteed unique solution).
var DIFFICULTY_HOLES = { easy: 36, medium: 44, hard: 52 };
var DIFFICULTIES = ["easy", "medium", "hard"];

function holesFor(diff) {
    return DIFFICULTY_HOLES[diff] || DIFFICULTY_HOLES.medium;
}

var PUZZLE = [    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9]
];

var SOLUTION = [
    [5, 3, 4, 6, 7, 8, 9, 1, 2],
    [6, 7, 2, 1, 9, 5, 3, 4, 8],
    [1, 9, 8, 3, 4, 2, 5, 6, 7],
    [8, 5, 9, 7, 6, 1, 4, 2, 3],
    [4, 2, 6, 8, 5, 3, 7, 9, 1],
    [7, 1, 3, 9, 2, 4, 8, 5, 6],
    [9, 6, 1, 5, 3, 7, 2, 8, 4],
    [2, 8, 7, 4, 1, 9, 6, 3, 5],
    [3, 4, 5, 2, 8, 6, 1, 7, 9]
];

// ---------------------------------------------------------------------------
// Puzzle generator with a unique solution (full board via backtracking +
// symmetric removal with a uniqueness test). Runs in ms under QML/JS.
// ---------------------------------------------------------------------------

function shuffled(arr) {
    var a = arr.slice();
    for (var i = a.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1));
        var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
}

function flat9(grid9) {
    var f = [];
    for (var y = 0; y < 9; y++)
        for (var x = 0; x < 9; x++)
            f.push(grid9[y][x]);
    return f;
}

function to9x9(flat) {
    var g = [];
    for (var y = 0; y < 9; y++)
        g.push(flat.slice(y * 9, y * 9 + 9));
    return g;
}

function peersOk(grid, i, n) {
    var r = Math.floor(i / 9), c = i % 9;
    for (var k = 0; k < 9; k++) {
        if (grid[r * 9 + k] === n || grid[k * 9 + c] === n)
            return false;
    }
    var br = Math.floor(r / 3) * 3, bc = Math.floor(c / 3) * 3;
    for (var dy = 0; dy < 3; dy++)
        for (var dx = 0; dx < 3; dx++)
            if (grid[(br + dy) * 9 + bc + dx] === n)
                return false;
    return true;
}

// Counts solutions up to `limit` (for the uniqueness test, limit = 2).
function solveCount(grid, limit) {
    var at = -1;
    for (var i = 0; i < 81; i++)
        if (grid[i] === 0) { at = i; break; }
    if (at < 0)
        return 1;
    var count = 0;
    for (var n = 1; n <= 9; n++) {
        if (peersOk(grid, at, n)) {
            grid[at] = n;
            count += solveCount(grid, limit - count);
            grid[at] = 0;
            if (count >= limit)
                return count;
        }
    }
    return count;
}

function fillGrid(grid) {
    var at = -1;
    for (var i = 0; i < 81; i++)
        if (grid[i] === 0) { at = i; break; }
    if (at < 0)
        return true;
    var nums = shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    for (var k = 0; k < 9; k++) {
        if (peersOk(grid, at, nums[k])) {
            grid[at] = nums[k];
            if (fillGrid(grid))
                return true;
            grid[at] = 0;
        }
    }
    return false;
}

// Returns {puzzle, solution} flat (81). `holes` = target empty cells.
function generatePuzzle(holes) {
    holes = holes || 42;
    var best = null;
    for (var attempt = 0; attempt < 3; attempt++) {
        var sol = new Array(81).fill(0);
        fillGrid(sol);
        var puz = sol.slice();
        var order = shuffled([...Array(81).keys()]);
        var removed = 0;
        for (var k = 0; k < 81 && removed < holes; k++) {
            var i = order[k];
            var mirror = 80 - i;
            // symmetric removal: drop the pair if uniqueness is preserved
            var bak1 = puz[i], bak2 = puz[mirror];
            if (bak1 === 0)
                continue;
            puz[i] = 0;
            var takeMirror = (mirror !== i && bak2 !== 0 && removed + 1 < holes);
            if (takeMirror)
                puz[mirror] = 0;
            if (solveCount(puz.slice(), 2) !== 1) {
                puz[i] = bak1;
                if (takeMirror)
                    puz[mirror] = bak2;
            } else {
                removed += takeMirror ? 2 : 1;
            }
        }
        best = { puzzle: puz, solution: sol, holes: removed };
        if (removed >= holes)
            break;
    }
    return best;
}

function newState(puzzle9, solution9, difficulty) {
    var gen = null;
    if (!puzzle9 || !solution9) {
        gen = generatePuzzle(holesFor(difficulty));
        puzzle9 = to9x9(gen.puzzle);
        solution9 = to9x9(gen.solution);
    }
    var grid = [];
    for (var y = 0; y < 9; y++) {
        var row = [];
        for (var x = 0; x < 9; x++) {
            row.push({
                given: puzzle9[y][x] !== 0,
                value: puzzle9[y][x] !== 0 ? puzzle9[y][x] : 0,
                notes: [false, false, false, false, false, false, false, false, false]
            });
        }
        grid.push(row);
    }
    return {
        grid: grid,
        puzzle: puzzle9,
        solution: solution9,
        difficulty: DIFFICULTIES.indexOf(difficulty) >= 0 ? difficulty : "medium",
        id: null,
        name: "",
        createdAt: 0,
        cx: 0, cy: 0,
        mode: "normal", // "normal" | "insert"
        message: "hjkl move | hold Space to insert | 1-9 notes | q quits",
        mistakes: 0,
        moves: 0,
        undo: [],
        redo: [],
        won: false,
        gameover: false,
        // clock: accumulated elapsedMs + runningSince (timestamp or 0)
        elapsedMs: 0,
        runningSince: 0
    };
}

function cell(st) {
    return st.grid[st.cy][st.cx];
}

function notesString(c) {
    var s = "";
    for (var i = 0; i < 9; i++)
        if (c.notes[i])
            s += String(i + 1);
    return s;
}

function snapshot(grid) {
    return grid.map(function (row) {
        return row.map(function (c) {
            return { value: c.value, notes: c.notes.slice() };
        });
    });
}

function pushUndo(st) {
    st.undo.push(snapshot(st.grid));
    st.redo = []; // a new action invalidates redo, like in vim
    if (st.undo.length > 500)
        st.undo.shift();
}

function restoreSnap(st, snap) {
    for (var y = 0; y < 9; y++)
        for (var x = 0; x < 9; x++)
            if (!st.grid[y][x].given) {
                st.grid[y][x].value = snap[y][x].value;
                st.grid[y][x].notes = snap[y][x].notes.slice();
            }
}

function doUndo(st) {
    var snap = st.undo.pop();
    if (!snap) {
        st.message = "nothing to undo";
        return;
    }
    st.redo.push(snapshot(st.grid));
    restoreSnap(st, snap);
    st.won = false;
    checkWin(st);
    if (!st.won)
        st.message = "undone (u)";
}

function doRedo(st) {
    var snap = st.redo.pop();
    if (!snap) {
        st.message = "nothing to redo";
        return;
    }
    st.undo.push(snapshot(st.grid));
    restoreSnap(st, snap);
    st.won = false;
    checkWin(st);
    if (!st.won)
        st.message = "redone (r)";
}

function moveCursor(st, dx, dy) {
    st.cx = Math.max(0, Math.min(8, st.cx + dx));
    st.cy = Math.max(0, Math.min(8, st.cy + dy));
}

function enterInsert(st, shiftRight) {
    if (shiftRight && st.cx < 8)
        st.cx += 1;
    st.mode = "insert";
    st.message = "INSERT: 1-9 plays | release Space for NORMAL";
}

function enterNormal(st) {
    st.mode = "normal";
    st.message = "NORMAL: 1-9 notes | hold Space to insert | x clears | u undoes";
}

// NORMAL: 1-9 toggles a pencil mark
function toggleNote(st, n) {
    if (st.won || st.gameover)
        return;
    var c = cell(st);
    if (c.given) {
        st.message = "given cell, can't take notes";
        return;
    }
    if (c.value !== 0) {
        st.message = "cell already has a value (x clears it first)";
        return;
    }
    pushUndo(st);
    c.notes[n - 1] = !c.notes[n - 1];
    st.moves += 1;
    st.message = "note " + n + (c.notes[n - 1] ? " ON" : " OFF");
}

// Removes notes for digit n from the neighbours (same row, column and 3x3 box)
function removePeerNotes(st, cx, cy, n) {
    var idx = n - 1;
    for (var i = 0; i < 9; i++) {
        st.grid[cy][i].notes[idx] = false;
        st.grid[i][cx].notes[idx] = false;
    }
    var bx = Math.floor(cx / 3) * 3, by = Math.floor(cy / 3) * 3;
    for (var dy = 0; dy < 3; dy++) {
        for (var dx = 0; dx < 3; dx++) {
            st.grid[by + dy][bx + dx].notes[idx] = false;
        }
    }
}

// INSERT: 1-9 actually places the number — right or wrong.
// A wrong number goes to the board marked (red) and counts as a mistake;
// 3 mistakes end the game.
function tryPlace(st, n) {
    if (st.won || st.gameover)
        return;
    var c = cell(st);
    if (c.given) {
        st.message = "given cell!";
        return;
    }
    if (c.value === n) {
        st.message = "that " + n + " is already there";
        return;
    }
    pushUndo(st);
    c.value = n;
    c.notes = [false, false, false, false, false, false, false, false, false];
    st.moves += 1;
    if (n === st.solution[st.cy][st.cx]) {
        st.message = "correct! " + n + " placed";
        removePeerNotes(st, st.cx, st.cy, n);
        checkWin(st);
    } else {
        st.mistakes += 1;
        if (st.mistakes >= MAX_MISTAKES) {
            st.gameover = true;
            st.message = "game over: 3 mistakes";
        } else {
            st.message = "wrong! " + n + " doesn't go here (" + st.mistakes + "/" + MAX_MISTAKES + " mistakes)";
        }
    }
}

function clearCell(st) {
    if (st.won || st.gameover)
        return;
    var c = cell(st);
    if (c.given) {
        st.message = "given cell, can't clear it";
        return;
    }
    if (c.value === 0 && notesString(c) === "") {
        st.message = "already empty";
        return;
    }
    pushUndo(st);
    c.value = 0;
    c.notes = [false, false, false, false, false, false, false, false, false];
    st.moves += 1;
    st.message = "cell cleared (x)";
}

function checkWin(st) {
    for (var y = 0; y < 9; y++)
        for (var x = 0; x < 9; x++)
            if (st.grid[y][x].value !== st.solution[y][x])
                return;
    st.won = true;
    st.message = "you win! " + st.moves + " moves, " + st.mistakes + " mistakes. q to quit";
}

// Restarts the same board from scratch (after game over).
function retryPuzzle(st) {
    for (var y = 0; y < 9; y++)
        for (var x = 0; x < 9; x++)
            if (!st.grid[y][x].given) {
                st.grid[y][x].value = 0;
                st.grid[y][x].notes = [false, false, false, false, false, false, false, false, false];
            }
    st.undo = [];
    st.redo = [];
    st.mistakes = 0;
    st.moves = 0;
    st.won = false;
    st.gameover = false;
    st.elapsedMs = 0;
    st.runningSince = 0;
    st.cx = 0;
    st.cy = 0;
    st.mode = "normal";
    st.message = "again! same board, zero mistakes";
}

// A played value that does not match the solution (givens are never wrong).
function isWrong(st, x, y) {
    var c = st.grid[y][x];
    return !c.given && c.value !== 0 && c.value !== st.solution[y][x];
}

// mm:ss (or h:mm:ss) to display the clock.
function formatElapsed(ms) {
    var s = Math.max(0, Math.floor(ms / 1000));
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var sec = s % 60;
    var mm = (h > 0 && m < 10 ? "0" : "") + (h > 0 ? m : (m < 10 ? "0" + m : "" + m));
    var ss = sec < 10 ? "0" + sec : "" + sec;
    return (h > 0 ? h + ":" + mm : mm) + ":" + ss;
}

// A note stops being valid if the digit already appears in the same
// row, column or 3x3 box (the UI paints it red in that case).
function noteValid(st, x, y, n) {
    for (var i = 0; i < 9; i++) {
        if (st.grid[y][i].value === n)
            return false;
        if (st.grid[i][x].value === n)
            return false;
    }
    var bx = Math.floor(x / 3) * 3, by = Math.floor(y / 3) * 3;
    for (var dy = 0; dy < 3; dy++)
        for (var dx = 0; dx < 3; dx++)
            if (st.grid[by + dy][bx + dx].value === n)
                return false;
    return true;
}

// How many of each digit (1-9) still need to be filled in CORRECTLY on the board.
// Counts the solution positions where the digit has not been placed correctly yet.
function remainingCounts(st) {
    var counts = [0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 9; x++) {
            var sol = st.solution[y][x];
            var cur = st.grid[y][x].value;
            if (sol >= 1 && sol <= 9 && cur !== sol) {
                counts[sol - 1]++;
            }
        }
    }
    return counts;
}

// Cells filled in correctly (includes givens and correct plays) — used for progress.
function progress(st) {
    var done = 0;
    for (var y = 0; y < 9; y++)
        for (var x = 0; x < 9; x++)
            if (st.grid[y][x].value !== 0 && st.grid[y][x].value === st.solution[y][x])
                done++;
    return { done: done, total: 81 };
}

// ---------------------------------------------------------------------------
// Multi-game persistence (v2 format). Each slot stores the board, the solution
// (to validate moves after reloading), the cursor, the score and undo/redo.
// Finished games (won) are not restored — deserialize returns null.
// ---------------------------------------------------------------------------

function serialize(st) {
    return {
        v: 2,
        id: st.id,
        name: st.name,
        createdAt: st.createdAt,
        cx: st.cx, cy: st.cy,
        mode: st.mode,
        mistakes: st.mistakes,
        moves: st.moves,
        won: st.won,
        gameover: st.gameover,
        difficulty: st.difficulty,
        elapsedMs: st.elapsedMs,
        runningSince: st.runningSince,
        puzzle: flat9(st.puzzle),
        solution: flat9(st.solution),
        grid: st.grid.map(function (row) {
            return row.map(function (c) {
                var bits = "";
                for (var i = 0; i < 9; i++)
                    bits += c.notes[i] ? "1" : "0";
                return [c.given ? 1 : 0, c.value, bits];
            });
        }),
        undo: st.undo.slice(-30),
        redo: st.redo.slice(-30)
    };
}

function validSnap(s) {
    // same shape as snapshot(): 9x9 array of {value, notes[9]}
    if (!Array.isArray(s) || s.length !== 9)
        return null;
    var out = [];
    for (var y = 0; y < 9; y++) {
        if (!Array.isArray(s[y]) || s[y].length !== 9)
            return null;
        var row = [];
        for (var x = 0; x < 9; x++) {
            var e = s[y][x];
            if (!e || !Array.isArray(e.notes) || e.notes.length !== 9)
                return null;
            if (typeof e.value !== "number" || e.value < 0 || e.value > 9)
                return null;
            row.push({ value: e.value, notes: e.notes.map(Boolean) });
        }
        out.push(row);
    }
    return out;
}

function deserialize(d) {
    try {
        if (!d || d.v !== 2 || d.won)
            return null;
        if (!Array.isArray(d.puzzle) || d.puzzle.length !== 81)
            return null;
        if (!Array.isArray(d.solution) || d.solution.length !== 81)
            return null;
        if (!Array.isArray(d.grid) || d.grid.length !== 9)
            return null;
        var puzzle9 = to9x9(d.puzzle), solution9 = to9x9(d.solution);
        for (var i = 0; i < 81; i++) {
            if (puzzle9[Math.floor(i / 9)][i % 9] < 0 || puzzle9[Math.floor(i / 9)][i % 9] > 9)
                return null;
            if (solution9[Math.floor(i / 9)][i % 9] < 1 || solution9[Math.floor(i / 9)][i % 9] > 9)
                return null;
        }
        var st = newState(puzzle9, solution9);
        for (var y = 0; y < 9; y++) {
            if (!Array.isArray(d.grid[y]) || d.grid[y].length !== 9)
                return null;
            for (var x = 0; x < 9; x++) {
                var e = d.grid[y][x];
                if (!Array.isArray(e) || e.length !== 3)
                    return null;
                if (typeof e[1] !== "number" || e[1] < 0 || e[1] > 9)
                    return null;
                if (typeof e[2] !== "string" || !/^[01]{9}$/.test(e[2]))
                    return null;
                st.grid[y][x].given = (e[0] === 1);
                st.grid[y][x].value = e[1];
                for (var n = 0; n < 9; n++)
                    st.grid[y][x].notes[n] = (e[2][n] === "1");
            }
        }
        st.id = (typeof d.id === "string") ? d.id : null;
        st.name = (typeof d.name === "string") ? d.name : "";
        st.createdAt = (typeof d.createdAt === "number") ? d.createdAt : 0;
        st.cx = (Number.isInteger(d.cx) && d.cx >= 0 && d.cx <= 8) ? d.cx : 0;
        st.cy = (Number.isInteger(d.cy) && d.cy >= 0 && d.cy <= 8) ? d.cy : 0;
        // INSERT is momentary (Space held) — never restores as insert
        st.mode = "normal";
        st.mistakes = (Number.isInteger(d.mistakes) && d.mistakes >= 0) ? d.mistakes : 0;
        st.moves = (Number.isInteger(d.moves) && d.moves >= 0) ? d.moves : 0;
        st.gameover = (d.gameover === true);
        st.difficulty = DIFFICULTIES.indexOf(d.difficulty) >= 0 ? d.difficulty : "medium";
        st.elapsedMs = (Number.isInteger(d.elapsedMs) && d.elapsedMs >= 0) ? d.elapsedMs : 0;
        // never resumes a running timestamp: the clock restarts on focus
        st.runningSince = 0;
        st.undo = Array.isArray(d.undo) ? d.undo.map(validSnap).filter(Boolean) : [];
        st.redo = Array.isArray(d.redo) ? d.redo.map(validSnap).filter(Boolean) : [];
        st.message = "previous game restored";
        return st;
    } catch (e) {
        return null;
    }
}
