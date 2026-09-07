// Constraint propagation over one line at a time — the reasoning a person
// actually does when they solve a nonogram by hand.
//
// It exists so the shipped pictures can be held to a standard: `tests/` runs
// every bundled pattern through `solve` and fails the build if any of them
// needs a guess. A player who loses time for a wrong answer is owed a puzzle
// that never requires one.

var UNKNOWN = -1
var EMPTY = 0
var FILL = 1

// Every arrangement of `clues` that is consistent with what is already known
// about the line, reduced to the cells all of them agree on. Arrangements are
// counted rather than collected: only the per-cell tally is needed, and a wide
// line with loose clues has more arrangements than are worth holding.
function solveLine(clues, known) {
  var length = known.length
  var runs = (clues.length === 1 && clues[0] === 0) ? [] : clues
  var fillCounts = []
  for (var i = 0; i < length; i++) fillCounts.push(0)
  var arrangements = 0
  var trial = []

  function layEmpty(from, to) {
    for (var i = from; i < to; i++) {
      if (known[i] === FILL) return false
      trial[i] = EMPTY
    }
    return true
  }

  function layFilled(from, to) {
    for (var i = from; i < to; i++) {
      if (known[i] === EMPTY) return false
      trial[i] = FILL
    }
    return true
  }

  function place(runIndex, from) {
    if (runIndex === runs.length) {
      if (!layEmpty(from, length)) return
      arrangements++
      for (var j = 0; j < length; j++) if (trial[j] === FILL) fillCounts[j]++
      return
    }

    // Width this run and every run after it occupies together, gaps included.
    var spanNeeded = -1
    for (var k = runIndex; k < runs.length; k++) spanNeeded += runs[k] + 1

    for (var start = from; start + spanNeeded <= length; start++) {
      // A known-filled cell in the gap can never be left empty, and moving the
      // run further right only widens that gap — so this line is exhausted.
      if (!layEmpty(from, start)) break
      if (!layFilled(start, start + runs[runIndex])) continue

      var after = start + runs[runIndex]
      if (after >= length) { place(runIndex + 1, after); continue }
      if (known[after] === FILL) continue
      trial[after] = EMPTY
      place(runIndex + 1, after + 1)
    }
  }

  place(0, 0)

  if (arrangements === 0) return { ok: false, line: known.slice() }

  var deduced = []
  for (var c = 0; c < length; c++) {
    if (fillCounts[c] === arrangements) deduced.push(FILL)
    else if (fillCounts[c] === 0) deduced.push(EMPTY)
    else deduced.push(UNKNOWN)
  }
  return { ok: true, line: deduced }
}

// A column lifted out of the grid and put back, so the column sweep below can
// read as the same statement as the row sweep rather than as a pair of loops.
function columnOf(grid, col) {
  var line = []
  for (var r = 0; r < grid.length; r++) line.push(grid[r][col])
  return line
}

function writeColumn(grid, col, line) {
  for (var r = 0; r < grid.length; r++) grid[r][col] = line[r]
}

function blankGrid(size) {
  var grid = []
  for (var r = 0; r < size; r++) {
    var row = []
    for (var c = 0; c < size; c++) row.push(UNKNOWN)
    grid.push(row)
  }
  return grid
}

function countUnknown(grid) {
  var total = 0
  for (var r = 0; r < grid.length; r++)
    for (var c = 0; c < grid[r].length; c++) if (grid[r][c] === UNKNOWN) total++
  return total
}

// Sweep rows and columns until a pass deduces nothing new. `solved` means the
// picture fell out of pure logic; `ok: false` means the clues contradict.
function solve(rowClues, columnClues) {
  var size = rowClues.length
  var grid = blankGrid(size)
  var passes = 0

  for (;;) {
    var before = countUnknown(grid)
    passes++

    for (var r = 0; r < size; r++) {
      var rowResult = solveLine(rowClues[r], grid[r])
      if (!rowResult.ok) return { ok: false, solved: false, grid: grid, passes: passes }
      grid[r] = rowResult.line
    }

    for (var c = 0; c < size; c++) {
      var columnResult = solveLine(columnClues[c], columnOf(grid, c))
      if (!columnResult.ok) return { ok: false, solved: false, grid: grid, passes: passes }
      writeColumn(grid, c, columnResult.line)
    }

    var after = countUnknown(grid)
    if (after === 0) return { ok: true, solved: true, grid: grid, passes: passes }
    if (after === before) return { ok: true, solved: false, grid: grid, passes: passes }
  }
}

// True when the picture is reachable by logic alone from its own clues.
function isLogicallySolvable(puzzle) {
  var result = solve(puzzle.rowClues, puzzle.columnClues)
  if (!result.solved) return false
  for (var r = 0; r < puzzle.size; r++)
    for (var c = 0; c < puzzle.size; c++)
      if (result.grid[r][c] !== (puzzle.cells[r][c] ? FILL : EMPTY)) return false
  return true
}

if (typeof module !== "undefined") {
  module.exports = {
    UNKNOWN: UNKNOWN,
    EMPTY: EMPTY,
    FILL: FILL,
    solveLine: solveLine,
    columnOf: columnOf,
    writeColumn: writeColumn,
    blankGrid: blankGrid,
    countUnknown: countUnknown,
    solve: solve,
    isLogicallySolvable: isLogicallySolvable
  }
}
