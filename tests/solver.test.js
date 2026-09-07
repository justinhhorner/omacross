const test = require("node:test")
const assert = require("node:assert/strict")

const Puzzle = require("../Puzzle.js")
const Solver = require("../Solver.js")

const { UNKNOWN, EMPTY, FILL } = Solver

test("a full line is fully determined", () => {
  assert.deepEqual(Solver.solveLine([3], [UNKNOWN, UNKNOWN, UNKNOWN]).line, [FILL, FILL, FILL])
})

test("an empty line is fully determined", () => {
  assert.deepEqual(Solver.solveLine([0], [UNKNOWN, UNKNOWN]).line, [EMPTY, EMPTY])
})

test("overlap is deduced even when the run can slide", () => {
  // A run of 3 in 4 cells must cover the middle two wherever it sits.
  assert.deepEqual(Solver.solveLine([3], new Array(4).fill(UNKNOWN)).line, [UNKNOWN, FILL, FILL, UNKNOWN])
})

test("a run with no room to slide is pinned by what is already known", () => {
  const known = [UNKNOWN, UNKNOWN, UNKNOWN, UNKNOWN, FILL]
  assert.deepEqual(Solver.solveLine([2], known).line, [EMPTY, EMPTY, EMPTY, FILL, FILL])
})

test("multiple runs are packed with their gaps", () => {
  assert.deepEqual(Solver.solveLine([1, 1], [UNKNOWN, UNKNOWN, UNKNOWN]).line, [FILL, EMPTY, FILL])
})

test("clues that cannot fit are reported as a contradiction", () => {
  assert.equal(Solver.solveLine([3], [UNKNOWN, UNKNOWN]).ok, false)
  assert.equal(Solver.solveLine([1], [EMPTY, EMPTY]).ok, false)
  assert.equal(Solver.solveLine([0], [FILL, UNKNOWN]).ok, false)
})

test("a whole picture falls out of its own clues", () => {
  const puzzle = Puzzle.parse("#.#\n###\n#.#\n", "h")
  const result = Solver.solve(puzzle.rowClues, puzzle.columnClues)

  assert.equal(result.solved, true)
  assert.equal(Solver.countUnknown(result.grid), 0)
  assert.equal(Solver.isLogicallySolvable(puzzle), true)
})

test("an ambiguous picture is reported as needing a guess", () => {
  // Two diagonals share these clues, so logic alone cannot pick one.
  const puzzle = Puzzle.parse("#.\n.#\n", "diag")
  const result = Solver.solve(puzzle.rowClues, puzzle.columnClues)

  assert.equal(result.ok, true)
  assert.equal(result.solved, false)
  assert.ok(Solver.countUnknown(result.grid) > 0)
  assert.equal(Solver.isLogicallySolvable(puzzle), false)
})

test("contradictory clues stop the sweep instead of looping", () => {
  const result = Solver.solve([[2], [0]], [[0], [0]])
  assert.equal(result.ok, false)
  assert.equal(result.solved, false)
})

test("a blank grid starts entirely unknown", () => {
  assert.equal(Solver.countUnknown(Solver.blankGrid(4)), 16)
})

test("a contradiction in a row stops the sweep as surely as one in a column", () => {
  // Two rows, so a two-wide grid — and a row clue of 3 cannot be laid in it.
  const result = Solver.solve([[3], [0]], [[1], [1], [1]])
  assert.equal(result.ok, false)
  assert.equal(result.solved, false)
})

test("clues that solve cleanly to a different picture are not solvable", () => {
  // `parse` derives clues from the cells, so the two can only disagree if
  // something hand-built them. The check is that solvable means "the solver
  // reaches this picture", not merely "the solver reaches some picture".
  const clues = { size: 2, rowClues: [[2], [0]], columnClues: [[1], [1]] }
  assert.equal(Solver.isLogicallySolvable(Object.assign({ cells: [[1, 1], [0, 0]] }, clues)), true)
  assert.equal(Solver.isLogicallySolvable(Object.assign({ cells: [[0, 0], [1, 1]] }, clues)), false)
})

test("a column can be lifted out of the grid and put back", () => {
  const grid = Solver.blankGrid(3)
  Solver.writeColumn(grid, 1, [FILL, EMPTY, FILL])

  assert.deepEqual(Solver.columnOf(grid, 1), [FILL, EMPTY, FILL])
  assert.deepEqual(Solver.columnOf(grid, 0), [UNKNOWN, UNKNOWN, UNKNOWN])
})
