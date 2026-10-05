import QtQuick
import qs.Commons
import qs.Ui

// The notification-count badge over an icon: the one mark behind the app,
// folder and folder-cell badges. It sits on a corner of anchorRef and takes
// its style, corner and colour from the dock's badge settings.
Rectangle {
  id: badge

  property var rootRef: null
  readonly property var root: rootRef
  // The icon (or icon box) the badge sits on.
  property Item anchorRef: null
  property int count: 0
  // Rim colour of the surface the badge floats over (dock card, menu).
  property color rim: Color.bar.background

  readonly property string badgeStyle: root ? root.badgeStyle : "count"
  readonly property bool onRight: (root ? root.badgePosition : "top-right").indexOf("left") < 0
  readonly property bool atBottom: (root ? root.badgePosition : "top-right").indexOf("bottom") === 0

  visible: badge.count > 0 && badge.anchorRef !== null
  width: badge.badgeStyle === "dot" ? badge.height : Math.max(Style.space(17), badgeText.implicitWidth + Style.space(8))
  height: badge.badgeStyle === "dot" ? Style.space(10) : Style.space(17)
  radius: height / 2
  color: root ? root.badgeFill : Color.accent
  border.width: 1
  border.color: badge.rim
  z: 2

  // Placed by x/y, not by switching anchors: when the corner changes, the
  // left/right (or top/bottom) anchor bindings update one at a time, the
  // badge is briefly anchored on both sides and stretched over the icon,
  // and it keeps that size once the other anchor is released.
  // anchorRef is the badge's parent or a sibling, as anchors required.
  readonly property real refX: (!badge.anchorRef || badge.anchorRef === badge.parent) ? 0 : badge.anchorRef.x
  readonly property real refY: (!badge.anchorRef || badge.anchorRef === badge.parent) ? 0 : badge.anchorRef.y
  readonly property real overhang: Style.space(3)
  x: !badge.anchorRef ? 0
    : badge.onRight ? badge.refX + badge.anchorRef.width + badge.overhang - badge.width
    : badge.refX - badge.overhang
  y: !badge.anchorRef ? 0
    : badge.atBottom ? badge.refY + badge.anchorRef.height + badge.overhang - badge.height
    : badge.refY - badge.overhang

  Text {
    id: badgeText
    visible: badge.badgeStyle !== "dot"
    anchors.centerIn: parent
    text: badge.count > 99 ? "99+" : String(badge.count)
    textFormat: Text.PlainText
    color: root ? root.badgeInk : "#f2efec"
    font.family: Style.font.family
    font.pixelSize: Style.space(10)
    font.bold: true
  }
}
