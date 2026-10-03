# Popup Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the dock's VRAM from ~194 MiB to <= 40 MiB by shrinking the full-screen dock layer to a short full-width strip and moving every popup and tooltip into its own Quickshell `PopupWindow`.

**Architecture:** Two small reusable components carry the change: `DockPopupWindow.qml` (menus: context menu, folder stack, app group; anchored above the card, dismissed by `HyprlandFocusGrab`) and `TooltipWindow.qml` (input-transparent tooltips anchored above their item). Existing popup/tooltip items keep their content and sizing; only their positioning moves to the wrappers. Then the dock window height shrinks to card + headroom.

**Tech Stack:** Quickshell 0.3.1 (`PopupWindow`, `PopupAnchor`, `HyprlandFocusGrab`), Hyprland 0.56 Lua layer rules, QML.

**Spec:** `docs/superpowers/specs/2026-10-02-performance-design.md` (section A and its 2026-10-03 amendment)

## Global Constraints

- Branch `feat/popup-windows` is cut from `feat/window-previews` (PR #22) in the worktree `~/.local/share/omadock-wt/popups`. All code edits happen there.
- The live dock (`priard`) only gets the branch through a merge done in a temporary worktree (`git worktree add -b merge/popups ~/.local/share/omadock-wt/merge-popups priard`), conflicts resolved there, then `git merge --ff-only merge/popups` in the live checkout. Expect conflicts with the fork's hover-effects / presets / hardening / perf work in `Dock.qml`, `DockItem.qml`, `DockCard.qml`.
- Edited QML is not hot-reloaded reliably: after a merge, `omarchy restart shell; sleep 10; bash tests/smoke-test.sh`.
- No clicks or keyboard input. Pointer moves are allowed (enter from y≈1250 so hover fires). To open a menu without clicking, add a temporary `debugOpen(kind: string): string` IPC to `DockHost.qml` in the live checkout, restart, use it, then `git checkout DockHost.qml` and restart again. Clicking, dragging, renaming a group and real use are tested by the user.
- Screenshots: `grim -o DP-1 file.png`; the dock is at about y 2010–2160 physical, centred on x 3840; crop larger regions above it for popups.
- English in code and commits, no AI attribution, one topic per commit with a why. Opening the upstream PR needs the user's go-ahead.

## Rulings (made while planning)

- **No `PopupAdjustment` on menus.** Our anchor rect is already clamped to the full-width window, and the app-group drag-out needs the popup's exact origin (`anchor.rect`) to map pointer positions into the card; compositor sliding would make that origin unknown. Tooltips may use `Slide` (no input mapping).
- **Dismissal by `HyprlandFocusGrab`** over `[popup, dockWindow]`, like Omarchy's `PopupCard`. Clicks on the dock itself keep working as today (they reach the card's own handlers). The `globalDismiss` item stays only for clearing a drag released outside the card (`dockDragActive`).
- **Group rename keyboard focus:** first rely on the focus grab (it gives the grabbed windows keyboard focus). If the user reports typing does not reach the field, set `grabFocus: appGroupPopup.isEditingName` on that popup in a follow-up commit.
- **The pre-existing two-argument `handleDragMoved` call** in `AppGroupPopup` gets the y argument too (it is needed for the new mapping anyway).

## Review Focus

- A menu opened near the left or right screen edge must stay fully on screen (x clamp in `onAnchoring`). Checked live in Task 5 with alignment left/right via `setAlignment` IPC and `debugOpen`.
- A popup whose content height changes while open (folder stack navigating into a subfolder, context-menu pages) must re-anchor so it stays above the card. Covered by `onImplicitHeightChanged: anchor.updateAnchor()` in Task 1; checked by the user.
- Dragging an app out of a group popup onto the dock must still drop at the pointer position. Mapping in Task 2; user test.
- Autohide: a menu/tooltip must hide when the dock hides, and the dock must stay shown while a menu is open (existing flags). Checked in Task 5 by reading `syncVisibility` and by the user.
- Multi-monitor: each dock's popups anchor to that dock's window (the wrapper takes the window from its own `dockRoot`). Read-checked in Task 1.

---

## File Structure

