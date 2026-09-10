const test = require("node:test")
const assert = require("node:assert/strict")

const Puzzle = require("../Puzzle.js")
const Game = require("../Game.js")

// ..#..   a small plus sign, five filled cells
// .###.
// ..#..
function plus() {
  return Puzzle.parse(".#.\n###\n.#.\n", "plus.picross")
}

function newGame(difficultyId = "easy") {
  return Game.createGame(plus(), difficultyId)
}

test("difficulty is a grid size and a clock", () => {
  assert.equal(Game.difficultyFor("easy").size, 5)
  assert.equal(Game.difficultyFor("normal").size, 10)
  assert.equal(Game.difficultyFor("hard").size, 15)
  assert.ok(Game.difficultyFor("easy").seconds < Game.difficultyFor("hard").seconds)
})

test("an unknown difficulty falls back rather than failing", () => {
  assert.equal(Game.difficultyFor("nonsense").id, "normal")
  assert.equal(Game.difficultyForSize(7), null)
  assert.equal(Game.difficultyForSize(15).id, "hard")
})

test("mistakes cost 2, then 4, then 8 minutes forever", () => {
  assert.equal(Game.penaltyMsFor(1), 120000)
  assert.equal(Game.penaltyMsFor(2), 240000)
  assert.equal(Game.penaltyMsFor(3), 480000)
  assert.equal(Game.penaltyMsFor(9), 480000)
})

test("a new game starts full of time and empty of marks", () => {
  const state = newGame()
  assert.equal(state.status, "playing")
  assert.equal(state.remainingMs, 600000)
  assert.equal(state.mistakes, 0)
  assert.equal(state.remainingFilled, 5)
  assert.equal(state.board.length, 9)
  assert.ok(state.board.every(cell => cell === Game.UNKNOWN))
})

test("a correct guess fills the cell and costs nothing", () => {
  const state = newGame()
  const result = Game.guess(state, 1, 1)

  assert.equal(result.correct, true)
  assert.equal(result.penaltyMs, 0)
  assert.equal(Game.cellAt(state, 1, 1), Game.FILLED)
  assert.equal(state.remainingMs, 600000)
  assert.equal(state.remainingFilled, 4)
})

test("a correct guess can be undone, unlocking the cell again", () => {
  const state = newGame()
  Game.guess(state, 1, 1)
  assert.equal(Game.unguess(state, 1, 1), true)
  assert.equal(Game.cellAt(state, 1, 1), Game.UNKNOWN)
  assert.equal(state.remainingFilled, 5)

  assert.equal(Game.guess(state, 1, 1).correct, true)
  assert.equal(state.remainingFilled, 4)
})

test("undoing an unfilled cell does nothing", () => {
  const state = newGame()
  assert.equal(Game.unguess(state, 1, 1), false)
  Game.mark(state, 1, 1)
  assert.equal(Game.unguess(state, 1, 1), false)
  assert.equal(Game.cellAt(state, 1, 1), Game.MARKED)
})

test("a wrong guess takes the time but leaves the cell open to try again", () => {
  const state = newGame()
  const result = Game.guess(state, 0, 0)

  assert.equal(result.correct, false)
  assert.equal(result.penaltyMs, 120000)
  assert.equal(Game.cellAt(state, 0, 0), Game.UNKNOWN)
  assert.equal(state.remainingMs, 480000)
  assert.equal(state.mistakes, 1)
})

test("penalties escalate across a game", () => {
  const state = newGame()
  Game.guess(state, 0, 0)
  Game.guess(state, 0, 2)
  assert.equal(state.remainingMs, 600000 - 120000 - 240000)
  assert.equal(state.mistakes, 2)
})

test("a filled cell cannot be revisited by either hand", () => {
  const state = newGame()
  Game.guess(state, 1, 1)
  assert.equal(Game.guess(state, 1, 1).changed, false)
  assert.equal(Game.mark(state, 1, 1), false)
})

test("a forgotten wrong guess can be made again, at a steeper price", () => {
  const state = newGame()
  Game.guess(state, 0, 0)
  assert.equal(state.mistakes, 1)

  const second = Game.guess(state, 0, 0)
  assert.equal(second.changed, true)
  assert.equal(second.correct, false)
  assert.equal(second.penaltyMs, 240000)
  assert.equal(state.mistakes, 2, "the board forgot, but the clock didn't")
})

