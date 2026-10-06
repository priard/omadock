import QtQuick
import qs.Commons
import qs.Ui

// The name label on a dock tile (apps, app groups, folders). Rendering
// policy — visibility, size, contrast, band height — lives in
// DockLabelLogic; the tile passes the name it already shows in its tooltip.
// Purely visual: no input handling, so hover, drag and clicks pass through,
// and its x/y placement never changes the tile's layout size.
Item {
  id: label

  property var rootRef: null
  readonly property var root: rootRef
  property string name: ""
  property string kind: "app"
  property Item tile: parent

  readonly property var style: root ? root.labelStyle(label.kind) : null
  readonly property real gap: Style.space(2)
  visible: false // rebuilt beside the icon in the next commits

  width: tile ? tile.width + Style.space(10) : 0
  height: 0

  Rectangle {
    visible: false
    anchors.fill: parent
    radius: height / 2
    color: Util.alpha(Color.bar.background, 0.85)
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    text: label.name
    textFormat: Text.PlainText
    color: label.style ? label.style.ink : Color.bar.text
    font.family: Style.font.family
    font.pixelSize: label.style ? label.style.fontPx : Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    maximumLineCount: 1
  }
}