```
components/DockPopupWindow.qml   # new: PopupWindow wrapper for menus above the card
components/TooltipWindow.qml     # new: input-transparent PopupWindow for tooltips
Dock.qml                         # dockWindowRef alias, popupMaxHeight, wrap 3 menus, mask, globalDismiss,
                                 # window height, blur_popups in the layer rule
components/DockContextMenu.qml   # drop anchors/x (positioned by the wrapper)
components/FolderPopup.qml       # drop anchors/x, maxAllowedHeight from root.popupMaxHeight
components/AppGroupPopup.qml     # drop anchors/x, drag-out mapping through the wrapper
components/HoverTooltip.qml      # BorderSurface moves into a TooltipWindow
components/DockItem.qml          # item tooltip into a TooltipWindow
components/PreviewTile.qml       # tile tooltip into a TooltipWindow
components/DockCard.qml          # Unpin bubble clamped inside the short window
```

---

### Task 1: `DockPopupWindow` and the context menu

**Files:**
- Create: `components/DockPopupWindow.qml`
- Modify: `Dock.qml` (alias `dockWindowRef`, wrap `DockContextMenu`, mask), `components/DockContextMenu.qml`

**Interfaces:**
- Produces `DockPopupWindow` with properties: `dockRoot` (the Dock root), `open: bool`, `centerX: real` (dock-window x the popup centres on), `body: Item` (the hosted popup item, sized by its own width/height); signal `dismissed()`; function `toDockWindow(item, x, y) -> point` mapping a point in a hosted item to dock-window coordinates.
- Produces `Dock.dockWindowRef` (the dock `PanelWindow`) and `Dock.popupMaxHeight` (real).

- [ ] **Step 1: Create `components/DockPopupWindow.qml`**

```qml
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
```

- [ ] **Step 2: Expose the window and a popup height limit in `Dock.qml`**

Next to the other aliases at the top (`readonly property alias contentItemRef: dockWindow.contentItem`), add:

```qml
  readonly property alias dockWindowRef: dockWindow
```

Next to `property var dockModel`, add:

```qml
  // Height a popup may use above the card: the screen above the dock, less
  // the margin the full-screen layer used to leave (Style.space(36)).
  readonly property real popupMaxHeight: Math.max(240,
    (root.dockScreen ? root.dockScreen.height : 1080) - Style.space(36)
    - Style.gapsOut - (dockCardComp ? dockCardComp.dockCard.height : 0) - Style.space(16))
```

- [ ] **Step 3: Wrap the context menu**

In `Dock.qml`, replace

```qml
    // ------------------------------------------------------------ context menu
    DockContextMenu {
      id: contextMenuComp
      rootRef: root
    }
```

with

```qml
    // ------------------------------------------------------------ context menu
    DockPopupWindow {
      id: contextMenuWindow
      dockRoot: root
      open: root.contextAppId !== ""
      centerX: root.contextX
      body: contextMenuComp
      onDismissed: root.closeContext()

      DockContextMenu {
        id: contextMenuComp
        rootRef: root
      }
    }
```

In `components/DockContextMenu.qml`, delete the three positioning lines:

```qml
  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.contextX : 0) - width / 2))
```

In the `mask: Region { ... regions: [...] }` of `dockWindow`, delete `Region { item: contextMenuComp },`.

- [ ] **Step 4: Check references still resolve**

Run (worktree): `grep -n "contextMenuComp\|contextMenu\b\|appContextMenuColumn" Dock.qml components/*.qml | head -30`
Expected: the root aliases `contextMenu: contextMenuComp` and `appContextMenuColumnRef: contextMenuComp.appContextMenuColumn` still name `contextMenuComp`, which is still declared (inside the wrapper), so they resolve. `DockItem.qml` reaches it through `root.appContextMenuColumnRef` — unchanged.
Also `grep -n "Quickshell.Hyprland" components/DockContextMenu.qml Dock.qml` — `Dock.qml` already imports it (needed by the wrapper file only, which imports it itself).

- [ ] **Step 5: Commit**

```bash
git add components/DockPopupWindow.qml Dock.qml components/DockContextMenu.qml
git commit -m "refactor(menus): context menu in its own popup window

The context menu lived inside the dock layer, which therefore had to be
nearly as tall as the screen. DockPopupWindow hosts it in an xdg popup of
the dock layer, positioned above the card in onAnchoring and dismissed by
a Hyprland focus grab, so the layer can shrink later."
```

---

