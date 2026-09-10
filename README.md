# Omacross

A nonogram game that lives in the Omarchy bar.

Inspired by one of my favorite game boy games from 1995, **Mario's Picross**. The timer counts *down*, a
wrong guess costs you time and each further mistake costs more, and the picture
is not named until you have solved it.

## Install

```bash
omarchy plugin add https://github.com/<you>/omacross.git --enable
```

## Playing

Left-click the grid icon in the bar to open the game, or:

```bash
omarchy-shell omacross toggle
```

Pick a difficulty and press `enter`. Difficulty is the grid and the clock
together:

| Difficulty | Grid | Clock |
| --- | --- | --- |
| Easy | 5×5 | 10:00 |
| Normal | 10×10 | 30:00 |
| Hard | 15×15 | 45:00 |

**Fill** a cell you believe is part of the picture. Right, and it stays filled.
Wrong, and  the clock takes the hit, **2:00** for the first mistake, **4:00** for the
second, **8:00** for the third and every one after it, so a forgotten cell can
cost you again. **Cross out** a cell you have reasoned is empty; that is a note
to yourself.

Solve the picture before the clock runs out and it is finally named, with a
grade: `PERFECT` (no mistakes), `GREAT`, `GOOD`, or `CLEARED`. Run out of time
and the picture stays hidden — you can try the same one again.

### Mouse

| Input | Action |
| --- | --- |
| Left click | Fill — the primary move |
| Right click | Cross out |


### Keyboard

| Key | Action |
| --- | --- |
| `h` `j` `k` `l` or arrows | Move the cursor (it wraps at the edges) |
| `space` | Fill |
| `x` | Cross out |
| `0` / `$` | First / last column |
| `g` / `G` | First / last row |
| `Ctrl+Q` | Quit the current picture (asks first) |
| `Ctrl+N` | New game (asks first if one is in progress) |
| `esc` | Close the panel |

On the title screen, `enter` starts a new game, `j`/`k` choose a difficulty, and
`1`/`2`/`3` jump straight to one.

## Drawing your own

Press `e` on the title screen to open the pattern editor — a floating window
of its own, so it can sit next to the game rather than replace it. Whatever is
on the board is always the top row of the list on the left, saved or not — a
fresh, blank "New Pattern" if you have no patterns of your own yet.

There are two tools, fill and deselect. There is no cross-out here the way
there is in the game — anything you leave unfilled *is* the "wrong guess"
the finished puzzle will grade against, so there is nothing more to mark.

| Input | Action |
| --- | --- |
| Left click | Fill |
| Right click | Deselect a filled cell |

| Key | Action |
| --- | --- |
| `space` | Fill a cell |
| `x` | Deselect a filled cell |
| `h` `j` `k` `l` or ← → | Move the cursor |
| `↑` `↓` | Move the selection in the pattern list |
| `enter` | Load the selected pattern (asks first if the current one is unsaved) |
| `d` | Delete the selected pattern (asks first) |
| `Ctrl+N` | Start a new pattern (asks first if the current one is unsaved) |
| `Ctrl+S` | Save the pattern you're drawing |
| `Ctrl+Q` | Close the editor (asks first if the current one is unsaved) |

Saving asks for a name and writes a `.picross` file under
`~/.config/omacross/user-patterns/<size>x<size>/`, sized by whatever board you
were drawing on — a 10×10 stays 10×10 even if the drawing on it only fills a
corner. That is what the file's `size = WxH` line is for: it pins the board so
a reload does not crop the empty margin away and recenter what is left, the
way a plain hand-typed picture does. Those three folders are watched the same
way the bundled and extra folders are, so a saved pattern is in the deal —
and counted on the title screen — the moment it lands.

## Pictures

A picture is simply a text file.

```
name = Heart
author = Omacross

.###.###.
#########
.#######.
..#####..
...###...
....#....
```

- Any line made only of cell characters is a row of the picture. `#` is
  filled; `.` is empty.
- `key = value` (or `key: value`) sets metadata. `name` is what you are shown
  when you solve it; without one, the file name is used.
- Anything else is a comment. There is no comment character to remember —
  because a space is not a cell character, `# a note about this one` is prose,
  while `#####` is a row.
- Ragged rows are padded, empty margins are trimmed, and a non-square drawing is
  centered in a square board. The resulting size decides the difficulty it is
  dealt at, so a picture must come out 5×5, 10×10 or 15×15.
- A `size = WxH` metadata line skips that trimming and recentering: it pins
  the board to exactly the picture's own raw dimensions, provided they
  already match. The pattern editor writes this on every save, which is how
  it keeps a drawing at the size — and in the exact position — it was drawn.

Drop your own into `~/.config/omacross/patterns/` (or set **Extra pictures
folder** in the widget's settings). Both folders are watched — save a file in
your editor and it is in the next deal, no restart.

`Puzzle.js` is the whole format contract: `parse(text, fileName)` returns a
puzzle or `{ ok: false, error }`, and `format(puzzle)` writes one back out. A
picture editor is those two functions plus a grid.

38 pictures ship with the plugin — 15 easy, 14 normal, 9 hard.

## Development

```bash
./tests/run      # rules, parsing, solver, and every bundled picture
./dev/sync       # copy this checkout into the plugin dir
./dev/sync --restart
```

`tests/validate-patterns.js` run directly prints every bundled picture as block
art, which is the quickest way to see what you just drew.

Two notes that cost time to find, if you are hacking on this:

- **Sync, don't symlink.** The shell watches `~/.config/omarchy/plugins` with
  `inotifywait -r`, which does not follow a symlink into its target, so a
  symlinked checkout never hot-reloads. `./dev/sync` copies.
- **Changed QML needs a reload, not a rescan.** `rescanPlugins` refreshes plugin
  metadata but reuses the cached component for an unchanged entry-point URL.
  Saving into the watched tree triggers the real reload; `./dev/sync --restart`
  forces it.

### Layout

| File | Purpose |
| --- | --- |
| `Puzzle.js` | Pattern text → picture, clues, and back out again |
| `Game.js` | The rules: difficulty, guesses, penalties, the clock, grading |
| `Solver.js` | Line solver, used to prove pictures are fair |
| `Logo.js` | The Omarchy mark as a 13×13 picture, and the title animation |
| `Panel.qml` | Bar widget: the clock, input routing, and the three screens |
| `BoardView.qml` | The grid and its clues |
| `TitleScreen.qml` | The mark assembling out of static, and difficulty |
| `PatternLibrary.qml` | Watches the bundled, extra, and per-size user-pattern folders |
| `PatternEditor.js` | The editor's own tiny state machine: fill, save |
| `PatternEditor.qml` | The floating drawing window and its pattern list |

The rules are plain JavaScript with no QML in them, which is why `tests/` can
play whole games. `Panel.qml` holds the state machine in a plain object and
republishes it through `syncState()` — that one function is the entire bridge
from the rules to anything QML can bind to.

## Remove

```bash
omarchy plugin remove justinhhorner.picross --yes
```

## License

MIT. See [LICENSE](LICENSE).
