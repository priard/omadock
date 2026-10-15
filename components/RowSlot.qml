import QtQuick

// One element of the dock's row as it enters and leaves (DockMotion). The
// slot is as wide as its element times `appear`, so the neighbours and the
// card ease along; the element scales up from 0.6 and fades in with it.
// Repeater rows set `fresh` and `leaving` (KeyedListModel); a single element
// (the Omarchy button) or a row that hides itself sets `shown`. Reduced
// keeps only the fade (the width snaps); Off changes at once.
Item {
  id: slot

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: root ? root.motion : null
  property bool fresh: false
  property bool leaving: false
  property bool shown: true
  readonly property bool wanted: slot.shown && !slot.leaving

  // A drag inside the dock picks the element up (DockLift): its slot folds
  // away, the row spacing after it too, so the row closes over it; on the
  // drop it unfolds at once, on a drag that ends without one it eases back
  // open as the drop gap eases shut. The slot the drop lands in shows its element
  // only once the dragged copy has settled there.
  property string liftKey: ""
  readonly property var lift: (root && root.dockCard) ? root.dockCard.liftRef : null
  readonly property bool lifted: slot.liftKey !== "" && !!slot.lift && slot.lift.key === slot.liftKey
  readonly property bool landing: slot.liftKey !== "" && !!slot.lift && slot.lift.landKey === slot.liftKey
  property real _lift: 0
  property bool _liftEases: false
  Behavior on _lift {
    enabled: slot._liftEases
    NumberAnimation { duration: slot.motion ? slot.motion.base : 0; easing.type: Easing.OutCubic }
  }
  onLiftedChanged: {
    slot._liftEases = !(slot.lift && slot.lift.snapping) && !!slot.motion && slot.motion.base > 0
    slot._lift = slot.lifted ? 1 : 0
  }
  // Dropped into another run: the held slot leaves with nothing to show.
  onLeavingChanged: if (slot.leaving && slot.lifted) slot._start(0)
  // The dock's rows all space their elements by gapWidth.
  readonly property real _spacing: root ? root.gapWidth : 0

  default property alias content: holder.data
  readonly property Item child: holder.children.length > 0 ? holder.children[0] : null

  // Set by hand, not bound: a delegate's required roles (fresh, leaving)
  // arrive after its bindings and onCompleted first ran.
  property real appear: 1
  property bool _snap: false
  // The easing reads the Behavior's target (set before the animation
  // starts); bound to `wanted` it could start with the old one.
  Behavior on appear {
    id: appearMotion
    enabled: !slot._snap && !!slot.motion && slot.motion.base > 0
    NumberAnimation {
      duration: slot.motion ? slot.motion.base : 0
      easing.type: appearMotion.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
    }
  }
  // A write past the Behavior.
  function _start(from) {
    slot._snap = true
    slot.appear = from
    slot._snap = false
  }
  // The model's roles reach a new delegate only after it completes (and
  // without a change signal), so the slot waits one turn, drawn as nothing,
  // and then knows whether it is fresh.
  property bool _settled: false
  Component.onCompleted: {
    slot._start(0)
    Qt.callLater(function() {
      slot._settled = true
      if (!slot.fresh || slot.landing) slot._start(slot.wanted ? 1 : 0)
      else slot.appear = slot.wanted ? 1 : 0
    })
  }
  // A row that hides or shows itself while the dock starts (its data still
  // arriving) does so at once.
  readonly property real _bornAt: Date.now()
  onWantedChanged: {
    if (!slot._settled) return
    if (Date.now() - slot._bornAt < 1500) slot._start(slot.wanted ? 1 : 0)
    else slot.appear = slot.wanted ? 1 : 0
  }

  readonly property real full: slot.child ? slot.child.width : 0
  readonly property real _open: (slot.motion && slot.motion.layout) ? slot.full * slot.appear : (slot.appear > 0.001 ? slot.full : 0)
  width: slot._open + (-slot._spacing - slot._open) * slot._lift
  height: slot.child ? slot.child.height : 0
  visible: slot.appear > 0.001
  // A zoomed element raises itself over its neighbours; in the Row that
  // takes the slot's z.
  z: slot.child ? slot.child.z : 0

  Item {
    id: holder
    width: slot.full
    height: slot.height
    x: Math.round((slot.width - slot.full) / 2)
    opacity: slot.landing ? 0 : slot.appear
    // A leaving element takes no clicks, hovers or drops during its exit.
    enabled: slot.wanted
    scale: (slot.motion && slot.motion.scale) ? 0.6 + 0.4 * slot.appear : 1
    transformOrigin: Item.Bottom
  }
}
