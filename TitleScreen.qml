import QtQuick
import qs.Commons
import "Logo.js" as Logo
import "Game.js" as Game

// The Omarchy mark, assembled out of static.
//
// Every cell starts as noise and settles on its real value at its own moment,
// ordered outward from the center — so the square resolves the way a picross
// grid does under a player's hands, rather than simply fading in.
Item {
  id: root

  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property string difficultyId: "easy"
  property string notice: ""
  property var library: null

  signal difficultyPicked(string id)
  signal startRequested()

  readonly property var cells: Logo.logoFlat()
  readonly property int size: Logo.LOGO_SIZE
  readonly property int cellSize: Style.space(11)
  readonly property int cellGap: Math.max(1, Style.space(1))

  property real progress: 0
  property int tick: 0
  readonly property bool settled: progress >= 1

  // Measured from the pieces rather than from the Column: children centered
  // with a horizontal anchor do not contribute to a positioner's implicit
  // width, and the hint line is wider than the logo that sets the rest.
  implicitWidth: Math.max(logoGrid.implicitWidth, hint.implicitWidth, Style.space(260))
  implicitHeight: column.implicitHeight

  function replay() {
    progress = 0
    tick = 0
    reveal.restart()
  }

  NumberAnimation {
    id: reveal
    target: root
    property: "progress"
    from: 0
    to: 1
    duration: 1500
    easing.type: Easing.InOutQuad
    running: true
  }

  // Drives the static. Stops once everything has settled so an idle title
  // screen is not repainting a 169-cell grid forever.
  Timer {
    interval: 70
    repeat: true
    running: !root.settled
    onTriggered: root.tick++
  }

  Column {
    id: column
    // Explicit, so the centered children below anchor to a width that does not
    // depend on them.
    width: root.width
    spacing: Style.space(16)

    Grid {
      id: logoGrid
      anchors.horizontalCenter: parent.horizontalCenter
      columns: root.size
      spacing: root.cellGap

      Repeater {
        model: root.size * root.size

        Rectangle {
          id: logoCell
          required property int index

          readonly property bool lit: Logo.titleCellAt(index, root.size, root.progress, root.tick, root.cells)
          readonly property bool resolved: root.progress >= Logo.settleThreshold(index, root.size)

          width: root.cellSize
          height: root.cellSize
          radius: Math.max(1, Style.space(1))
          color: !lit
            ? Util.alpha(root.foreground, 0.05)
            : (resolved ? root.foreground : Util.alpha(root.muted, 0.45))

          // Only the settling step is worth easing. Animating the static as
          // well would smear it into a grey wash.
          Behavior on color {
            enabled: logoCell.resolved
            ColorAnimation { duration: 180 }
          }
        }
      }
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "OMACROSS"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.letterSpacing: Style.space(4)
        font.bold: true
        opacity: root.progress
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "picross for omarchy"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: Style.space(1)
        opacity: root.progress
      }
    }

    Column {
      id: choices
      width: Math.min(column.width, Style.space(280))
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(3)
      opacity: root.progress

      Repeater {
        model: Game.DIFFICULTIES

        Rectangle {
          id: choice
          required property var modelData
          required property int index

          readonly property bool current: modelData.id === root.difficultyId
          readonly property int available: root.library ? (root.library.counts[modelData.size] || 0) : 0

          width: choices.width
          height: Style.space(30)
          radius: Style.cornerRadius
          color: choice.current ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
          border.width: choice.current ? Style.selectedBorderWidth : 0
          border.color: Style.selectedBorderFor(root.foreground, root.accent)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: choice.modelData.label.toUpperCase()
            color: choice.current ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: choice.current
            font.letterSpacing: Style.space(1)
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: choice.modelData.size + "×" + choice.modelData.size + "   "
              + Game.formatClock(choice.modelData.seconds * 1000) + "   "
              + choice.available + (choice.available === 1 ? " pic" : " pics")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: {
              root.difficultyPicked(choice.modelData.id)
              root.startRequested()
            }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.notice !== ""
      text: root.notice
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    KeyHints {
      id: hint
      anchors.horizontalCenter: parent.horizontalCenter
      columns: 4
      color: Util.alpha(root.muted, 0.85)
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      opacity: root.progress
      // Enter is the way to start from here. Ctrl+N still works — it is the
      // shortcut that reaches a new game from mid-play — but on the title
      // screen it does exactly what Enter does, and listing both invited the
      // reader to look for the difference between "play" and "new game".
      hints: ["enter", "new game", "j k", "difficulty"]
    }
  }
}
