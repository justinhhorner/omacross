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

  signal guessRequested(int row, int col)
  signal markRequested(int row, int col)
  signal cellEntered(int row, int col)

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

        x: col * root.cellSize
        y: row * root.cellSize
        width: root.cellSize
        height: root.cellSize

        color: {
          if (mark === Game.FILLED) return root.foreground
          if (mark === Game.PENALTY) return Util.alpha(root.urgent, 0.14)
          if (mark === Game.MARKED) return Util.alpha(root.foreground, 0.05)
          return "transparent"
        }
        border.width: 1
        border.color: root.gridLine

        Behavior on color {
          ColorAnimation { duration: 90 }
        }

        // Both cross-outs are an ×; only the color says whether it was your
        // own deduction or the game's correction.
        Text {
          anchors.centerIn: parent
          visible: cell.mark === Game.MARKED || cell.mark === Game.PENALTY
          text: "×"
          color: cell.mark === Game.PENALTY ? root.urgent : Util.alpha(root.muted, 0.9)
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
        if (inside(row, col)) root.cellEntered(row, col)
      }

      onClicked: function(mouse) {
        var row = cellRow(mouse.y)
        var col = cellColumn(mouse.x)
        if (!inside(row, col)) return
        if (mouse.button === Qt.RightButton) root.markRequested(row, col)
        else root.guessRequested(row, col)
      }
    }
  }
}
