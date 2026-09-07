const test = require("node:test")
const assert = require("node:assert/strict")

const Puzzle = require("../Puzzle.js")

test("a picture row is any line made only of cell characters", () => {
  assert.equal(Puzzle.classifyLine("#.#.#").kind, "row")
  assert.equal(Puzzle.classifyLine("  ##..  ").kind, "row")
  assert.equal(Puzzle.classifyLine("").kind, "blank")
})

test("key = value lines are metadata, in either separator", () => {
  assert.deepEqual(Puzzle.classifyLine("name = Heart"), { kind: "meta", key: "name", value: "Heart" })
  assert.deepEqual(Puzzle.classifyLine("Author: Someone"), { kind: "meta", key: "author", value: "Someone" })
})

test("prose lines are comments, so # stays free to mean filled", () => {
  assert.equal(Puzzle.classifyLine("# a note about this picture").kind, "comment")
  assert.equal(Puzzle.classifyLine("; another note").kind, "comment")
  // The line that makes it work: a space is not a cell character.
  assert.equal(Puzzle.classifyLine("# #").kind, "comment")
})

test("every filled alias reads as filled and every empty alias as empty", () => {
  for (const character of "#*XxOo1@") assert.equal(Puzzle.isFilledChar(character), true, character)
  for (const character of ".-_0") assert.equal(Puzzle.isFilledChar(character), false, character)
})

test("parse reads metadata and the picture", () => {
  const result = Puzzle.parse("name = Heart\nauthor = Someone\n\n.#.\n###\n.#.\n", "heart.picross")

  assert.equal(result.ok, true)
  assert.equal(result.name, "Heart")
  assert.equal(result.author, "Someone")
  assert.equal(result.size, 3)
  assert.equal(result.filled, 5)
  assert.deepEqual(result.cells, [[0, 1, 0], [1, 1, 1], [0, 1, 0]])
})

test("the file name titles a picture that does not name itself", () => {
  assert.equal(Puzzle.parse("#\n", "big-red_boat.picross").name, "Big red boat")
  assert.equal(Puzzle.titleFromFileName("/some/where/ghost.picross"), "Ghost")
  assert.equal(Puzzle.titleFromFileName(""), "Untitled")
})

test("ragged rows pad out to the widest one", () => {
  const result = Puzzle.parse("###\n#\n##\n", "x")
  assert.deepEqual(result.cells, [[1, 1, 1], [1, 0, 0], [1, 1, 0]])
})

test("empty margins are trimmed and the picture recentered in a square", () => {
  const result = Puzzle.parse("....\n.##.\n.##.\n....\n", "x")
  assert.equal(result.size, 2)
  assert.deepEqual(result.cells, [[1, 1], [1, 1]])
})

test("a non-square picture is centered in a square board", () => {
  const result = Puzzle.parse("#####\n#####\n", "x")
  assert.equal(result.size, 5)
  // Two rows of five, centered vertically in a 5x5 board.
  assert.deepEqual(result.cells[0], [0, 0, 0, 0, 0])
  assert.deepEqual(result.cells[1], [1, 1, 1, 1, 1])
  assert.deepEqual(result.cells[2], [1, 1, 1, 1, 1])
  assert.deepEqual(result.cells[3], [0, 0, 0, 0, 0])
})

test("a file with no picture is reported, not thrown", () => {
  assert.deepEqual(Puzzle.parse("name = Nothing\n", "x"), { ok: false, error: "no picture rows found" })
  assert.deepEqual(Puzzle.parse("....\n....\n", "x"), { ok: false, error: "picture has no filled cells" })
  assert.equal(Puzzle.parse(undefined, "x").ok, false)
  assert.equal(Puzzle.parse(null, "x").ok, false)
})

test("clues are the run lengths, and an empty line is clued zero", () => {
  assert.deepEqual(Puzzle.runsOf([1, 1, 0, 1, 0, 1, 1, 1]), [2, 1, 3])
  assert.deepEqual(Puzzle.runsOf([0, 0, 0]), [0])
  assert.deepEqual(Puzzle.runsOf([1, 1, 1]), [3])
})

test("row and column clues describe the same picture from both sides", () => {
  const result = Puzzle.parse("#.#\n###\n#.#\n", "x")
  assert.deepEqual(result.rowClues, [[1, 1], [3], [1, 1]])
  assert.deepEqual(result.columnClues, [[3], [1], [3]])
})

test("format writes a file that parses back to the same picture", () => {
  const original = Puzzle.parse("name = Arrow\nauthor = Omacross\n\n..#..\n.###.\n#####\n..#..\n..#..\n", "arrow")
  const roundTripped = Puzzle.parse(Puzzle.format(original), "ignored")

  assert.equal(roundTripped.name, original.name)
  assert.equal(roundTripped.author, original.author)
  assert.deepEqual(roundTripped.cells, original.cells)
  assert.deepEqual(roundTripped.rowClues, original.rowClues)
})

test("windows line endings survive", () => {
  const result = Puzzle.parse("name = CRLF\r\n\r\n##\r\n##\r\n", "x")
  assert.equal(result.ok, true)
  assert.equal(result.name, "CRLF")
  assert.deepEqual(result.cells, [[1, 1], [1, 1]])
})
