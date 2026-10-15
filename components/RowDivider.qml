import QtQuick 6.11
import qs.Commons

// A divider slot in the dock's row (pinned | tiles | running | folders |
// drives). With split sections the slot is the gap between two panels and
// draws no line. It narrows to nothing and fades its line when its section
// goes (DockMotion), and stays in the row while it has width, so a split
// panel narrows with it instead of vanishing in one frame. A hidden divider
// (separatorWidth below zero) never has width: it leaves the row.
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
  // Width set by hand, after shown: the easing then matches the direction
  // (a bound width started before the easing changed), and changes in the
  // first moments, while the dock starts and its data arrives, land at once.
  readonly property real full: root ? root.separatorWidth : Style.space(1)
  readonly property real _bornAt: Date.now()
  property bool _going: !divider.shown
  property bool _snap: false
  property real _w: 0
  width: divider._w
  function _set() {
    divider._going = !divider.shown
    divider._snap = Date.now() - divider._bornAt < 1500
    divider._w = divider.shown ? divider.full : 0
    divider._snap = false
  }
  Component.onCompleted: divider._set()
  onShownChanged: divider._set()
  onFullChanged: divider._set()
  Behavior on _w {
    enabled: !divider._snap && !!divider.motion && divider.motion.layout
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
    // "Hidden" dividers keep the gap between sections and draw no line.
    visible: !divider.lineHidden && !!divider.root && divider.root.dividerStyle !== "none"
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