test("your own cross-out toggles freely and costs nothing", () => {
  const state = newGame()
  assert.equal(Game.mark(state, 0, 0), true)
  assert.equal(Game.cellAt(state, 0, 0), Game.MARKED)
  assert.equal(Game.mark(state, 0, 0), true)
  assert.equal(Game.cellAt(state, 0, 0), Game.UNKNOWN)
  assert.equal(state.remainingMs, 600000)
})

test("a marked cell can still be guessed afterwards", () => {
  const state = newGame()
  Game.mark(state, 1, 1)
  assert.equal(Game.guess(state, 1, 1).correct, true)
})

test("finding every filled cell wins, and marks are irrelevant to it", () => {
  const state = newGame()
  Game.mark(state, 0, 0)
  for (const [row, col] of [[0, 1], [1, 0], [1, 1], [1, 2], [2, 1]]) Game.guess(state, row, col)

  assert.equal(state.status, "won")
  assert.equal(state.remainingFilled, 0)
})

test("running out of time loses, and further moves do nothing", () => {
  const state = newGame()
  assert.equal(Game.tick(state, 599999), "playing")
  assert.equal(Game.tick(state, 1), "lost")
  assert.equal(state.remainingMs, 0)

  assert.equal(Game.guess(state, 1, 1).changed, false)
  assert.equal(Game.mark(state, 0, 0), false)
  assert.equal(Game.moveCursor(state, 1, 0), false)
  assert.equal(Game.tick(state, 1000), "lost")
})

test("a mistake that empties the clock ends the game there", () => {
  const state = newGame()
  state.remainingMs = 60000
  Game.guess(state, 0, 0)
  assert.equal(state.remainingMs, 0)
  assert.equal(state.status, "lost")
})

test("the last correct cell wins even when it is also the last second", () => {
  const state = newGame()
  for (const [row, col] of [[0, 1], [1, 0], [1, 1], [1, 2]]) Game.guess(state, row, col)
  state.remainingMs = 1
  Game.guess(state, 2, 1)
  assert.equal(state.status, "won")
})

test("the cursor wraps at every edge", () => {
  const state = newGame()
  Game.moveCursor(state, -1, -1)
  assert.equal(state.cursorRow, 2)
  assert.equal(state.cursorCol, 2)
  Game.moveCursor(state, 1, 1)
  assert.equal(state.cursorRow, 0)
  assert.equal(state.cursorCol, 0)
})

test("the cursor can be placed directly, but not off the board", () => {
  const state = newGame()
  assert.equal(Game.setCursor(state, 2, 1), true)
  assert.equal(state.cursorRow, 2)
  assert.equal(Game.setCursor(state, 3, 0), false)
  assert.equal(Game.setCursor(state, -1, 0), false)
  assert.equal(state.cursorRow, 2, "a rejected placement leaves the cursor alone")
})

test("guesses and marks off the board are ignored", () => {
  const state = newGame()
  assert.equal(Game.guess(state, 5, 5).changed, false)
  assert.equal(Game.mark(state, -1, 0), false)
  assert.equal(Game.cellAt(state, 9, 9), Game.UNKNOWN)
})

test("a line is solved once its filled cells are all found — marks aside", () => {
  const state = newGame()
  assert.equal(Game.rowSolved(state, 1), false)
  Game.guess(state, 1, 0)
  Game.guess(state, 1, 1)
  assert.equal(Game.rowSolved(state, 1), false)
  Game.guess(state, 1, 2)
  assert.equal(Game.rowSolved(state, 1), true)

  assert.equal(Game.columnSolved(state, 0), true, "a column whose only run is already found reads solved")
  assert.equal(Game.columnSolved(state, 1), false)
})

test("the clock formats as minutes and seconds, rounding up", () => {
  assert.equal(Game.formatClock(0), "00:00")
  assert.equal(Game.formatClock(1), "00:01")
  assert.equal(Game.formatClock(1000), "00:01")
  assert.equal(Game.formatClock(61000), "01:01")
  assert.equal(Game.formatClock(600000), "10:00")
  assert.equal(Game.formatClock(-5000), "00:00")
  assert.equal(Game.formatPenalty(120000), "-02:00")
})

