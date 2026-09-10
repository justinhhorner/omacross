const test = require("node:test")
const assert = require("node:assert/strict")

const Editor = require("../PatternEditor.js")
const Puzzle = require("../Puzzle.js")

test("createGrid makes a size×size grid of unknown cells", () => {
  const grid = Editor.createGrid(5)
  assert.equal(grid.length, 5)
  for (const row of grid) {
    assert.equal(row.length, 5)
    assert.ok(row.every(cell => cell === Editor.UNKNOWN))
  }
})

test("toggleFill flips a cell on then back off", () => {
  let grid = Editor.createGrid(3)
  grid = Editor.toggleFill(grid, 1, 1)
  assert.equal(grid[1][1], Editor.FILLED)
  grid = Editor.toggleFill(grid, 1, 1)
  assert.equal(grid[1][1], Editor.UNKNOWN)
})

test("toggleFill does not mutate the grid it was given", () => {
  const grid = Editor.createGrid(3)
  const next = Editor.toggleFill(grid, 0, 0)
  assert.equal(grid[0][0], Editor.UNKNOWN)
  assert.equal(next[0][0], Editor.FILLED)
})

test("setCell returns the same reference when nothing changes", () => {
  const grid = Editor.createGrid(3)
  const next = Editor.setCell(grid, 0, 0, Editor.UNKNOWN)
  assert.equal(next, grid)
})

test("flatten reads row-major, matching BoardView's board array", () => {
  let grid = Editor.createGrid(2)
  grid = Editor.toggleFill(grid, 0, 1)
  assert.deepEqual(Editor.flatten(grid), [Editor.UNKNOWN, Editor.FILLED, Editor.UNKNOWN, Editor.UNKNOWN])
})

test("toBinary keeps only what is filled", () => {
  let grid = Editor.createGrid(2)
  grid = Editor.toggleFill(grid, 0, 0)
  assert.deepEqual(Editor.toBinary(grid), [[1, 0], [0, 0]])
})

test("fromBinary is the inverse of toBinary", () => {
  const binary = [[1, 0], [0, 1]]
  const grid = Editor.fromBinary(binary)
  assert.deepEqual(Editor.toBinary(grid), binary)
})

test("hasContent is false until something is filled", () => {
  let grid = Editor.createGrid(4)
  assert.equal(Editor.hasContent(grid), false)
  grid = Editor.toggleFill(grid, 2, 2)
  assert.equal(Editor.hasContent(grid), true)
})

test("dirNameForSize matches the three difficulty sizes", () => {
  assert.equal(Editor.dirNameForSize(5), "5x5")
  assert.equal(Editor.dirNameForSize(10), "10x10")
  assert.equal(Editor.dirNameForSize(15), "15x15")
})

test("slugify lowercases, collapses punctuation, and trims dashes", () => {
  assert.equal(Editor.slugify("My Heart!!"), "my-heart")
  assert.equal(Editor.slugify("  --Château--  "), "ch-teau")
  assert.equal(Editor.slugify(""), "pattern")
  assert.equal(Editor.slugify("###"), "pattern")
})

test("uniqueFileName only adds a suffix when the name is taken", () => {
  assert.equal(Editor.uniqueFileName("heart", []), "heart")
  assert.equal(Editor.uniqueFileName("heart", ["heart"]), "heart-2")
  assert.equal(Editor.uniqueFileName("heart", ["heart", "heart-2"]), "heart-3")
})

test("a saved-then-reparsed grid round-trips through Puzzle.format/parse", () => {
  let grid = Editor.createGrid(5)
  grid = Editor.toggleFill(grid, 0, 0)
  grid = Editor.toggleFill(grid, 4, 4)

  const text = Puzzle.format({ name: "Corner Dots", author: "", cells: Editor.toBinary(grid), pinSize: true })
  const parsed = Puzzle.parse(text, "corner-dots.picross")

  assert.equal(parsed.ok, true)
  assert.equal(parsed.name, "Corner Dots")
  assert.equal(parsed.size, 5)
  assert.deepEqual(parsed.cells, Editor.toBinary(grid))
})

// The whole point of `pinSize`: the pattern editor lets a player draw a
// small design anywhere on a board they chose the size of, and a save must
// not shrink or recenter it — plain `Puzzle.parse`/`format` crop and
// recenter by design, which is exactly what an editor-authored file has to
// opt out of.
test("a 10x10 pattern with a small, off-center drawing still saves as 10x10", () => {
  let grid = Editor.createGrid(10)
  grid = Editor.toggleFill(grid, 1, 1)
  grid = Editor.toggleFill(grid, 1, 2)
  grid = Editor.toggleFill(grid, 2, 1)

  const text = Puzzle.format({ name: "Corner Blob", cells: Editor.toBinary(grid), pinSize: true })
  const parsed = Puzzle.parse(text, "corner-blob.picross")

  assert.equal(parsed.ok, true)
  assert.equal(parsed.size, 10)
  assert.deepEqual(parsed.cells, Editor.toBinary(grid), "the drawing keeps its exact position, not just its size")
})

test("without pinSize the same drawing would have cropped down", () => {
  let grid = Editor.createGrid(10)
  grid = Editor.toggleFill(grid, 1, 1)
  grid = Editor.toggleFill(grid, 1, 2)
  grid = Editor.toggleFill(grid, 2, 1)

  const text = Puzzle.format({ name: "Corner Blob", cells: Editor.toBinary(grid) })
  const parsed = Puzzle.parse(text, "corner-blob.picross")

  assert.equal(parsed.ok, true)
  assert.notEqual(parsed.size, 10)
})
