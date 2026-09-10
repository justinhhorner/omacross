import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Game.js" as Game

// Omacross — a picross game in the Omarchy bar.
//
// The panel owns the clock and the input routing; the rules live in Game.js and
// the pixels in BoardView/TitleScreen. Game state is a plain JavaScript object,
// which QML cannot bind to, so every mutation ends in `syncState()` — that is
// the one place where the state machine becomes properties the view can watch.
Panel {
  id: root
  moduleName: "justinhhorner.picross"
  ipcTarget: "omacross"

  // ------------------------------------------------------------------- theme
  //
  // Read straight off the shell's Color singleton, which the theme switcher
  // reassigns in place. Binding rather than copying is the whole of the
  // "follows the active Omarchy theme" requirement.
  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------------- state
  property string screen: "title"          // title | playing | result
  property string difficultyId: setting("difficulty", "easy")
  property string prompt: ""               // "" | "quit" | "new" | "hint"
  property string notice: ""

  // The live game, or null on the title screen.
  property var game: null
  property string lastFile: ""

  // Mirrors of `game`, republished by syncState() so bindings have something
  // to depend on.
  property var board: []
  property double remainingMs: 0
  property int mistakes: 0
  property string status: "idle"
  property int cursorRow: 0
  property int cursorCol: 0

  property string penaltyText: ""
  property int penaltyRow: -1
  property int penaltyCol: -1
  // The play screen lives in a Component, so its animation has no id at this
  // scope. Bumping a counter is the handshake: the board watches the token.
  property int penaltyToken: 0

  // The cells a hint just revealed, and the token that tells the board to
  // flip them in. `hintAnimating` blocks every input path — mouse (via
  // BoardView.interactive) and keyboard (via handleKey) alike — until the
  // board reports the reveal has finished playing.
  property var hintCells: []
  property int hintToken: 0
  property bool hintAnimating: false

  // Drag-select: holding the fill button (mouse or space) and moving keeps
  // guessing every cell entered, until either a wrong one breaks the streak
  // or the button is released — whichever comes first re-arms it.
  property bool dragSelecting: false
  property bool dragBroken: false
  readonly property int dragSelectNavDelayMs: 100
  // Set from the cell the run started on: filled means this run undoes,
  // unfilled means it guesses. Fixed for the whole run so brushing back over
  // a cell it already touched never flips it a second time — mirrors
  // dragMarkErasing.
  property bool dragSelectErasing: false

  // Drag-mark: the same gesture, but for crossing out. There is no wrong
  // cell here — marking always succeeds or no-ops — so nothing ever breaks
  // a mark run; only releasing the button/key ends it. Its own constant, not
  // a reuse of dragSelectNavDelayMs, since the two paces may want to diverge.
  property bool dragMarking: false
  readonly property int dragMarkNavDelayMs: 100
  // Set from the cell the run started on: marked means this run erases,
  // unmarked means it marks. Fixed for the whole run so passing back over a
  // cell it already touched — or lingering on one, which can re-fire the
  // same cell — never flips it a second time.
  property bool dragMarkErasing: false

  // A mistake that empties the clock still has to be seen as a mistake: cut
  // straight to the result screen and the wrong-cell reveal underneath it is
  // gone before it plays. Holding here for a beat is what lets it land.
  readonly property int mistakeResultDelayMs: 1000

  onOpenedChanged: if (!opened) { dragSelecting = false; dragBroken = false; dragMarking = false; hintAnimating = false }

  readonly property var difficulty: Game.difficultyFor(difficultyId)
  readonly property var puzzle: game ? game.puzzle : null
  readonly property bool playing: screen === "playing" && status === "playing"
  readonly property bool clockRunning: playing && opened && prompt === ""
  readonly property bool lowOnTime: playing && remainingMs <= 60000

  // Passing `board` in is what makes these re-evaluate: Game reads the live
  // array inside `game`, which QML has no way to observe on its own.
  readonly property var solvedRows: rowsSolved(board)
  readonly property var solvedColumns: columnsSolved(board)

  function rowsSolved(currentBoard) {
    var out = []
    if (!game || currentBoard.length === 0) return out
    for (var i = 0; i < game.size; i++) out.push(Game.rowSolved(game, i))
    return out
  }

  function columnsSolved(currentBoard) {
    var out = []
    if (!game || currentBoard.length === 0) return out
    for (var i = 0; i < game.size; i++) out.push(Game.columnSolved(game, i))
    return out
  }

  // "no misses" / "1 miss" / "3 misses" — the header shouts it in caps, the
  // result screen says it in the middle of a sentence, so the casing is the
  // caller's business and the pluralisation is stated once.
  function missesText(count) {
    if (count === 0) return "no misses"
    return count + (count === 1 ? " miss" : " misses")
  }

  function syncState() {
    if (!game) {
      board = []
      remainingMs = 0
      mistakes = 0
      status = "idle"
      return
    }
    board = game.board.slice()
    remainingMs = game.remainingMs
    mistakes = game.mistakes
    status = game.status
    cursorRow = game.cursorRow
    cursorCol = game.cursorCol
  }

  // ------------------------------------------------------------- game control
  function startGame() {
    var next = patternLibrary.pick(difficulty.size, lastFile)
    if (!next) {
      notice = "No " + difficulty.size + "×" + difficulty.size + " pictures found."
      return
    }
    notice = ""
    lastFile = next.file
    game = Game.createGame(next, difficultyId)
    prompt = "hint"
    screen = "playing"
    dragSelecting = false
    dragBroken = false
    dragMarking = false
    hintAnimating = false
    syncState()
    clock.restartFrom()
  }

  function retryGame() {
    if (!game) return startGame()
    game = Game.createGame(game.puzzle, difficultyId)
    prompt = "hint"
    screen = "playing"
    dragSelecting = false
    dragBroken = false
    dragMarking = false
    hintAnimating = false
    syncState()
    clock.restartFrom()
  }

  function toTitle() {
    game = null
    prompt = ""
    notice = ""
    screen = "title"
    dragSelecting = false
    dragBroken = false
    dragMarking = false
    hintAnimating = false
    syncState()
  }

  function pickDifficulty(id) {
    difficultyId = id
    notice = ""
  }

  function stepDifficulty(delta) {
    var list = Game.DIFFICULTIES
    var current = 0
    for (var i = 0; i < list.length; i++) if (list[i].id === difficultyId) current = i
    pickDifficulty(list[((current + delta) % list.length + list.length) % list.length].id)
  }

  function finishIfOver() {
    if (!game || game.status === "playing") return
    screen = "result"
  }

  // A filled cell is already correct, so deliberately selecting it again
  // undoes it instead of bouncing off it — the one way to take back a right
  // answer. `allowUndo` is true only for the cell a click or drag-select run
  // starts on; every cell the run enters afterward passes it as false, so
  // brushing back over your own trail doesn't flicker cells on and off.
  function guessAt(row, col, allowUndo) {
    if (!playing || prompt !== "") return null
    if (allowUndo && Game.cellAt(game, row, col) === Game.FILLED) {
      if (!Game.unguess(game, row, col)) return null
      Game.setCursor(game, row, col)
      syncState()
      return { changed: true, correct: false, penaltyMs: 0, status: game.status }
    }
    var outcome = Game.guess(game, row, col)
    if (!outcome.changed) return outcome
    Game.setCursor(game, row, col)
    syncState()
    if (outcome.penaltyMs > 0) {
      penaltyText = Game.formatPenalty(outcome.penaltyMs)
      penaltyRow = row
      penaltyCol = col
      penaltyToken++
    }
    // A mistake that ends the game gets a beat before the result screen
    // covers it, so the player sees the miss that cost them. Every other
    // ending (a win, or the clock simply running out) has nothing to wait
    // for and cuts straight there.
    if (outcome.penaltyMs > 0 && game.status !== "playing") mistakeResultDelay.restart()
    else finishIfOver()
    return outcome
  }

  Timer {
    id: mistakeResultDelay
    interval: root.mistakeResultDelayMs
    onTriggered: root.finishIfOver()
  }

  // ---------------------------------------------------------- drag-select
  //
  // Pressing (mouse) or holding space (keyboard) starts a run; every cell
  // entered while it's live gets guessed, at most once per
  // `dragSelectNavDelayMs`, until a wrong one breaks it. Release re-arms.
  function beginDragSelect(row, col) {
    dragSelecting = true
    dragBroken = false
    dragSelectErasing = playing && Game.cellAt(game, row, col) === Game.FILLED
    jumpCursor(row, col)
    attemptDragGuess(row, col)
    dragSelectThrottle.restart()
  }

  function continueDragSelect(row, col) {
    if (!dragSelecting || dragBroken || dragSelectThrottle.running) return
    jumpCursor(row, col)
    attemptDragGuess(row, col)
    dragSelectThrottle.restart()
  }

  function endDragSelect() {
    dragSelecting = false
    dragBroken = false
  }

  // Drives a cell toward this run's fixed outcome (undo or guess) rather
  // than toggling it — a cell already there is left alone, so brushing back
  // over the run's own trail never flickers it. Mirrors dragMarkAt.
  function attemptDragGuess(row, col) {
    if (!playing || prompt !== "") return
    var alreadyFilled = Game.cellAt(game, row, col) === Game.FILLED
    if (dragSelectErasing !== alreadyFilled) return
    var outcome = guessAt(row, col, dragSelectErasing)
    if (outcome && outcome.penaltyMs > 0) dragBroken = true
  }

  Timer {
    id: dragSelectThrottle
    interval: root.dragSelectNavDelayMs
  }

  // ------------------------------------------------------------ drag-mark
  //
  // Same shape as drag-select, minus the breaking condition: a mark never
  // "goes wrong", so a run only ever ends on release. What it does is fixed
  // at the start rather than toggled per cell — see `dragMarkErasing`.
  function beginDragMark(row, col) {
    dragMarking = true
    dragMarkErasing = playing && Game.cellAt(game, row, col) === Game.MARKED
    jumpCursor(row, col)
    dragMarkAt(row, col)
    dragMarkThrottle.restart()
  }

  function continueDragMark(row, col) {
    if (!dragMarking || dragMarkThrottle.running) return
    jumpCursor(row, col)
    dragMarkAt(row, col)
    dragMarkThrottle.restart()
  }

  function endDragMark() {
    dragMarking = false
  }

  Timer {
    id: dragMarkThrottle
    interval: root.dragMarkNavDelayMs
  }

  function markAt(row, col) {
    if (!playing || prompt !== "") return
    if (!Game.mark(game, row, col)) return
    Game.setCursor(game, row, col)
    syncState()
  }

  // Drives a cell toward this run's fixed outcome rather than toggling it —
  // a cell already there (already marked mid-mark-run, already bare
  // mid-erase-run) is left alone instead of being flipped back.
  function dragMarkAt(row, col) {
    if (!playing || prompt !== "") return
    var target = dragMarkErasing ? Game.UNKNOWN : Game.MARKED
    if (Game.cellAt(game, row, col) === target) return
    markAt(row, col)
  }

  function moveCursor(dRow, dCol) {
    if (!playing || prompt !== "") return
    Game.moveCursor(game, dRow, dCol)
    syncState()
  }

  function jumpCursor(row, col) {
    if (!playing || prompt !== "") return
    Game.setCursor(game, row === -1 ? game.cursorRow : row, col === -1 ? game.cursorCol : col)
    syncState()
  }

  // --------------------------------------------------------------- confirming
  //
  // Ctrl+Q and Ctrl+N both throw away a game in progress, so both ask first —
  // and neither asks when there is nothing to lose.
  function requestPrompt(kind) {
    if (!playing) {
      if (kind === "new") startGame()
      else close()
      return
    }
    prompt = kind
  }

  function confirmPrompt() {
    var kind = prompt
    prompt = ""
    if (kind === "quit") toTitle()
    else if (kind === "new") startGame()
    else if (kind === "hint") applyHint()
  }

  // The one freebie: a random row and column, revealed before the clock has
  // taken a single tick off. Declining just drops the prompt and starts play
  // exactly as before. The board is updated immediately — the win check and
  // the result screen wait for the flip animation to finish, via
  // handleHintRevealFinished below, so a puzzle a hint happens to complete
  // isn't whisked away before the player sees it revealed.
  function applyHint() {
    if (!game) return
    var hint = Game.revealHint(game)
    syncState()
    hintCells = (hint && hint.cells) || []
    if (hintCells.length > 0) {
      hintAnimating = true
      hintToken++
    } else {
      finishIfOver()
    }
  }

  function handleHintRevealFinished() {
    hintAnimating = false
    finishIfOver()
  }

  // ------------------------------------------------------------------- clock
  //
  // Driven off wall-clock deltas rather than counting ticks: the timer is
  // paused whenever the panel is closed or a prompt is up, and a coarse or
  // late-firing tick must not quietly hand the player extra seconds.
  Timer {
    id: clock
    interval: 100
    repeat: true
    running: root.clockRunning
    property double lastMs: 0

    function restartFrom() { lastMs = Date.now() }

    onRunningChanged: if (running) restartFrom()

    onTriggered: {
      if (!root.game) return
      var now = Date.now()
      var delta = Math.max(0, now - lastMs)
      lastMs = now
      if (delta === 0) return
      Game.tick(root.game, delta)
      root.syncState()
      root.finishIfOver()
    }
  }

  PatternLibrary {
    id: patternLibrary
    extraDir: root.setting("patternsDir", "")
  }


  // -------------------------------------------------------------- bar trigger
  //
  // The bar sizes each slot from its widget's implicit size, so the root has to
  // report the button's — anchors.fill only sets the button's actual size, and
  // a root that stays implicitly zero gets a zero-wide slot and never appears.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font "th": a nine-square grid, which is a nonogram at a glance.
    text: ""
    active: root.playing
    tooltipText: root.playing
      ? "Omacross — " + Game.formatClock(root.remainingMs) + " left"
      : "Omacross"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    // fittedContentHeight adds the card's padding and borders for you;
    // fittedContentWidth does not — it takes the finished window width. Adding
    // the horizontal inset here is what keeps the widest line from being
    // clipped by the padding it was never measured against.
    contentWidth: panel.fittedContentWidth(content.implicitWidth + panel.padding * 2
      + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }
      Keys.onReleased: function(event) { root.handleKeyRelease(event) }

      Item {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        // Size to the screen actually showing, not to the largest of the
        // three: the panel should be as big as the board in front of you, and
        // the title screen is taller than a 5×5 game.
        readonly property Item activeScreen: root.screen === "playing" ? gameLoader
          : (root.screen === "result" ? resultLoader : titleLoader)

        implicitWidth: activeScreen.implicitWidth
        implicitHeight: activeScreen.implicitHeight
        width: implicitWidth
        height: implicitHeight

        // --------------------------------------------------------- title
        Loader {
          id: titleLoader
          anchors.horizontalCenter: parent.horizontalCenter
          active: root.screen === "title"
          visible: active
          sourceComponent: TitleScreen {
            foreground: root.foreground
            accent: root.accent
            muted: root.muted
            fontFamily: root.fontFamily
            difficultyId: root.difficultyId
            notice: root.notice
            urgent: root.urgent
            opened: root.opened
            // Not `library: library`: inside an object declaration an
            // unqualified name resolves to that object's own property first,
            // so the id has to differ from the property it feeds.
            library: patternLibrary
            onDifficultyPicked: function(id) { root.pickDifficulty(id) }
            onStartRequested: root.startGame()
          }
        }

        // ---------------------------------------------------------- game
        Loader {
          id: gameLoader
          anchors.horizontalCenter: parent.horizontalCenter
          active: root.screen === "playing" && root.game !== null
          visible: active
          sourceComponent: playColumn
        }

        // -------------------------------------------------------- result
        Loader {
          id: resultLoader
          anchors.horizontalCenter: parent.horizontalCenter
          active: root.screen === "result" && root.game !== null
          visible: active
          sourceComponent: resultColumn
        }
      }

      // ------------------------------------------------------------ prompt
      Rectangle {
        anchors.fill: parent
        visible: root.prompt !== ""
        color: Util.alpha(Color.popups.background, 0.92)

        Column {
          // Bounded to the panel's actual width, not the prompt's own text —
          // a small board (easy's 5x5) makes a narrower panel than the
          // longest prompt sentence, so without a cap and wrapping the text
          // spills past the card's border instead of staying inside it.
          anchors.centerIn: parent
          width: parent.width - Style.space(24)
          spacing: Style.space(14)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.prompt === "quit" ? "Quit this picture?"
              : root.prompt === "new" ? "Start a new picture?"
              : "Want a hint?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.prompt === "hint" ? "Reveal a random row and column for free."
              : "Your progress on this one is lost."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(10)

            Button {
              text: root.prompt === "quit" ? "Quit"
                : root.prompt === "new" ? "New picture"
                : "Reveal hint"
              bordered: true
              onClicked: root.confirmPrompt()
            }

            Button {
              text: root.prompt === "hint" ? "No thanks" : "Keep playing"
              bordered: true
              onClicked: root.prompt = ""
            }
          }

          KeyHints {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 4
            color: Util.alpha(root.muted, 0.85)
            fontFamily: root.fontFamily
            hints: root.prompt === "hint" ? ["enter", "reveal hint", "esc", "no thanks"]
              : ["enter", "confirm", "esc", "keep playing"]
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ play screen
  Component {
    id: playColumn

    Item {
      id: playView

      // The grid is what the eye centers on, but the row clues hang off its
      // left side only — so a panel sized to the board as a whole leaves the
      // grid pushed right by the width of that gutter. Reserving the same
      // gutter again on the right centers the grid itself, and hands the
      // header the room it needs to space out.
      readonly property real gutter: boardView.rowClueWidth

      // The floor: difficulty, clock and misses side by side, with a gap
      // either side of the clock that the panel may grow but never shrink.
      readonly property real headerGap: Style.space(16)
      readonly property real headerFloor: difficultyLabel.implicitWidth
        + missCount.measuredWidth + clockText.implicitWidth + 2 * headerGap

      // The hint line is deliberately absent from this measurement: letting a
      // sentence of key names decide the panel size made a 5x5 board sit in
      // the middle of a panel built for the text under it.
      implicitWidth: Math.max(boardView.implicitWidth + gutter, headerFloor)
      implicitHeight: playStack.implicitHeight

      Column {
        id: playStack
        width: playView.width
        spacing: Style.space(12)

        Item {
          width: playStack.width
          implicitHeight: Math.max(difficultyLabel.implicitHeight, clockText.implicitHeight, missCount.implicitHeight)

          Column {
            id: difficultyLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              text: root.difficulty.label.toUpperCase()
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: Style.space(1)
            }
            Text {
              text: root.difficulty.size + "×" + root.difficulty.size
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            id: clockText
            x: Math.round(difficultyLabel.width
              + (parent.width - difficultyLabel.width - missCount.width - implicitWidth) / 2)
            anchors.verticalCenter: parent.verticalCenter
            text: Game.formatClock(root.remainingMs)
            color: root.lowOnTime ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true

            // The last minute reads as an alarm without needing a second label.
            SequentialAnimation on opacity {
              running: root.lowOnTime
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { to: 0.45; duration: 500 }
              NumberAnimation { to: 1.0; duration: 500 }
            }
          }

          // Right-aligned by measuring the column and aligning the text inside
          // it, not by anchoring the children to its edge: an anchored child
          // leaves the Column implicitly zero wide, and the header floor above
          // is measured from exactly that number.
          Column {
            id: missCount
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)
            // A positioner computes its own implicitWidth and will not take an
            // assignment, so the measurement lives beside it and the children
            // take their width from that.
            readonly property real measuredWidth: Math.max(missLabel.implicitWidth, nextPenaltyLabel.implicitWidth)

            Text {
              id: missLabel
              width: missCount.measuredWidth
              horizontalAlignment: Text.AlignRight
              text: root.missesText(root.mistakes).toUpperCase()
              color: root.mistakes === 0 ? root.muted : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: root.mistakes > 0
              font.letterSpacing: Style.space(1)
            }
            Text {
              id: nextPenaltyLabel
              width: missCount.measuredWidth
              horizontalAlignment: Text.AlignRight
              text: "next " + Game.formatPenalty(Game.penaltyMsFor(root.mistakes + 1))
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        BoardView {
          id: boardView
          // Centering the board as a whole would center the clues-plus-grid
          // block; shifting it back by half the gutter centers the grid.
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.horizontalCenterOffset: -Math.round(playView.gutter / 2)
          size: root.game.size
          board: root.board
          rowClues: root.game.puzzle.rowClues
          columnClues: root.game.puzzle.columnClues
          solvedRows: root.solvedRows
          solvedColumns: root.solvedColumns
          cursorRow: root.cursorRow
          cursorCol: root.cursorCol
          interactive: root.prompt === "" && !root.hintAnimating
          foreground: root.foreground
          accent: root.accent
          urgent: root.urgent
          muted: root.muted
          fontFamily: root.fontFamily
          penaltyText: root.penaltyText
          penaltyRow: root.penaltyRow
          penaltyCol: root.penaltyCol
          penaltyToken: root.penaltyToken
          hintCells: root.hintCells
          hintToken: root.hintToken
          onHintRevealFinished: root.handleHintRevealFinished()
          onDragSelectStarted: function(row, col) { root.beginDragSelect(row, col) }
          onDragSelectMoved: function(row, col) { root.continueDragSelect(row, col) }
          onDragSelectEnded: root.endDragSelect()
          onDragMarkStarted: function(row, col) { root.beginDragMark(row, col) }
          onDragMarkMoved: function(row, col) { root.continueDragMark(row, col) }
          onDragMarkEnded: root.endDragMark()
          // Fires on every pointer move over the grid, button or no. A
          // select or mark run started from the keyboard (holding space or
          // x) has no mouse button to report movement on its own, so this is
          // what lets the mouse keep driving it as it wanders across the
          // board.
          onCellEntered: function(row, col) {
            if (root.dragSelecting) root.continueDragSelect(row, col)
            else if (root.dragMarking) root.continueDragMark(row, col)
            else root.jumpCursor(row, col)
          }
        }

        // Keys only. The mouse does the same two things and needs no telling —
        // and spelling both out was most of the width this panel was carrying.
        //
        // Broken across two lines on purpose. Left to wrap, it broke wherever
        // the narrowest board happened to put it; as a fixed pair of lines the
        // legend reads the same at every difficulty and fits a 5x5 panel.
        KeyHints {
          id: playHint
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 4
          color: Util.alpha(root.muted, 0.85)
          fontFamily: root.fontFamily
          hints: [
            "space", "fill", "x", "cross out",
            "hjkl", "move", "ctrl+q", "quit"
          ]
        }
      }
    }
  }

  // ---------------------------------------------------------- result screen
  Component {
    id: resultColumn

    Item {
      id: resultView
      readonly property bool won: root.status === "won"
      readonly property int pictureCell: root.game.size <= 5 ? Style.space(22)
        : (root.game.size <= 10 ? Style.space(14) : Style.space(10))

      // Same measuring rule as the play screen: the hint line is the widest
      // thing here, and centered children do not size their Column.
      implicitWidth: Math.max(picture.implicitWidth, resultHint.implicitWidth, stats.implicitWidth)
      implicitHeight: resultStack.implicitHeight

      Column {
        id: resultStack
        width: resultView.width
        spacing: Style.space(14)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: resultView.won ? Game.grade(root.game) : "TIME UP"
          color: resultView.won ? root.accent : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.bold: true
          font.letterSpacing: Style.space(4)
        }

        // Won: the picture, finally named. Lost: the grid you got to, still
        // nameless — the reveal is the prize, so losing does not hand it over.
        Grid {
          id: picture
          anchors.horizontalCenter: parent.horizontalCenter
          columns: root.game.size
          spacing: Math.max(1, Style.space(1))

          Repeater {
            model: root.game.size * root.game.size

            Rectangle {
              id: pictureCellRect
              required property int index
              readonly property int row: Math.floor(index / root.game.size)
              readonly property int col: index % root.game.size
              readonly property bool solid: resultView.won
                ? root.game.puzzle.cells[row][col] === 1
                : root.board[index] === Game.FILLED

              width: resultView.pictureCell
              height: resultView.pictureCell
              radius: Math.max(1, Style.space(1))
              color: solid ? root.foreground : Util.alpha(root.foreground, 0.06)
            }
          }
        }

        Column {
          id: stats
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(3)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: resultView.won ? root.game.puzzle.name : "Picture not revealed"
            color: resultView.won ? root.foreground : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: resultView.won
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: resultView.won
              ? Game.formatClock(root.remainingMs) + " left      " + root.missesText(root.mistakes)
              : root.missesText(root.mistakes) + " cost you the clock"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Button {
            text: resultView.won ? "Next picture" : "Try again"
            bordered: true
            onClicked: resultView.won ? root.startGame() : root.retryGame()
          }

          Button {
            text: "Title"
            bordered: true
            onClicked: root.toTitle()
          }
        }

        KeyHints {
          id: resultHint
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 6
          color: Util.alpha(root.muted, 0.85)
          fontFamily: root.fontFamily
          hints: [
            "enter", resultView.won ? "next picture" : "try again",
            "ctrl+n", resultView.won ? "new game" : "new picture",
            "esc", "close"
          ]
        }
      }
    }
  }

  // ------------------------------------------------------------------- input
  //
  // One handler for every screen. Modifier combinations are checked first, so
  // Ctrl+N never reaches the title screen's plain-`n` handling.
  function handleKey(event) {
    // The hint reveal is a short, uninterruptible beat — every key is
    // swallowed rather than routed anywhere while it plays.
    if (hintAnimating) { event.accepted = true; return }

    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var text = event.text

    if (ctrl && event.key === Qt.Key_Q) { requestPrompt("quit"); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_N) { requestPrompt("new"); event.accepted = true; return }

    // A prompt is modal: it answers every key itself so a stray motion cannot
    // reach the board underneath it.
    if (prompt !== "") {
      if (event.key === Qt.Key_Escape || text === "n" || text === "N") prompt = ""
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || text === "y" || text === "Y") confirmPrompt()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) { close(); event.accepted = true; return }

    if (screen === "title") { handleTitleKey(event, text); return }
    if (screen === "result") { handleResultKey(event, text); return }
    if (screen === "playing") handlePlayKey(event, text)
  }

  // The fill and cross-out buttons are the only keys worth a release
  // handler — everything else on the play screen is a single action with
  // nothing to hold. An autorepeat never reaches here, only the real key-up.
  function handleKeyRelease(event) {
    if (screen !== "playing" || event.isAutoRepeat) return
    if (event.key === Qt.Key_Space) { endDragSelect(); event.accepted = true }
    else if (event.key === Qt.Key_X) { endDragMark(); event.accepted = true }
  }

  function handleTitleKey(event, text) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      startGame(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || text === "j" || text === "l") {
      stepDifficulty(1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || text === "k" || text === "h") {
      stepDifficulty(-1); event.accepted = true; return
    }
    if (text === "1" || text === "2" || text === "3") {
      pickDifficulty(Game.DIFFICULTIES[Number(text) - 1].id); event.accepted = true
    }
  }

  function handleResultKey(event, text) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      if (status === "won") startGame()
      else retryGame()
      event.accepted = true
      return
    }
    if (text === "t" || text === "T") { toTitle(); event.accepted = true }
  }

  function handlePlayKey(event, text) {
    if (!game) return

    // Space's own key-up is handled separately; here, only its initial press
    // (not the OS's autorepeat while it's held) starts a drag-select run —
    // the same run a mouse-press starts, guessing the cell under the cursor
    // and staying live until release or a wrong guess breaks it.
    if (event.key === Qt.Key_Space) {
      if (!event.isAutoRepeat) beginDragSelect(cursorRow, cursorCol)
      event.accepted = true
      return
    }

    // Same hold-to-run gesture as fill, but for crossing out — and with no
    // wrong cell to break it, so nothing here ever needs to check dragBroken.
    if (event.key === Qt.Key_X) {
      if (!event.isAutoRepeat) beginDragMark(cursorRow, cursorCol)
      event.accepted = true
      return
    }

    var dRow = 0, dCol = 0
    if (event.key === Qt.Key_Down || text === "j") dRow = 1
    else if (event.key === Qt.Key_Up || text === "k") dRow = -1
    else if (event.key === Qt.Key_Right || text === "l") dCol = 1
    else if (event.key === Qt.Key_Left || text === "h") dCol = -1

    if (dRow !== 0 || dCol !== 0) {
      moveWithinPlay(dRow, dCol)
      event.accepted = true
      return
    }

    // The rest of the motions a vim user reaches for without thinking.
    if (text === "0" || text === "^") { jumpCursor(-1, 0); event.accepted = true; return }
    if (text === "$") { jumpCursor(-1, game.size - 1); event.accepted = true; return }
    if (text === "g") { jumpCursor(0, -1); event.accepted = true; return }
    if (text === "G") { jumpCursor(game.size - 1, -1); event.accepted = true; return }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      guessAt(cursorRow, cursorCol, true); event.accepted = true; return
    }
  }

  // A plain move just steps the cursor. While a drag-select or drag-mark run
  // is live it also acts on the landing cell — throttled to that run's own
  // nav-delay constant so the keyboard's autorepeat can't fire faster than
  // that. Select takes priority on the rare chance both keys are held.
  function moveWithinPlay(dRow, dCol) {
    if (dragSelecting && !dragBroken) {
      if (dragSelectThrottle.running) return
      moveCursor(dRow, dCol)
      attemptDragGuess(cursorRow, cursorCol)
      dragSelectThrottle.restart()
      return
    }
    if (dragMarking) {
      if (dragMarkThrottle.running) return
      moveCursor(dRow, dCol)
      dragMarkAt(cursorRow, cursorCol)
      dragMarkThrottle.restart()
      return
    }
    moveCursor(dRow, dCol)
  }
}
