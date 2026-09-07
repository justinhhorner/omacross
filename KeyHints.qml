import QtQuick
import qs.Commons

// The key legend that sits at the bottom of every screen.
//
// Keys are bold so they read out of the line at a glance. That is the reason
// this is a Grid of items rather than one padded string: bolding part of a
// string needs rich text, and the columns only stay aligned across rows
// because a Grid sizes each column to its own widest item.
Grid {
  id: root

  // Flat and alternating: key, label, key, label, ...
  property var hints: []
  property color color: Color.muted
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.caption

  columns: 4
  columnSpacing: Style.space(7)
  rowSpacing: Style.space(2)

  Repeater {
    model: root.hints

    Text {
      required property var modelData
      required property int index

      readonly property bool isKey: index % 2 === 0
      readonly property bool endsRow: (index % root.columns) === root.columns - 1

      text: modelData
      color: root.color
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: isKey
      // Sets a pair apart from the next one. Skipped at the end of a row, where
      // it would only pad the legend out and shift it off center.
      rightPadding: !isKey && !endsRow ? Style.space(17) : 0
    }
  }
}
