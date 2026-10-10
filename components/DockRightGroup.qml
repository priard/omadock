import QtQuick
import qs.Commons
import qs.Ui
import "../DockIcons.js" as DockIcons

// Folders, command buttons and drives: the right group of the dock's row
// (DockCard), its own Row so the Both sides gap before it can be sized from
// its width without the outer row measuring itself.
Row {
  property var rootRef: null
  readonly property var root: rootRef
  // The card (dividers' geometry), its wrapper (drag handlers, drop lines,
  // the Both sides shift) and the outer row (spacing, y).
  property var cardRef: null
  property var wrapper: null
  property var outerRow: null
  property alias folderSeparator: folderSeparator
  property alias driveSeparator: driveSeparator
  property alias foldersRepeater: foldersRepeater
  property alias drivesRepeater: drivesRepeater
  property alias trailingDropGap: trailingDropGap
  id: group
  spacing: group.outerRow.spacing
  anchors.verticalCenter: parent.verticalCenter
  visible: root ? (root.hasFolderSeparator || root.folderSlots > 0 || root.driveSlots > 0 || trailingDropGap.open) : true

  Item {
    id: folderSeparator
    visible: root ? root.hasFolderSeparator : false
    anchors.verticalCenter: parent.verticalCenter
    width: root ? root.separatorWidth : Style.space(1)
    height: root ? (root.iconSize * 0.7) : 24

    // The line, placed by dockCard (70% of its height by default, as on
    // macOS). It overflows the slot, so it does not grow the row. With
    // split sections the slot is the gap between two panels and no line
    // is drawn.
    Rectangle {
      visible: !(root && (root.placement.split || root.placement.align === "spread"))
      anchors.horizontalCenter: parent.horizontalCenter
      y: root && root.dividerGeometry === "long"
        ? group.cardRef.dividerTop - group.outerRow.y - group.y - parent.y : (root ? root.iconCenterOffset : 0)
      width: group.cardRef.dividerWidth
      height: root && root.dividerGeometry === "long" ? group.cardRef.dividerLength : parent.height
      color: root ? root.dividerLineColor : Util.alpha(Color.bar.text, 0.25)
    }
  }

  Repeater {
    id: foldersRepeater
    // Folders first, then the command buttons: the section keeps one row.
    model: root ? root.pinnedFolders.concat(root.pinnedButtons) : []
    delegate: DockFolderItem {
      rootRef: group.wrapper.rootRef
      folderPath: modelData.path || ""
      command: modelData.command || ""
      name: modelData.name || "Folder"
      icon: modelData.icon || (modelData.command ? "application-x-executable" : DockIcons.folderIconFor(modelData.path, ""))
      slotIndex: index
      dropLineHere: group.wrapper.dropLineFolder === index
      homeCenter: root ? root.slotHomeCenter(
        root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + index,
        root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + index,
        (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0),
        root.tilesFixedWidth + group.wrapper.spreadShift) : 0
      labelSlot: root ? root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + index : -1
      onOpenStackRequested: function(fpath, fname, cx, cy) {
        if (root) root.openFolderStack(fpath, fname, cx)
      }
      onMenuRequested: function(fpath, fname, cx, cy, cmd) {
        if (root) root.openFolderContext(fpath, fname, cx, cy, cmd)
      }
      onDragStarted: function(fpath) { group.wrapper.handleFolderDragStarted(fpath) }
      onDragMoved: function(fpath, mx, my) { group.wrapper.handleFolderDragMoved(fpath, mx, my) }
      onDragDropped: function(fpath) { group.wrapper.handleFolderDragDropped(fpath) }
    }
  }

  // A folder dragged after the last one.
  DropGap {
    rootRef: group.wrapper.rootRef
    spacer: true
    open: group.wrapper.dropLineFolder >= 0 && group.wrapper.dropLineFolder === foldersRepeater.count
  }

  // Drop gap after the last pinned folder (see DockFolderItem.gapWidth).
  DropGhost {
    id: trailingDropGap
    rootRef: group.wrapper.rootRef
    readonly property bool open: root ? (root.dropPreviewPath !== "" && root.dropInsertIndex >= foldersRepeater.count) : false
    width: open && root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }

  Item {
    id: driveSeparator
    visible: root ? root.hasDriveSeparator : false
    anchors.verticalCenter: parent.verticalCenter
    width: root ? root.separatorWidth : Style.space(1)
    height: root ? (root.iconSize * 0.7) : 24

    // The line, placed by dockCard (70% of its height by default, as on
    // macOS). It overflows the slot, so it does not grow the row. With
    // split sections the slot is the gap between two panels and no line
    // is drawn.
    Rectangle {
      visible: !(root && root.placement.split)
      anchors.horizontalCenter: parent.horizontalCenter
      y: root && root.dividerGeometry === "long"
        ? group.cardRef.dividerTop - group.outerRow.y - group.y - parent.y : (root ? root.iconCenterOffset : 0)
      width: group.cardRef.dividerWidth
      height: root && root.dividerGeometry === "long" ? group.cardRef.dividerLength : parent.height
      color: root ? root.dividerLineColor : Util.alpha(Color.bar.text, 0.25)
    }
  }

  Repeater {
    id: drivesRepeater
    model: (root && root.showRemovableDrives) ? root.mountedDrives : []
    delegate: DockDriveItem {
      rootRef: group.wrapper.rootRef
      dev: modelData.dev || ""
      mountpoint: modelData.mountpoint || ""
      name: modelData.name || "USB Drive"
      size: modelData.size || ""
      space: modelData.space || ""
      fstype: modelData.fstype || ""
      icon: modelData.icon || "drive-removable-media"
      homeCenter: root ? root.slotHomeCenter(
        root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + root.folderSlots + (root.hasDriveSeparator ? 1 : 0) + index,
        root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + root.folderSlots + index,
        (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0) + (root.hasDriveSeparator ? 1 : 0),
        root.tilesFixedWidth + group.wrapper.spreadShift) : 0
      onOpenStackRequested: function(fpath, fname, cx, cy) {
        if (root) root.openFolderStack(fpath, fname, cx)
      }
      onMenuRequested: function(d, mp, n, s, cx, cy) {
        if (root) root.openDriveContext(d, mp, n, s, cx, cy)
      }
    }
  }
}
