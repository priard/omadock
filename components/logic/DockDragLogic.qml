import QtQuick
import Quickshell
import qs.Commons
import "../../DockModel.js" as DockModel

// Logic extracted from DockCard.qml: stateless functions taking the
// dock root and the card wrapper. Bodies are verbatim.

QtObject {
  // Insert index among the pinned folders for a pointer at row x: before the
  // first folder whose icon centre lies right of it. The icon sits right of
  // any open gap, so moving through the gap keeps the same index.
  // The folder section of the row: from the folder divider on, or, with no
  // divider (no folders or drives yet, or nothing before them), the last
  // three quarters of a slot at the end of the row and beyond.
  function inPinZone(root, card, px) {
    if (card.folderSeparatorRef.visible) return px >= card.folderSeparatorRef.x - (root ? root.gapWidth : 0)
    if (card.foldersRepeater.count > 0) {
      var first = card.foldersRepeater.itemAt(0)
      if (first) return px >= first.x
    }
    return px >= card.row.width - (root ? root.iconSlot * 0.75 : 0)
  }

  function folderInsertIndex(root, card, px) {
    var n = card.foldersRepeater ? card.foldersRepeater.count : 0
    for (var i = 0; i < n; i++) {
      var it = card.foldersRepeater.itemAt(i)
      if (!it) continue
      var iconCenter = it.x + (it.iconCenterX !== undefined ? it.iconCenterX : it.width - (root ? root.iconSlot : it.width) / 2)
      if (px < iconCenter) return i
    }
    return n
  }

  // A drag pulled this far above the card takes the item off the dock.
  function offDockAt(root, card, my) {
    return root ? my < -(root.iconSlot * 0.75) : false
  }

  // Over the running apps that are not pinned: from the divider before
  // them to the gap after the last one.
  function overRunningAt(root, card, rx) {
    var n = card.runningRepeater.count
    var first = n > 0 ? card.runningRepeater.itemAt(0) : null
    var last = n > 0 ? card.runningRepeater.itemAt(n - 1) : null
    if (!first || !last) return false
    var start = card.separatorRef.visible ? card.separatorRef.x : first.x - card.row.spacing / 2
    return rx >= start && rx <= last.x + last.width + card.row.spacing / 2
  }

  function handleDragMoved(root, card, aid, mx, my) {
    if (!root) return
    root.dropBeforeId = ""
    root.dropTargetAppId = ""
    root.dropTargetGroupId = ""
    root.dragPointerX = mx
    root.dragPointerY = my

    // Only a pin can be taken off, by pulling it up off the dock or over to
    // the running apps; a running app that is not pinned stays.
    root.dragRemoveArmed = root.dragSourceGroupId === "" && DockModel.isPinned(root.pinnedIds, aid)
      && (cardWrapper.offDockAt(my) || cardWrapper.overRunningAt(mx - card.row.x))
    if (root.dragRemoveArmed) return

    // Over the middle of a group: add to it. Over the middle of another
    // pinned app: make a group of the two. Otherwise a place in the run.
    var rx = mx - card.row.x
    var n = card.pinnedRowRepeater.count
    for (var i = 0; i < n; i++) {
      var slot = card.pinnedRowRepeater.itemAt(i)
      var it = slot ? slot.item : null
      if (!it) continue
      var extra = it.labelExtra || 0
      var centre = slot.x + (it.iconCenterX !== undefined ? it.iconCenterX : slot.width / 2)
      var span = slot.width - extra
      if (slot.isGroup) {
        if (Math.abs(rx - centre) < span * 0.45) {
          root.dropTargetGroupId = it.groupId
          root.dropRowIndex = -1
          return
        }
      } else if (it.appId !== aid && Math.abs(rx - centre) < span * 0.38) {
        root.dropTargetAppId = it.appId
        root.dropRowIndex = -1
        return
      }
    }

    var idx = cardWrapper.rowInsertIndex(rx)
    // Past the end of the run, a running app that is not pinned lands after
    // the last item only while the pointer stays next to it: further right
    // it is over the running apps, its own place, where letting go does
    // nothing.
    if (idx === n && !DockModel.isPinned(root.pinnedIds, aid)) {
      var last = card.pinnedRowRepeater.itemAt(n - 1)
      if (!last || rx > last.x + last.width + root.iconSlot / 2) idx = -1
    }
    root.dropRowIndex = idx
    if (idx < 0) return
    root.dropIndicatorX = cardWrapper.rowIndicatorX(idx)
    // The first app at or after the drop, for moves that work in pin order.
    for (var j = idx; j < n; j++) {
      var s2 = card.pinnedRowRepeater.itemAt(j)
      if (s2 && !s2.isGroup && s2.item && s2.item.appId !== aid) {
        root.dropBeforeId = s2.item.appId
        break
      }
    }
  }

  // Insert index in the pinned run for a pointer at row x: before the first
  // item whose centre lies right of it, so past the end of the run (over the
  // running apps, say) means its end. -1 when the run is empty.
  function rowInsertIndex(root, card, rx) {
    var n = card.pinnedRowRepeater.count
    if (n === 0) return -1
    for (var i = 0; i < n; i++) {
      var slot = card.pinnedRowRepeater.itemAt(i)
      var it = slot ? slot.item : null
      if (slot && rx < slot.x + (it && it.iconCenterX !== undefined ? it.iconCenterX : slot.width / 2)) return i
    }
    return n
  }

  function rowIndicatorX(root, card, idx) {
    var n = card.pinnedRowRepeater.count
    if (idx < n) return card.row.x + card.pinnedRowRepeater.itemAt(idx).x - card.row.spacing / 2 - Style.space(1)
    var last = card.pinnedRowRepeater.itemAt(n - 1)
    return card.row.x + last.x + last.width + card.row.spacing / 2 - Style.space(1)
  }

  function handleDragDropped(root, card, aid) {
    if (!root) return
    var dragId = root.dragAppId
    var targetGroupId = root.dropTargetGroupId
    var targetAppId = root.dropTargetAppId
    var beforeId = root.dropBeforeId
    var sourceGroupId = root.dragSourceGroupId
    var removeArmed = root.dragRemoveArmed
    var rowIdx = root.dropRowIndex

    root.dragAppId = ""
    root.dropBeforeId = ""
    root.dropTargetGroupId = ""
    root.dropTargetAppId = ""
    root.dropRowIndex = -1
    root.dragRemoveArmed = false

    if (dragId !== "" && removeArmed) {
      root.dragSourceGroupId = ""
      root.togglePin(dragId)
    } else if (dragId !== "") {
      if (sourceGroupId !== "") {
        if (targetGroupId === sourceGroupId) {
          root.dragSourceGroupId = ""
          root.syncVisibility()
          return
        }
        root.removeAppFromGroup(sourceGroupId, dragId)
      }

      if (targetGroupId !== "") {
        root.addAppToGroup(targetGroupId, dragId)
      } else if (targetAppId !== "" && targetAppId !== dragId) {
        root.createAppGroupFromDrop(targetAppId, dragId)
      } else {
        var rowNow = root.pinnedRow
        if (sourceGroupId !== "") {
          // Out of an open group: the group has just changed under the drag,
          // so place the app by pin order alone.
          root.setPinned(DockModel.reorderPinned(root.pinnedIds, dragId, beforeId))
        } else if (rowIdx >= 0) {
          // A pinned app moves within the run; a running one dropped in it
          // gets pinned there. Groups keep their places.
          var from = -1
          for (var r = 0; r < rowNow.length; r++) {
            if (rowNow[r].kind === "app" && rowNow[r].appId === dragId) { from = r; break }
          }
          var nextRow
          if (from >= 0) {
            nextRow = DockModel.moveBefore(rowNow, from, rowIdx)
          } else {
            nextRow = rowNow.slice()
            nextRow.splice(rowIdx, 0, { kind: "app", appId: dragId })
          }
          if (nextRow !== rowNow) root.applyPinnedRow(nextRow)
        }
      }
      root.dragSourceGroupId = ""
    } else {
      root.dragSourceGroupId = ""
    }
    root.syncVisibility()
  }

  function handleFolderDragStarted(root, card, path) {
    if (!root) return
    root.dragFolderPath = path
    root.dropFolderIndex = -1
    root.dragRemoveArmed = false
  }

  // Reorders within the folder section: from the gap before the first
  // folder to the gap after the last one.
  function handleFolderDragMoved(root, card, path, mx, my) {
    if (!root) return
    root.dragPointerX = mx
    root.dragPointerY = my
    root.dragRemoveArmed = cardWrapper.offDockAt(my)
    var n = card.foldersRepeater.count
    var first = n > 0 ? card.foldersRepeater.itemAt(0) : null
    var last = n > 0 ? card.foldersRepeater.itemAt(n - 1) : null
    var rx = mx - card.row.x
    if (root.dragRemoveArmed || !first || !last
        || rx < first.x - card.row.spacing || rx > last.x + last.width + card.row.spacing) {
      root.dropFolderIndex = -1
      return
    }
    var idx = cardWrapper.folderInsertIndex(rx)
    root.dropFolderIndex = idx
    root.dropIndicatorX = idx < n
      ? card.row.x + card.foldersRepeater.itemAt(idx).x - card.row.spacing / 2 - Style.space(1)
      : card.row.x + last.x + last.width + card.row.spacing / 2 - Style.space(1)
  }

  function handleFolderDragDropped(root, card, path) {
    if (!root) return
    var removeArmed = root.dragRemoveArmed
    var idx = root.dropFolderIndex
    root.dragFolderPath = ""
    root.dropFolderIndex = -1
    root.dragRemoveArmed = false
    if (removeArmed) root.toggleFolderPin(path, "", "")
    else if (idx >= 0) root.moveFolder(path, idx)
    root.syncVisibility()
  }

  // App groups move anywhere in the pinned run, among the pinned apps; an
  // accent line marks where the group lands.
  function handleGroupDragStarted(root, card, gid) {
    if (!root) return
    root.dragGroupId = gid
    root.dropRowIndex = -1
    root.dragRemoveArmed = false
  }

  function handleGroupDragMoved(root, card, gid, mx, my) {
    if (!root) return
    root.dragPointerX = mx
    root.dragPointerY = my
    root.dragRemoveArmed = cardWrapper.offDockAt(my)
    var idx = root.dragRemoveArmed ? -1 : cardWrapper.rowInsertIndex(mx - card.row.x)
    root.dropRowIndex = idx
    if (idx >= 0) root.dropIndicatorX = cardWrapper.rowIndicatorX(idx)
  }

  function handleGroupDragDropped(root, card, gid) {
    if (!root) return
    var removeArmed = root.dragRemoveArmed
    var idx = root.dropRowIndex
    root.dragGroupId = ""
    root.dropRowIndex = -1
    root.dragRemoveArmed = false
    if (removeArmed) root.removeAppGroup(gid)
    else if (idx >= 0) root.moveAppGroup(gid, idx)
    root.syncVisibility()
  }
}
