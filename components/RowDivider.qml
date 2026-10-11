import QtQuick
import qs.Commons

// A divider slot in the dock's row (pinned | tiles | running | folders |
// drives). With split sections the slot is the gap between two panels and
// draws no line. It narrows to nothing and fades its line when its section
// goes (DockMotion), and stays in the row while it has width, so a split
// panel narrows with it instead of vanishing in one frame.
Item {
  id: divider

  property var rootRef: null
  readonly property var root: rootRef
  // The card (the long divider's top and length) and the y of the row this
  // divider sits in, in the card's coordinates.
  property var cardRef: null
  property real rowY: 0
  property bool shown: false
  property bool lineHidden: false
  readonly property var motion: root ? root.motion : null

  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  // Set in onShownChanged, after shown, so the easing the animation picks
  // up is the new direction's (a bound width started before it changed).
  readonly property real full: root ? root.separatorWidth : Style.space(1)
  property bool _going: !divider.shown
  width: divider.shown ? divider.full : 0
  onShownChanged: divider._going = !divider.shown
  Behavior on width {
    enabled: !!divider.motion && divider.motion.layout
    NumberAnimation {
      duration: divider.motion ? divider.motion.base : 0
      easing.type: divider._going ? Easing.InCubic : Easing.OutCubic
    }
  }
  height: root ? (root.iconSize * 0.7) : 24
  visible: width > 0.5

  // The line, placed by the card (70% of its height by default, as on
  // macOS). It overflows the slot, so it does not grow the row.
  Rectangle {
    visible: !divider.lineHidden
    anchors.horizontalCenter: parent.horizontalCenter
    y: divider.root && divider.root.dividerGeometry === "long" && divider.cardRef
      ? divider.cardRef.dividerTop - divider.rowY - divider.y : (divider.root ? divider.root.iconCenterOffset : 0)
    width: divider.cardRef ? divider.cardRef.dividerWidth : 1
    height: divider.root && divider.root.dividerGeometry === "long" && divider.cardRef ? divider.cardRef.dividerLength : divider.height
    color: divider.root ? divider.root.dividerLineColor : Util.alpha(Color.bar.text, 0.25)
    opacity: divider.shown ? 1 : 0
    Behavior on opacity {
      enabled: !!divider.motion && divider.motion.fade
      NumberAnimation { duration: divider.motion ? divider.motion.fast : 0 }
    }
  }
}
