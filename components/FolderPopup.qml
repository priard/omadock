import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The open folder stack: a fixed header (Back, folder name, entry count), a
// scrolling body and a fixed footer. The body is a list ("stack" view) or a
// grid of larger icons and previews ("grid" view), chosen per pinned folder.
// Clicking a folder steps into it; Back returns the way it came.
BorderSurface {
  id: folderStackPopover

  property var rootRef: null
  readonly property var root: rootRef
  property var targetCard: root ? (root.dockCardComp || root.dockCard) : null
  property var targetWindow: root ? root.contentItemRef : null

  readonly property bool isOpen: root ? (root.activeStackFolder !== "" && root.dockVisible) : false
  readonly property bool gridView: root ? root.activeStackView === "grid" : false
  readonly property var entries: root ? root.activeStackEntries : []
  readonly property bool canGoBack: root ? root.activeStackTrail.length > 0 : false

  visible: isOpen
  opacity: isOpen ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 120 } }

  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  readonly property real maxAllowedHeight: targetCard
    ? Math.max(240, targetCard.y - Style.space(16))
    : (parent ? (parent.height - Style.space(80)) : 500)

  // Grid geometry: up to five columns, never wider than the entries need.
  readonly property real tileWidth: Style.space(92)
  readonly property int gridColumns: Math.max(3, Math.min(5, entries.length))
  readonly property real gridWidth: gridColumns * tileWidth + (gridColumns - 1) * Style.space(4)

  // List rows size to their widest content; FileStackRow and ContextRow pick
  // this up through their parent chain.
  readonly property real rowWidth: !isOpen ? 0
    : gridView ? gridWidth
    : Math.max(root.menuContentWidth(listColumn), root.menuContentWidth(headerColumn))

  width: isOpen ? rowWidth + contentLeftInset + contentRightInset : 0
  height: isOpen
    ? Math.min(maxAllowedHeight, headerColumn.implicitHeight + bodyFlick.contentHeight + footerColumn.implicitHeight + contentTopInset + contentBottomInset + Style.space(4))
    : 0

  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.activeStackX : 0) - width / 2))

  function homePath(p) {
    return String(p || "").replace(/^~/, Quickshell.env("HOME"))
  }

  function activate(entry) {
    if (!root || !entry) return
    if (entry.isDir) {
      root.enterStackDir(entry.path, entry.name)
      return
    }
    // xdg-open hands the file to its default application. argv form: names
    // are never re-parsed by a shell.
    Util.execArgv(["uwsm-app", "--", "xdg-open", entry.path])
    root.closeFolderStack()
  }

  function dragDone(action) {
    if (action !== Qt.IgnoreAction && root) root.closeFolderStack()
  }

  // A new directory starts at the top.
  Connections {
    target: root
    function onActiveStackPathChanged() { bodyFlick.contentY = 0 }
  }

  // ---------------------------------------------------------------- header
  Column {
    id: headerColumn
    x: folderStackPopover.contentLeftInset
    y: folderStackPopover.contentTopInset
    width: folderStackPopover.rowWidth

    Item {
      readonly property bool isMenuContent: true
      implicitWidth: backButton.width + Style.space(8) + titleText.implicitWidth + Style.space(16)
      width: parent.width
      height: Math.max(Style.space(28), 28)

      Rectangle {
        id: backButton
        visible: folderStackPopover.canGoBack
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? height : 0
        height: parent.height - Style.space(4)
        radius: Style.cornerRadius
        color: backArea.containsMouse ? Color.menu.selectedBackground : "transparent"

        Text {
          anchors.centerIn: parent
          text: "‹"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }

        MouseArea {
          id: backArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root) root.stackBack()
        }
      }

      Text {
        id: titleText
        anchors.left: backButton.right
        anchors.leftMargin: folderStackPopover.canGoBack ? Style.space(4) : Style.space(8)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: ((root ? root.activeStackName : "") || "Folder")
          + ((root && root.activeStackTotalCount > 0) ? "  (" + root.activeStackTotalCount + ")" : "")
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideMiddle
      }
    }
  }

  // ------------------------------------------------------------------ body
  Flickable {
    id: bodyFlick
    anchors.left: parent.left
    anchors.leftMargin: folderStackPopover.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: folderStackPopover.contentRightInset
    anchors.top: headerColumn.bottom
    anchors.topMargin: Style.space(2)
    anchors.bottom: footerColumn.top
    anchors.bottomMargin: Style.space(2)

    contentWidth: width
    contentHeight: folderStackPopover.gridView ? grid.implicitHeight : listColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    // Wheel only: drag-flicking would steal the press that starts a drag out.
    interactive: false

    WheelHandler {
      target: null
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        var dy = event.pixelDelta.y !== 0
          ? -event.pixelDelta.y
          : -event.angleDelta.y / 120 * Style.space(40)
        if (dy === 0) return
        var maxY = Math.max(0, bodyFlick.contentHeight - bodyFlick.height)
        bodyFlick.contentY = Math.max(0, Math.min(maxY, bodyFlick.contentY + dy))
      }
    }

    Column {
      id: listColumn
      visible: !folderStackPopover.gridView
      width: parent.width
      spacing: Style.space(2)

      Text {
        visible: folderStackPopover.entries.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Folder is empty"
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        padding: Style.space(8)
      }

      Repeater {
        model: folderStackPopover.gridView ? [] : folderStackPopover.entries
        delegate: FileStackRow {
          name: modelData.name
          path: modelData.path
          icon: modelData.icon
          subtext: modelData.isDir ? "›" : modelData.size
          themeVersion: root ? root.themeVersion : 0
          currentIconThemeName: root ? root.currentIconThemeName : "Yaru"
          folderColor: root ? root.folderColor : "theme"
          appLibrary: root ? root.appLibrary : null
          onTriggered: folderStackPopover.activate(modelData)
          onDragFinished: function(action) { folderStackPopover.dragDone(action) }
        }
      }
    }

    Grid {
      id: grid
      visible: folderStackPopover.gridView
      columns: folderStackPopover.gridColumns
      spacing: Style.space(4)

      Repeater {
        model: folderStackPopover.gridView ? folderStackPopover.entries : []
        delegate: FileTile {
          width: folderStackPopover.tileWidth
          name: modelData.name
          path: modelData.path
          icon: modelData.icon
          thumb: modelData.thumb || ""
          isDir: modelData.isDir
          themeVersion: root ? root.themeVersion : 0
          currentIconThemeName: root ? root.currentIconThemeName : "Yaru"
          folderColor: root ? root.folderColor : "theme"
          appLibrary: root ? root.appLibrary : null
          onTriggered: folderStackPopover.activate(modelData)
          onDragFinished: function(action) { folderStackPopover.dragDone(action) }
        }
      }
    }

    Text {
      visible: folderStackPopover.gridView && folderStackPopover.entries.length === 0
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Folder is empty"
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      padding: Style.space(8)
    }
  }

  // ---------------------------------------------------------------- footer
  Column {
    id: footerColumn
    x: folderStackPopover.contentLeftInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: folderStackPopover.contentBottomInset
    width: folderStackPopover.rowWidth
    spacing: Style.space(2)

    MenuDivider {}

    // The listing is capped (scripts/list-folder.py); say so instead of
    // silently truncating.
    ContextRow {
      visible: root ? (root.activeStackTotalCount > root.activeStackEntries.length) : false
      text: "+ " + (root ? (root.activeStackTotalCount - root.activeStackEntries.length) : 0) + " more — open in File Manager"
      onTriggered: {
        if (!root) return
        Util.execArgv(["uwsm-app", "--", "xdg-open", root.activeStackPath])
        root.closeFolderStack()
      }
    }

    ContextRow {
      text: "Open in File Manager"
      onTriggered: {
        if (!root) return
        Util.execArgv(["uwsm-app", "--", "xdg-open", root.activeStackPath])
        root.closeFolderStack()
      }
    }
  }
}
