// Pattern text → puzzle. One `.picross` file is one picture, and the picture
// is written as literal characters so a text editor is a level editor:
//
//     name = Heart
//     author = Omacross
//
//     .###.###.
//     #########
//     .#######.
//     ..#####..
//     ...###...
//     ....#....
//
// Everything here is pure data manipulation with no QML dependency, so the
// same functions back both the shell plugin and `tests/`. A future picture
// editor writes this format and gets validation for free by calling `parse`.

// A line is a grid row when every character on it is a cell character.
// Space is deliberately NOT a cell character: that is what lets a prose line
// ("# a note about this picture") fall through to the comment branch instead
// of being read as a row of alternating filled and empty cells.
var FILLED_CHARS = "#"
var EMPTY_CHARS = "."

var GRID_LINE = new RegExp("^[" + FILLED_CHARS + EMPTY_CHARS + "]+$")
var META_LINE = /^([A-Za-z][A-Za-z0-9_-]*)\s*[:=]\s*(.*)$/

function isFilledChar(character) {
  return FILLED_CHARS.indexOf(character) >= 0
}

// Anything that is neither a grid row nor `key = value` is a comment. Not
// reserving a comment character keeps `#` free to mean "filled", which is the
// one convention every nonogram text format shares.
function classifyLine(line) {
  var trimmed = String(line).replace(/^\s+|\s+$/g, "")
  if (trimmed === "") return { kind: "blank" }
  if (GRID_LINE.test(trimmed)) return { kind: "row", text: trimmed }
  var meta = trimmed.match(META_LINE)
  if (meta) return { kind: "meta", key: meta[1].toLowerCase(), value: meta[2].replace(/\s+$/, "") }
  return { kind: "comment" }
}

// Ragged rows pad out to the widest one rather than failing: half-drawn
// pictures stay loadable while they are being worked on, and trailing empty
// cells are exactly what the author left off.
function normalizeRows(rows) {
  var width = 0
  for (var i = 0; i < rows.length; i++) width = Math.max(width, rows[i].length)
  var out = []
  for (var r = 0; r < rows.length; r++) {
    var cells = []
    for (var c = 0; c < width; c++) cells.push(c < rows[r].length && isFilledChar(rows[r].charAt(c)) ? 1 : 0)
    out.push(cells)
  }
  return out
}

// Trim fully empty edges so a picture drawn with a margin still counts as the
// size it looks like. A picture that is empty everywhere trims to nothing and
// is rejected by `parse` as having no filled cells.
function cropped(cells) {
  var rows = cells.length
  var cols = rows > 0 ? cells[0].length : 0
  var top = 0, bottom = rows - 1, left = 0, right = cols - 1

  function rowEmpty(r) {
    for (var c = 0; c < cols; c++) if (cells[r][c]) return false
    return true
  }
  function colEmpty(c) {
    for (var r = 0; r < rows; r++) if (cells[r][c]) return false
    return true
  }

  while (top <= bottom && rowEmpty(top)) top++
  while (bottom >= top && rowEmpty(bottom)) bottom--
  while (left <= right && colEmpty(left)) left++
  while (right >= left && colEmpty(right)) right--
  if (top > bottom || left > right) return []

  var out = []
  for (var row = top; row <= bottom; row++) out.push(cells[row].slice(left, right + 1))
  return out
}

// Grow a cropped picture back out to a square of `size`, centered. Difficulty
// is a grid size, so a 9x7 drawing has to sit in a 10x10 board without the
// clues implying it was drawn that way.
function padToSquare(cells, size) {
  var rows = cells.length
  var cols = rows > 0 ? cells[0].length : 0
  if (rows > size || cols > size) return null

  var top = Math.floor((size - rows) / 2)
  var left = Math.floor((size - cols) / 2)
  var out = []
  for (var r = 0; r < size; r++) {
    var row = []
    for (var c = 0; c < size; c++) {
      var inside = r >= top && r < top + rows && c >= left && c < left + cols
      row.push(inside ? cells[r - top][c - left] : 0)
    }
    out.push(row)
  }
  return out
}

// Run lengths of filled cells along one line. A line with nothing on it is
// clued `[0]`, which is how every nonogram prints an empty line and what the
// solver below expects.
function runsOf(line) {
  var runs = []
  var run = 0
  for (var i = 0; i < line.length; i++) {
    if (line[i]) run++
    else if (run > 0) { runs.push(run); run = 0 }
  }
  if (run > 0) runs.push(run)
  return runs.length > 0 ? runs : [0]
}

function rowClues(cells) {
  var out = []
  for (var r = 0; r < cells.length; r++) out.push(runsOf(cells[r]))
  return out
}

