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
  function openAppGroup(root, gdata, cx, cy) {
    if (root.activeAppGroupId === (gdata && gdata.id ? gdata.id : "")) {
      root.closeAppGroup()
      return
    }
    root.closeContext()
    root.closeFolderStack()
    root.activeAppGroupId = (gdata && gdata.id) ? gdata.id : ""
    root.activeAppGroupData = gdata
    root.activeAppGroupX = cx
    root.syncVisibility()
  }

  function closeAppGroup(root) {
    root.activeAppGroupId = ""
    root.activeAppGroupData = null
    root.syncVisibility()
  }

  function openAppGroupContext(root, gdata, cx, cy) {
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    root.contextAppId = "__app_group_context__"
    root.contextAppGroupData = gdata
    root.contextX = cx
    root.contextY = cy
  }

  function createAppGroupFromRunning(root) {
    var all = (root.pinnedSection || []).concat(root.runningSection || [])
    var ids = []
    for (var i = 0; i < all.length; i++) {
      if (all[i] && all[i].running && all[i].appId && ids.indexOf(all[i].appId) < 0) {
        ids.push(all[i].appId)
      }
    }
    if (ids.length === 0) return
    var newGroup = {
      id: "group_" + Date.now(),
      name: "Group " + (root.appGroups ? (root.appGroups.length + 1) : 1),
      icon: "folder",
      apps: ids,
      cols: 3
    }
    root.appGroups = (root.appGroups || []).concat([newGroup])
    root.saveConfig()
  }

  function createAppGroupFromDrop(root, targetAppId, draggedAppId) {
    if (!targetAppId || !draggedAppId || targetAppId === draggedAppId) return
    var targetEntry = DockModel.entryFor(root.appRows, targetAppId)
    var folderName = "Folder"
    if (targetEntry && targetEntry.name) {
      folderName = targetEntry.name + " & more"
    }

    // The group takes the place of the app it was dropped on.
    var pinsNow = root.pinnedIds || []
    var at = pinsNow.indexOf(targetAppId)
    var anchor = ""
    for (var n = at + 1; at >= 0 && n < pinsNow.length; n++) {
      if (pinsNow[n] !== targetAppId && pinsNow[n] !== draggedAppId) { anchor = pinsNow[n]; break }
    }
    var newGroup = {
      id: "group_" + Date.now(),
      name: folderName,
      icon: "folder",
      apps: [targetAppId, draggedAppId],
      cols: 3,
      before: anchor
    }
    root.appGroups = (root.appGroups || []).concat([newGroup])

    // Remove grouped items from pinnedIds so they now live inside the folder
    var pins = root.pinnedIds || []
    var nextPins = []
    for (var p = 0; p < pins.length; p++) {
      if (pins[p] !== targetAppId && pins[p] !== draggedAppId) {
        nextPins.push(pins[p])
      }
    }
    root.setPinned(nextPins)
    root.saveConfig()
  }

  function addAppToGroup(root, groupId, appId) {
    if (!groupId || !appId) return
    var groups = root.appGroups || []
    var next = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        var curApps = DockModel.toArray(g.apps)
        if (curApps.indexOf(appId) < 0) curApps.push(appId)
        next.push({ id: g.id, name: g.name, icon: g.icon, apps: curApps, cols: g.cols || 3, before: g.before || "" })
      } else {
        next.push(g)
      }
    }
    root.appGroups = next

    // Remove from pinnedIds if it was pinned
    var pins = root.pinnedIds || []
    var nextPins = []
    for (var p = 0; p < pins.length; p++) {
      if (pins[p] !== appId) nextPins.push(pins[p])
    }
    root.setPinned(nextPins)
    root.saveConfig()
  }

  function updateAppGroupName(root, groupId, newName) {
    if (!groupId || !newName) return
    var groups = root.appGroups || []
    var next = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        next.push({ id: g.id, name: newName.trim(), icon: g.icon, apps: g.apps, cols: g.cols || 3, before: g.before || "" })
      } else {
        next.push(g)
      }
    }
    root.appGroups = next
    if (root.activeAppGroupData && root.activeAppGroupData.id === groupId) {
      root.activeAppGroupData = Object.assign({}, root.activeAppGroupData, { name: newName.trim() })
    }
    root.saveConfig()
  }

  function renameAppGroup(root, groupId, newName) {
    root.updateAppGroupName(groupId, newName)
  }

  function updateAppGroupColumns(root, groupId, cols) {
    if (!groupId || !cols) return
    var groups = root.appGroups || []
    var next = []
    var c = Math.max(2, Math.min(4, cols))
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        next.push({ id: g.id, name: g.name, icon: g.icon, apps: g.apps, cols: c, before: g.before || "" })
      } else {
        next.push(g)
      }
    }
    root.appGroups = next
    if (root.activeAppGroupData && root.activeAppGroupData.id === groupId) {
      root.activeAppGroupData = Object.assign({}, root.activeAppGroupData, { cols: c })
    }
    root.saveConfig()
  }

  function removeAppFromGroup(root, groupId, appId, insertBeforeId) {
    if (!groupId || !appId) return
    var groups = root.appGroups || []
    var next = []
    var remainingApps = []

    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        var curApps = DockModel.toArray(g.apps)
        var filtered = []
        for (var a = 0; a < curApps.length; a++) {
          if (curApps[a] !== appId) filtered.push(curApps[a])
        }
        remainingApps = filtered
        if (filtered.length > 1) {
          next.push({ id: g.id, name: g.name, icon: g.icon, apps: filtered, cols: g.cols || 3, before: g.before || "" })
        }
      } else {
        next.push(g)
      }
    }
    root.appGroups = next

    var pins = (root.pinnedIds || []).slice()

    // If remaining length === 1, dissolve group: extract single remaining app into pinnedIds
    if (remainingApps.length === 1) {
      var lastApp = remainingApps[0]
      if (pins.indexOf(lastApp) < 0) {
        pins.push(lastApp)
      }
      if (root.activeAppGroupId === groupId) {
        root.closeAppGroup()
      }
    } else if (remainingApps.length === 0) {
      if (root.activeAppGroupId === groupId) {
        root.closeAppGroup()
      }
    }

    // Restore removed app to pinned items if not dragging (e.g. context menu ungroup)
    if (!root.dragSourceGroupId) {
      if (pins.indexOf(appId) < 0) {
        if (insertBeforeId) {
          var toIdx = pins.indexOf(DockModel.stripDesktop(insertBeforeId))
          if (toIdx >= 0) pins.splice(toIdx, 0, appId)
          else pins.push(appId)
        } else {
          pins.push(appId)
        }
      }
    }

    root.setPinned(pins)
    root.saveConfig()

    if (remainingApps.length > 1 && root.activeAppGroupId === groupId) {
      var foundGroup = null
      for (var j = 0; j < next.length; j++) {
        if (next[j].id === groupId) { foundGroup = next[j]; break }
      }
      if (foundGroup) root.activeAppGroupData = foundGroup
      else root.closeAppGroup()
    }
  }

  // Dissolves a group: its apps become pins where the group stood. Removing
  // a group (removeAppGroup) drops its apps from the dock instead, as
  // dragging a pin off the dock unpins it.
  function ungroupAppGroup(root, groupId) {
    if (!groupId) return
    if (root.activeAppGroupId === groupId) root.closeAppGroup()
    root.applyPinnedRow(DockModel.ungroupRow(root.pinnedRow, groupId))
  }

  function removeAppGroup(root, groupId) {
    var groups = root.appGroups || []
    var next = []
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] && groups[i].id !== groupId) {
        next.push(groups[i])
      }
    }
    root.appGroups = next
    root.saveConfig()
    if (root.activeAppGroupId === groupId) root.closeAppGroup()
  }

  // Move an app group within the pinned run, or a pinned folder among the
  // folders, so it lands before the item now at insertIndex (the end when
  // insertIndex is past the last one).
  function moveAppGroup(root, groupId, insertIndex) {
    var row = root.pinnedRow
    var from = -1
    for (var i = 0; i < row.length; i++) {
      if (row[i].kind === "group" && row[i].id === groupId) { from = i; break }
    }
    var next = DockModel.moveBefore(row, from, insertIndex)
    if (next !== row) root.applyPinnedRow(next)
  }
}
