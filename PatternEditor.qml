import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Puzzle.js" as Puzzle
import "PatternEditor.js" as Editor

// Draw your own picture, in a window of its own rather than the bar's
// popup — the popup is sized and keyed for playing a puzzle, not for
// drawing one, and a player switching between "look at the picture" and
// "look at the list of my pictures" wants both on screen at once.
//
// The rules are the two functions the README already promises: `Puzzle.parse`
// and `Puzzle.format`. Everything in between — the grid the player actually
// touches — is `PatternEditor.js`, which knows nothing about files or QML.
Item {
  id: root

  property bool opened: false
  property var library: null

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color border: Color.popups.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color muted: Color.muted
  readonly property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.family

  // The window only ever asks to close; whether "opened" actually goes false
  // is the parent's call, since the parent is the one holding the binding
  // that fed it in. Setting `opened` from in here would just break that
  // binding instead of closing anything.
  signal closed()

  // The saved, file-backed patterns — what the folder watcher actually
  // knows about.
  readonly property var savedEntries: root.library ? root.library.editorPuzzles : []

  // Whatever is on the board right now is always in this list too, saved or
  // not: an empty `editFile` means nothing has been written for it yet, so
  // it is represented by a stand-in row instead of a real one. That is what
  // keeps the buffer from ever being an orphan the list has no entry for —
  // including the moment the editor first opens, before anything has been
  // drawn.
  readonly property bool hasDraft: editFile === ""
  readonly property var entries: hasDraft ? [draftEntry()].concat(savedEntries) : savedEntries
  property int selectedIndex: -1

  function draftEntry() {
    return { file: "", name: editName, size: editSize, cells: clueCells }
  }

  // ---------------------------------------------------------------- buffer
  property int editSize: Editor.DEFAULT_SIZE
  property var editCells: Editor.createGrid(Editor.DEFAULT_SIZE)
  property string editName: "New Pattern"
  property string editFile: ""
  property bool dirty: false
  // Set the instant a save lands so the list picks the new file back up as
  // soon as the folder watcher reports it, rather than falling back to
  // "first pattern" for the one turn in between.
  property string pendingSelectFile: ""

  property int cursorRow: 0
  property int cursorCol: 0

  readonly property var editBoard: Editor.flatten(editCells)
  readonly property var clueCells: Editor.toBinary(editCells)
  readonly property var rowClues: Puzzle.rowClues(clueCells)
  readonly property var columnClues: Puzzle.columnClues(clueCells)

  // ---------------------------------------------------------------- prompts
  property string prompt: ""          // "" | "confirmSave" | "confirmDelete" | "nameInput"
  property string pendingAction: ""   // "" | "load" | "quit" | "new" — what happens once a save/discard resolves
  property string pendingLoadFile: ""

  // `openNamePrompt` hands the text field active focus so the player can
  // type into it; nothing hands it back on its own once that field goes
  // invisible again. Without this, every Enter/Escape afterward — including
  // ones the player has no idea are reaching a hidden text field — keeps
  // landing on it instead of the board, silently resaving under whatever
  // name was last typed there. `nameInput` is the one prompt that manages
  // its own focus (see `openNamePrompt`); every other state, including no
  // prompt at all, belongs to the board and list.
  onPromptChanged: {
    if (prompt !== "nameInput") Qt.callLater(function() { if (keys) keys.forceActiveFocus() })
  }

  // ------------------------------------------------------------- drag state
  property bool fillDragging: false
  property bool fillErasing: false
  // `x` and the right mouse button are a dedicated eraser — unlike fill's
  // own erase-by-toggle, this one never turns a cell on, so there is no
  // "erasing" flag to fix at the start of the run.
  property bool eraseDragging: false
  readonly property int dragNavDelayMs: 100

  onOpenedChanged: {
    if (opened) {
      // The close branch below always leaves a fresh draft behind, so this
      // is really "select the draft" — entries[0] whenever one is present,
      // same row `resetBuffer` is about to put the board on.
      selectedIndex = entries.length > 0 ? 0 : -1
      // WlrKeyboardFocus.Exclusive grabs the surface at the compositor
      // level; something inside it still has to hold Qt's own active focus
      // for Keys.onPressed to fire, and re-opening a window that already
      // exists does not do that on its own.
      Qt.callLater(function() { if (keys) keys.forceActiveFocus() })
    } else {
      resetBuffer()
      prompt = ""
      pendingAction = ""
      pendingLoadFile = ""
      fillDragging = false
      eraseDragging = false
    }
  }

  // A file appearing or disappearing under the watched folders — a save
  // landing, a delete completing, or the player editing the folder by hand —
  // re-lands on the file that just got saved if there is one pending, else
  // keeps the current selection if it is still there, else falls back to the
  // first pattern.
  onEntriesChanged: {
    if (pendingSelectFile !== "") {
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].file === pendingSelectFile) {
          selectedIndex = i
          pendingSelectFile = ""
          return
        }
      }
    }
    reconcileSelection()
  }

  function reconcileSelection() {
    if (entries.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0 || selectedIndex >= entries.length) selectedIndex = 0
  }

  function resetBuffer() {
    editSize = Editor.DEFAULT_SIZE
    editCells = Editor.createGrid(Editor.DEFAULT_SIZE)
    editName = "New Pattern"
    editFile = ""
    dirty = false
    cursorRow = 0
    cursorCol = 0
  }

  // Ctrl+N, and what a blank editor opens on: a fresh, unsaved draft, always
  // the first row of `entries` since it is the one with no file.
  function createNewDraft() {
    resetBuffer()
    selectedIndex = 0
  }

  function baseNameOf(path) {
    var parts = String(path).split("/")
    var last = parts[parts.length - 1]
    return last.replace(/\.picross$/, "")
  }

  // --------------------------------------------------------------- editing
  function setCellValue(row, col, value) {
    var next = Editor.setCell(editCells, row, col, value)
    if (next === editCells) return
    editCells = next
    dirty = true
  }

  function setCursor(row, col) {
    cursorRow = row
    cursorCol = col
  }

  function jumpAxis(row, col) {
    cursorRow = row === -1 ? cursorRow : row
    cursorCol = col === -1 ? cursorCol : col
  }

  function stepCursor(dRow, dCol) {
    cursorRow = ((cursorRow + dRow) % editSize + editSize) % editSize
    cursorCol = ((cursorCol + dCol) % editSize + editSize) % editSize
  }

  function moveCursor(dRow, dCol) {
    if (fillDragging) {
      if (fillThrottle.running) return
      stepCursor(dRow, dCol)
      driveFill(cursorRow, cursorCol)
      fillThrottle.restart()
      return
    }
    if (eraseDragging) {
      if (eraseThrottle.running) return
      stepCursor(dRow, dCol)
      driveErase(cursorRow, cursorCol)
      eraseThrottle.restart()
      return
    }
    stepCursor(dRow, dCol)
  }

  // Fixed for the whole drag run: brushing back over a cell the run already
  // touched never flips it a second time.
  function beginFillDrag(row, col) {
    fillDragging = true
    fillErasing = editCells[row][col] === Editor.FILLED
    setCursor(row, col)
    driveFill(row, col)
    fillThrottle.restart()
  }

  function continueFillDrag(row, col) {
    if (!fillDragging || fillThrottle.running) return
    setCursor(row, col)
    driveFill(row, col)
    fillThrottle.restart()
  }

  function endFillDrag() { fillDragging = false }

  function driveFill(row, col) {
    var target = fillErasing ? Editor.UNKNOWN : Editor.FILLED
    if (editCells[row][col] === target) return
    setCellValue(row, col, target)
  }

  // `x` and the right mouse button: deselect a filled cell. An already-empty
  // cell has nothing to deselect, so brushing across a mix of filled and
  // empty cells only ever touches the filled ones.
  function beginEraseDrag(row, col) {
    eraseDragging = true
    setCursor(row, col)
    driveErase(row, col)
    eraseThrottle.restart()
  }

  function continueEraseDrag(row, col) {
    if (!eraseDragging || eraseThrottle.running) return
    setCursor(row, col)
    driveErase(row, col)
    eraseThrottle.restart()
  }

  function endEraseDrag() { eraseDragging = false }

  function driveErase(row, col) {
    if (editCells[row][col] !== Editor.FILLED) return
    setCellValue(row, col, Editor.UNKNOWN)
  }

  // ------------------------------------------------------------------ list
  function moveSelection(delta) {
    if (entries.length === 0) return
    selectedIndex = ((selectedIndex + delta) % entries.length + entries.length) % entries.length
  }

  function loadEntry(index) {
    var entry = entries[index]
    if (!entry) return
    editSize = entry.size
    editCells = Editor.fromBinary(entry.cells)
    editName = entry.name
    editFile = entry.file
    dirty = false
    cursorRow = 0
    cursorCol = 0
    selectedIndex = index
    pendingAction = ""
    pendingLoadFile = ""
    prompt = ""
  }

  function requestLoad() {
    if (selectedIndex === -1) {
      // Nothing in the list to load — Enter's only useful job here is to
      // save whatever is on the board.
      if (dirty) openNamePrompt()
      return
    }
    if (entries[selectedIndex].file === editFile) return
    if (dirty) {
      pendingAction = "load"
      // The file, not the index: saving first (to resolve the prompt this
      // triggers) removes the draft row and shifts every real entry below
      // it up by one, so an index captured now would point at the wrong
      // row — or past the end of the list — by the time it is used.
      pendingLoadFile = entries[selectedIndex].file
      prompt = "confirmSave"
    } else {
      loadEntry(selectedIndex)
    }
  }

  function indexOfFile(file) {
    for (var i = 0; i < entries.length; i++) if (entries[i].file === file) return i
    return -1
  }

  function requestDelete() {
    if (selectedIndex === -1) return
    // The draft row has no file behind it yet — nothing there to delete.
    if (entries[selectedIndex].file === "") return
    prompt = "confirmDelete"
  }

  function requestQuit() {
    if (dirty) {
      pendingAction = "quit"
      prompt = "confirmSave"
    } else {
      closed()
    }
  }

  // Ctrl+N: start a fresh, unsaved pattern, asking first if the current one
  // would otherwise be lost — the same rule as loading or quitting.
  function requestNew() {
    if (dirty) {
      pendingAction = "new"
      prompt = "confirmSave"
    } else {
      createNewDraft()
    }
  }

  function cancelPrompt() {
    prompt = ""
    pendingAction = ""
    pendingLoadFile = ""
  }

  function proceedWithPendingAction() {
    var action = pendingAction
    var loadFile = pendingLoadFile
    pendingAction = ""
    pendingLoadFile = ""
    if (action === "load") {
      var index = indexOfFile(loadFile)
      if (index !== -1) loadEntry(index)
    } else if (action === "quit") {
      closed()
    } else if (action === "new") {
      createNewDraft()
    }
  }

  function discardThenContinue() {
    prompt = ""
    proceedWithPendingAction()
  }

  function startSaveThenContinue() {
    if (editFile !== "") { performSave(editFile, editName); return }
    openNamePrompt()
  }

  // Ctrl+S: save whatever is on the board right now, without navigating away
  // or quitting first. Same rule as every other save path — a pattern that
  // already has a file is overwritten in place, a new one is named first.
  function requestSave() {
    if (!dirty) return
    if (editFile !== "") { performSave(editFile, editName); return }
    openNamePrompt()
  }

  function openNamePrompt() {
    prompt = "nameInput"
    Qt.callLater(function() {
      if (!nameField) return
      nameField.text = root.editName
      nameField.selectAll()
      nameField.forceActiveFocus()
    })
  }

  function confirmName() {
    // Guards against the one way this could still fire outside the prompt
    // it belongs to: focus lagging a beat behind a prompt change.
    if (prompt !== "nameInput") return
    var typed = String(nameField ? nameField.text : "").trim()
    var name = typed.length > 0 ? typed : "Untitled"
    var dir = root.library.userPatternsDirFor(editSize)
    var taken = []
    for (var i = 0; i < savedEntries.length; i++)
      if (savedEntries[i].size === editSize) taken.push(baseNameOf(savedEntries[i].file))
    var fileBase = Editor.uniqueFileName(Editor.slugify(name), taken)
    prompt = ""
    performSave(dir + "/" + fileBase + ".picross", name)
  }

  function confirmDeleteYes() {
    prompt = ""
    if (selectedIndex === -1) return
    var entry = entries[selectedIndex]
    if (entry.file === "") return
    deleteProc.targetFile = entry.file
    deleteProc.wasLoaded = entry.file === editFile
    deleteProc.command = ["rm", "-f", entry.file]
    deleteProc.running = true
  }

  function performSave(path, name) {
    // A save already in flight has not updated `savedEntries` yet, so a
    // second call this soon would recompute the same "is this name taken"
    // answer and could pick a different unique file for what the player
    // thinks is one save — belt-and-suspenders alongside the isAutoRepeat
    // guards on every key that can reach here.
    if (saveProc.running) return
    var dir = path.substring(0, path.lastIndexOf("/"))
    var text = Puzzle.format({ name: name, author: "", cells: clueCells, pinSize: true })
    saveProc.targetPath = path
    saveProc.savedName = name
    saveProc.command = ["bash", "-c",
      "mkdir -p " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(text)
      + " > " + Util.shellQuote(path)]
    saveProc.running = true
  }

  Process {
    id: saveProc
    property string targetPath: ""
    property string savedName: ""
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.editFile = saveProc.targetPath
      root.editName = saveProc.savedName
      root.dirty = false
      root.pendingSelectFile = saveProc.targetPath
      root.proceedWithPendingAction()
    }
  }

  Process {
    id: deleteProc
    property string targetFile: ""
    property bool wasLoaded: false
    onExited: function(exitCode) {
      if (exitCode === 0 && deleteProc.wasLoaded) root.resetBuffer()
    }
  }

  Timer { id: fillThrottle; interval: root.dragNavDelayMs }
  Timer { id: eraseThrottle; interval: root.dragNavDelayMs }

  // -------------------------------------------------------------- keyboard
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var text = event.text

    // Every one of these fires a save, a load, or a delete — a key held a
    // moment too long auto-repeats several of these a second, and since the
    // save path's uniqueness check races the async folder watcher, a
    // repeated save can land on a different file each time instead of the
    // same one twice. `isAutoRepeat` is what keeps a single held press a
    // single action, matching how Space and X already guard the drag keys.
    if (ctrl && event.key === Qt.Key_Q) { if (!event.isAutoRepeat) requestQuit(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_S) { if (!event.isAutoRepeat) requestSave(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_N) { if (!event.isAutoRepeat) requestNew(); event.accepted = true; return }

    // The name field is a real text input with its own key handling; leave
    // every key alone so it can be typed into.
    if (prompt === "nameInput") return

    if (prompt === "confirmSave") {
      if (event.key === Qt.Key_Escape) cancelPrompt()
      else if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) startSaveThenContinue()
      else if (!event.isAutoRepeat && (text === "d" || text === "D")) discardThenContinue()
      event.accepted = true
      return
    }

    if (prompt === "confirmDelete") {
      if (event.key === Qt.Key_Escape || text === "n" || text === "N") cancelPrompt()
      else if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || text === "y" || text === "Y")) confirmDeleteYes()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Up) { moveSelection(-1); event.accepted = true; return }
    if (event.key === Qt.Key_Down) { moveSelection(1); event.accepted = true; return }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!event.isAutoRepeat) requestLoad()
      event.accepted = true
      return
    }
    if (text === "d" || text === "D") {
      if (!event.isAutoRepeat) requestDelete()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Space) {
      if (!event.isAutoRepeat) beginFillDrag(cursorRow, cursorCol)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_X) {
      if (!event.isAutoRepeat) beginEraseDrag(cursorRow, cursorCol)
      event.accepted = true
      return
    }

    var dRow = 0, dCol = 0
    if (text === "j") dRow = 1
    else if (text === "k") dRow = -1
    else if (event.key === Qt.Key_Left || text === "h") dCol = -1
    else if (event.key === Qt.Key_Right || text === "l") dCol = 1

    if (dRow !== 0 || dCol !== 0) { moveCursor(dRow, dCol); event.accepted = true; return }

    if (text === "0" || text === "^") { jumpAxis(-1, 0); event.accepted = true; return }
    if (text === "$") { jumpAxis(-1, editSize - 1); event.accepted = true; return }
    if (text === "g") { jumpAxis(0, -1); event.accepted = true; return }
    if (text === "G") { jumpAxis(editSize - 1, -1); event.accepted = true; return }
  }

  function handleKeyRelease(event) {
    if (event.isAutoRepeat) return
    if (event.key === Qt.Key_Space) { endFillDrag(); event.accepted = true }
    else if (event.key === Qt.Key_X) { endEraseDrag(); event.accepted = true }
  }

  // ---------------------------------------------------------------- window
  PanelWindow {
    id: floatWindow
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacross-pattern-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      visible: root.opened
      color: root.scrim
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }
      Keys.onReleased: function(event) { root.handleKeyRelease(event) }

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: cardRow.implicitWidth + Style.space(28)
        height: cardRow.implicitHeight + Style.space(28)
        radius: Style.cornerRadius
        color: root.background
        border.width: 1
        border.color: root.border

        Row {
          id: cardRow
          anchors.centerIn: parent
          spacing: Style.space(18)

          // ------------------------------------------------------- sidebar
          Column {
            id: sidebar
            width: Style.space(190)
            spacing: Style.space(8)

            Text {
              text: "MY PATTERNS"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: Style.space(1)
            }

            Flickable {
              width: sidebar.width
              height: Style.space(320)
              contentWidth: width
              contentHeight: listColumn.implicitHeight
              clip: true

              Column {
                id: listColumn
                width: sidebar.width
                spacing: Style.space(2)

                Repeater {
                  model: root.entries

                  Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: index === root.selectedIndex

                    width: listColumn.width
                    height: Style.space(30)
                    radius: Style.cornerRadius
                    color: current ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.right: sizeLabel.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: row.modelData.name
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      color: row.current ? root.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: row.current
                    }

                    Text {
                      id: sizeLabel
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: row.modelData.size + "×" + row.modelData.size
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectedIndex = row.index
                    }
                  }
                }

                Text {
                  visible: root.entries.length === 0
                  width: listColumn.width
                  wrapMode: Text.WordWrap
                  text: "No patterns yet — draw one and save it."
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          Rectangle {
            width: 1
            height: mainColumn.implicitHeight
            color: root.border
          }

          // -------------------------------------------------------- board
          Column {
            id: mainColumn
            spacing: Style.space(10)

            Item {
              width: boardView.implicitWidth
              implicitHeight: title.implicitHeight

              Text {
                id: title
                text: "PATTERN EDITOR"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: Style.space(1)
              }

              Text {
                anchors.right: parent.right
                text: root.editSize + "×" + root.editSize + (root.dirty ? "  •" : "")
                color: root.dirty ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            BoardView {
              id: boardView
              size: root.editSize
              board: root.editBoard
              rowClues: root.rowClues
              columnClues: root.columnClues
              solvedRows: []
              solvedColumns: []
              cursorRow: root.cursorRow
              cursorCol: root.cursorCol
              interactive: root.prompt === ""
              foreground: root.foreground
              accent: root.accent
              urgent: root.urgent
              muted: root.muted
              fontFamily: root.fontFamily
              onDragSelectStarted: function(r, c) { root.beginFillDrag(r, c) }
              onDragSelectMoved: function(r, c) { root.continueFillDrag(r, c) }
              onDragSelectEnded: root.endFillDrag()
              onDragMarkStarted: function(r, c) { root.beginEraseDrag(r, c) }
              onDragMarkMoved: function(r, c) { root.continueEraseDrag(r, c) }
              onDragMarkEnded: root.endEraseDrag()
              onCellEntered: function(r, c) {
                if (root.fillDragging) root.continueFillDrag(r, c)
                else if (root.eraseDragging) root.continueEraseDrag(r, c)
                else root.setCursor(r, c)
              }
            }

            KeyHints {
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 4
              color: Util.alpha(root.muted, 0.85)
              fontFamily: root.fontFamily
              hints: [
                "space", "fill", "x", "deselect",
                "hjkl", "move", "↑ ↓", "select",
                "enter", "load", "d", "delete",
                "ctrl+n", "new", "ctrl+s", "save",
                "ctrl+q", "quit"
              ]
            }
          }
        }

        // ------------------------------------------------------- prompts
        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          visible: root.prompt !== ""
          color: Util.alpha(root.background, 0.96)

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(14)
            visible: root.prompt === "confirmSave" || root.prompt === "confirmDelete"

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.prompt === "confirmSave" ? "Save your pattern?"
                : "Delete “" + (root.selectedIndex >= 0 ? root.entries[root.selectedIndex].name : "") + "”?"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.prompt === "confirmSave" ? "You have a pattern in progress that hasn't been saved."
                : "This cannot be undone."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(10)

              Button {
                visible: root.prompt === "confirmSave"
                text: "Save"
                bordered: true
                onClicked: root.startSaveThenContinue()
              }
              Button {
                visible: root.prompt === "confirmSave"
                text: "Discard"
                bordered: true
                onClicked: root.discardThenContinue()
              }
              Button {
                visible: root.prompt === "confirmDelete"
                text: "Delete"
                bordered: true
                onClicked: root.confirmDeleteYes()
              }
              Button {
                visible: root.prompt === "confirmDelete"
                text: "Cancel"
                bordered: true
                onClicked: root.cancelPrompt()
              }
            }

            KeyHints {
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 4
              color: Util.alpha(root.muted, 0.85)
              fontFamily: root.fontFamily
              hints: root.prompt === "confirmSave"
                ? ["enter", "save", "d", "discard", "esc", "cancel"]
                : ["enter", "delete", "esc", "cancel"]
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(14)
            visible: root.prompt === "nameInput"

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Name this pattern"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            TextField {
              id: nameField
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Style.space(240))
              placeholderText: "Untitled"
              foreground: root.foreground
              font.family: root.fontFamily

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelPrompt()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  // The key that opened this prompt is very often still
                  // held down a beat into it — without this guard, each
                  // auto-repeat tick calls confirmName() again, and because
                  // the uniqueness check races the async folder watcher, a
                  // held Enter can save the same drawing under several
                  // different names instead of once.
                  if (!event.isAutoRepeat) root.confirmName()
                  event.accepted = true
                }
              }
            }

            KeyHints {
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 4
              color: Util.alpha(root.muted, 0.85)
              fontFamily: root.fontFamily
              hints: ["enter", "save", "esc", "cancel"]
            }
          }
        }
      }
    }
  }
}
