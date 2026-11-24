// The rules, as a pure state machine. No QML, no timers, no rendering — the
// panel owns the clock and calls `tick`, and every other transition is a
// function from state to state so `tests/` can play whole games.
//
// Modelled on Mario's Picross (Game Boy, 1995):
//   * a countdown, not a stopwatch
//   * a wrong guess costs time, and each further mistake costs more
//   * a wrong guess is not remembered by the board — only by the clock, so a
//     forgotten cell can always be tried again (at the going rate)
//   * a correct fill can be undone, freeing the cell to be guessed again
//   * the picture's name is withheld until you have solved it

var UNKNOWN = 0   // untouched
var FILLED = 1    // correctly filled — locked
var MARKED = 2    // player's own cross-out, freely toggled

// Grid size and clock together are the difficulty. The original gives every
// puzzle 30:00 regardless of size; splitting the allowance by size is what
// makes a 5x5 an easy puzzle rather than merely a short one.
var DIFFICULTIES = [
  { id: "easy", label: "Easy", size: 5, seconds: 600 },
  { id: "normal", label: "Normal", size: 10, seconds: 1800 },
  { id: "hard", label: "Hard", size: 15, seconds: 2700 }
]

// 2:00, then 4:00, then 8:00 for the third and every mistake after it.
var PENALTY_STEPS_MS = [120000, 240000, 480000]

function difficultyFor(id) {
  for (var i = 0; i < DIFFICULTIES.length; i++) if (DIFFICULTIES[i].id === id) return DIFFICULTIES[i]
  return DIFFICULTIES[1]
}

function difficultyForSize(size) {
  for (var i = 0; i < DIFFICULTIES.length; i++) if (DIFFICULTIES[i].size === size) return DIFFICULTIES[i]
  return null
}

// `mistakeNumber` is 1-based: the cost of the mistake being made right now.
function penaltyMsFor(mistakeNumber) {
  var index = Math.max(1, mistakeNumber) - 1
  return PENALTY_STEPS_MS[Math.min(index, PENALTY_STEPS_MS.length - 1)]
}

function createBoard(size) {
  var board = []
  for (var i = 0; i < size * size; i++) board.push(UNKNOWN)
  return board
}

function createGame(puzzle, difficultyId) {
  var difficulty = difficultyFor(difficultyId)
  return {
    puzzle: puzzle,
    difficultyId: difficulty.id,
    size: puzzle.size,
    board: createBoard(puzzle.size),
    remainingMs: difficulty.seconds * 1000,
    totalMs: difficulty.seconds * 1000,
    mistakes: 0,
    // Counts down to zero as correct cells are found; the win check is a
    // comparison against a running total rather than a sweep of the board.
    remainingFilled: puzzle.filled,
    status: "playing",
    cursorRow: 0,
    cursorCol: 0
  }
}

function indexOf(state, row, col) {
  return row * state.size + col
}

function inBounds(state, row, col) {
  return row >= 0 && row < state.size && col >= 0 && col < state.size
}

function cellAt(state, row, col) {
  return inBounds(state, row, col) ? state.board[indexOf(state, row, col)] : UNKNOWN
}

function solutionAt(state, row, col) {
  return state.puzzle.cells[row][col] ? 1 : 0
}

// A locked cell is a confirmed fill: it resists guesses and marks alike until
// `unguess` deliberately reopens it. A mistake decides nothing — the board
// never records it — so it stays open to the mouse and the keyboard anyway.
function isLocked(value) {
  return value === FILLED
}

// Wraps at the edges. On a board this small, running off the right edge onto
// the next row's start is friendlier than stopping dead.
function moveCursor(state, dRow, dCol) {
  if (state.status !== "playing") return false
  var size = state.size
  state.cursorRow = ((state.cursorRow + dRow) % size + size) % size
  state.cursorCol = ((state.cursorCol + dCol) % size + size) % size
  return true
}

function setCursor(state, row, col) {
  if (!inBounds(state, row, col)) return false
  state.cursorRow = row
  state.cursorCol = col
  return true
}

function checkFinished(state) {
  if (state.remainingFilled <= 0) state.status = "won"
  else if (state.remainingMs <= 0) { state.remainingMs = 0; state.status = "lost" }
}

// The primary move: claim a cell is part of the picture.
//
// Right, and it stays filled. Wrong, and the clock takes the hit — which is
// the whole tension of the game, so the result reports the cost for the UI to
// show — but the cell itself is left exactly as it was, free to guess again.
function guess(state, row, col) {
  var result = { changed: false, correct: false, penaltyMs: 0, status: state.status }
  if (state.status !== "playing" || !inBounds(state, row, col)) return result

  var index = indexOf(state, row, col)
  if (isLocked(state.board[index])) return result

  result.changed = true
  if (solutionAt(state, row, col)) {
    state.board[index] = FILLED
    state.remainingFilled--
    result.correct = true
  } else {
    state.mistakes++
    var cost = penaltyMsFor(state.mistakes)
    state.remainingMs = Math.max(0, state.remainingMs - cost)
    result.penaltyMs = cost
  }

  checkFinished(state)
  result.status = state.status
  return result
}

