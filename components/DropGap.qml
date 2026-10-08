import QtQuick
import qs.Commons
import "../DockLabels.js" as DockLabels

// Where a drag inside the dock will land: the room it opens there and the
// accent line in the middle of it.
// An item puts one at its leading edge and adds its width to its own,
// so the line also takes the row spacing before the item into account;
// a run puts a spacer one (spacer: true) after its last item for a drop at
// its end.
Item {
  id: gap

  property var rootRef: null
  readonly property var root: rootRef
  property bool open: false
  property bool spacer: false

  // Enough that the line reads between tiles packed close together
  // (plates one small gap apart), and a little anywhere so the dock
  // answers the drag.
  readonly property real room: {
    if (!root) return 0
    var seen = root.labelPlates ? root.plateSpacing.gap
      : root.gapWidth + (root.iconSlot - root.baseIconArt) / (root.labelMode === "always" ? 2 : 1)
    return DockLabels.gridRound(Math.max(Style.space(6), Style.space(18) - seen), root.outputScale)
  }
  width: gap.open ? gap.room : 0
  height: parent ? parent.height : 0
  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  // A spacer leaves the Row's layout while closed.
  visible: gap.spacer ? gap.width > 0.5 : gap.open

  Rectangle {
    visible: gap.open
    readonly property real spacing: gap.root ? gap.root.gapWidth : 0
    // The middle of what lies between the tiles on either side.
    x: Math.round((gap.spacer ? gap.width / 2 : (gap.width - spacing) / 2) - width / 2)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(2)
    height: gap.root ? gap.root.iconSize + Style.space(4) : 36
    radius: 1
    color: Color.accent
  }
}
