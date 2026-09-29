import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

BorderSurface {
  id: contextMenu

  property var rootRef: null
  readonly property var root: rootRef
  property var targetCard: root ? (root.dockCardComp || root.dockCard) : null
  property var targetWindow: root ? root.contentItemRef : null

  property alias appContextMenuColumn: appContextMenuColumn

  visible: root ? (root.contextAppId !== "") : false
  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  readonly property real rowWidth: (root && root.contextAppId !== "")
    ? root.menuContentWidth(menuColumn)
    : 0

  width: (root && root.contextAppId !== "")
    ? rowWidth + contentLeftInset + contentRightInset
    : 0
  height: (root && root.contextAppId !== "")
    ? Math.min(540, menuColumn.implicitHeight + contentTopInset + contentBottomInset)
    : 0

  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.contextX : 0) - width / 2))

  onVisibleChanged: {
    if (!visible) menuFlickable.contentY = 0
  }

  Connections {
    target: root
    function onContextAppIdChanged() { menuFlickable.contentY = 0 }
  }

  Flickable {
    id: menuFlickable
    anchors.left: parent.left
    anchors.leftMargin: contextMenu.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: contextMenu.contentRightInset
    anchors.top: parent.top
    anchors.topMargin: contextMenu.contentTopInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: contextMenu.contentBottomInset

    contentWidth: width
    contentHeight: menuColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    WheelHandler {
      target: menuFlickable
      onWheel: function(event) {
        if (event.angleDelta.y === 0) return
        var step = Style.space(32)
        var dy = event.angleDelta.y > 0 ? -step : step
        menuFlickable.contentY = Math.max(0, Math.min(menuFlickable.contentHeight - menuFlickable.height, menuFlickable.contentY + dy))
      }
    }

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(2)

    // Dock menu (right-click on the Omarchy button or the dock background):
    // quick toggles plus the way into the full settings panel, which holds
    // every option the old category pages used to carry.
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__dock_settings__" : false

      ContextRow {
        text: "Omadock"
        isHeader: true
      }

      ContextRow {
        text: "Dock Settings…"
        textColor: Color.accent
        onTriggered: { if (root) root.openSettingsPanel() }
      }

      MenuDivider {}

      ContextRow {
        text: "Autohide"
        checked: root ? root.autohide : false
        onTriggered: { if (root) root.setAutohideMode(root.autohide ? "always" : "intelligent") }
      }

      ContextRow {
        text: "Create Group from Running Apps"
        onTriggered: {
          if (root) {
            root.createAppGroupFromRunning()
            root.closeContext()
          }
        }
      }
    }

    // Folder Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__folder_context__" : false

      ContextRow {
        text: (root ? root.contextFolderName : "") || "Folder"
        isHeader: true
      }

      ContextRow {
        text: "Open in File Manager"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.contextFolderPath.replace(/^~/, Quickshell.env("HOME"))))
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Open in Terminal"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- xdg-terminal-exec --dir=" + Util.shellQuote(root.contextFolderPath.replace(/^~/, Quickshell.env("HOME"))))
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: "Unpin from Dock"
        danger: true
        onTriggered: {
          if (root) {
            root.toggleFolderPin(root.contextFolderPath, root.contextFolderName, "")
            root.closeContext()
          }
        }
      }
    }

    // Minimized Window Tile Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__tile_context__" : false

      ContextRow {
        text: (root && root.contextTileName !== "") ? root.contextTileName : ((root && root.contextTileAppId !== "") ? root.contextTileAppId : "Window")
        isHeader: true
      }

      ContextRow {
        text: (root && root.contextTileWins.length > 1) ? "Restore All Here" : "Restore Here"
        onTriggered: {
          if (root) {
            root.restoreContextTile()
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: (root && root.contextTileWins.length > 1) ? "Restore All to Original" : "Restore to Original"
        onTriggered: {
          if (root) {
            root.restoreContextTileOriginal()
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: (root && root.contextTilePinned) ? "Unpin from Dock" : "Pin to Dock"
        onTriggered: {
          if (root) {
            root.togglePin(root.contextTileAppId)
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: (root && root.contextTileWins.length > 1) ? "Close All" : "Close"
        danger: true
        onTriggered: {
          if (root) {
            root.closeContextTile()
            root.closeContext()
          }
        }
      }
    }

    // Removable Drive Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__drive_context__" : false

      ContextRow {
        text: (root ? root.contextDriveName : "") || "USB Drive"
        isHeader: true
      }

      ContextRow {
        text: root ? (root.contextDriveSpace !== "" ? root.contextDriveSpace : root.contextDriveMount) : ""
        textColor: Util.alpha(Color.menu.text, 0.6)
        isHeader: true
        visible: text !== ""
      }

      MenuDivider {}

      ContextRow {
        text: "Open in File Manager"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.contextDriveMount))
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Open in Terminal"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- omarchy-terminal -d " + Util.shellQuote(root.contextDriveMount))
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Copy Mount Path"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- wl-copy " + Util.shellQuote(root.contextDriveMount))
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: "Safely Eject / Unmount"
        textColor: Color.urgent || Color.accent
        onTriggered: {
          if (root) {
            root.ejectDrive(root.contextDriveDev, root.contextDriveMount, root.contextDriveName)
          }
        }
      }
    }

    // App Group Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__app_group_context__" : false

      ContextRow {
        text: (root && root.contextAppGroupData) ? root.contextAppGroupData.name : "App Group"
        isHeader: true
      }

      ContextRow {
        text: (root && root.contextAppGroupData && root.contextAppGroupData.apps) ? (root.contextAppGroupData.apps.length + " Apps") : ""
        textColor: Util.alpha(Color.menu.text, 0.6)
        isHeader: true
        visible: text !== ""
      }

      MenuDivider {}

      ContextRow {
        text: "Open Group Grid"
        onTriggered: {
          if (root && root.contextAppGroupData) {
            root.openAppGroup(root.contextAppGroupData, root.contextX, root.contextY)
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Ungroup / Remove Group"
        danger: true
        onTriggered: {
          if (root && root.contextAppGroupData) {
            root.removeAppGroup(root.contextAppGroupData.id)
            root.closeContext()
          }
        }
      }
    }

    // Regular App Context Menu
    Item {
      id: appContextMenuWrapper
      visible: root ? (root.contextAppId !== "" && root.contextAppId !== "__dock_settings__" && root.contextAppId !== "__folder_context__" && root.contextAppId !== "__tile_context__" && root.contextAppId !== "__drive_context__" && root.contextAppId !== "__app_group_context__") : false
      implicitWidth: appContextMenuColumn.implicitWidth
      implicitHeight: appContextMenuColumn.implicitHeight
      width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
      height: appContextMenuColumn.implicitHeight

      Column {
        id: appContextMenuColumn
        spacing: Style.space(2)
        width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth

        property int selectedWindowIdx: -1

        // 1. Multi-window / Active Window instance list
        Column {
          id: windowListSection
          spacing: Style.space(1)
          visible: root ? (root.contextWindowList.length > 0) : false

          ContextRow {
            text: (root && root.contextWindowList.length > 1)
              ? ("Windows (" + root.contextWindowList.length + ")")
              : "Active Window"
            isHeader: true
          }

          Repeater {
            model: root ? root.contextWindowList.slice(0, 8) : []
            delegate: ContextRow {
              text: root ? root.windowRowLabel(modelData) : ""
              isWindowRow: true
              winFocused: root ? root.isWindowFocused(modelData) : false
              winParked: root ? root.isWindowParked(modelData) : false
              checked: appContextMenuColumn.selectedWindowIdx === index

              onTriggered: {
                if (modelData && modelData.address && root) {
                  root.focusWindowByAddress(modelData.address, root.contextAppId)
                }
                if (root) root.closeContext()
              }
            }
          }

          ContextRow {
            visible: root ? (root.contextWindowList.length > 8) : false
            text: "+ " + (root ? (root.contextWindowList.length - 8) : 0) + " more windows"
            isHeader: true
          }

          MenuDivider {}
        }

        // 2. Native Desktop Actions / Jump List
        Column {
          spacing: Style.space(1)
          visible: root ? (root.contextDesktopActions.length > 0) : false

          Repeater {
            model: root ? root.contextDesktopActions : []
            delegate: ContextRow {
              text: modelData.name || modelData.id
              onTriggered: {
                if (root) {
                  root.launchDesktopAction(modelData, root.contextName)
                  root.closeContext()
                }
              }
            }
          }

          MenuDivider {}
        }

        // Fallback Default Action Row when no custom desktop actions exist
        ContextRow {
          text: (root && root.contextWindows > 0) ? "New Window" : "Launch"
          visible: root ? (root.contextDesktopActions.length === 0) : true
          onTriggered: {
            if (root) {
              root.launchApp(root.contextAppId, null)
              root.closeContext()
            }
          }
        }

        // 3. Window & Dock Management
        ContextRow {
          text: "Minimize Window"
          visible: root ? (root.minimizeMode !== "off" && root.contextWindows > 1) : false
          onTriggered: {
            if (root) {
              root.minimizeOneWindow(root.entryForId(root.contextAppId))
              root.closeContext()
            }
          }
        }

        ContextRow {
          text: (root && root.contextPinned) ? "Unpin from Dock" : "Pin to Dock"
          onTriggered: {
            if (root) {
              var deskEntry = DockModel.entryFor(root.appRows, root.contextAppId)
              if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
                deskEntry = DesktopEntries.heuristicLookup(root.contextAppId) || DesktopEntries.byId(root.contextAppId)
              }
              var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : root.contextAppId
              root.togglePin(canonicalId)
              root.closeContext()
            }
          }
        }

        ContextRow {
          text: (root && root.contextWindows > 1) ? "Close All Windows" : "Close Window"
          visible: root ? (root.contextWindows > 0) : false
          danger: true
          onTriggered: {
            if (root) {
              DockModel.closeApp((ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []), root.contextAppId)
              root.closeContext()
            }
          }
        }
      }

      // Wheel-scroll overlay to cycle window selection
      MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          if (!root || wheel.angleDelta.y === 0 || root.contextWindowList.length <= 1) return
          var dir = wheel.angleDelta.y > 0 ? -1 : 1
          var len = root.contextWindowList.length
          if (appContextMenuColumn.selectedWindowIdx < 0) {
            var cur = 0
            for (var c = 0; c < len; c++) {
              if (root.isWindowFocused(root.contextWindowList[c])) { cur = c; break }
            }
            appContextMenuColumn.selectedWindowIdx = (cur + dir + len) % len
          } else {
            appContextMenuColumn.selectedWindowIdx = (appContextMenuColumn.selectedWindowIdx + dir + len) % len
          }
        }
      }
    }
  }
}
}
