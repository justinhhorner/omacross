// The picture editor's own small state machine — no QML, no file I/O.
//
// Unlike Game.js there is no solution to guess against: every cell the player
// touches simply becomes what they asked for, and there is exactly one thing
// to ask for — filled or not. A cell is part of the picture, or (per
// Game.js's own rules) it is what a player who guessed it would be told is
// wrong. There is no third, cosmetic "cross-out" layer here the way there is
// during play: an editor cell that isn't filled *is* the "incorrect choice"
// the finished puzzle will grade against, so marking it separately would
// only record the same fact twice.
//
// `Puzzle.js` still owns the file format; this module only gets a grid to and
// from the shape `Puzzle.format`/`Puzzle.parse` already speak, per the
// project's own README: "A picture editor is those two functions plus a
// grid."

var UNKNOWN = 0
var FILLED = 1

var SIZES = [5, 10, 15]
var DEFAULT_SIZE = 10

function createGrid(size) {
  var cells = []
  for (var r = 0; r < size; r++) {
    var row = []
    for (var c = 0; c < size; c++) row.push(UNKNOWN)
    cells.push(row)
  }
  return cells
}

function cloneGrid(cells) {
  var out = []
  for (var r = 0; r < cells.length; r++) out.push(cells[r].slice())
  return out
}

// Drives one cell to an explicit value rather than toggling it in place —
// the caller decides "on" or "off" for a whole drag run. Returns a new grid,
// or the same one if nothing changed, so a caller can tell whether to bump
// `dirty`.
function setCell(cells, row, col, value) {
  if (cells[row][col] === value) return cells
  var next = cloneGrid(cells)
  next[row][col] = value
  return next
}

// The single key-press toggle: flip to filled, or back to blank if it
// already was.
function toggleFill(cells, row, col) {
  return setCell(cells, row, col, cells[row][col] === FILLED ? UNKNOWN : FILLED)
}

function flatten(cells) {
  var out = []
  for (var r = 0; r < cells.length; r++) for (var c = 0; c < cells[r].length; c++) out.push(cells[r][c])
  return out
}

// The editor's own UNKNOWN/FILLED values already line up with the 0/1 shape
// `Puzzle.rowClues`/`columnClues`/`format` expect, but a distinct name keeps
// "editor cell state" and "the binary picture" from being read as the same
// concept by accident — and leaves room for the editor to grow a state this
// mapping is not the identity function for.
function toBinary(cells) {
  var out = []
  for (var r = 0; r < cells.length; r++) {
    var row = []
    for (var c = 0; c < cells[r].length; c++) row.push(cells[r][c] === FILLED ? 1 : 0)
    out.push(row)
  }
  return out
}

// The inverse, for loading a parsed puzzle's 0/1 cells back into the editor.
function fromBinary(binaryCells) {
  var out = []
  for (var r = 0; r < binaryCells.length; r++) {
    var row = []
    for (var c = 0; c < binaryCells[r].length; c++) row.push(binaryCells[r][c] ? FILLED : UNKNOWN)
    out.push(row)
  }
  return out
}

function hasContent(cells) {
  for (var r = 0; r < cells.length; r++)
    for (var c = 0; c < cells[r].length; c++) if (cells[r][c] === FILLED) return true
  return false
}

function dirNameForSize(size) {
  return size + "x" + size
}

// Turns whatever the player typed into a filesystem-safe stem: lowercase,
// runs of anything that isn't a letter or digit collapsed to one dash, no
// leading or trailing dash. An empty or all-punctuation name still needs a
// file to land in, hence the fallback.
function slugify(text) {
  var lowered = String(text === undefined || text === null ? "" : text).toLowerCase()
  var slug = lowered.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return slug || "pattern"
}

// The first file name in `takenNames` (base names, no directory or
// extension) not already used: `heart`, then `heart-2`, `heart-3`, ... A
// player saving a second picture with the same title should not silently
// clobber the first.
function uniqueFileName(baseName, takenNames) {
  var taken = {}
  for (var i = 0; i < takenNames.length; i++) taken[takenNames[i]] = true
  if (!taken[baseName]) return baseName
  var n = 2
  while (taken[baseName + "-" + n]) n++
  return baseName + "-" + n
}

if (typeof module !== "undefined") {
  module.exports = {
    UNKNOWN: UNKNOWN,
    FILLED: FILLED,
    SIZES: SIZES,
    DEFAULT_SIZE: DEFAULT_SIZE,
    createGrid: createGrid,
    cloneGrid: cloneGrid,
    setCell: setCell,
    toggleFill: toggleFill,
    flatten: flatten,
    toBinary: toBinary,
    fromBinary: fromBinary,
    hasContent: hasContent,
    dirNameForSize: dirNameForSize,
    slugify: slugify,
    uniqueFileName: uniqueFileName
  }
}
