import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../../DockIcons.js" as DockIcons

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  // Called on drag enter: finds the first directory among the dragged URLs.
  function previewDraggedFolder(root, urls) {
    root.dropCandidatePath = ""
    root.dropPinArmed = false
    var paths = root.localPathsFromUrls(urls)
    if (paths.length === 0) return
    if (root.dropFolderProbeRef.running) root.dropFolderProbeRef.running = false
    root.dropFolderProbeRef.command = ["sh", "-c", 'for p; do [ -d "$p" ] && { printf "%s\\n" "$p"; exit 0; }; done', "sh"].concat(paths)
    root.dropFolderProbeRef.running = true
  }

  function insertFolderPin(root, path, name, icon, index) {
    if (root.isFolderPinned(path)) return
    var next = (root.pinnedFolders || []).slice()
    var at = (index >= 0 && index <= next.length) ? index : next.length
    next.splice(at, 0, { path: path, name: name || "Folder", icon: icon || DockIcons.folderIconFor(path, "") })
    root.pinnedFolders = next
    root.saveConfig()
  }

  function localPathsFromUrls(root, urls) {
    return DockModel.localPathsFromUrls(urls)
  }

  function pinDroppedFolders(root, urls) {
    var paths = root.localPathsFromUrls(urls)
    root.dropFolderCheckRef.insertAt = root.dropInsertIndex
    root.dropPinArmed = false
    root.dropCandidatePath = ""
    root.dropInsertIndex = -1
    if (paths.length === 0) return
    // Only directories are pinned; the check runs out of process.
    root.dropFolderCheckRef.command = ["sh", "-c", 'for p; do [ -d "$p" ] && printf "%s\\n" "$p"; done', "sh"].concat(paths)
    root.dropFolderCheckRef.running = true
  }

  // ------------------------------------------------- media controls
  // The MPRIS player an app exposes, matched on the player's DesktopEntry
  // (or, failing that, its Identity) against the dock app id. Proxies such as
  // playerctld name no app, so they never match. A playing instance wins
  // when an app exposes several (e.g. browser tabs).
  function mediaPlayerFor(root, appId) {
    if (!appId || appId.indexOf("__") === 0) return null
    var list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var entry = String(p.desktopEntry || "").replace(/\.desktop$/, "")
      var ident = String(p.identity || "")
      var matches = (entry !== "" && DockModel.isAppMatch(appId, entry))
        || (entry === "" && ident !== "" && DockModel.isAppMatch(appId, ident))
      if (!matches) continue
      if (p.isPlaying) return p
      if (!fallback) fallback = p
    }
    return fallback
  }

  // The desktop entry id an app launches through (same lookup as launchApp).
  function desktopIdFor(root, appId) {
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    return (deskEntry && deskEntry.id) ? deskEntry.id : appId
  }

  function beginAppDrop(root, appId, urls) {
    root.appDropTargetId = appId
    root._appDropOpenId = ""
    root.appDropPaths = root.localPathsFromUrls(urls)
    if (root.appDropPaths.length === 0) {
      root.appDropState = "no"
      return
    }
    root.appDropState = "pending"
    if (root.appDropCheckRef.running) root.appDropCheckRef.running = false
    root.appDropCheckRef.command = ["python3",
      root.scriptPath("drop-check.py"),
      root.desktopIdFor(appId)].concat(root.appDropPaths)
    root.appDropCheckRef.running = true
  }

  function endAppDrop(root, appId) {
    if (root.appDropTargetId !== appId) return
    root.appDropTargetId = ""
    // A drop still waiting on the check keeps its state until it answers.
    if (root._appDropOpenId === "") root.appDropState = ""
  }

  // Returns false when the app cannot take the files (the drop is refused).
  function dropOnApp(root, appId) {
    root.appDropTargetId = ""
    if (root.appDropState === "yes") {
      root.openFilesWith(appId, root.appDropPaths)
      root.appDropState = ""
      return true
    }
    if (root.appDropState === "pending") {
      root._appDropOpenId = appId
      return true
    }
    root.appDropState = ""
    return false
  }

  function openFilesWith(root, appId, paths) {
    if (!paths || paths.length === 0) return
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", "--", root.desktopIdFor(appId) + ".desktop"].concat(paths))
  }

  function entryForId(root, appId) {
    var i
    for (i = 0; i < root.pinnedSection.length; i++) {
      if (root.pinnedSection[i].appId === appId || DockModel.isAppMatch(root.pinnedSection[i].appId, appId))
        return root.pinnedSection[i]
    }
    for (i = 0; i < root.runningSection.length; i++) {
      if (root.runningSection[i].appId === appId || DockModel.isAppMatch(root.runningSection[i].appId, appId))
        return root.runningSection[i]
    }
    var grouped = root.groupedSection || []
    for (i = 0; i < grouped.length; i++) {
      if (grouped[i].appId === appId || DockModel.isAppMatch(grouped[i].appId, appId))
        return grouped[i]
    }
    return null
  }

  function setPinned(root, next) {
    // A group standing before an app that is no longer pinned moves before
    // the next one that is, instead of dropping to the end.
    var groups = DockModel.reanchorGroups(root.appGroups, root.pinnedIds, next)
    root.pinnedIds = next
    root.dockFileRef.setText(DockModel.serializePinned(next))
    if (groups !== root.appGroups) {
      root.appGroups = groups
      root.saveConfig()
    }
  }

  // Puts pinned apps and app groups in the order of a pinnedRow.
  function applyPinnedRow(root, row) {
    var state = DockModel.rowState(row, root.pinnedIds)
    root.appGroups = state.groups
    root.setPinned(state.pins)
    root.saveConfig()
  }

  function togglePin(root, appId) {
    var id = DockModel.stripDesktop(appId)
    if (!id) return
    // Pin-time validation: never pin an id that no longer resolves to an
    // installed desktop entry — the pin could only ever bounce silently.
    // Unpinning bypasses the check so stale pins can always be removed.
    if (!DockModel.isPinned(root.pinnedIds, id) && !root.resolveDesktopEntry(id)) {
      root.notifyAppMissing(id, "It cannot be pinned to the dock — reinstall the app first.")
      return
    }
    root.setPinned(DockModel.togglePinned(root.pinnedIds, id))
  }

  function resolveDesktopEntry(root, appId) {
    var entry = DockModel.entryFor(root.appRows, appId)
    if (!entry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      entry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    return entry || null
  }
}
