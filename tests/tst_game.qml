import QtTest
import "../qml/Game.js" as Game

TestCase {
    name: "GameLogic"

    // Fixed classic board for deterministic tests
    // (newState() with no args generates a random puzzle).
    function classic() {
        return Game.newState(Game.PUZZLE, Game.SOLUTION);
    }

    function test_toggle_note_on_off() {
        var st = classic();
        // (0,0) is a given (5) — use an empty cell: (0,2) expects 4
        st.cx = 2; st.cy = 0;
        Game.toggleNote(st, 4);
        compare(Game.notesString(Game.cell(st)), "4");
        Game.toggleNote(st, 4);
        compare(Game.notesString(Game.cell(st)), "");
    }

    function test_note_blocked_on_given() {
        var st = classic();
        st.cx = 0; st.cy = 0; // given
        Game.toggleNote(st, 5);
        compare(Game.notesString(Game.cell(st)), "");
        compare(st.undo.length, 0);
    }

    function test_try_place_correct() {
        var st = classic();
        // Notes on neighbouring cells (same row, column and box)
        st.cx = 5; st.cy = 0; Game.toggleNote(st, 4);
        st.cx = 2; st.cy = 4; Game.toggleNote(st, 4);
        st.cx = 1; st.cy = 1; Game.toggleNote(st, 4);
        compare(st.grid[0][5].notes[3], true);
        compare(st.grid[4][2].notes[3], true);
        compare(st.grid[1][1].notes[3], true);

        // Play the correct 4 at (2, 0)
        st.cx = 2; st.cy = 0; // solution = 4
        Game.tryPlace(st, 4);
        compare(Game.cell(st).value, 4);
        compare(st.mistakes, 0);

        // The neighbours' 4 notes were cleared automatically
        compare(st.grid[0][5].notes[3], false);
        compare(st.grid[4][2].notes[3], false);
        compare(st.grid[1][1].notes[3], false);
    }

    function test_try_place_wrong() {
        var st = classic();
        st.cx = 2; st.cy = 0; // solution = 4
        Game.tryPlace(st, 9);
        compare(Game.cell(st).value, 9); // a wrong value goes to the board
        compare(st.mistakes, 1);
        verify(!st.gameover);
        verify(Game.isWrong(st, 2, 0));
        verify(!Game.isWrong(st, 0, 0)); // a given is never wrong
    }

    function test_gameover_on_third_mistake() {
        var st = classic();
        st.cx = 2; st.cy = 0;
        Game.tryPlace(st, 9); // 1
        st.cx = 3; st.cy = 0;
        Game.tryPlace(st, 1); // 2 (solution = 6)
        verify(!st.gameover);
        st.cx = 5; st.cy = 0;
        Game.tryPlace(st, 1); // 3 (solution = 8)
        verify(st.gameover);
        compare(st.mistakes, 3);
        // mutations blocked on game over
        Game.toggleNote(st, 2);
        Game.clearCell(st);
        Game.tryPlace(st, 8);
        compare(st.mistakes, 3);
        // retry restarts the same board
        Game.retryPuzzle(st);
        verify(!st.gameover);
        compare(st.mistakes, 0);
        compare(st.moves, 0);
        compare(st.grid[0][5].value, 0);
        compare(st.grid[0][0].value, 5); // given left intact
    }

    function test_clear_and_undo() {
        var st = classic();
        st.cx = 2; st.cy = 0;
        Game.toggleNote(st, 4);
        Game.clearCell(st);
        compare(Game.notesString(Game.cell(st)), "");
        Game.doUndo(st); // undoes the clear → the note is back
        compare(Game.notesString(Game.cell(st)), "4");
        Game.doUndo(st); // undoes the note → empty
        compare(Game.notesString(Game.cell(st)), "");
    }

    function test_cursor_clamp() {
        var st = classic();
        Game.moveCursor(st, -5, -5);
        compare(st.cx, 0);
        compare(st.cy, 0);
        Game.moveCursor(st, 99, 99);
        compare(st.cx, 8);
        compare(st.cy, 8);
    }

    function test_enter_insert_shift() {
        var st = classic();
        st.cx = 3;
        Game.enterInsert(st, true); // like `a`: moves 1 to the right
        compare(st.mode, "insert");
        compare(st.cx, 4);
        Game.enterNormal(st);
        compare(st.mode, "normal");
    }

    function test_note_validity() {
        var st = classic();
        // (0,2) empty: row 0 has 5,3,7 · column 2 has 8 · box has 6,9
        verify(!Game.noteValid(st, 2, 0, 5)); // row
        verify(!Game.noteValid(st, 2, 0, 8)); // column
        verify(!Game.noteValid(st, 2, 0, 6)); // box
        verify(Game.noteValid(st, 2, 0, 4)); // solution: still possible
        // after playing the 4, it invalidates the neighbours
        st.cx = 2; st.cy = 0;
        Game.tryPlace(st, 4);
        verify(!Game.noteValid(st, 5, 0, 4));
    }

    function test_redo() {
        var st = classic();
        st.cx = 2; st.cy = 0;
        Game.toggleNote(st, 4);
        Game.doUndo(st);
        compare(Game.notesString(Game.cell(st)), "");
        Game.doRedo(st);
        compare(Game.notesString(Game.cell(st)), "4");
        // a new action invalidates redo
        Game.doUndo(st);
        Game.toggleNote(st, 7);
        Game.doRedo(st);
        compare(st.message, "nothing to redo");
        compare(Game.notesString(Game.cell(st)), "7");
        // redo with no history does not break
        var fresh = classic();
        Game.doRedo(fresh);
        compare(fresh.message, "nothing to redo");
    }
    function test_win_detection() {
        var st = classic();
        // fill everything with the solution via tryPlace
        for (var y = 0; y < 9; y++)
            for (var x = 0; x < 9; x++) {
                st.cx = x; st.cy = y;
                if (Game.cell(st).value === 0)
                    Game.tryPlace(st, st.solution[y][x]);
            }
        verify(st.won);
    }

    function validSolution(sol) {
        for (var r = 0; r < 9; r++) {
            var row = {}, col = {}, box = {};
            for (var c = 0; c < 9; c++) {
                row[sol[r][c]] = true;
                col[sol[c][r]] = true;
                var br = Math.floor(r / 3) * 3 + Math.floor(c / 3);
                var bc = (r % 3) * 3 + (c % 3);
                box[sol[br][bc]] = true;
            }
            if (Object.keys(row).length !== 9) return false;
            if (Object.keys(col).length !== 9) return false;
            if (Object.keys(box).length !== 9) return false;
        }
        return true;
    }

    function test_generator_unique() {
        var gen = Game.generatePuzzle(35);
        var sol = Game.to9x9(gen.solution);
        verify(validSolution(sol));
        // givens match the solution and the solution is unique
        var puz = gen.puzzle.slice();
        for (var i = 0; i < 81; i++)
            if (puz[i] !== 0)
                verify(puz[i] === gen.solution[i]);
        compare(Game.solveCount(puz.slice(), 2), 1);
    }

    function test_difficulty() {
        compare(Game.holesFor("easy"), 36);
        compare(Game.holesFor("medium"), 44);
        compare(Game.holesFor("hard"), 52);
        compare(Game.holesFor("x"), 44);
        var st = Game.newState(Game.PUZZLE, Game.SOLUTION, "hard");
        compare(st.difficulty, "hard");
        var dflt = Game.newState(Game.PUZZLE, Game.SOLUTION);
        compare(dflt.difficulty, "medium");
        var back = Game.deserialize(JSON.parse(JSON.stringify(Game.serialize(st))));
        compare(back.difficulty, "hard");
        var bad = Game.serialize(st);
        bad.difficulty = "nope";
        compare(Game.deserialize(bad).difficulty, "medium");
    }

    function test_timer() {
        compare(Game.formatElapsed(0), "00:00");
        compare(Game.formatElapsed(61000), "01:01");
        compare(Game.formatElapsed(3599000), "59:59");
        compare(Game.formatElapsed(3661000), "1:01:01");
        compare(Game.formatElapsed(-5), "00:00");
        var st = classic();
        compare([st.elapsedMs, st.runningSince], [0, 0]);
        st.elapsedMs = 90000;
        var back = Game.deserialize(JSON.parse(JSON.stringify(Game.serialize(st))));
        compare(back.elapsedMs, 90000);
        compare(back.runningSince, 0); // never resumes a running timestamp
        Game.retryPuzzle(st);
        compare([st.elapsedMs, st.runningSince], [0, 0]);
    }

    function test_remaining_counts() {
        var st = classic();
        var rem = Game.remainingCounts(st);
        compare(rem.length, 9);
        // the sum equals the cells left to fill in correctly
        var total = 0, k;
        for (k = 0; k < 9; k++)
            total += rem[k];
        compare(total, 81 - Game.progress(st).done);
        // a correct play lowers that digit's remaining count
        var before = Game.remainingCounts(st)[3]; // digit 4
        st.cx = 2; st.cy = 0;
        Game.tryPlace(st, 4);
        compare(Game.remainingCounts(st)[3], before - 1);
        // a wrong play does NOT lower the count of cells still needing the digit
        var remBefore9 = Game.remainingCounts(st)[8];
        st.cx = 3; st.cy = 0; // sol[0][3] is 6
        Game.tryPlace(st, 9); // wrong play
        compare(Game.remainingCounts(st)[8], remBefore9);
    }

    function test_serialize_roundtrip() {        var st = classic();
        st.id = "g1"; st.name = "Game 1"; st.createdAt = 123;
        st.cx = 2; st.cy = 0;
        Game.toggleNote(st, 4);
        Game.toggleNote(st, 7);
        st.cx = 5; st.cy = 4;
        Game.tryPlace(st, st.solution[4][5]);
        var back = Game.deserialize(JSON.parse(JSON.stringify(Game.serialize(st))));
        verify(back !== null);
        compare(back.id, "g1");
        compare(back.name, "Game 1");
        compare([back.cx, back.cy], [5, 4]);
        compare(Game.notesString(back.grid[0][2]), "47");
        compare(back.grid[4][5].value, st.solution[4][5]);
        compare(back.moves, st.moves);
        compare(back.undo.length, st.undo.length);
        // corrupted or finished → null
        verify(Game.deserialize(null) === null);
        verify(Game.deserialize({v: 2}) === null);
        verify(Game.deserialize({v: 1}) === null);
        var wonSave = Game.serialize(st);
        wonSave.won = true;
        verify(Game.deserialize(wonSave) === null);
    }
}
