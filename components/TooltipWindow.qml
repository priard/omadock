import QtQuick
import Quickshell
import qs.Commons

// A tooltip above `target` in its own popup surface, so the dock layer does
// not need room for it. Display only: an empty mask lets the pointer through.
PopupWindow {
  id: tip

  property Item target: null
  property bool shown: false
  property Item body: null
  property real gap: Style.space(6)

  readonly property var hostWindow: target ? target.QsWindow.window : null

  color: "transparent"
  mask: Region {}
  visible: shown && hostWindow !== null && body !== null && body.width > 0 && body.height > 0
  implicitWidth: Math.max(1, body ? Math.ceil(body.width) : 1)
  implicitHeight: Math.max(1, body ? Math.ceil(body.height) : 1)

  anchor.window: hostWindow
  anchor.rect.width: 1
  anchor.rect.height: 1
  // Anchored at its bottom centre and growing upward, so content that grows
  // after the tooltip appears never covers the item (see DockPopupWindow).
  anchor.edges: Edges.Top
  anchor.gravity: Edges.Top
  anchor.adjustment: PopupAdjustment.SlideX
  anchor.onAnchoring: {
    if (!tip.hostWindow || !tip.target) return
    var win = tip.hostWindow.contentItem
    var p = win.mapFromItem(tip.target, tip.target.width / 2, 0)
    var half = tip.implicitWidth / 2
    tip.anchor.rect.x = Math.round(Math.max(Style.gapsOut + half, Math.min(win.width - Style.gapsOut - half, p.x)))
    tip.anchor.rect.y = Math.round(p.y - tip.gap)
  }
  onImplicitWidthChanged: if (tip.visible) tip.anchor.updateAnchor()
}