// The take-back: unlock a correct fill, returning it to unknown so it can be
// guessed again. Free of charge — undoing a guess is not a mistake — and it
// un-counts toward the win.
function unguess(state, row, col) {
  if (state.status !== "playing" || !inBounds(state, row, col)) return false
  var index = indexOf(state, row, col)
  if (!isLocked(state.board[index])) return false

  state.board[index] = UNKNOWN
  state.remainingFilled++
  return true
}

// The bookkeeping move: cross a cell you have reasoned is empty. Costs
// nothing, proves nothing, and toggles freely — it is a note to yourself.
function mark(state, row, col) {
  if (state.status !== "playing" || !inBounds(state, row, col)) return false
  var index = indexOf(state, row, col)
  if (isLocked(state.board[index])) return false
  state.board[index] = state.board[index] === MARKED ? UNKNOWN : MARKED
  return true
}

// A one-time hint: pick a random row and a random column and fill every
// solution cell in them outright, as if each had been guessed correctly.
// Free — it costs no time and is never counted as a mistake — which is why
// it's only ever offered before the clock has started.
// Records into `cells` (in the order revealed) so the view can play a
// staggered reveal animation over exactly — and only — the cells that
// actually changed.
function revealCell(state, row, col, cells) {
  var index = indexOf(state, row, col)
  if (state.board[index] === FILLED) return
  if (solutionAt(state, row, col)) {
    state.board[index] = FILLED
    state.remainingFilled--
    cells.push({ row: row, col: col })
  }
}

function revealHint(state) {
  if (state.status !== "playing") return null
  var row = Math.floor(Math.random() * state.size)
  var col = Math.floor(Math.random() * state.size)
  var cells = []
  for (var c = 0; c < state.size; c++) revealCell(state, row, c, cells)
  for (var r = 0; r < state.size; r++) revealCell(state, r, col, cells)
  checkFinished(state)
  return { row: row, col: col, cells: cells }
}

function tick(state, deltaMs) {
  if (state.status !== "playing") return state.status
  state.remainingMs = Math.max(0, state.remainingMs - deltaMs)
  checkFinished(state)
  return state.status
}

// A line is done when every cell the picture wants in it has been found. Wrong
// guesses can never fill a cell, so "found them all" is the same statement as
// "these clues are satisfied" — which is what lets the view dim solved clues.
function rowSolved(state, row) {
  for (var c = 0; c < state.size; c++)
    if (solutionAt(state, row, c) && state.board[indexOf(state, row, c)] !== FILLED) return false
  return true
}

function columnSolved(state, col) {
  for (var r = 0; r < state.size; r++)
    if (solutionAt(state, r, col) && state.board[indexOf(state, r, col)] !== FILLED) return false
  return true
}

function pad2(value) {
  return (value < 10 ? "0" : "") + value
}

function formatClock(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  var minutes = Math.floor(total / 60)
  var seconds = total % 60
  return pad2(minutes) + ":" + pad2(seconds)
}

function formatPenalty(ms) {
  return "-" + formatClock(ms)
}

// Rank the finish the way an arcade would: time left, against mistakes made.
function grade(state) {
  if (state.status !== "won") return ""
  if (state.mistakes === 0) return "PERFECT"
  var fraction = state.totalMs > 0 ? state.remainingMs / state.totalMs : 0
  if (fraction >= 0.5) return "GREAT"
  if (fraction >= 0.2) return "GOOD"
  return "CLEARED"
}

if (typeof module !== "undefined") {
  module.exports = {
    UNKNOWN: UNKNOWN,
    FILLED: FILLED,
    MARKED: MARKED,
    DIFFICULTIES: DIFFICULTIES,
    PENALTY_STEPS_MS: PENALTY_STEPS_MS,
    difficultyFor: difficultyFor,
    difficultyForSize: difficultyForSize,
    penaltyMsFor: penaltyMsFor,
    createBoard: createBoard,
    createGame: createGame,
    indexOf: indexOf,
    inBounds: inBounds,
    cellAt: cellAt,
    solutionAt: solutionAt,
    isLocked: isLocked,
    moveCursor: moveCursor,
    setCursor: setCursor,
    guess: guess,
    unguess: unguess,
    mark: mark,
    revealHint: revealHint,
    tick: tick,
    rowSolved: rowSolved,
    columnSolved: columnSolved,
    formatClock: formatClock,
    formatPenalty: formatPenalty,
    grade: grade
  }
}