### Task 2: Folder stack and app group popups

**Files:**
- Modify: `Dock.qml`, `components/FolderPopup.qml`, `components/AppGroupPopup.qml`

**Interfaces:**
- Consumes: `DockPopupWindow` (`toDockWindow`), `Dock.popupMaxHeight` (Task 1).

- [ ] **Step 1: Wrap both popups in `Dock.qml`**

Replace

```qml
    // ------------------------------------------------------------ Folder Stack Popover
    FolderPopup {
      id: folderStackPopoverComp
      rootRef: root
    }

    // ------------------------------------------------------------ App Group Popover
    AppGroupPopup {
      id: appGroupPopupComp
      rootRef: root
    }
```

with

```qml
    // ------------------------------------------------------------ Folder Stack Popover
    DockPopupWindow {
      id: folderStackWindow
      dockRoot: root
      open: root.activeStackFolder !== "" && root.dockVisible
      centerX: root.activeStackX
      body: folderStackPopoverComp
      onDismissed: root.closeFolderStack()

      FolderPopup {
        id: folderStackPopoverComp
        rootRef: root
      }
    }

    // ------------------------------------------------------------ App Group Popover
    DockPopupWindow {
      id: appGroupWindow
      dockRoot: root
      open: root.activeAppGroupId !== "" && root.dockVisible
      centerX: root.activeAppGroupX
      body: appGroupPopupComp
      onDismissed: root.closeAppGroup()

      AppGroupPopup {
        id: appGroupPopupComp
        rootRef: root
        popupWindow: appGroupWindow
      }
    }
```

Remove `Region { item: folderStackPopoverComp },` and `Region { item: appGroupPopupComp },` from the mask.

- [ ] **Step 2: `FolderPopup.qml`**

Delete the positioning lines (`anchors.bottom: targetCard ? ...`, `anchors.bottomMargin: Style.space(6)`, `x: Math.max(Style.gapsOut, ...activeStackX...)`). Replace

```qml
  readonly property real maxAllowedHeight: targetCard
    ? Math.max(240, targetCard.y - Style.space(16))
    : (parent ? (parent.height - Style.space(80)) : 500)
```

with

```qml
  readonly property real maxAllowedHeight: root ? root.popupMaxHeight : 500
```

- [ ] **Step 3: `AppGroupPopup.qml`**

Delete the positioning lines (`anchors.bottom`, `anchors.bottomMargin`, `x: ...activeAppGroupX...`). Add next to `property var rootRef`:

```qml
  // The DockPopupWindow hosting this popup; maps drag positions to the dock.
  property var popupWindow: null
```

In `cellMouseArea.onPositionChanged`, replace

```qml
                  if (cellItem.isDragging && root && root.dockCardComp) {
                    var cardPt = cellItem.mapToItem(root.dockCardComp, mouse.x, mouse.y)
                    root.dockCardComp.handleDragMoved(cellItem.appId, cardPt.x)
                  }
```

with

```qml
                  if (cellItem.isDragging && root && root.dockCardComp && appGroupPopup.popupWindow) {
                    // The popup is its own surface: go through dock-window
                    // coordinates to reach the card.
                    var winPt = appGroupPopup.popupWindow.toDockWindow(cellItem, mouse.x, mouse.y)
                    var cardPt = root.dockCardComp.mapFromItem(root.contentItemRef, winPt.x, winPt.y)
                    root.dockCardComp.handleDragMoved(cellItem.appId, cardPt.x, cardPt.y)
                  }
```

Run: `grep -n "targetCard\|targetWindow" components/FolderPopup.qml components/AppGroupPopup.qml components/DockContextMenu.qml` and delete the `targetCard` / `targetWindow` properties wherever nothing else uses them (keep any that are still referenced).

- [ ] **Step 4: `globalDismiss` only for drags**

In `Dock.qml` `globalDismiss`, change both size conditions from
`(root.contextAppId !== "" || root.activeStackFolder !== "" || root.activeAppGroupId !== "" || root.dockDragActive)` to `root.dockDragActive`, and delete its `onClicked` handler (the focus grabs dismiss the popups now). Update its comment to `// Clears a drag released outside the card (popups dismiss through their focus grabs).`

- [ ] **Step 5: Commit**

