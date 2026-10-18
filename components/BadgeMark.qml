import QtQuick 6.11
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
  property string glyph: ""
  property color badgeColor: "transparent"
  // Rim colour of the surface the badge floats over (dock card, menu).
  property color rim: Color.bar.background

  readonly property string badgeStyle: root ? root.badgeStyle : "count"
  readonly property bool onRight: (root ? root.badgePosition : "top-right").indexOf("left") < 0
  readonly property bool atBottom: (root ? root.badgePosition : "top-right").indexOf("bottom") === 0

  // It grows and fades in and out (DockMotion) and keeps showing the last
  // count while it fades.
  readonly property var motion: root ? root.motion : null
  property int shownCount: 0
  property string shownGlyph: ""
  onCountChanged: {
    if (badge.count > 0) {
      badge.shownCount = badge.count
      if (badge.glyph === "") badge.shownGlyph = ""
    }
  }
  onGlyphChanged: {
    if (badge.glyph !== "") {
      badge.shownGlyph = badge.glyph
    } else if (badge.count > 0) {
      badge.shownGlyph = ""
    }
  }
  Component.onCompleted: {
    if (badge.count > 0) badge.shownCount = badge.count
    if (badge.glyph !== "") badge.shownGlyph = badge.glyph
  }
  readonly property bool hasContent: badge.count > 0 || badge.glyph !== ""
  property real level: badge.hasContent ? 1 : 0
  onLevelChanged: {
    if (badge.level <= 0.01 && !badge.hasContent) {
      badge.shownGlyph = ""
      badge.shownCount = 0
    }
  }
  // The easing reads the Behavior's target (set before the animation
  // starts); bound to the count it could start with the old one.
  Behavior on level {
    id: levelMotion
    enabled: !!badge.motion && badge.motion.fade
    NumberAnimation {
      duration: badge.motion ? badge.motion.base : 0
      easing.type: levelMotion.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
    }
  }
  visible: badge.level > 0.01 && badge.anchorRef !== null
  opacity: badge.level
  scale: (badge.motion && badge.motion.scale) ? 0.5 + 0.5 * badge.level : 1
  width: (badge.badgeStyle === "dot" && badge.glyph === "") ? badge.height : Math.max(Style.space(17), badgeText.implicitWidth + Style.space(8))
  Behavior on width {
    enabled: !!badge.motion && badge.motion.layout
    NumberAnimation { duration: badge.motion ? badge.motion.fast : 0; easing.type: Easing.OutCubic }
  }
  height: (badge.badgeStyle === "dot" && badge.glyph === "") ? Style.space(10) : Style.space(17)
  radius: height / 2
  color: badge.badgeColor.a > 0 ? badge.badgeColor : (root ? root.badgeFill : Color.accent)
  border.width: 1
  border.color: badge.rim
  property bool isSecondary: false
  z: badge.isSecondary ? 2 : 3

  readonly property real stackShiftX: badge.isSecondary ? Style.space(9) : 0
  readonly property real stackShiftY: 0

  // Placed by x/y, not by switching anchors: when the corner changes, the
  // left/right (or top/bottom) anchor bindings update one at a time, the
  // badge is briefly anchored on both sides and stretched over the icon,
  // and it keeps that size once the other anchor is released.
  // anchorRef is the badge's parent or a sibling, as anchors required.
  readonly property real refX: (!badge.anchorRef || badge.anchorRef === badge.parent) ? 0 : badge.anchorRef.x
  readonly property real refY: (!badge.anchorRef || badge.anchorRef === badge.parent) ? 0 : badge.anchorRef.y
  readonly property real overhang: Style.space(3)
  x: !badge.anchorRef ? 0
    : badge.onRight ? badge.refX + badge.anchorRef.width + badge.overhang - badge.width - badge.stackShiftX
    : badge.refX - badge.overhang + badge.stackShiftX
  y: !badge.anchorRef ? 0
    : badge.atBottom ? badge.refY + badge.anchorRef.height + badge.overhang - badge.height - badge.stackShiftY
    : badge.refY - badge.overhang + badge.stackShiftY

  Text {
    id: badgeText
    visible: badge.badgeStyle !== "dot" || badge.glyph !== ""
    anchors.centerIn: parent
    text: badge.shownGlyph !== "" ? badge.shownGlyph : (badge.shownCount > 99 ? "99+" : String(badge.shownCount))
    textFormat: Text.PlainText
    color: badge.shownGlyph !== "" ? "#12100f" : (root ? root.badgeInk : "#f2efec")
    font.family: Style.font.family
    font.pixelSize: Style.space(10)
    font.bold: true
  }
}
