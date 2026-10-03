import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// A menu above the dock card in its own popup surface, so the dock layer
// only needs to be as tall as the card. Positioned in onAnchoring (the
// pattern of Omarchy's Ui/PopupCard.qml): centred on centerX, clamped to the
// window, its bottom Style.space(6) above the card. No compositor adjustment:
// toDockWindow() relies on the popup sitting exactly at anchor.rect.
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
  visible: open && body !== null && body.width > 0 && body.height > 0
  implicitWidth: Math.max(1, body ? Math.ceil(body.width) : 1)
  implicitHeight: Math.max(1, body ? Math.ceil(body.height) : 1)

  anchor.window: dockWindow
  anchor.rect.width: 1
  anchor.rect.height: 1
  anchor.edges: Edges.Top | Edges.Left
  anchor.gravity: Edges.Bottom | Edges.Right
  anchor.adjustment: PopupAdjustment.None
  anchor.onAnchoring: {
    if (!popup.dockWindow || !popup.dockRoot || !popup.dockRoot.dockCard) return
    var win = popup.dockWindow.contentItem
    var cardTop = win.mapFromItem(popup.dockRoot.dockCard, 0, 0).y
    var maxX = win.width - popup.implicitWidth - Style.gapsOut
    popup.anchor.rect.x = Math.round(Math.max(Style.gapsOut, Math.min(maxX, popup.centerX - popup.implicitWidth / 2)))
    popup.anchor.rect.y = Math.round(cardTop - popup.gap - popup.implicitHeight)
  }

  // Content that grows or shrinks while open (a folder page, a submenu)
  // keeps the popup's bottom edge on the card.
  onImplicitHeightChanged: if (popup.visible) popup.anchor.updateAnchor()
  onImplicitWidthChanged: if (popup.visible) popup.anchor.updateAnchor()
  onCenterXChanged: if (popup.visible) popup.anchor.updateAnchor()

  // A point in an item hosted by this popup, in dock-window coordinates.
  function toDockWindow(item, x, y) {
    var p = item.mapToItem(popup.contentItem, x, y)
    return Qt.point(popup.anchor.rect.x + p.x, popup.anchor.rect.y + p.y)
  }

  // A click outside the popup and the dock closes it, as the full-surface
  // dismiss area used to.
  HyprlandFocusGrab {
    active: popup.visible
    windows: popup.dockWindow ? [popup, popup.dockWindow] : [popup]
    onCleared: popup.dismissed()
  }
}