```bash
git add Dock.qml components/FolderPopup.qml components/AppGroupPopup.qml
git commit -m "refactor(menus): folder stack and app group in popup windows

Both popups move into DockPopupWindow like the context menu. The stack's
height limit now comes from the screen instead of the card's position in
the full-screen layer, and dragging an app out of a group maps through
dock-window coordinates because the popup is a separate surface. The
full-surface dismiss area remains only for drags released off the card."
```

---

### Task 3: Tooltips in `TooltipWindow`

**Files:**
- Create: `components/TooltipWindow.qml`
- Modify: `components/HoverTooltip.qml`, `components/DockItem.qml` (`itemTooltip`), `components/PreviewTile.qml` (`tileTooltip`)

**Interfaces:**
- Produces `TooltipWindow` with properties `target: Item` (centre over), `shown: bool`, `body: Item`; input-transparent.

- [ ] **Step 1: Create `components/TooltipWindow.qml`**

```qml
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
  anchor.edges: Edges.Top | Edges.Left
  anchor.gravity: Edges.Bottom | Edges.Right
  anchor.adjustment: PopupAdjustment.Slide
  anchor.onAnchoring: {
    if (!tip.hostWindow || !tip.target) return
    var win = tip.hostWindow.contentItem
    var p = win.mapFromItem(tip.target, tip.target.width / 2, 0)
    var maxX = win.width - tip.implicitWidth - Style.gapsOut
    tip.anchor.rect.x = Math.round(Math.max(Style.gapsOut, Math.min(maxX, p.x - tip.implicitWidth / 2)))
    tip.anchor.rect.y = Math.round(p.y - tip.gap - tip.implicitHeight)
  }
  onImplicitHeightChanged: if (tip.visible) tip.anchor.updateAnchor()
  onImplicitWidthChanged: if (tip.visible) tip.anchor.updateAnchor()
}
```

- [ ] **Step 2: `HoverTooltip.qml`**

Today the file's root is a `BorderSurface` placed by its parent's coordinates. Change the root to a zero-size `Item` that keeps the same public properties and hosts the bubble in a `TooltipWindow` targeted at its parent:

1. Change `BorderSurface {` / `id: bubble` at the top into:

```qml
Item {
  id: bubble
  width: 0
  height: 0
```

keeping the properties `text`, `hovered`, `blocked`, `shown`, `showTooltips`, `tooltipDelay`, `contextAppId`, the `onHoveredChanged`, `onBlockedChanged` handlers and the `dwell` Timer at this level.
2. Move the visual part into:

```qml
  TooltipWindow {
    target: bubble.parent
    shown: bubble.shown && bubble.text !== "" && bubble.showTooltips
      && !bubble.blocked && bubble.contextAppId === ""
    body: bubbleSurface

    BorderSurface {
      id: bubbleSurface
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius
      padding: Style.space(4)
      width: bubbleLabel.implicitWidth + contentLeftInset + contentRightInset
      height: bubbleLabel.implicitHeight + contentTopInset + contentBottomInset

      Text {
        id: bubbleLabel
        x: bubbleSurface.contentLeftInset
        y: bubbleSurface.contentTopInset
        text: bubble.text
        textFormat: Text.PlainText
        color: Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
```

3. Delete the old `visible`, `z`, `color`, `borderSpec`, `radius`, `padding`, `width`, `height` and the whole `x:` binding from the root.

Run: `grep -n "HoverTooltip {" -A8 components/*.qml` and check no caller reads `width`/`height`/`visible` of the tooltip for layout; callers that set `y:` or `anchors` on it keep compiling (they now position a 0×0 item) — remove those lines for clarity.

- [ ] **Step 3: `DockItem.qml` item tooltip**

Read `sed -n '/id: itemTooltip/,/^  }/p' components/DockItem.qml` first. Turn `itemTooltip` (a `BorderSurface` with `wanted`, `shown`, `visible`, `x`, `y` bindings) into a `TooltipWindow` host:

1. Rename the existing `BorderSurface { id: itemTooltip ... }` to `BorderSurface { id: itemTooltipSurface ... }`, keep its `color/borderSpec/radius/padding/width/height` and children (`tooltipContent` column, `tooltipDwell` timer stays outside, see 3), delete its `x`, `y`, `z` and `visible` bindings.
2. Wrap it:

