import QtQuick
import qs.Commons

// One running/open indicator under a dock item. Every item (apps, groups,
// folder stacks, drives) draws its marks through this, so they share sizes,
// colours and shape:
//
//   window     a window that is open: a solid dot
//   active     the focused window, or an open stack: an accent bar
//   minimized  a parked window: a hollow dot
//   background running with no window (e.g. a media player closed to the
//              tray that still exposes MPRIS): a faint dot
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
  // Stacked in a column (side indicators on a label plate): the accent bar
  // stands upright.
  property bool vertical: false
  // Ink for marks standing on a label plate (transparent: the dock's own).
  property color inkOverride: "transparent"
  // 0..1 breathing for urgent marks, driven by the item.
  property real pulse: 1.0
  // Anything that moves the mark without changing its own x or y (a plate
  // lifting it on hover, say): the owner binds it so the mark re-snaps.
  property real moveKey: 0
  onMoveKeyChanged: Qt.callLater(mark.resnap)

  // Marks are unsmoothed rectangles, so at a fractional scale (1.5) they lost
  // or gained a row of pixels depending on where they landed, and anything
  // that shifted the dock by a fraction of a pixel (the border width, say)
  // made them look bigger or smaller. Sizes are whole device pixels at the
  // classic dimensions (5px dots, 4px tall bars), and the mark nudges
  // itself onto the pixel grid (snapX, snapY).
  // The output's pixel grid (see Dock.outputScale), not Qt's render ratio.
  readonly property real dpr: root ? root.outputScale : 1
  onDprChanged: Qt.callLater(mark.resnap)
  function snap(v) { return Math.max(1, Math.round(v * mark.dpr)) / mark.dpr }
  readonly property real hairline: Math.max(1, Math.floor(mark.dpr)) / mark.dpr
  // The dock's classic mark dimensions: 5px dots (4px dense) and a 12x4
  // accent bar (9x4 dense). A fix for fractional-scale borders once thinned
  // every mark a pixel with it; the sizes here are the look the dock ships.
  // A side column on a plate uses the dense dot: beside a name the full
  // dot read heavy.
  readonly property real dotSize: Math.max(2 / mark.dpr, mark.snap(Style.space((dense || vertical) ? 4 : 5)))
  readonly property real barHeight: Math.max(2 / mark.dpr, mark.snap(Style.space(4)))

  property real snapX: 0
  property real snapY: 0
  transform: Translate { x: mark.snapX; y: mark.snapY }

  function resnap() {
    var p = mark.mapToItem(null, 0, 0)
    if (!p) return
    var px = (p.x - mark.snapX) * mark.dpr
    var py = (p.y - mark.snapY) * mark.dpr
    mark.snapX = (Math.round(px) - px) / mark.dpr
    mark.snapY = (Math.round(py) - py) / mark.dpr
  }

  // The scene position is not bindable; re-snap when something that can move
  // the dock by a fraction of a pixel changes. The show/hide slide settles
  // after its animation, hence the delay.
  Component.onCompleted: Qt.callLater(mark.resnap)
  onXChanged: Qt.callLater(mark.resnap)
  onYChanged: Qt.callLater(mark.resnap)
  Timer {
    id: settleSnap
    interval: 320
    onTriggered: mark.resnap()
  }
  Connections {
    target: mark.root
    ignoreUnknownSignals: true
    function onBorderWidthChanged() { Qt.callLater(mark.resnap) }
    function onShowBorderChanged() { Qt.callLater(mark.resnap) }
    function onIconSizeChanged() { Qt.callLater(mark.resnap) }
    function onDockVisibleChanged() { settleSnap.restart() }
  }
  // The card re-centres as tiles come and go or a drop gap opens.
  Connections {
    target: mark.root ? mark.root.dockCard : null
    ignoreUnknownSignals: true
    function onXChanged() { Qt.callLater(mark.resnap) }
    function onWidthChanged() { Qt.callLater(mark.resnap) }
  }
  readonly property color ink: urgent
    ? Color.urgent
    : Util.alpha(mark.inkOverride.a > 0 ? mark.inkOverride : (root ? root.dockForeground : Color.bar.text), 0.88)

  readonly property real barLength: mark.snap(Style.space(dense ? 9 : 12))
  // Upright in a column the bar is as thick as a dot: the 1.5 output is
  // drawn at 2x and scaled down, so a thinner bar could not be centred on
  // the dots and leaned a pixel to one side.
  width: kind === "active" ? (mark.vertical ? mark.dotSize : mark.barLength) : dotSize
  height: kind === "active" ? (mark.vertical ? mark.barLength : mark.barHeight) : dotSize
  radius: (root && root.indicatorSquare) ? 0 : Math.min(width, height) / 2

  color: kind === "active" ? Color.accent
    : kind === "minimized" ? "transparent"
    : kind === "background" ? Util.alpha(mark.ink, 0.35)
    : mark.ink
  border.color: kind === "minimized" ? mark.ink
    : kind === "background" ? Qt.rgba(0, 0, 0, 0.18)
    : Qt.rgba(0, 0, 0, 0.45)
  border.width: kind === "minimized" ? mark.hairline * 1.5 : mark.hairline

  opacity: urgent ? (0.4 + 0.6 * pulse) : 1.0

  Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on border.color { ColorAnimation { duration: 120 } }
}
