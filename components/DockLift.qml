import QtQuick
import qs.Commons

// The element a drag inside the dock holds, picked up off the row. While
// held its slot folds away (RowSlot.liftKey) and a copy of it follows the
// pointer, whole and opaque; the drop gap opens as wide as the element
// (DropGap). On the drop the row takes its final shape at once (`snapping`)
// and the copy settles into the element's new place, or fades where the
// element goes into a group or off the dock. Lives in the card, so its
// coordinates are the drag's (DockPressDrag.mapTarget).
Item {
  id: lift

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: root ? root.motion : null
  // Finds a live RowSlot by its liftKey (DockCard.slotByLiftKey).
  property var findSlot: null

  // The held slot's key ("" when nothing is held), the key it was picked up
  // from, and the element itself.
  property string key: ""
  property string sourceKey: ""
  property var source: null
  // The element's width without any drop gap of its own: what the drop gap
  // opens to.
  property real liftWidth: 0
  // "held" while the button is down, "settle" while the copy lands.
  property string phase: ""
  readonly property bool active: lift.phase === "held"
  // True for the drop itself: gaps close and slots unfold without easing.
  property bool snapping: false
  // The slot the copy lands in; its element stays hidden until it has.
  property string landKey: ""
  property bool _fade: false

  // Room around the element for what spills past its box (badges, a lifted
  // icon).
  readonly property real pad: Style.space(10)
  property real _offX: 0
  property real _offY: 0
  property bool _haveOffset: false
  property real _x: 0
  property real _y: 0
  property real _fromX: 0
  property real _fromY: 0
  property real _w: 0
  property real _h: 0
  property real _t: 0

  function begin(slotKey, item) {
    if (!item) return
    settleMotion.stop()
    lift._finish()
    lift.source = item
    lift.sourceKey = slotKey
    lift.liftWidth = item.width - (item.gapWidth !== undefined ? item.gapWidth : (item.dropGap || 0))
    lift._w = item.width
    lift._h = item.height
    lift._haveOffset = false
    lift.phase = "held"
    lift.key = slotKey
  }

  function move(mx, my) {
    if (lift.phase !== "held" || !lift.source) return
    if (!lift._haveOffset) {
      var p = lift.source.mapToItem(lift.parent, 0, 0)
      lift._offX = mx - p.x
      lift._offY = my - p.y
      lift._haveOffset = true
    }
    lift._x = mx - lift._offX
    lift._y = Math.max(lift.windowTop, my - lift._offY)
  }

  // Before the drop changes the row: what follows lands without easing.
  function drop() {
    if (lift.phase === "held") lift.snapping = true
  }

  // After it: the copy lands in the slot keyed `toKey`, or fades ("" or
  // fade). The held slot unfolds at once.
  function settle(toKey, fade) {
    if (lift.phase !== "held") return
    lift.key = ""
    lift.snapping = false
    lift._fade = !!fade || toKey === ""
    lift.landKey = lift._fade ? "" : toKey
    lift._fromX = lift._x
    lift._fromY = lift._y
    lift.phase = "settle"
    var ms = lift.motion ? (lift._fade || toKey !== lift.sourceKey ? lift.motion.fast : lift.motion.base) : 0
    if (ms <= 0) { lift._finish(); return }
    settleMotion.duration = ms
    lift._t = 0
    settleMotion.start()
  }

  function _finish() {
    lift.phase = ""
    lift.key = ""
    lift.landKey = ""
    lift.snapping = false
    lift._fade = false
    lift._t = 0
    lift.source = null
  }

  // Each step aims at where the slot stands now: the row lays itself out
  // after the drop, a frame later.
  on_TChanged: {
    if (lift.phase !== "settle" || lift._fade || !lift.findSlot) return
    var slot = lift.findSlot(lift.landKey)
    var el = slot ? slot.child : null
    if (!el) return
    var p = el.mapToItem(lift.parent, 0, 0)
    lift._x = lift._fromX + (p.x - lift._fromX) * lift._t
    lift._y = lift._fromY + (p.y - lift._fromY) * lift._t
  }

  NumberAnimation {
    id: settleMotion
    target: lift
    property: "_t"
    from: 0
    to: 1
    easing.type: Easing.OutCubic
    onFinished: lift._finish()
  }

  // A drag that ends without a drop (released outside the card) goes home.
  Connections {
    target: lift.root
    function onDockDragActiveChanged() {
      if (lift.root && !lift.root.dockDragActive && lift.phase === "held" && !lift.snapping)
        lift.settle(lift.sourceKey, false)
    }
  }

  // The layer ends a little above the card; the copy stays inside it.
  readonly property real windowTop: lift.root && lift.root.dockWindowRef && lift.parent
    ? -((lift.root.dockWindowRef.height - lift.root.edgeGap - lift.parent.height)) : -1e6

  ShaderEffectSource {
    id: copy
    visible: lift.phase !== "" && !!lift.source
    sourceItem: lift.phase !== "" ? lift.source : null
    hideSource: true
    // Frozen once dropped: the element may leave the row under it.
    live: lift.phase === "held"
    sourceRect: Qt.rect(-lift.pad, -lift.pad, lift._w + lift.pad * 2, lift._h + lift.pad * 2)
    x: Math.round(lift._x - lift.pad)
    y: Math.round(lift._y - lift.pad)
    width: lift._w + lift.pad * 2
    height: lift._h + lift.pad * 2
    smooth: false
    opacity: lift._fade ? 1 - lift._t : ((lift.root && lift.root.dragRemoveArmed) ? 0.4 : 1)
    scale: lift._fade ? 1 - 0.3 * lift._t : 1
    Behavior on opacity {
      enabled: lift.phase === "held"
      NumberAnimation { duration: lift.motion ? lift.motion.fast : 0 }
    }
  }
}
