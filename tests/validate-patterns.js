// Renders and checks every bundled pattern. Run directly to eyeball the
// pictures (`node tests/validate-patterns.js`); `tests/patterns.test.js`
// asserts the same conditions.
const fs = require("node:fs")
const path = require("node:path")

const Puzzle = require("../Puzzle.js")
const Game = require("../Game.js")
const Solver = require("../Solver.js")

const patternDir = path.join(__dirname, "..", "patterns")

function loadAll() {
  return fs.readdirSync(patternDir)
    .filter(name => name.endsWith(".picross"))
    .sort()
    .map(name => ({
      file: name,
      result: Puzzle.parse(fs.readFileSync(path.join(patternDir, name), "utf8"), name)
    }))
}

function render(puzzle) {
  return puzzle.cells.map(row => row.map(v => (v ? "██" : "· ")).join("")).join("\n")
}

function report(entry) {
  const { file, result } = entry
  if (!result.ok) return { file, ok: false, reason: result.error }
  const difficulty = Game.difficultyForSize(result.size)
  if (!difficulty) return { file, ok: false, reason: `${result.size}x${result.size} matches no difficulty` }
  if (!Solver.isLogicallySolvable(result)) return { file, ok: false, reason: "needs a guess" }
  return { file, ok: true, difficulty: difficulty.id, puzzle: result }
}

if (require.main === module) {
  let failures = 0
  for (const entry of loadAll()) {
    const status = report(entry)
    if (!status.ok) {
      failures++
      console.log(`\n✗ ${status.file}: ${status.reason}`)
      if (entry.result.ok) console.log(render(entry.result))
      continue
    }
    console.log(`\n✓ ${status.file} — "${status.puzzle.name}" (${status.difficulty}, ${status.puzzle.size}×${status.puzzle.size})`)
    console.log(render(status.puzzle))
  }
  process.exit(failures > 0 ? 1 : 0)
}

module.exports = { loadAll, render, report, patternDir }
