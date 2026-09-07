const test = require("node:test")
const assert = require("node:assert/strict")

const Game = require("../Game.js")
const Solver = require("../Solver.js")
const { loadAll, report } = require("./validate-patterns.js")

const entries = loadAll()

test("there are pictures to play", () => {
  assert.ok(entries.length > 0)
})

test("every difficulty has pictures", () => {
  for (const difficulty of Game.DIFFICULTIES) {
    const matching = entries.filter(entry => entry.result.ok && entry.result.size === difficulty.size)
    assert.ok(matching.length > 0, `no ${difficulty.size}×${difficulty.size} pictures for ${difficulty.id}`)
  }
})

for (const entry of entries) {
  test(`${entry.file} parses, fits a difficulty, and needs no guessing`, () => {
    const status = report(entry)
    assert.equal(status.ok, true, status.reason)
    assert.ok(status.puzzle.name.length > 0)
    assert.ok(status.puzzle.filled > 0)
  })
}

test("no two pictures share a name", () => {
  const seen = new Map()
  for (const entry of entries) {
    if (!entry.result.ok) continue
    const previous = seen.get(entry.result.name)
    assert.equal(previous, undefined, `"${entry.result.name}" is used by both ${previous} and ${entry.file}`)
    seen.set(entry.result.name, entry.file)
  }
})

test("a picture is winnable by playing the solution the solver found", () => {
  // End to end: solve a bundled picture with the solver, play those cells
  // through the real rules, and expect a clean win.
  const entry = entries.find(candidate => candidate.result.ok)
  const puzzle = entry.result
  const solved = Solver.solve(puzzle.rowClues, puzzle.columnClues)
  const state = Game.createGame(puzzle, "easy")

  for (let row = 0; row < puzzle.size; row++)
    for (let column = 0; column < puzzle.size; column++)
      if (solved.grid[row][column] === Solver.FILL) Game.guess(state, row, column)

  assert.equal(state.status, "won")
  assert.equal(state.mistakes, 0)
  assert.equal(Game.grade(state), "PERFECT")
})
