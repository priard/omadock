import QtQuick
import qs.Commons

// One running/open indicator under a dock item. Every item (apps, groups,
// folder stacks, drives) draws its marks through this, so they share sizes,
// colours and shape:
//
//   window     a window that is open: a solid dot
//   active     the focused window, or an open stack: an accent bar
//   minimized  a parked window: a hollow dot
//
// Shape follows the dock's indicatorShape (see Dock.indicatorSquare): round
// dots and pills, or square dots and bars.
Rectangle {
  id: mark

  property var rootRef: null
  readonly property var root: rootRef

  property string kind: "window"
  property bool urgent: false
  // Smaller marks when many sit side by side.
  property bool dense: false
  // 0..1 breathing for urgent marks, driven by the item.
  property real pulse: 1.0

  readonly property real dotSize: Style.space(dense ? 4 : 5)
  readonly property color ink: urgent
    ? Color.urgent
    : Util.alpha(root ? root.dockForeground : Color.bar.text, 0.88)

  width: kind === "active" ? Style.space(dense ? 9 : 12) : dotSize
  height: dotSize
  radius: (root && root.indicatorSquare) ? 0 : height / 2

  color: kind === "active" ? Color.accent : (kind === "minimized" ? "transparent" : mark.ink)
  border.color: kind === "minimized" ? mark.ink : Qt.rgba(0, 0, 0, 0.45)
  border.width: kind === "minimized" ? 1.5 : 1

  opacity: urgent ? (0.4 + 0.6 * pulse) : 1.0

  Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on border.color { ColorAnimation { duration: 120 } }
}
