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
  moduleName: "omacross.picross"
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
  property string prompt: ""               // "" | "quit" | "new"
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
  // The play screen lives in a Component, so its animation has no id at this
  // scope. Bumping a counter is the handshake: the badge watches the token.
  property int penaltyToken: 0

  readonly property var difficulty: Game.difficultyFor(difficultyId)
  readonly property var puzzle: game ? game.puzzle : null
  readonly property bool playing: screen === "playing" && status === "playing"
  readonly property bool clockRunning: playing && opened && prompt === ""
  readonly property bool lowOnTime: playing && remainingMs <= 60000

  // Passing `board` in is what makes these re-evaluate: Game reads the live
  // array inside `game`, which QML has no way to observe on its own.
  readonly property var solvedRows: linesSolved(board, true)
  readonly property var solvedColumns: linesSolved(board, false)

  function linesSolved(currentBoard, byRow) {
    var out = []
    if (!game || currentBoard.length === 0) return out
    for (var i = 0; i < game.size; i++)
      out.push(byRow ? Game.rowSolved(game, i) : Game.columnSolved(game, i))
    return out
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
    prompt = ""
    screen = "playing"
    syncState()
    clock.restartFrom()
  }

  function retryGame() {
    if (!game) return startGame()
    game = Game.createGame(game.puzzle, difficultyId)
    prompt = ""
    screen = "playing"
    syncState()
    clock.restartFrom()
  }

  function toTitle() {
    game = null
    prompt = ""
    notice = ""
    screen = "title"
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

  function guessAt(row, col) {
    if (!playing || prompt !== "") return
    var outcome = Game.guess(game, row, col)
    if (!outcome.changed) return
    Game.setCursor(game, row, col)
    syncState()
    if (outcome.penaltyMs > 0) {
      penaltyText = Game.formatPenalty(outcome.penaltyMs)
      penaltyToken++
    }
    finishIfOver()
  }

  function markAt(row, col) {
    if (!playing || prompt !== "") return
    if (!Game.mark(game, row, col)) return
    Game.setCursor(game, row, col)
    syncState()
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
          anchors.centerIn: parent
          spacing: Style.space(14)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.prompt === "quit" ? "Quit this picture?" : "Start a new picture?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Your progress on this one is lost."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(10)

            Button {
              text: root.prompt === "quit" ? "Quit" : "New picture"
              bordered: true
              onClicked: root.confirmPrompt()
            }

            Button {
              text: "Keep playing"
              bordered: true
              onClicked: root.prompt = ""
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "enter  confirm      esc  keep playing"
            color: Util.alpha(root.muted, 0.85)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

        Text {
          id: penaltyBadge
          anchors.horizontalCenter: clockText.horizontalCenter
          anchors.top: clockText.bottom
          text: root.penaltyText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          opacity: 0

          SequentialAnimation {
            id: penaltyPulse
            NumberAnimation { target: penaltyBadge; property: "opacity"; to: 1; duration: 60 }
            PauseAnimation { duration: 800 }
            NumberAnimation { target: penaltyBadge; property: "opacity"; to: 0; duration: 400 }
          }

          Connections {
            target: root
            function onPenaltyTokenChanged() { penaltyPulse.restart() }
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
            text: root.mistakes === 0 ? "NO MISSES" : root.mistakes + (root.mistakes === 1 ? " MISS" : " MISSES")
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
        interactive: root.prompt === ""
        foreground: root.foreground
        accent: root.accent
        urgent: root.urgent
        muted: root.muted
        fontFamily: root.fontFamily
        onGuessRequested: function(row, col) { root.guessAt(row, col) }
        onMarkRequested: function(row, col) { root.markAt(row, col) }
        onCellEntered: function(row, col) { root.jumpCursor(row, col) }
      }

      // Keys only. The mouse does the same two things and needs no telling —
      // and spelling both out was most of the width this panel was carrying.
      //
      // Broken across two lines on purpose. Left to wrap, it broke wherever
      // the narrowest board happened to put it; as a fixed pair of lines the
      // legend reads the same at every difficulty and fits a 5x5 panel.
      // Padded into fixed columns and left-aligned inside a centered Column,
      // so the two rows line up as a legend instead of each being centered on
      // its own length. The bar font is monospace, which is what makes the
      // padding land.
      Column {
        id: playHint
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(2)

        Repeater {
          model: [
            "space  fill       x       cross out",
            "hjkl   move       ctrl+q  quit"
          ]

          Text {
            required property var modelData
            text: modelData
            color: Util.alpha(root.muted, 0.85)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
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
            ? Game.formatClock(root.remainingMs) + " left      "
              + (root.mistakes === 0 ? "no misses" : root.mistakes + (root.mistakes === 1 ? " miss" : " misses"))
            : root.mistakes + (root.mistakes === 1 ? " miss" : " misses") + " cost you the clock"
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

      Text {
        id: resultHint
        anchors.horizontalCenter: parent.horizontalCenter
        text: resultView.won
          ? "enter  next picture      ctrl+n  new game      esc  close"
          : "enter  try again      ctrl+n  new picture      esc  close"
        color: Util.alpha(root.muted, 0.85)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    }
  }

  // ------------------------------------------------------------------- input
  //
  // One handler for every screen. Modifier combinations are checked first, so
  // Ctrl+N never reaches the title screen's plain-`n` handling.
  function handleKey(event) {
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
    if (event.key === Qt.Key_Down || text === "j") { moveCursor(1, 0); event.accepted = true; return }
    if (event.key === Qt.Key_Up || text === "k") { moveCursor(-1, 0); event.accepted = true; return }
    if (event.key === Qt.Key_Right || text === "l") { moveCursor(0, 1); event.accepted = true; return }
    if (event.key === Qt.Key_Left || text === "h") { moveCursor(0, -1); event.accepted = true; return }

    // The rest of the motions a vim user reaches for without thinking.
    if (text === "0" || text === "^") { jumpCursor(-1, 0); event.accepted = true; return }
    if (text === "$") { jumpCursor(-1, game.size - 1); event.accepted = true; return }
    if (text === "g") { jumpCursor(0, -1); event.accepted = true; return }
    if (text === "G") { jumpCursor(game.size - 1, -1); event.accepted = true; return }

    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      guessAt(cursorRow, cursorCol); event.accepted = true; return
    }
    if (text === "x" || text === "X") { markAt(cursorRow, cursorCol); event.accepted = true }
  }
}