function columnClues(cells) {
  var rows = cells.length
  var cols = rows > 0 ? cells[0].length : 0
  var out = []
  for (var c = 0; c < cols; c++) {
    var line = []
    for (var r = 0; r < rows; r++) line.push(cells[r][c])
    out.push(runsOf(line))
  }
  return out
}

function titleFromFileName(fileName) {
  var base = String(fileName || "").replace(/^.*\//, "").replace(/\.[^.]*$/, "")
  base = base.replace(/[-_]+/g, " ").replace(/^\s+|\s+$/g, "")
  if (base === "") return "Untitled"
  return base.charAt(0).toUpperCase() + base.slice(1)
}

function countFilled(cells) {
  var total = 0
  for (var r = 0; r < cells.length; r++)
    for (var c = 0; c < cells[r].length; c++) if (cells[r][c]) total++
  return total
}

// A `size = WxH` meta line pins the board instead of letting it fall out of
// the drawing. Honored only when it is square and matches the picture's own
// raw dimensions exactly — a stale or hand-typed value that disagrees with
// what is actually there falls back to the usual crop-and-recenter rather
// than silently padding or truncating a mismatch. This is what lets the
// pattern editor promise a board never comes back smaller than it was drawn:
// it always writes the full canvas *and* the size that names it, so an empty
// margin the artist meant to keep is never mistaken for one they just never
// got to.
function declaredSize(rawSize, normalized) {
  var match = /^\s*(\d+)\s*x\s*(\d+)\s*$/i.exec(String(rawSize || ""))
  if (!match) return 0
  var width = Number(match[1])
  var height = Number(match[2])
  if (width !== height || width <= 0) return 0
  if (normalized.length !== height) return 0
  if (normalized[0].length !== width) return 0
  return width
}

// Parse one pattern file. Returns `{ ok: false, error }` rather than throwing,
// because the caller is a QML file watcher loading whatever the user just
// saved into their patterns directory — a typo there must not take the panel
// down with it.
function parse(text, fileName) {
  var lines = String(text === undefined || text === null ? "" : text).split(/\r?\n/)
  var meta = {}
  var rawRows = []

  for (var i = 0; i < lines.length; i++) {
    var classified = classifyLine(lines[i])
    if (classified.kind === "meta") meta[classified.key] = classified.value
    else if (classified.kind === "row") rawRows.push(classified.text)
  }

  if (rawRows.length === 0) return { ok: false, error: "no picture rows found" }

  var normalized = normalizeRows(rawRows)
  var pinned = declaredSize(meta.size, normalized)

  var size, squared
  if (pinned) {
    size = pinned
    squared = normalized
  } else {
    var cells = cropped(normalized)
    if (cells.length === 0) return { ok: false, error: "picture has no filled cells" }
    size = Math.max(cells.length, cells[0].length)
    squared = padToSquare(cells, size)
  }

  // Only the pinned path can still be blank here — `cropped` already refused
  // an unfilled picture above, and padding an already-non-empty crop never
  // erases it.
  if (pinned && countFilled(squared) === 0) return { ok: false, error: "picture has no filled cells" }

  return {
    ok: true,
    name: meta.name || titleFromFileName(fileName),
    author: meta.author || "",
    file: String(fileName || ""),
    size: size,
    cells: squared,
    filled: countFilled(squared),
    rowClues: rowClues(squared),
    columnClues: columnClues(squared)
  }
}

// Render a puzzle back to the canonical file text. This is the other half of
// the editor contract: a tool can `parse` a file, edit `cells`, and `format`
// it back out without inventing its own writer.
//
// `puzzle.pinSize` writes the `size = WxH` line `parse` looks for above —
// opt in, since it changes what a reload does with an empty margin. Every
// existing bundled picture relies on the plain crop-and-recenter behavior,
// so this only fires for a caller that asks for it (the pattern editor).
function format(puzzle) {
  var out = []
  if (puzzle.name) out.push("name = " + puzzle.name)
  if (puzzle.author) out.push("author = " + puzzle.author)
  if (puzzle.pinSize) out.push("size = " + puzzle.cells.length + "x" + (puzzle.cells[0] ? puzzle.cells[0].length : 0))
  out.push("")
  for (var r = 0; r < puzzle.cells.length; r++) {
    var row = ""
    for (var c = 0; c < puzzle.cells[r].length; c++) row += puzzle.cells[r][c] ? "#" : "."
    out.push(row)
  }
  return out.join("\n") + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    FILLED_CHARS: FILLED_CHARS,
    EMPTY_CHARS: EMPTY_CHARS,
    isFilledChar: isFilledChar,
    classifyLine: classifyLine,
    normalizeRows: normalizeRows,
    cropped: cropped,
    padToSquare: padToSquare,
    runsOf: runsOf,
    rowClues: rowClues,
    columnClues: columnClues,
    titleFromFileName: titleFromFileName,
    countFilled: countFilled,
    parse: parse,
    format: format
  }
}
