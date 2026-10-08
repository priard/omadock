import QtQuick
import qs.Commons
import qs.Ui
import "../DockLabels.js" as DockLabels

// The plate an unlabelled tile (the Omarchy button) wears when
// always-on labels use plates, so the row reads as one set of buttons.
// Same fill, corners, margins and height mode as the label plates
// (DockLabel); it lifts with the tile's art. ink is what the tile should
// draw its glyph in to read on the plate.
Rectangle {
  id: plate

  property var rootRef: null
  readonly property var root: rootRef
  property Item tile: parent
  property bool hovered: false

  readonly property var style: root ? root.labelStyle("app") : null
  readonly property color ink: style ? style.ink : Color.bar.text
  readonly property real art: root ? root.baseIconArt : 28
  readonly property real artTop: (root && tile) ? tile.height - root.iconArtBottom - art : 0
  readonly property real vMargin: Style.space(4)
  readonly property var spacing: root ? root.plateSpacing : null

  property real level: plate.hovered ? 1 : 0
  Behavior on level { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  visible: !!root && root.labelPlates
  x: spacing ? spacing.inset : 0
  width: tile ? tile.width - 2 * x : 0
  // The same vertical box as the label plates (DockLabelLogic.plateBox).
  readonly property var box: (root && tile) ? root.labelPlateBox(tile.height) : null
  y: box ? box.y : artTop - vMargin
  height: box ? box.h : art + vMargin * 2
  radius: style ? Math.min(height * 0.32, DockLabels.labelRadius(style.shape, height, style.dockRatio)) : 0
  color: root ? Util.alpha(root.labelFillFor(ink, false), 0.55 + 0.25 * level) : "transparent"
  transform: Translate { y: (plate.root && plate.root.hoverEffect === "lift") ? -plate.art * 0.16 * plate.level : 0 }
}
