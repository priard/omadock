import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// A menu above the dock card in its own popup surface, so the dock layer
// only needs to be as tall as the card.
//
// The surface keeps one fixed size for its whole life: the room above the
// dock (popupMaxHeight) by maxWidth. The menu (body) sits at its bottom,
// centred over centerX, and grows or shrinks inside it; the rest of the
// surface is transparent and outside the input mask. A popup that changed
// its surface size with its content (a folder being listed, another folder
// opened, the stack closing) showed the new size at the old position for a
// frame or two until the compositor repositioned it, flashing over the dock.
//
// Placement (onAnchoring, the pattern of Omarchy's Ui/PopupCard.qml): the
// anchor point is Style.space(6) above the card; the surface hangs above it,
// centred and clamped to the screen. No compositor adjustment, so
// toDockWindow() can rely on it.
PopupWindow {
  id: popup

  property var dockRoot: null
  property bool open: false
  property real centerX: 0
  property Item body: null

  signal dismissed()

  readonly property var dockWindow: dockRoot ? dockRoot.dockWindowRef : null
  readonly property real gap: Style.space(6)
  readonly property real maxWidth: Style.space(900)

  // Surface centre in dock-window x, clamped so the surface stays on screen.
  readonly property real surfaceCenterX: {
    var w = popup.dockWindow ? popup.dockWindow.width : 1920
    var half = popup.implicitWidth / 2
    return Math.round(Math.max(Style.gapsOut + half, Math.min(w - Style.gapsOut - half, popup.centerX)))
  }

  color: "transparent"
  visible: open && body !== null
  implicitWidth: Math.ceil(Math.min(popup.maxWidth, popup.dockWindow ? popup.dockWindow.width - Style.gapsOut * 2 : popup.maxWidth))
  implicitHeight: Math.ceil(popup.dockRoot ? popup.dockRoot.popupMaxHeight : 600)

  // Input only over the menu itself.
  mask: Region { item: popup.body }

  // The body at the bottom of the surface, centred over centerX and kept
  // inside the surface (which may itself be clamped at a screen edge).
  Binding {
    target: popup.body
    property: "x"
    value: Math.round(Math.max(0, Math.min(popup.implicitWidth - (popup.body ? popup.body.width : 0),
      popup.centerX - (popup.surfaceCenterX - popup.implicitWidth / 2) - (popup.body ? popup.body.width : 0) / 2)))
  }
  Binding {
    target: popup.body
    property: "y"
    value: Math.round(popup.implicitHeight - (popup.body ? popup.body.height : 0))
  }

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
    popup.anchor.rect.x = popup.surfaceCenterX
    popup.anchor.rect.y = Math.round(cardTop - popup.gap)
  }

  // The surface only moves when it should sit over another item.
  onSurfaceCenterXChanged: if (popup.visible) popup.anchor.updateAnchor()

  // A point in an item hosted by this popup, in dock-window coordinates.
  function toDockWindow(item, x, y) {
    var p = item.mapToItem(popup.contentItem, x, y)
    return Qt.point(popup.surfaceCenterX - Math.round(popup.implicitWidth / 2) + p.x,
                    popup.anchor.rect.y - popup.implicitHeight + p.y)
  }

  // A click outside the menu and the dock closes it, as the full-surface
  // dismiss area used to.
  HyprlandFocusGrab {
    active: popup.visible
    windows: popup.dockWindow ? [popup, popup.dockWindow] : [popup]
    onCleared: popup.dismissed()
  }
}
