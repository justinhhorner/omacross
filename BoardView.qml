import QtQuick
import qs.Commons
import "Game.js" as Game

// The grid and its clues.
//
// Purely a view: it renders `board` and reports where the player clicked. Every
// rule lives in Game.js, and every value it paints is a binding on `board`, so
// one array reassignment in the panel repaints the whole thing consistently.
Item {
  id: root

  property int size: 5
  property var board: []
  property var rowClues: []
  property var columnClues: []
  property var solvedRows: []
  property var solvedColumns: []
  property int cursorRow: 0
  property int cursorCol: 0
  property bool interactive: true

  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color muted: Color.muted
  property string fontFamily: Style.font.family

  // The wrong guess just made: which cell, and what it cost. Bumping the
  // token is the handshake that tells the cell and the floating label to
  // replay their animation, even if the same cell is wrong again.
  property string penaltyText: ""
  property int penaltyRow: -1
  property int penaltyCol: -1
  property int penaltyToken: 0

  // How long the cost floats upward before it fades, and how long that fade
  // takes — named here so either can be retuned without hunting animations.
  readonly property int penaltyRiseDurationMs: 1000
  readonly property int penaltyFadeDurationMs: 400

  // A wrong guess is shown as if it were right, then — once the player has
  // believed it — the cell shatters back to empty. These are the two beats
  // of that trick: how long the lie holds, and how long it takes to break.
  readonly property int penaltyRevealDelayMs: 250
  readonly property int penaltyShatterDurationMs: 450

  signal cellEntered(int row, int col)

  // The drag-select gesture: press starts it (and guesses the pressed cell),
  // every subsequent cell the pointer enters while the button stays down
  // continues it, and release ends it. The panel owns what "continues"
  // means — throttling and the stop-on-wrong-cell rule are its business, not
  // this view's.
  signal dragSelectStarted(int row, int col)
  signal dragSelectMoved(int row, int col)
  signal dragSelectEnded()

  // Same gesture, for crossing out: press starts it (and marks the pressed
  // cell), moving while the button stays down continues it. There is no
  // wrong cell to break it — only release ends a mark run.
  signal dragMarkStarted(int row, int col)
  signal dragMarkMoved(int row, int col)
  signal dragMarkEnded()

  // Cells shrink as the grid grows so a 15×15 board and its clues still sit in
  // a bar popup without the panel outgrowing the screen.
  readonly property int cellSize: size <= 5 ? Style.space(30) : (size <= 10 ? Style.space(25) : Style.space(21))
  readonly property int clueStep: Math.round(cellSize * 0.62)
  readonly property int clueFontSize: size <= 5 ? Style.font.body : Style.font.bodySmall

  // How many numbers the longest clue in a set needs room for. At least one,
  // so an all-empty line still reserves the space its `0` is printed in.
  function longestClue(clues) {
    var most = 1
    for (var i = 0; i < clues.length; i++) most = Math.max(most, clues[i].length)
    return most
  }

  readonly property int maxRowClues: longestClue(rowClues)
  readonly property int maxColumnClues: longestClue(columnClues)

  readonly property int gridSpan: cellSize * size
  readonly property int rowClueWidth: clueStep * maxRowClues + Style.space(6)
  readonly property int columnClueHeight: clueStep * maxColumnClues + Style.space(6)

  readonly property color gridLine: Util.alpha(foreground, 0.22)
  readonly property color majorLine: Util.alpha(foreground, 0.55)
  readonly property color doneClue: Util.alpha(muted, 0.45)

  implicitWidth: rowClueWidth + gridSpan
  implicitHeight: columnClueHeight + gridSpan

  // ------------------------------------------------------------- column clues
  Item {
    x: root.rowClueWidth
    y: 0
    width: root.gridSpan
    height: root.columnClueHeight

    Repeater {
      model: root.size

      Item {
        id: columnClue
        required property int index
        readonly property var runs: root.columnClues[index] || [0]
        readonly property bool done: root.solvedColumns[index] === true

        x: index * root.cellSize
        y: 0
        width: root.cellSize
        height: root.columnClueHeight

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(5)
          spacing: 0

          Repeater {
            model: columnClue.runs

            Text {
              required property var modelData
              width: root.cellSize
              height: root.clueStep
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData
              color: columnClue.done ? root.doneClue : root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.clueFontSize
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- row clues
  Item {
    x: 0
    y: root.columnClueHeight
    width: root.rowClueWidth
    height: root.gridSpan

    Repeater {
      model: root.size

      Item {
        id: rowClue
        required property int index
        readonly property var runs: root.rowClues[index] || [0]
        readonly property bool done: root.solvedRows[index] === true

        x: 0
        y: index * root.cellSize
        width: root.rowClueWidth
        height: root.cellSize

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Repeater {
            model: rowClue.runs

            Text {
              required property var modelData
              width: root.clueStep
              height: root.cellSize
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData
              color: rowClue.done ? root.doneClue : root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.clueFontSize
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------------- grid
  Item {
    x: root.rowClueWidth
    y: root.columnClueHeight
    width: root.gridSpan
    height: root.gridSpan

    Repeater {
      model: root.size * root.size

      Rectangle {
        id: cell
        required property int index
        readonly property int row: Math.floor(index / root.size)
        readonly property int col: index % root.size
        // Not named `state`: Item already owns that name for its state machine.
        readonly property int mark: root.board[index] === undefined ? Game.UNKNOWN : root.board[index]

        // The board never records a wrong guess, so this cell has to play the
        // trick itself: pose as a correct fill, hold it, then break apart —
        // two beats, two flags. Neither survives a wrong guess elsewhere or a
        // fresh game, since a new `penaltyToken` is the only thing that sets
        // them, and a losing/won board stops issuing those.
        property bool wrongReveal: false
        property bool shattering: false

        x: col * root.cellSize
        y: row * root.cellSize
        width: root.cellSize
        height: root.cellSize

        Connections {
          target: root
          function onPenaltyTokenChanged() {
            if (cell.row !== root.penaltyRow || cell.col !== root.penaltyCol) return
            shatterTimer.stop()
            cell.shattering = false
            cell.wrongReveal = true
            revealTimer.restart()
          }
        }

        Timer {
          id: revealTimer
          interval: root.penaltyRevealDelayMs
          onTriggered: { cell.shattering = true; shatterTimer.restart() }
        }

        Timer {
          id: shatterTimer
          interval: root.penaltyShatterDurationMs
          onTriggered: { cell.wrongReveal = false; cell.shattering = false }
        }

        color: {
          if (mark === Game.FILLED) return root.foreground
          if (mark === Game.MARKED) return Util.alpha(root.foreground, 0.05)
          return "transparent"
        }
        border.width: 1
        border.color: root.gridLine

        Behavior on color {
          ColorAnimation { duration: 90 }
        }

        // The lie: for a moment, a wrong guess looks exactly like a right one.
        Rectangle {
          anchors.fill: parent
          color: root.foreground
          visible: cell.wrongReveal && !cell.shattering
        }

        // The reveal: nine tiles standing in for that same fill, flying apart
        // once the lie has held long enough to be believed. A plain Item, not
        // a Grid: a positioner would keep re-snapping the shards back into
        // place against the very animation meant to fly them apart.
        Item {
          anchors.fill: parent
          visible: cell.shattering

          Repeater {
            model: 9

            Rectangle {
              id: shard
              required property int index
              readonly property real baseX: (index % 3) * width
              readonly property real baseY: Math.floor(index / 3) * height
              readonly property real angle: (index / 9) * 2 * Math.PI + (Math.random() - 0.5) * 0.6
              readonly property real distance: root.cellSize * (0.7 + Math.random() * 0.5)
              readonly property real spin: (Math.random() - 0.5) * 260

              width: root.cellSize / 3
              height: root.cellSize / 3
              color: root.foreground
              x: baseX
              y: baseY
              transformOrigin: Item.Center

              Connections {
                target: cell
                function onShatteringChanged() {
                  if (!cell.shattering) return
                  shard.x = shard.baseX
                  shard.y = shard.baseY
                  shard.rotation = 0
                  shard.opacity = 1
                  shardFly.restart()
                }
              }

              ParallelAnimation {
                id: shardFly
                NumberAnimation { target: shard; property: "x"; to: shard.baseX + Math.cos(shard.angle) * shard.distance; duration: root.penaltyShatterDurationMs; easing.type: Easing.OutQuad }
                NumberAnimation { target: shard; property: "y"; to: shard.baseY + Math.sin(shard.angle) * shard.distance; duration: root.penaltyShatterDurationMs; easing.type: Easing.OutQuad }
                NumberAnimation { target: shard; property: "rotation"; to: shard.spin; duration: root.penaltyShatterDurationMs }
                NumberAnimation { target: shard; property: "opacity"; to: 0; duration: root.penaltyShatterDurationMs; easing.type: Easing.InQuad }
              }
            }
          }
        }

        // The player's own cross-out is the only mark left wearing an ×.
        Text {
          anchors.centerIn: parent
          visible: cell.mark === Game.MARKED
          text: "×"
          color: Util.alpha(root.muted, 0.9)
          font.family: root.fontFamily
          font.pixelSize: Math.round(root.cellSize * 0.62)
        }
      }
    }

    // Every fifth line drawn heavier, the way a printed nonogram is ruled —
    // without it, counting to eleven across a 15-wide row is the puzzle.
    Repeater {
      model: Math.max(0, Math.ceil(root.size / 5) - 1)

      Item {
        id: rule
        required property int index
        readonly property int offset: (index + 1) * 5 * root.cellSize

        Rectangle {
          x: rule.offset - 1
          y: 0
          width: 2
          height: root.gridSpan
          color: root.majorLine
        }
        Rectangle {
          x: 0
          y: rule.offset - 1
          width: root.gridSpan
          height: 2
          color: root.majorLine
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: 2
      border.color: root.majorLine
    }

    // Cursor sits above the rules so it stays visible on a major gridline.
    Rectangle {
      x: root.cursorCol * root.cellSize - 1
      y: root.cursorRow * root.cellSize - 1
      width: root.cellSize + 2
      height: root.cellSize + 2
      color: "transparent"
      border.width: 2
      border.color: root.accent

      Behavior on x { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
      Behavior on y { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
    }

    // The cost of the last wrong guess, floating up from the cell it was
    // charged against, then fading — the one telling a locked-empty cell
    // gets before it goes quiet.
    Text {
      id: penaltyFloat
      property real baseY: 0

      text: root.penaltyText
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.cellSize * 0.5)
      font.bold: true
      opacity: 0
      z: 10

      Connections {
        target: root
        function onPenaltyTokenChanged() {
          penaltyFloat.x = root.penaltyCol * root.cellSize + (root.cellSize - penaltyFloat.implicitWidth) / 2
          penaltyFloat.baseY = root.penaltyRow * root.cellSize + root.cellSize * 0.15
          penaltyFloat.y = penaltyFloat.baseY
          penaltyFloatAnim.restart()
        }
      }

      SequentialAnimation {
        id: penaltyFloatAnim
        ParallelAnimation {
          NumberAnimation { target: penaltyFloat; property: "y"; to: penaltyFloat.baseY - root.cellSize * 0.7; duration: root.penaltyRiseDurationMs; easing.type: Easing.OutQuad }
          NumberAnimation { target: penaltyFloat; property: "opacity"; from: 0; to: 1; duration: 150 }
        }
        NumberAnimation { target: penaltyFloat; property: "opacity"; to: 0; duration: root.penaltyFadeDurationMs }
      }
    }

    // One mouse area for the whole grid rather than one per cell: 225 hover
    // handlers on a hard board is a lot of plumbing for a coordinate divide.
    MouseArea {
      id: pointer
      anchors.fill: parent
      enabled: root.interactive
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      function cellRow(y) { return Math.floor(y / root.cellSize) }
      function cellColumn(x) { return Math.floor(x / root.cellSize) }
      function inside(row, col) {
        return row >= 0 && row < root.size && col >= 0 && col < root.size
      }

      onPositionChanged: function(mouse) {
        var row = cellRow(mouse.y)
        var col = cellColumn(mouse.x)
        if (!inside(row, col)) return
        root.cellEntered(row, col)
        if (mouse.buttons & Qt.LeftButton) root.dragSelectMoved(row, col)
        if (mouse.buttons & Qt.RightButton) root.dragMarkMoved(row, col)
      }

      onPressed: function(mouse) {
        var row = cellRow(mouse.y)
        var col = cellColumn(mouse.x)
        if (!inside(row, col)) return
        if (mouse.button === Qt.RightButton) root.dragMarkStarted(row, col)
        else root.dragSelectStarted(row, col)
      }

      onReleased: function(mouse) {
        if (mouse.button === Qt.LeftButton) root.dragSelectEnded()
        if (mouse.button === Qt.RightButton) root.dragMarkEnded()
      }
    }
  }
}
