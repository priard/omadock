import QtQuick 6.11
import Quickshell
import qs.Commons
import "../DockFit.js" as DockFit
import "../DockKeys.js" as DockKeys
import "../DockModel.js" as DockModel

// The dock's fit to its screen (DockFit.js): gathers the row's items and
// sizes from the dock, keeps the plan, and recomputes it a turn later
// (child Timer: a burst of changes gives one plan). Dock.qml reads plan for
// its effective icon size and spacing; row items reach this through
// root.fitHostRef, since Dock.qml has no lines left under its cap.
Item {
  id: host
  property var dockRoot: null
  readonly property var root: dockRoot
  width: 0
  height: 0

  // ---- the plan
  // A room in px that replaces the measured one (-1: measure).
  property real availableOverride: -1
  property var plan: ({ level: 0, t: 1, gap: 0, iconSize: 0, overflowFrom: -1, width: 0, rest: 0 })
  property var hidden: ({})
  property var shown: ({ button: 1, pinned: 0, tiles: 0, running: 0, folders: 0, drives: 0 })
  property var hiddenItems: []
  // A drag on the dock keeps the plan, so its drop zones do not move; the
  // plan catches up after the drop.
  readonly property bool frozen: !!host.root && host.root.dockDragActive
  onFrozenChanged: if (!host.frozen) host.schedule()

  // Spacing as configured, and the minimum the plan may go down to.
  function gapAt(t) { return t * Style.space(root.itemSpacing) }
  // Dock.separatorWidth at spacing fraction t (split sections widen with it).
  function separatorWidthAt(t) {
    if (root.placement.split) return Math.max(Style.space(1), Style.space(root.sectionSpacing) * t + 2 * root.baseRowLeft - 2 * host.gapAt(t))
    if (root.dividerStyle === "none") return -host.gapAt(t)
    return Style.space(1) + Style.space(7)
  }

  function room() {
    if (host.availableOverride >= 0) return host.availableOverride
    var card = root ? root.dockCardComp : null
    var win = root ? root.dockWindowRef : null
    if (!card || !win) return 1e9
    var insets = card.dockCard.contentLeftInset + card.dockCard.contentRightInset
    if (card.stretch) return card.stretch.width - insets
    return win.width - 4 * Style.gapsOut - insets
  }

  // The row in order.
  function items() {
    var out = []
    if (root.showAppsButton) out.push({ id: "button", kind: "button" })
    var pins = root.pinnedRow || []
    for (var i = 0; i < pins.length; i++) {
      var p = pins[i]
      out.push({ id: "pin:" + root.pinnedRowKey(p), kind: p.group ? "group" : "app" })
    }
    var tiles = root.tileModel || []
    if (tiles.length > 0 && root.hasLeftTileSeparator) out.push({ id: "sep:pinTiles", kind: "separator" })
    for (var t = 0; t < tiles.length; t++) out.push({ id: "tile:" + DockKeys.tileKey(tiles[t]), kind: "tile" })
    if (root.hasSeparator) out.push({ id: "sep:run", kind: "separator" })
    var run = root.runningSection || []
    for (var r = 0; r < run.length; r++) {
      var re = run[r]
      if (root.showMinimizedTiles && DockModel.allWindowsMinimized(re.windowList, root.liveWsNameOf, root.minimizedWorkspace)) continue
      out.push({ id: "run:" + re.appId, kind: "app" })
    }
    var folders = (root.pinnedFolders || []).concat(root.pinnedButtons || [])
    if (root.hasFolderSeparator) out.push({ id: "sep:folders", kind: "separator" })
    for (var f = 0; f < folders.length; f++) {
      out.push({ id: "folder:" + DockKeys.folderKey(folders[f]), kind: "folder" })
    }
    var drives = (root.showRemovableDrives && root.mountedDrives) ? root.mountedDrives : []
    if (root.hasDriveSeparator) out.push({ id: "sep:drives", kind: "separator" })
    for (var d = 0; d < drives.length; d++) out.push({ id: "drive:" + DockKeys.driveKey(drives[d]), kind: "drive" })
    return out
  }

  function recompute() {
    if (!root || host.frozen) return
    var list = host.items()
    var spread = root.placement.align === "spread"
    var input = {
      available: host.room(), items: list,
      iconSize: root.baseIconSize, floor: Math.max(24, Math.round(root.baseIconSize / 2)),
      slotPad: Style.space(10), gapMax: host.gapAt(1), gapMin: host.gapAt(0),
      sepMax: host.separatorWidthAt(1), sepMin: host.separatorWidthAt(0),
      tileFactor: 1.5, wave: root.waveHover,
      margin: Style.space(8),
      // Both sides: the gap item is always in the row (DockCard), one more
      // spacing and its floor of one pixel (DockLayout.spreadGap).
      fixedGaps: spread ? 1 : 0, fixedWidth: spread ? 1 : 0
    }
    var next = DockFit.plan(input, host.plan.iconSize > 0 ? host.plan : null)
    var hid = {}
    var hiddenList = []
    if (next.overflowFrom >= 0) {
      for (var i = next.overflowFrom; i < list.length; i++) {
        if (list[i].kind === "separator") continue
        hid[list[i].id] = true
        hiddenList.push(list[i].id)
      }
    }
    var counts = { button: 0, pinned: 0, tiles: 0, running: 0, folders: 0, drives: 0 }
    var names = { button: "button", pin: "pinned", tile: "tiles", run: "running", folder: "folders", drive: "drives" }
    for (var j = 0; j < list.length; j++) {
      var it = list[j]
      if (hid[it.id] || it.kind === "separator") continue
      counts[names[it.id.split(":")[0]]]++
    }
    if (JSON.stringify(next) !== JSON.stringify(host.plan)) host.plan = next
    if (JSON.stringify(hid) !== JSON.stringify(host.hidden)) host.hidden = hid
    if (JSON.stringify(counts) !== JSON.stringify(host.shown)) host.shown = counts
    if (JSON.stringify(hiddenList) !== JSON.stringify(host.hiddenItems)) host.hiddenItems = hiddenList
  }

  Timer { id: later; interval: 0; onTriggered: host.recompute() }
  function schedule() { later.restart() }

  // Everything the input reads. The plan's own outputs (iconSize, gapWidth)
  // are deliberately not here.
  Connections {
    target: host.root
    function onPinnedRowChanged() { host.schedule() }
    function onRunningSectionChanged() { host.schedule() }
    function onTileModelChanged() { host.schedule() }
    function onPinnedFoldersChanged() { host.schedule() }
    function onPinnedButtonsChanged() { host.schedule() }
    function onMountedDrivesChanged() { host.schedule() }
    function onBaseIconSizeChanged() { host.schedule() }
    function onItemSpacingChanged() { host.schedule() }
    function onSectionSpacingChanged() { host.schedule() }
    function onPlacementChanged() { host.schedule() }
    function onHoverEffectChanged() { host.schedule() }
    function onShowAppsButtonChanged() { host.schedule() }
    function onShowRemovableDrivesChanged() { host.schedule() }
    function onShowMinimizedTilesChanged() { host.schedule() }
  }
  Connections {
    target: host.root ? host.root.dockWindowRef : null
    function onWidthChanged() { host.schedule() }
  }
  onAvailableOverrideChanged: host.schedule()
  Component.onCompleted: host.schedule()

  // What the hidden items would show on the dock, summed for the "»" tile:
  // a window open, an urgent app, notification badges.
  readonly property var hiddenState: {
    var s = { windows: false, urgent: false, badges: 0 }
    var dock = host.root
    if (!dock) return s
    var apps = []
    for (var i = 0; i < host.hiddenItems.length; i++) {
      var id = host.hiddenItems[i]
      var sep = id.indexOf(":")
      var kind = id.slice(0, sep), key = id.slice(sep + 1)
      if (kind === "run") apps.push(key)
      else if (kind === "pin") {
        var p = dock.pinnedRowByKey[key]
        if (p && p.entry) apps.push(p.entry.appId)
        else if (p && p.group && DockModel.isList(p.group.apps)) apps = apps.concat(DockModel.toArray(p.group.apps))
      }
    }
    for (var a = 0; a < apps.length; a++) {
      var e = dock.entryForId(apps[a])
      if (e && e.running) s.windows = true
      if (dock.showUrgentHint && dock.urgentMap && dock.urgentMap[apps[a]]) s.urgent = true
    }
    if (dock.showNotificationBadges) s.badges = DockModel.groupBadgeTotal(apps, dock.notificationBadges)
    return s
  }

  // ---- the overflow popup, opened by the "»" tile (DockOverflowTile)
  // The dock's other popup lives (PopupLife rivals): opening one ends
  // another still fading out, so its window cannot clear the new grab.
  property var rivals: []
  property bool overflowOpen: false
  property real overflowX: 0
  readonly property alias overflowLife: overflowLifeObj
  function openOverflow(cx) {
    if (host.overflowOpen) { host.overflowOpen = false; return }
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    host.overflowX = cx
    host.overflowOpen = true
  }
  function closeOverflow() { host.overflowOpen = false }
  // A stack or an opened group anchored on an item that just moved into
  // "»" has nothing left to point at.
  onHiddenChanged: {
    var dock = host.root
    if (!dock) return
    if (dock.activeAppGroupId !== "" && host.hidden["pin:group:" + dock.activeAppGroupId]) dock.closeAppGroup()
    var stack = dock.activeStackFolder
    if (stack === "") return
    if (host.hidden["folder:path:" + stack]) { dock.closeFolderStack(); return }
    var drives = dock.mountedDrives || []
    for (var i = 0; i < drives.length; i++) {
      if (drives[i] && drives[i].mountpoint === stack && host.hidden["drive:" + DockKeys.driveKey(drives[i])]) { dock.closeFolderStack(); return }
    }
  }
  // Nothing left to show: the row fits again.
  onHiddenItemsChanged: if (host.hiddenItems.length === 0) host.overflowOpen = false
  // Another popup taking over, or the dock hiding, closes it.
  Connections {
    target: host.root
    function onContextAppIdChanged() { if (host.root.contextAppId !== "") host.overflowOpen = false }
    function onActiveStackFolderChanged() { if (host.root.activeStackFolder !== "") host.overflowOpen = false }
    function onActiveAppGroupIdChanged() { if (host.root.activeAppGroupId !== "") host.overflowOpen = false }
    function onDockVisibleChanged() { if (!host.root.dockVisible) host.overflowOpen = false }
  }

  PopupLife { id: overflowLifeObj; dockRoot: host.root; rivals: host.rivals; want: host.overflowOpen && !!host.root && host.root.dockVisible }
  LazyLoader {
    active: overflowLifeObj.alive
    DockPopupWindow {
      id: overflowWindow
      life: overflowLifeObj
      dockRoot: host.root
      open: true
      centerX: host.overflowX
      body: overflowBody
      onDismissed: host.closeOverflow()
      OverflowPopup {
        id: overflowBody
        rootRef: host.root
        hostRef: host
        popupWindow: overflowWindow
      }
    }
  }
}