```qml
  TooltipWindow {
    id: itemTooltip
    property bool wanted: <the old itemTooltip.wanted expression>
    target: iconWrapper   // the item the old tooltip was centred on; use the same parent the old x binding mapped from
    shown: <the old itemTooltip.visible expression, with itemTooltip.shown replaced by itemTooltip.tipShown>
    property bool tipShown: false
    body: itemTooltipSurface
    onWantedChanged: { ...old handler body, with itemTooltip.shown -> itemTooltip.tipShown... }

    BorderSurface { id: itemTooltipSurface ... }
  }
  Timer { id: tooltipDwell; interval: root ? root.tooltipDelay : 450; onTriggered: itemTooltip.tipShown = true }
```

Keep every other reference working: `grep -n "itemTooltip\." components/DockItem.qml` and update `itemTooltip.visible` users (e.g. `cardStack.active: wanted && itemTooltip.visible`) — `itemTooltip.visible` is still the right signal (the popup's visibility). Inside the surface, references to `itemTooltip.contentLeftInset`/`contentTopInset` become `itemTooltipSurface.*`.

- [ ] **Step 4: `PreviewTile.qml` tile tooltip**

Same pattern: `tileTooltip` `BorderSurface` → `tileTooltipSurface` (drop `x`, `y`, `z`, `visible`), wrapped by

```qml
  TooltipWindow {
    target: tile
    shown: tile.tooltipShown && tile.tileHovered && !tile.tileMenuOpen && tile.tileTitle !== "" && (root ? root.showTooltips : true)
    body: tileTooltipSurface
    BorderSurface { id: tileTooltipSurface ... }
  }
```

Update `tileTooltip.contentLeftInset` etc. inside to `tileTooltipSurface.*`, and `tooltipImplicitHeight()` callers.

- [ ] **Step 5: Grep for leftovers**

Run: `grep -n "contentItemRef" components/*.qml Dock.qml`
Expected: only the menu-opener sites that compute `contextX`/`activeStackX`/`activeAppGroupX` (window coordinates, still valid with a full-width window) — no tooltip x bindings remain.

- [ ] **Step 6: Commit**

```bash
git add components/TooltipWindow.qml components/HoverTooltip.qml components/DockItem.qml components/PreviewTile.qml
git commit -m "refactor(tooltips): show tooltips in input-transparent popups

Tooltips, including the window-preview card stack, were drawn above their
item inside the dock layer and needed it to be tall. TooltipWindow hosts
each one in a popup surface anchored above its item, with an empty input
mask so the pointer passes through."
```

---

### Task 4: Short dock window, Unpin bubble, popup blur

**Files:**
- Modify: `Dock.qml` (`dockWindow.implicitHeight`, `applyBlurRule`), `components/DockCard.qml` (remove bubble)

- [ ] **Step 1: Window height**

In `dockWindow`, replace `implicitHeight: Math.max(650, Math.round((root.dockScreen ? root.dockScreen.height : 1080) - Style.space(36)))` with

```qml
    // Only the card plus room above it for magnification, the launch/urgent
    // bounce and the drag "Unpin" bubble; menus and tooltips are popups.
    // Even logical height keeps the layer origin on the physical pixel grid
    // at scale 1.5 (DockIndicator snaps to it).
    readonly property real dockHeadroom: Style.space(56)
    implicitHeight: {
      var h = Math.ceil((dockCardComp ? dockCardComp.dockCard.height : 64) + Style.gapsOut + dockWindow.dockHeadroom)
      return h + (h % 2)
    }
```

- [ ] **Step 2: Unpin bubble stays inside the window**

In `components/DockCard.qml`, in the "Unpin" `BorderSurface` (`visible: root ? root.dragRemoveArmed : false`), replace its `y:` with

```qml
      // The layer is short now: keep the bubble below its top edge.
      readonly property real windowTop: -((root && root.dockWindowRef ? root.dockWindowRef.height : 0) - Style.gapsOut - dockCard.height)
      y: Math.max(windowTop + Style.space(2), Math.round((root ? root.dragPointerY : 0) - height - Style.space(16)))
```

- [ ] **Step 3: Blur popups with the dock**

In `applyBlurRule`, the rule string `hl.layer_rule({ match = { namespace = \"^omadock$\" }, blur = ` ... `, ignore_alpha = 0.05 })` gains `blur_popups = ` with the same boolean as `blur`:

```js
        lua += " _G.omadock_blur_rule = hl.layer_rule({ match = { namespace = \"^omadock$\" }, blur = "
          + (root.blurMode === "on" ? "true" : "false") + ", blur_popups = "
          + (root.blurMode === "on" ? "true" : "false") + ", ignore_alpha = 0.05 })"
```

- [ ] **Step 4: Commit**

```bash
git add Dock.qml components/DockCard.qml
git commit -m "perf(layer): shrink the dock layer to the card and its headroom

With menus and tooltips in popups, the full-width layer only needs the
card plus room for magnification, the bounce and the Unpin bubble. Its
buffers drop from about 194 MiB to about 26 MiB on a 5120x1440 @1.5
output. The blur rule now also blurs the dock's popups."
```

---

### Task 5: Merge, verify live, measure, PR

- [ ] **Step 1: Merge into priard** (temp worktree, per Global Constraints). In conflicts keep both sides' intent: the fork's hover effects, presets, perf and hardening changes plus this branch's popup wrappers. Then `node --test tests/unit/*.test.mjs`, `git merge --ff-only merge/popups` in the live checkout, remove the temp worktree/branch, `omarchy restart shell; sleep 10; bash tests/run-all.sh --all` → ALL PASSED. `journalctl --user --since "-1 min" | grep -iE "omadock/|TypeError|ReferenceError|binding loop"` → empty.

- [ ] **Step 2: Layer size** — `hyprctl layers | grep omadock` → height ≈ card + 56 (well under 200), width 5120.

- [ ] **Step 3: Tooltip** — move the pointer from y 1250 down onto an app icon centre (use `omarchy-shell omadock itemGeometry` + layer offset, as the bench does), wait 0.8 s, `grim`, crop 1600×700 around the icon: the tooltip (with preview cards for a multi-window app) must sit centred above the icon, blurred background. Restore the pointer.

- [ ] **Step 4: Menus** — add the temporary IPC to `DockHost.qml` (live checkout):

```qml
    function debugOpen(kind: string): string {
      var d = host.orderedDocks()
      if (d.length === 0) return "no dock"
      var dock = d[0]
      var items = JSON.parse(dock.itemGeometry())
      var app = items.filter(function(i) { return i.kind === "app" })[0]
      var folder = items.filter(function(i) { return i.kind === "folder" })[0]
      if (kind === "context" && app) dock.openContext(app.id, app.x + app.w / 2)
      else if (kind === "stack" && folder) dock.openFolderStack(folder.id, folder.x + folder.w / 2)
      else if (kind === "close") { dock.closeContext(); dock.closeFolderStack(); dock.closeAppGroup() }
      return "ok"
    }
```

Check the real signatures first (`grep -n "function openContext\|function openFolderStack" Dock.qml`) and adapt the calls. Restart, then for `context` and `stack`: open, `grim`, crop, verify the popup sits above the card at the item, fully on screen, blurred; `close`. Repeat `context` with `setAlignment left` and `right` (restore the original alignment after). Remove the debug function (`git checkout DockHost.qml`), restart.

- [ ] **Step 5: VRAM** — `python3 tests/bench/bench.py run --full --repeat 1` (asks no question with `--yes`; tell the user the shell restarts twice). Expected: `Dock cost` VRAM ≤ 40 MiB (was 194). Then `python3 tests/bench/bench.py compare bench/results/2026-10-03-1036-omarchy-desk-pri.json <new>`; S1 (hover sweep) VRAM should not exceed S0 by more than the few MiB a tooltip popup costs.

- [ ] **Step 6: Commit results, push, PR**

```bash
git add bench/results/*.json && git commit -m "test(bench): dock cost after moving popups out of the layer"
git push fork priard
git -C ~/.local/share/omadock-wt/popups push -u fork feat/popup-windows
```

Write `<scratchpad>/popups-pr.md` (based on #22; what moved where; VRAM numbers; what the user tested by hand: menus, stack navigation, group drag-out and rename, autohide, alignment) and ask the user before `gh pr create -R thepathless/omadock --head priard:feat/popup-windows --base main --title "perf: popups and tooltips in their own surfaces, short dock layer" --body-file <scratchpad>/popups-pr.md`. Note in the body that it is based on #22 (the tooltip it moves carries the card stack).
