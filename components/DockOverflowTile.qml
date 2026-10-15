import QtQuick 6.11
import qs.Commons
import qs.Ui

// "»": the end of a row that did not fit (DockFit.js). It stands for the
// items the dock's fit moved into the overflow popup (DockFitHost).
Item {
  id: tile
  property var rootRef: null
  readonly property var root: rootRef
  readonly property var fit: tile.root ? tile.root.fitHostRef : null
  readonly property int count: tile.fit ? tile.fit.hiddenItems.length : 0

  width: tile.root ? tile.root.iconSlot : 0
  height: tile.root ? tile.root.iconSlot : 0

  // A plate of its own in a plate row (TilePlate), like the Omarchy button.
  // Its place among the plates (DockCard.plateEdges): after every labelled item.
  readonly property int plateSlot: tile.fit ? tile.fit.shown.button + tile.fit.shown.pinned + tile.fit.shown.running + tile.fit.shown.folders : 0
  TilePlate { id: plate; rootRef: tile.rootRef; hovered: area.containsMouse; slot: tile.plateSlot }

  Text {
    id: glyph
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: tile.root ? tile.root.iconArtBottom : 0
    width: tile.root ? tile.root.baseIconArt : 28
    height: width
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: "»"
    textFormat: Text.PlainText
    color: tile.root ? (plate.visible ? plate.ink : tile.root.dockForeground) : Color.bar.text
    font.family: Style.font.family
    font.pixelSize: Math.round(width * 0.7)
    font.bold: true
    scale: area.pressed ? 0.92 : 1
    transformOrigin: Item.Bottom
  }

  // The badge the hidden items would carry, summed.
  BadgeMark {
    rootRef: tile.rootRef
    anchorRef: glyph
    count: tile.fit ? tile.fit.hiddenState.badges : 0
    rim: Color.bar.background
  }

  // A mark when a hidden app has windows; urgent when one asks for attention.
  DockIndicator {
    rootRef: tile.rootRef
    visible: !!tile.fit && (tile.fit.hiddenState.windows || tile.fit.hiddenState.urgent)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1) + (tile.root ? tile.root.indicatorLift : 0)
    kind: "window"
    urgent: !!tile.fit && tile.fit.hiddenState.urgent
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      var w = tile.root ? tile.root.contentItemRef : null
      var p = w ? tile.mapToItem(w, tile.width / 2, 0) : null
      if (tile.fit && p && typeof tile.fit.openOverflow === "function") tile.fit.openOverflow(p.x)
    }
  }

  HoverTooltip {
    dockRoot: tile.root
    text: tile.count + " more"
    hovered: area.containsMouse
    blocked: !tile.root || !tile.root.showTooltips
    showTooltips: tile.root ? tile.root.showTooltips : true
    tooltipDelay: tile.root ? tile.root.tooltipDelay : 450
    contextAppId: tile.root ? tile.root.contextAppId : ""
  }
}
