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

  default property alias content: holder.data
  readonly property Item child: holder.children.length > 0 ? holder.children[0] : null

  // Set by hand, not bound: a delegate's required roles (fresh, leaving)
  // arrive after its bindings and onCompleted first ran.
  property real appear: 1
  property bool _snap: false
  Behavior on appear {
    enabled: !slot._snap && !!slot.motion && slot.motion.base > 0
    NumberAnimation {
      duration: slot.motion ? slot.motion.base : 0
      easing.type: slot.wanted ? Easing.OutCubic : Easing.InCubic
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
      if (!slot.fresh) slot._start(slot.wanted ? 1 : 0)
      else slot.appear = slot.wanted ? 1 : 0
    })
  }
  onWantedChanged: if (slot._settled) slot.appear = slot.wanted ? 1 : 0

  readonly property real full: slot.child ? slot.child.width : 0
  width: (slot.motion && slot.motion.layout) ? slot.full * slot.appear : (slot.appear > 0.001 ? slot.full : 0)
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
    opacity: slot.appear
    scale: (slot.motion && slot.motion.scale) ? 0.6 + 0.4 * slot.appear : 1
    transformOrigin: Item.Bottom
  }
}
