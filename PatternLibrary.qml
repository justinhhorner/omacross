import QtQuick
import QtQml
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "Puzzle.js" as Puzzle
import "PatternEditor.js" as Editor

// Every picture the game can deal, from two folders: the ones bundled with the
// plugin, and a folder of the player's own. Both are watched, so saving a file
// in an editor puts the picture into the next deal without restarting the
// shell — which is the whole point of keeping pictures as text.
//
// The two Instantiator blocks are spelled out rather than factored into one
// inline component: an inline component gets its own scope and cannot reach
// the `root` id here, so its delegates would have nowhere to report to.
Item {
  id: root

  // Overrides the default user folder. Empty means ~/.config/omacross/patterns.
  property string extraDir: ""

  readonly property string userDir: extraDir === ""
    ? Quickshell.env("HOME") + "/.config/omacross/patterns"
    : (extraDir === "~" || extraDir.indexOf("~/") === 0
      ? Quickshell.env("HOME") + extraDir.substring(1)
      : extraDir)

  // Where the pattern editor saves what a player draws — a sibling folder
  // per grid size, so a save never has to guess a difficulty from a picture's
  // shape the way loading an arbitrary `.picross` file does.
  readonly property string userPatternsRoot: Quickshell.env("HOME") + "/.config/omacross/user-patterns"

  function userPatternsDirFor(size) {
    return userPatternsRoot + "/" + Editor.dirNameForSize(size)
  }

  // Puzzles the editor itself is responsible for, as opposed to the bundled
  // set or a player's separately-configured extra folder — what its own
  // pattern list shows, and what a delete there is allowed to remove.
  readonly property var editorPuzzles: puzzles.filter(function(p) {
    return p.file.indexOf(root.userPatternsRoot + "/") === 0
  })

  // The three size folders may not exist yet on a fresh install; the
  // FolderListModels below tolerate a missing folder as simply empty, but a
  // save has nowhere to land until this has run once.
  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p",
      root.userPatternsDirFor(5), root.userPatternsDirFor(10), root.userPatternsDirFor(15)]
  }
  Component.onCompleted: ensureDirsProc.running = true

  // file path -> parsed puzzle. Reassigned wholesale on every change so the
  // `puzzles` binding below re-runs; mutating it in place would not.
  property var byPath: ({})
  property var failures: ({})

  readonly property var puzzles: {
    var out = []
    for (var path in byPath) out.push(byPath[path])
    out.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return out
  }

  readonly property var problems: {
    var out = []
    for (var path in failures) out.push({ file: path, error: failures[path] })
    return out
  }

  // Counts per grid size, as a property rather than a function call.
  //
  // A binding that called a countOfSize(n) function here would capture no
  // dependency on `puzzles` — the read happens inside a function in this
  // component's scope, not at the binding site — so the title screen would show
  // whatever the count was when it first painted, which is zero. Reading a
  // property fixes that.
  readonly property var counts: {
    var out = ({})
    for (var i = 0; i < puzzles.length; i++) {
      var size = puzzles[i].size
      out[size] = (out[size] || 0) + 1
    }
    return out
  }

  function puzzlesOfSize(size) {
    var out = []
    for (var i = 0; i < puzzles.length; i++) if (puzzles[i].size === size) out.push(puzzles[i])
    return out
  }

  // Deal a picture of the requested size, avoiding an immediate repeat so two
  // games in a row are not the same picture when the folder is small.
  function pick(size, avoidFile) {
    var pool = puzzlesOfSize(size)
    if (pool.length === 0) return null
    if (pool.length > 1 && avoidFile) {
      var filtered = []
      for (var i = 0; i < pool.length; i++) if (pool[i].file !== avoidFile) filtered.push(pool[i])
      pool = filtered
    }
    return pool[Math.floor(Math.random() * pool.length)]
  }

  // A copy without one key. Both maps are replaced wholesale on every change
  // rather than mutated, so re-reading a file is always "drop what we knew
  // about that path, then record what it says now".
  function copyExcept(map, key) {
    var out = {}
    for (var k in map) if (k !== key) out[k] = map[k]
    return out
  }

  function ingest(path, text) {
    var parsed = Puzzle.parse(text, path)
    var nextPuzzles = copyExcept(byPath, path)
    var nextFailures = copyExcept(failures, path)

    if (parsed.ok) {
      parsed.file = path
      nextPuzzles[path] = parsed
    } else {
      nextFailures[path] = parsed.error
    }

    byPath = nextPuzzles
    failures = nextFailures
  }

  function forget(path) {
    byPath = copyExcept(byPath, path)
    failures = copyExcept(failures, path)
  }

  // One FileView per picture file. Instantiator tears a view down when its file
  // leaves the folder, and `forget` on destruction is what keeps a deleted
  // picture from staying in the deck.
  Instantiator {
    model: FolderListModel {
      folder: Qt.resolvedUrl("patterns")
      nameFilters: ["*.picross"]
      showDirs: false
      sortField: FolderListModel.Name
    }

    delegate: FileView {
      required property string filePath
      path: filePath
      watchChanges: true
      printErrors: false
      onLoaded: root.ingest(filePath, text())
      onFileChanged: reload()
      onLoadFailed: root.forget(filePath)
      Component.onDestruction: root.forget(filePath)
    }
  }

  Instantiator {
    model: FolderListModel {
      folder: "file://" + root.userDir
      nameFilters: ["*.picross"]
      showDirs: false
      sortField: FolderListModel.Name
    }

    delegate: FileView {
      required property string filePath
      path: filePath
      watchChanges: true
      printErrors: false
      onLoaded: root.ingest(filePath, text())
      onFileChanged: reload()
      onLoadFailed: root.forget(filePath)
      Component.onDestruction: root.forget(filePath)
    }
  }

  // The editor's own three folders, one per grid size. A fourth Instantiator
  // block spelled out per size (rather than one more nested Repeater) for the
  // same scoping reason as the two above.
  Instantiator {
    model: FolderListModel {
      folder: "file://" + root.userPatternsDirFor(5)
      nameFilters: ["*.picross"]
      showDirs: false
      sortField: FolderListModel.Name
    }

    delegate: FileView {
      required property string filePath
      path: filePath
      watchChanges: true
      printErrors: false
      onLoaded: root.ingest(filePath, text())
      onFileChanged: reload()
      onLoadFailed: root.forget(filePath)
      Component.onDestruction: root.forget(filePath)
    }
  }

  Instantiator {
    model: FolderListModel {
      folder: "file://" + root.userPatternsDirFor(10)
      nameFilters: ["*.picross"]
      showDirs: false
      sortField: FolderListModel.Name
    }

    delegate: FileView {
      required property string filePath
      path: filePath
      watchChanges: true
      printErrors: false
      onLoaded: root.ingest(filePath, text())
      onFileChanged: reload()
      onLoadFailed: root.forget(filePath)
      Component.onDestruction: root.forget(filePath)
    }
  }

  Instantiator {
    model: FolderListModel {
      folder: "file://" + root.userPatternsDirFor(15)
      nameFilters: ["*.picross"]
      showDirs: false
      sortField: FolderListModel.Name
    }

    delegate: FileView {
      required property string filePath
      path: filePath
      watchChanges: true
      printErrors: false
      onLoaded: root.ingest(filePath, text())
      onFileChanged: reload()
      onLoadFailed: root.forget(filePath)
      Component.onDestruction: root.forget(filePath)
    }
  }
}
