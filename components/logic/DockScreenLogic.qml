import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  function pickScreen(root) {
    var name = root.forcedScreenName || root.screenName
    var s = name ? root.screenForName(name) : null
    if (s) return s
    return root.realScreens.length > 0 ? root.realScreens[0] : null
  }

  function lookupOutputScale(root, _rev) {
    // HyprlandMonitor.scale stops tracking after load, but the monitor's
    // physical size and Qt's logical screen size stay live — their ratio is
    // the output scale. Diagonal over diagonal, since width alone breaks on a
    // rotated output. m.scale is only a last resort. _rev is the binding's
    // re-run hook (monitorRev), not an input.
    var m = root.dockScreen ? Hyprland.monitorFor(root.dockScreen) : null
    var lw = Screen.width
    var lh = Screen.height
    if (m && m.width > 0 && m.height > 0 && lw > 0 && lh > 0) {
      return Math.sqrt((m.width * m.width + m.height * m.height) / (lw * lw + lh * lh))
    }
    return (m && m.scale > 0) ? m.scale : 1
  }

  function recheckOutputScale(root) {
    Hyprland.refreshMonitors()
    root.scaleRevBumpRef.ticks = 0
    root.scaleRevBumpRef.restart()
  }

  function monitorNameForWorkspace(root, target) {
    if (!target || !Hyprland.workspaces) return ""
    var list = Hyprland.workspaces.values || []
    for (var i = 0; i < list.length; i++) {
      var ws = list[i]
      if (!ws) continue
      if (String(ws.name || "") === target || String(ws.id) === target)
        return (ws.monitor && ws.monitor.name) ? String(ws.monitor.name) : ""
    }
    return ""
  }

  // The monitor a window belongs to. A parked window sits on the shared
  // special workspace, so it belongs to the monitor it was minimized from.
  function monitorNameForHypr(root, h) {
    if (!h) return ""
    var addr = root.windowAddress(h)
    var origin = (addr && root.minimizedOrigins) ? root.minimizedOrigins[addr] : undefined
    if (origin !== undefined) {
      var fromOrigin = root.monitorNameForWorkspace(String(origin))
      if (fromOrigin) return fromOrigin
    }
    // The workspace's monitor tracks moveworkspace events; the window's own
    // monitor is only a fallback.
    var mon = (h.workspace && h.workspace.monitor) ? h.workspace.monitor : h.monitor
    return (mon && mon.name) ? String(mon.name) : ""
  }

  // Unresolved handles count as local: a window may show on every dock for a
  // beat while Hyprland catches up, but it never vanishes from all of them.
  function isHyprOnThisMonitor(root, h) {
    if (!root.filterByMonitor) return true
    var name = root.monitorNameForHypr(h)
    return name === "" || name === root.forcedScreenName
  }

  function isToplevelOnThisMonitor(root, top) {
    if (!root.filterByMonitor) return true
    var h = root.hyprToplevelFor(top)
    return h ? root.isHyprOnThisMonitor(h) : true
  }

  function pushSharedState(root) {
    if (!root.sharedState || root._syncingShared) return
    root._syncingShared = true
    root.sharedState.minimizedOrigins = root.minimizedOrigins
    root.sharedState.parkedAt = root.parkedAt
    root.sharedState.parkSlots = root.parkSlots
    root._syncingShared = false
  }

  function pullSharedState(root) {
    if (!root.sharedState || root._syncingShared) return
    root._syncingShared = true
    root.minimizedOrigins = root.sharedState.minimizedOrigins || ({})
    root.parkedAt = root.sharedState.parkedAt || ({})
    root.parkSlots = root.sharedState.parkSlots || ({})
    root._syncingShared = false
    root.modelTimerRef.restart()
  }

  function screenForName(root, name) {
    var list = root.realScreens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return null
  }
}
