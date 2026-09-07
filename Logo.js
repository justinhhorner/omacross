// The square Omarchy mark, as a 13x13 nonogram picture.
//
// Transcribed from `/usr/share/omarchy/icon.txt`, whose block art is the same
// mark drawn at 4 columns and 2 lines per pixel. Held here as literal rows so
// the title screen has no dependency on a file that may not be installed.
var LOGO_ROWS = [
  "#############",
  "#.....#.....#",
  "#.#####..##.#",
  "#.#.......#.#",
  "#.#.......#.#",
  "#.#.......#.#",
  "###.......#.#",
  "#.#.......#.#",
  "#.#.......#.#",
  "#.#.......#.#",
  "#.#########.#",
  "#.....#.....#",
  "#######.#####"
]

var LOGO_SIZE = LOGO_ROWS.length

function logoCells() {
  var cells = []
  for (var r = 0; r < LOGO_ROWS.length; r++) {
    var row = []
    for (var c = 0; c < LOGO_ROWS[r].length; c++) row.push(LOGO_ROWS[r].charAt(c) === "#" ? 1 : 0)
    cells.push(row)
  }
  return cells
}

function logoFlat() {
  var cells = logoCells()
  var flat = []
  for (var r = 0; r < cells.length; r++)
    for (var c = 0; c < cells[r].length; c++) flat.push(cells[r][c])
  return flat
}

// Deterministic hash in [0, 1). The title animation needs per-cell randomness
// that is stable across repaints — a live `Math.random()` in a binding would
// reshuffle the grid on every frame instead of resolving it.
function hash01(seed, salt) {
  var h = (seed | 0) * 374761393 + (salt | 0) * 668265263
  h = (h ^ (h >>> 13)) | 0
  h = (h * 1274126177) | 0
  h = (h ^ (h >>> 16)) >>> 0
  return h / 4294967296
}

// Each cell gets its own moment to settle, spread across the run. Sorting the
// spread by distance from the center biases the reveal outward from the middle,
// which reads as the mark assembling rather than as noise thinning out.
function settleThreshold(index, size) {
  var row = Math.floor(index / size)
  var col = index % size
  var center = (size - 1) / 2
  var distance = Math.sqrt(Math.pow(row - center, 2) + Math.pow(col - center, 2))
  var normalized = distance / (Math.sqrt(2) * center)
  // Two thirds ordering, one third jitter: the wave is legible but no two
  // neighbours land on exactly the same frame.
  return Math.min(0.98, normalized * 0.66 + hash01(index, 7) * 0.34)
}

// What a cell shows before it has settled: static that changes every tick.
function noiseAt(index, tick) {
  return hash01(index * 31 + tick * 17, tick) > 0.55 ? 1 : 0
}

// The value a cell paints at animation `progress` (0..1) on frame `tick`.
function titleCellAt(index, size, progress, tick, cells) {
  if (progress >= settleThreshold(index, size)) return cells[index]
  return noiseAt(index, tick)
}

if (typeof module !== "undefined") {
  module.exports = {
    LOGO_ROWS: LOGO_ROWS,
    LOGO_SIZE: LOGO_SIZE,
    logoCells: logoCells,
    logoFlat: logoFlat,
    hash01: hash01,
    settleThreshold: settleThreshold,
    noiseAt: noiseAt,
    titleCellAt: titleCellAt
  }
}
