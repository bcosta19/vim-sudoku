.pragma library

// vim-sudoku theme, mirroring Omarchy.
//
// The app runs inside Quickshell (qs -p), so it reads the real colors.toml
// through FileView and hands the text to parseColors() — a theme change
// applies live. defaults() is the fallback (Tokyo Night).

function defaults() {
    return {
        background: "#1a1b26",
        foreground: "#a9b1d6",
        bright: "#c0caf5",
        muted: "#565f89",
        selection: "#292e42",
        accent: "#7aa2f7",
        green: "#9ece6a",
        blue: "#7aa2f7",
        yellow: "#e0af68",
        red: "#f7768e",
        isLight: false,
        source: "fallback"
    };
}

// Minimal `key = "value"` parser (enough for colors.toml).
function parseColors(text) {
    var t = defaults();
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line || line[0] === "#" || line[0] === "[")
            continue;
        var eq = line.indexOf("=");
        if (eq < 0)
            continue;
        var key = line.slice(0, eq).trim();
        var val = line.slice(eq + 1).trim();
        // take the quoted content; ignore the rest of the line (comment)
        var m = val.match(/^"([^"]*)"/);
        if (m)
            val = m[1];
        else
            val = val.split(/\s/)[0].replace(/^"|"$/g, "");
        switch (key) {
        case "background": t.background = val; break;
        case "foreground": t.foreground = val; break;
        case "bright_foreground": t.bright = val; break;
        case "dark_foreground":
        case "muted": t.muted = val; break;
        case "selection": t.selection = val; break;
        case "accent": t.accent = val; break;
        case "green": t.green = val; break;
        case "blue": t.blue = val; break;
        case "yellow": t.yellow = val; break;
        case "red": t.red = val; break;
        case "mode": t.isLight = (val === "light"); break;
        }
    }
    t.source = "omarchy";
    return t;
}

// Readable text over a colored background (accent/blue/green).
function onAccent(t) {
    return t.isLight ? t.foreground : t.background;
}
