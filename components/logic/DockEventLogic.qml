import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel

// Logic extracted from Dock.qml: the Hyprland IPC event routing. Verbatim body; the
// only change is that timers and processes are reached through the root's refs, as in
// the other logic modules. State and wiring stay in Dock.qml.

QtObject {
function handleRawEvent(root, event) {
  var n = String((event && event.name) || "")
  // A config reload drops runtime layer rules along with the Lua state.
  if (n === "configreloaded") {
    root.applyBlurRule(true)
    root.modelSettleTimerRef.restart()
    root.terminalHostDebounceRef.restart()
    return
  }
  if (n === "windowtitlev2") {
    root.terminalHostDebounceRef.restart()
    root.modelTimerRef.restart()
  }
  if (n === "openwindow") {
    var rawAddr = String(event.data || "").split(",")[0].trim()
    if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
    var fullAddr = "0x" + rawAddr
    var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
    rec[fullAddr] = Date.now() + 3000
    root.recentOpenedWindowAddrs = rec
  }
  if (n === "urgent") {
    var rawAddr = String(event.data || "").trim()
    if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
    var fullAddr = "0x" + rawAddr

    // Foreground Suppression Rule: If the window is ALREADY active and focused, suppress urgency
    var activeAddr = root.windowAddress(root.hyprToplevelFor(ToplevelManager.activeToplevel))
    if (activeAddr && activeAddr === fullAddr) {
      return
    }

    // Suppress initial window startup / opening urgency
    if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr] && Date.now() < root.recentOpenedWindowAddrs[fullAddr]) {
      return
    }

    // Suppress if the app was recently launched by user
    var allEntries = root.pinnedSection.concat(root.runningSection)
    for (var e = 0; e < allEntries.length; e++) {
      var entry = allEntries[e]
      if (!entry) continue
      if (root.launchPending && root.launchPending[entry.id]) {
        var wins = entry.windowList || []
        for (var w = 0; w < wins.length; w++) {
          var wa = wins[w] ? wins[w].address : ""
          if (wa && wa === fullAddr) {
            return
          }
        }
      }
    }

    var map = DockModel.copyMap(root.urgentMap)
    map[fullAddr] = true
    root.urgentMap = map
    root.urgentEventKeys = [fullAddr]
    root.urgentEvents++
    root.modelTimerRef.restart()
  }
  if (n === "activewindow" || n === "activewindowv2") {
    var eventData = String(event.data || "").trim()
    if (n === "activewindowv2") {
      var rawAddr = eventData.split(",")[0].trim()
      if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
      var fullAddr = "0x" + rawAddr
      root.clearUrgentApp("", fullAddr)
    } else {
      var winClass = eventData.split(",")[0].trim()
      if (winClass) root.clearUrgentApp(winClass, "")
    }
  }
  if (n === "closewindow") {
    var rawAddr = String(event.data || "").trim()
    if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
    var fullAddr = "0x" + rawAddr
    if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr]) {
      var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
      delete rec[fullAddr]
      root.recentOpenedWindowAddrs = rec
    }
    if (root.urgentMap) {
      root.clearUrgentApp("", fullAddr)
    }
    if (root.minimizedOrigins && root.minimizedOrigins[fullAddr]) {
      var mo = DockModel.copyMap(root.minimizedOrigins)
      delete mo[fullAddr]
      root.minimizedOrigins = mo
    }
    root.dropParkSlot(fullAddr)
  }
  if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" ||
      n === "movewindow" || n === "movewindowv2" || n === "resizewindow" || n === "resizewindowv2" ||
      n === "activewindow" || n === "activewindowv2" || n === "changefloatingmode" ||
      n === "fullscreen" || n === "pin" || n === "focusedmon" ||
      n === "monitoradded" || n === "monitorremoved") {
    root.debounceOverlapTimerRef.restart()
  }
  if (n === "openwindow" || n === "closewindow" || n === "urgent"
      || n === "movewindow" || n === "movewindowv2"
      || n === "workspace" || n === "workspacev2") root.modelTimerRef.restart()
  // Per-monitor docks: a workspace (and its windows) changing monitor
  // moves those apps to another dock.
  if (root.filterByMonitor && (n === "moveworkspace" || n === "moveworkspacev2"
      || n === "monitoradded" || n === "monitorremoved")) root.modelSettleTimerRef.restart()
  // Park/restore moves get one deferred rebuild: the 40ms rebuild can land
  // inside Quickshell's Hyprland-handle lag and freeze pre-move state into
  // the model (stale isMinimized kept the running icon beside its tile).
  // Event-driven single shot — self-terminating, no polling.
  if (n === "movewindow" || n === "movewindowv2") root.modelSettleTimerRef.restart()
  // configreloaded fires Quickshell refreshWorkspaces + refreshToplevels
  // which destroy/recreate workspace objects and re-assign toplevel handles.
  // Settle handles cleanly via root.modelSettleTimerRef.
  if (n === "configreloaded") root.modelSettleTimerRef.restart()
}}
