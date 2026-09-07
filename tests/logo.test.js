const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")

const Logo = require("../Logo.js")

test("the mark is a square grid", () => {
  assert.equal(Logo.LOGO_SIZE, 13)
  for (const row of Logo.LOGO_ROWS) assert.equal(row.length, Logo.LOGO_SIZE, row)
  assert.equal(Logo.logoFlat().length, 13 * 13)
})

// The mark is a transcription of Omarchy's own icon art, drawn there at four
// columns and two lines per pixel. Checking against the installed file when it
// is present is what keeps the transcription honest.
test("the mark matches Omarchy's installed icon art", { skip: !fs.existsSync("/usr/share/omarchy/icon.txt") }, () => {
  const lines = fs.readFileSync("/usr/share/omarchy/icon.txt", "utf8").split("\n").filter(line => line.length > 0)
  assert.equal(lines.length, Logo.LOGO_SIZE * 2)

  const width = lines[0].length
  const cells = Logo.logoCells()
  for (let row = 0; row < Logo.LOGO_SIZE; row++) {
    for (let column = 0; column < Logo.LOGO_SIZE; column++) {
      // Sample the middle of each block so the block-art rounding at the
      // boundaries (54 characters over 13 columns) cannot tip a comparison.
      const x = Math.floor((column + 0.5) * width / Logo.LOGO_SIZE)
      const lit = lines[row * 2][x] === "█" ? 1 : 0
      assert.equal(cells[row][column], lit, `cell ${row},${column}`)
    }
  }
})

test("the hash is stable, bounded, and varies with both inputs", () => {
  assert.equal(Logo.hash01(3, 7), Logo.hash01(3, 7))
  assert.notEqual(Logo.hash01(3, 7), Logo.hash01(4, 7))
  assert.notEqual(Logo.hash01(3, 7), Logo.hash01(3, 8))
  for (let i = 0; i < 500; i++) {
    const value = Logo.hash01(i, i * 3)
    assert.ok(value >= 0 && value < 1, `${value} out of range`)
  }
})

test("every cell settles before the animation ends", () => {
  for (let index = 0; index < Logo.LOGO_SIZE * Logo.LOGO_SIZE; index++) {
    const threshold = Logo.settleThreshold(index, Logo.LOGO_SIZE)
    assert.ok(threshold >= 0 && threshold <= 0.98, `${index}: ${threshold}`)
  }
})

test("the center settles before the corners", () => {
  const center = Logo.settleThreshold(6 * 13 + 6, 13)
  const corner = Logo.settleThreshold(0, 13)
  assert.ok(center < corner, `center ${center} should settle before corner ${corner}`)
})

test("a finished animation paints the mark exactly", () => {
  const cells = Logo.logoFlat()
  for (let index = 0; index < cells.length; index++) {
    assert.equal(Logo.titleCellAt(index, Logo.LOGO_SIZE, 1, 99, cells), cells[index])
  }
})

test("an unsettled cell shows static that changes over time", () => {
  const cells = Logo.logoFlat()
  const frames = new Set()
  for (let tick = 0; tick < 40; tick++) frames.add(Logo.titleCellAt(0, Logo.LOGO_SIZE, 0, tick, cells))
  assert.equal(frames.size, 2, "cell 0 should flicker before it settles")
})
