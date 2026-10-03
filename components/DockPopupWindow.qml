import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// A menu above the dock card in its own popup surface, so the dock layer
// only needs to be as tall as the card. Positioned in onAnchoring (the
// pattern of Omarchy's Ui/PopupCard.qml): the anchor point sits on the line
// Style.space(6) above the card and the popup grows upward from it, centred
// on centerX (clamped so it stays on screen). Anchoring the bottom keeps a
// popup whose content grows or shrinks (a folder being listed, another
// folder opened) from flashing over the dock while the compositor catches
// up. No compositor adjustment: toDockWindow() relies on that placement.
PopupWindow {
  id: popup

  property var dockRoot: null
  property bool open: false
  property real centerX: 0
  property Item body: null

  signal dismissed()

  readonly property var dockWindow: dockRoot ? dockRoot.dockWindowRef : null
  readonly property real gap: Style.space(6)

  color: "transparent"
  // Not gated on the body's size: menus measure their visible rows, and
  // nothing inside a hidden window is visible, so the size would stay 0.
  visible: open && body !== null
  implicitWidth: Math.max(1, body ? Math.ceil(body.width) : 1)
  implicitHeight: Math.max(1, body ? Math.ceil(body.height) : 1)

  anchor.window: dockWindow
  anchor.rect.width: 1
  anchor.rect.height: 1
  anchor.edges: Edges.Top
  anchor.gravity: Edges.Top
  anchor.adjustment: PopupAdjustment.None
  anchor.onAnchoring: {
    if (!popup.dockWindow || !popup.dockRoot || !popup.dockRoot.dockCard) return
    var win = popup.dockWindow.contentItem
    var cardTop = win.mapFromItem(popup.dockRoot.dockCard, 0, 0).y
    var half = popup.implicitWidth / 2
    var cx = Math.max(Style.gapsOut + half, Math.min(win.width - Style.gapsOut - half, popup.centerX))
    popup.anchor.rect.x = Math.round(cx)
    popup.anchor.rect.y = Math.round(cardTop - popup.gap)
  }

  // Height changes need no re-anchoring (the bottom is the anchor); a width
  // change can move the clamp, a new centerX the popup.
  onImplicitWidthChanged: if (popup.visible) popup.anchor.updateAnchor()
  onCenterXChanged: if (popup.visible) popup.anchor.updateAnchor()

  // A point in an item hosted by this popup, in dock-window coordinates: the
  // popup is centred on anchor.rect.x and ends at anchor.rect.y.
  function toDockWindow(item, x, y) {
    var p = item.mapToItem(popup.contentItem, x, y)
    return Qt.point(popup.anchor.rect.x - Math.round(popup.implicitWidth / 2) + p.x,
                    popup.anchor.rect.y - popup.implicitHeight + p.y)
  }

  // A click outside the popup and the dock closes it, as the full-surface
  // dismiss area used to.
  HyprlandFocusGrab {
    active: popup.visible
    windows: popup.dockWindow ? [popup, popup.dockWindow] : [popup]
    onCleared: popup.dismissed()
  }
}