test("the grade rewards a clean, fast finish", () => {
  const clean = newGame()
  for (const [row, col] of [[0, 1], [1, 0], [1, 1], [1, 2], [2, 1]]) Game.guess(clean, row, col)
  assert.equal(Game.grade(clean), "PERFECT")

  const scraped = newGame()
  Game.guess(scraped, 0, 0)
  for (const [row, col] of [[0, 1], [1, 0], [1, 1], [1, 2], [2, 1]]) Game.guess(scraped, row, col)
  assert.equal(Game.grade(scraped), "GREAT")

  scraped.remainingMs = scraped.totalMs * 0.3
  assert.equal(Game.grade(scraped), "GOOD")
  scraped.remainingMs = scraped.totalMs * 0.05
  assert.equal(Game.grade(scraped), "CLEARED")

  const lost = newGame()
  Game.tick(lost, lost.remainingMs)
  assert.equal(Game.grade(lost), "")
})

test("a board is as big as the picture, whatever the difficulty label says", () => {
  const state = Game.createGame(plus(), "hard")
  assert.equal(state.size, 3)
  assert.equal(state.board.length, 9)
  assert.equal(state.totalMs, Game.difficultyFor("hard").seconds * 1000)
})

test("the clock pads only the halves that need it", () => {
  assert.equal(Game.formatClock(90000), "01:30")
  assert.equal(Game.formatClock(599000), "09:59")
})

test("a game with no clock at all still grades", () => {
  const state = newGame()
  state.status = "won"
  state.mistakes = 1
  state.totalMs = 0
  assert.equal(Game.grade(state), "CLEARED")
})

test("a hint fills every solution cell in one random row and column, free", () => {
  const state = newGame()
  const original = Math.random
  Math.random = () => 0.4 // floor(0.4 * 3) === 1, for both row and col
  try {
    const hint = Game.revealHint(state)
    assert.equal(hint.row, 1)
    assert.equal(hint.col, 1)
    // Every solution cell the reveal touched, in the order it touched them.
    assert.deepEqual(hint.cells, [
      { row: 1, col: 0 }, { row: 1, col: 1 }, { row: 1, col: 2 },
      { row: 0, col: 1 }, { row: 2, col: 1 }
    ])
  } finally {
    Math.random = original
  }

  // Row 1 ("###") and column 1 (".#.", "###", ".#." down the middle) between
  // them cover every solution cell of the plus, but nothing outside it.
  assert.equal(state.remainingFilled, 0)
  assert.equal(state.status, "won")
  assert.equal(state.mistakes, 0)
  assert.equal(state.remainingMs, 600000)
  assert.equal(Game.cellAt(state, 0, 0), Game.UNKNOWN)
  assert.equal(Game.cellAt(state, 0, 2), Game.UNKNOWN)
  assert.equal(Game.cellAt(state, 2, 0), Game.UNKNOWN)
  assert.equal(Game.cellAt(state, 2, 2), Game.UNKNOWN)
})

test("a hint leaves cells the picture doesn't want alone, and does nothing once the game is over", () => {
  const state = newGame()
  const original = Math.random
  Math.random = () => 0 // row 0, col 0
  try {
    const hint = Game.revealHint(state)
    assert.deepEqual(hint.cells, [{ row: 0, col: 1 }, { row: 1, col: 0 }])
  } finally {
    Math.random = original
  }

  // Row 0 is ".#." and column 0 is ".#." (down the left edge of the plus) —
  // (0, 1) and (1, 0) are the only solution cells between them.
  assert.equal(Game.cellAt(state, 0, 0), Game.UNKNOWN)
  assert.equal(Game.cellAt(state, 0, 1), Game.FILLED)
  assert.equal(Game.cellAt(state, 1, 0), Game.FILLED)
  assert.equal(state.remainingFilled, 3)
  assert.equal(state.status, "playing")

  state.status = "lost"
  assert.equal(Game.revealHint(state), null)
})

test("winning stops the cursor keys the same way losing does", () => {
  const state = newGame()
  for (const [row, col] of [[0, 1], [1, 0], [1, 1], [1, 2], [2, 1]]) Game.guess(state, row, col)

  assert.equal(state.status, "won")
  assert.equal(Game.moveCursor(state, 1, 0), false)
  // setCursor is bounds-checked but not status-checked: the panel only calls
  // it while playing, so the board can never be pointed at after the finish.
  assert.equal(Game.setCursor(state, 2, 2), true)
})
