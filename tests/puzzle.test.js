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

test("# reads as filled and . as empty", () => {
  assert.equal(Puzzle.isFilledChar("#"), true)
  assert.equal(Puzzle.isFilledChar("."), false)
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

test("metadata takes the last value, and an empty one falls back", () => {
  assert.equal(Puzzle.parse("name = First\nname = Second\n#\n", "x").name, "Second")
  assert.equal(Puzzle.parse("name =\n#\n", "duck.picross").name, "Duck")
  // Keys may carry digits and dashes; a picture editor will want its own.
  assert.deepEqual(Puzzle.classifyLine("map-2 = ok"), { kind: "meta", key: "map-2", value: "ok" })
})

test("metadata is picked up wherever it sits, including after the rows", () => {
  assert.equal(Puzzle.parse("##\n##\nauthor = Late\n", "x").author, "Late")
})

test("a picture with no file name to fall back on is Untitled", () => {
  const result = Puzzle.parse("#\n")
  assert.equal(result.name, "Untitled")
  assert.equal(result.file, "")
})

test("normalizeRows pads the short rows", () => {
  assert.deepEqual(Puzzle.normalizeRows(["###", "#", "....."]), [
    [1, 1, 1, 0, 0],
    [1, 0, 0, 0, 0],
    [0, 0, 0, 0, 0]
  ])
})

test("cropping a picture with nothing in it leaves nothing", () => {
  assert.deepEqual(Puzzle.cropped([]), [])
  assert.deepEqual(Puzzle.cropped([[0, 0], [0, 0]]), [])
  assert.deepEqual(Puzzle.columnClues([]), [])
})

test("padToSquare refuses a picture bigger than the board", () => {
  // `parse` always asks for a board at least as big as the picture, so this
  // only bites an editor calling it directly — which is why it is exported.
  assert.equal(Puzzle.padToSquare([[1], [1], [1]], 2), null)
  assert.equal(Puzzle.padToSquare([[1, 1, 1]], 2), null)
  // An odd remainder rounds down, so a 1x2 in a 3x3 sits left of center.
  assert.deepEqual(Puzzle.padToSquare([[1, 1]], 3), [[0, 0, 0], [1, 1, 0], [0, 0, 0]])
  // Nothing at all pads out to an empty board, which is an editor's canvas.
  assert.deepEqual(Puzzle.padToSquare([], 2), [[0, 0], [0, 0]])
})

test("runs of an empty line are clued zero", () => {
  assert.deepEqual(Puzzle.runsOf([]), [0])
})

test("format leaves out metadata a puzzle does not have", () => {
  // An editor's blank canvas: cells and nothing else.
  assert.equal(Puzzle.format({ cells: [[1, 0], [0, 1]] }), "\n#.\n.#\n")
  assert.equal(Puzzle.format({ name: "N", cells: [[1]] }), "name = N\n\n#\n")
})

test("pinSize writes a size = WxH line ahead of the picture", () => {
  const text = Puzzle.format({ name: "Dot", cells: [[0, 0, 0], [0, 1, 0], [0, 0, 0]], pinSize: true })
  assert.equal(text, "name = Dot\nsize = 3x3\n\n...\n.#.\n...\n")
})

test("pinSize on a cell-less puzzle writes size = 0x0 rather than throwing", () => {
  assert.equal(Puzzle.format({ cells: [], pinSize: true }), "size = 0x0\n\n")
})

test("a matching size = WxH line pins the board instead of cropping it", () => {
  // A single filled cell in a 5x5 canvas would normally crop to 1x1.
  const result = Puzzle.parse("size = 5x5\n\n.....\n.....\n..#..\n.....\n.....\n", "x")
  assert.equal(result.ok, true)
  assert.equal(result.size, 5)
  assert.deepEqual(result.cells[2], [0, 0, 1, 0, 0])
})

test("a size line that disagrees with the picture is ignored, not enforced", () => {
  // 2 rows, not the 5 the size line claims — falls back to crop-and-recenter.
  const result = Puzzle.parse("size = 5x5\n\n##\n##\n", "x")
  assert.equal(result.ok, true)
  assert.equal(result.size, 2)

  // Right row count, wrong width — still a disagreement.
  const wideMismatch = Puzzle.parse("size = 3x3\n\n#####\n#####\n#####\n", "x")
  assert.equal(wideMismatch.ok, true)
  assert.equal(wideMismatch.size, 5)
})

test("a size line that isn't square, isn't a number, or is zero is ignored", () => {
  assert.equal(Puzzle.parse("size = 5x4\n\n#####\n#####\n#####\n#####\n#####\n", "x").size, 5)
  assert.equal(Puzzle.parse("size = huge\n\n###\n###\n###\n", "x").size, 3)
  assert.equal(Puzzle.parse("size = 0x0\n\n#\n", "x").size, 1)
})

test("a size line does not excuse an otherwise-empty picture", () => {
  assert.deepEqual(Puzzle.parse("size = 3x3\n\n...\n...\n...\n", "x"), { ok: false, error: "picture has no filled cells" })
})

test("pinSize round-trips a small, off-center drawing without recentering it", () => {
  const original = { name: "Corner", cells: [
    [0, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 0, 0],
    [0, 0, 0, 0]
  ], pinSize: true }
  const parsed = Puzzle.parse(Puzzle.format(original), "corner.picross")

  assert.equal(parsed.ok, true)
  assert.equal(parsed.size, 4)
  assert.deepEqual(parsed.cells, original.cells)
})

test("parse refuses oversized pictures before building a grid", () => {
  assert.equal(Puzzle.parse("#".repeat(5000)).ok, false)
  assert.equal(Puzzle.parse(Array(40).fill("#").join("\n")).ok, false)
  assert.equal(Puzzle.parse("#".repeat(16385)).ok, false)
  assert.equal(Puzzle.parse("#".repeat(15)).ok, true)
})
