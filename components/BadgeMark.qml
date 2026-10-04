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

  anchors.right: (badge.onRight && badge.anchorRef) ? badge.anchorRef.right : undefined
  anchors.left: (!badge.onRight && badge.anchorRef) ? badge.anchorRef.left : undefined
  anchors.top: (!badge.atBottom && badge.anchorRef) ? badge.anchorRef.top : undefined
  anchors.bottom: (badge.atBottom && badge.anchorRef) ? badge.anchorRef.bottom : undefined
  anchors.rightMargin: badge.onRight ? -Style.space(3) : 0
  anchors.leftMargin: badge.onRight ? 0 : -Style.space(3)
  anchors.topMargin: badge.atBottom ? 0 : -Style.space(3)
  anchors.bottomMargin: badge.atBottom ? -Style.space(3) : 0

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
