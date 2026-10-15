import QtQuick
import qs.Commons
import qs.Ui

// The element a drag inside the dock holds, picked up off the row. While
// held a copy of it follows the pointer, whole and opaque; the drop gap
// opens as wide as the element (DropGap) and its slot (RowSlot.liftKey)
// gives up as much room as the gaps take, so the dock keeps its width. On the drop the row takes its final shape at once (`snapping`)
// and the copy settles into the element's new place, or fades where the
// element goes into a group or off the dock. Lives in the card, so its
// coordinates are the drag's (DockPressDrag.mapTarget).
//
// Dropped into a group, the copy flies into the group's tile, shrinking to
// a member's size, and the tile takes it with a small pulse. An app dragged
// out of an opened group has no element in the row: the copy is its icon
// (beginIcon), drawn here and again over the popup's surface (popupCopy).
// It also hands slots over (handOff/handOn): an element that takes the
// place of others (a group made of an app, the apps of a dissolved group)
// starts as wide as the room they leave, so the dock eases from one width
// to the other in one move.
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
  // The slot the copy flies into (a group), shrinking as it goes.
  property string _intoKey: ""
  // Emitted when the copy has gone into the slot keyed `key` (RowSlot pulses).
  signal absorbed(string key)
  // The icon copy of an app dragged out of an opened group: its icon and
  // the group's slot, where a drop that goes nowhere returns it.
  property string iconSource: ""
  readonly property bool iconCopy: lift.phase !== "" && !lift.source && lift.iconSource !== ""

  // The room the open drop gaps take (DropGap reports its own), and what it
  // was when the drop came.
  property real gapSum: 0
  property real heldGapSum: 0
  property var _gaps: []
  function noteGap(g, w) {
    var list = lift._gaps
    var found = false
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].g !== g) continue
      found = true
      if (w > 0) list[i].w = w
      else list.splice(i, 1)
    }
    if (!found && w > 0) list.push({ g: g, w: w })
    var sum = 0
    for (var j = 0; j < list.length; j++) sum += list[j].w
    lift.gapSum = sum
  }

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
  // The icon's centre in the element's box, where the copy shrinks to.
  property real _iconX: 0
  property real _iconY: 0

  // The icon's vertical centre in a row element (DockItem, DockAppGroupItem):
  // its art sits iconArtBottom above the element's bottom.
  function _iconCenterY(el) {
    return lift.root ? el.height - lift.root.iconArtBottom - lift.root.baseIconArt / 2 : el.height / 2
  }

  function begin(slotKey, item) {
    if (!item) return
    settleMotion.stop()
    lift._finish()
    lift.source = item
    lift.iconSource = ""
    lift.sourceKey = slotKey
    lift.liftWidth = item.width - (item.gapWidth !== undefined ? item.gapWidth : (item.dropGap || 0))
    lift._w = item.width
    lift._h = item.height
    lift._iconX = item.iconCenterX !== undefined ? item.iconCenterX : item.width / 2
    lift._iconY = lift._iconCenterY(item)
    lift._haveOffset = false
    lift.phase = "held"
    lift.key = slotKey
  }

  // An app dragged out of an opened group: no element of the row is held,
  // the copy is the app's icon as the dock draws it, with the pointer at
  // (grabX, grabY) from the icon's centre. Its gap opens one icon wide.
  function beginIcon(slotKey, src, grabX, grabY) {
    if (!lift.root) return
    settleMotion.stop()
    lift._finish()
    lift.source = null
    lift.iconSource = src
    lift.sourceKey = slotKey
    lift._w = lift.root.iconSlot
    lift._h = lift.root.iconSlot
    lift.liftWidth = lift._w
    lift._iconX = lift._w / 2
    lift._iconY = lift._iconCenterY(lift)
    lift._offX = lift._iconX + grabX
    lift._offY = lift._iconY + grabY
    lift._haveOffset = true
    lift.phase = "held"
    lift.key = slotKey
  }

  function move(mx, my) {
    if (lift.phase !== "held" || (!lift.source && !lift.iconCopy)) return
    if (!lift._haveOffset) {
      var p = lift.source.mapToItem(lift.parent, 0, 0)
      lift._offX = mx - p.x
      lift._offY = my - p.y
      lift._haveOffset = true
    }
    lift._x = mx - lift._offX
    // An icon copy is drawn over the popup's surface too: no clamp.
    lift._y = lift.iconCopy ? my - lift._offY : Math.max(lift.windowTop, my - lift._offY)
  }

  // Before the drop changes the row: what follows lands without easing.
  function drop() {
    if (lift.phase !== "held") return
    lift.heldGapSum = lift.gapSum
    lift.snapping = true
    dwellTimer.stop()
    lift.dwellKey = ""
  }

  // After it: the copy lands in the slot keyed `toKey`, flies into it
  // (`into`, a group) or fades ("" or fade). The held slot unfolds at once.
  function settle(toKey, fade, into) {
    if (lift.phase !== "held") return
    lift.key = ""
    lift.snapping = false
    lift._fade = !!fade || toKey === "" || (!!into && !(lift.findSlot && lift.findSlot(toKey)))
    lift._intoKey = (!lift._fade && into) ? toKey : ""
    lift.landKey = (lift._fade || into) ? "" : toKey
    lift._fromX = lift._x
    lift._fromY = lift._y
    lift.phase = "settle"
    var ms = lift.motion ? (lift._intoKey !== "" || toKey === lift.sourceKey ? lift.motion.base : lift.motion.fast) : 0
    if (ms <= 0) { lift._finish(); return }
    settleMotion.duration = ms
    lift._t = 0
    settleMotion.start()
  }

  function _finish() {
    dwellTimer.stop()
    lift.dwellKey = ""
    var into = lift.phase === "settle" ? lift._intoKey : ""
    lift.phase = ""
    lift.key = ""
    lift.landKey = ""
    lift._intoKey = ""
    lift.snapping = false
    lift._fade = false
    lift._t = 0
    lift.source = null
    lift.iconSource = ""
    if (into !== "") lift.absorbed(into)
  }

  // Each step aims at where the slot stands now: the row lays itself out
  // after the drop, a frame later. Flying into a group, the copy's icon
  // heads for the group's icon.
  on_TChanged: {
    if (lift.phase !== "settle" || lift._fade || !lift.findSlot) return
    var into = lift._intoKey !== ""
    var slot = lift.findSlot(into ? lift._intoKey : lift.landKey)
    var el = slot ? slot.child : null
    if (!el) return
    var p = into
      ? el.mapToItem(lift.parent, el.iconCenterX - lift._iconX, lift._iconCenterY(el) - lift._iconY)
      : el.mapToItem(lift.parent, 0, 0)
    lift._x = lift._fromX + (p.x - lift._fromX) * lift._t
    lift._y = lift._fromY + (p.y - lift._fromY) * lift._t
  }

  NumberAnimation {
    id: settleMotion
    target: lift
    property: "_t"
    from: 0
    to: 1
    easing.type: lift._intoKey !== "" ? Easing.InOutCubic : Easing.OutCubic
    onFinished: lift._finish()
  }

  // Slot hand-over. handOff names the slots about to leave, before the
  // change (room: what is handed besides, an open drop gap); each one
  // leaving adds the room it had (RowSlot); handOn names the slots that
  // arrive in their place, after it. Each of those starts at an equal share
  // of that room, the row spacing it brings taken off. A single one swaps in
  // whole (no fade or scale). Hand-overs nest (an app dragged out of a group
  // that dissolves): handOn closes the latest open one.
  property var _open: []
  property var handTo: ({})
  function handOff(fromKeys, room) {
    var from = {}
    for (var i = 0; i < fromKeys.length; i++) from[fromKeys[i]] = true
    lift._open.push({ from: from, room: room || 0 })
    handClear.stop()
  }
  function _batchOf(key) {
    var all = lift._open.slice()
    for (var k in lift.handTo) if (all.indexOf(lift.handTo[k].batch) < 0) all.push(lift.handTo[k].batch)
    for (var i = all.length - 1; i >= 0; i--) if (all[i].from[key]) return all[i]
    return null
  }
  function handsOff(key) { return !!lift._batchOf(key) }
  function noteHanded(key, w) {
    var b = lift._batchOf(key)
    if (!b) return
    b.room += w
    // Readers follow handTo.
    lift.handTo = Object.assign({}, lift.handTo)
  }
  function handOn(toKeys) {
    var b = lift._open.pop()
    if (!b) return
    var m = Object.assign({}, lift.handTo)
    for (var i = 0; i < toKeys.length; i++) m[toKeys[i]] = { n: toKeys.length, batch: b }
    lift.handTo = m
    handClear.restart()
  }
  // A slot that has read its hand-over (RowSlot, the turn after it was made).
  function handTaken(key) {
    if (!lift.handTo[key]) return
    var m = Object.assign({}, lift.handTo)
    delete m[key]
    lift.handTo = m
  }
  function handBase(key) {
    var h = lift.handTo[key]
    if (!h || !lift.root) return 0
    return Math.max(0, h.batch.room / h.n - lift.root.gapWidth)
  }
  // New slots take their hand-over in the turn after they are made; this
  // only clears what no slot came for.
  Timer {
    id: handClear
    interval: 2000
    onTriggered: { lift._open = []; lift.handTo = ({}) }
  }

  // A drag aimed at a group or another app ("group:<id>", "app:<id>", ""
  // for none) becomes its target only once held there a moment: the halo
  // shows then, and only then does a drop go into the group.
  property string dwellKey: ""
  readonly property int dwellMs: 500
  function dwell(key) {
    if (key === lift.dwellKey) return
    lift.dwellKey = key
    dwellTimer.stop()
    if (lift.root) {
      lift.root.dropTargetAppId = ""
      lift.root.dropTargetGroupId = ""
    }
    if (key !== "") dwellTimer.restart()
  }
  Timer {
    id: dwellTimer
    interval: lift.dwellMs
    onTriggered: {
      if (!lift.root || lift.phase !== "held" || lift.snapping) return
      var k = lift.dwellKey
      if (k.indexOf("group:") === 0) lift.root.dropTargetGroupId = k.slice(6)
      else if (k.indexOf("app:") === 0) lift.root.dropTargetAppId = k.slice(4)
    }
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

  // What a copy shows: whole and opaque while held (dimmed while letting go
  // would take the element away), fading where it fades, and flying into a
  // group shrinking to a member's size around its icon, gone at the end.
  readonly property real copyOpacity: lift._fade ? 1 - lift._t
    : lift._intoKey !== "" ? Math.min(1, (1 - lift._t) / 0.35)
    : ((lift.root && lift.root.dragRemoveArmed) ? 0.4 : 1)
  readonly property real copyScale: lift._fade ? 1 - 0.3 * lift._t
    : lift._intoKey !== "" ? 1 - 0.65 * lift._t : 1
  property real _shownOpacity: lift.copyOpacity
  Behavior on _shownOpacity {
    enabled: lift.phase === "held"
    NumberAnimation { duration: lift.motion ? lift.motion.fast : 0 }
  }

  Item {
    id: carrier
    visible: lift.phase !== "" && (!!lift.source || lift.iconCopy)
    x: Math.round(lift._x - lift.pad)
    y: Math.round(lift._y - lift.pad)
    width: lift._w + lift.pad * 2
    height: lift._h + lift.pad * 2
    opacity: lift._shownOpacity
    transform: Scale {
      origin.x: lift.pad + lift._iconX
      origin.y: lift.pad + lift._iconY
      xScale: lift.copyScale
      yScale: lift.copyScale
    }

    ShaderEffectSource {
      anchors.fill: parent
      visible: !!lift.source
      sourceItem: lift.phase !== "" ? lift.source : null
      hideSource: true
      // Frozen once dropped: the element may leave the row under it.
      live: lift.phase === "held"
      sourceRect: Qt.rect(-lift.pad, -lift.pad, lift._w + lift.pad * 2, lift._h + lift.pad * 2)
      smooth: false
    }

    Loader {
      active: lift.iconCopy
      x: lift.pad + lift._iconX - width / 2
      y: lift.pad + lift._iconY - height / 2
      width: lift.root ? lift.root.baseIconArt : 0
      height: width
      sourceComponent: Component { LiftIcon { dockRoot: lift.root; source: lift.iconSource } }
    }
  }
}
