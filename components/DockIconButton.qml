import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockLabels.js" as DockLabels

Item {
  id: btn

  property var rootRef: null
  readonly property var root: rootRef
  property var dockCard: root ? root.dockCard : null

  property string glyph: ""
  property string tooltip: ""
  property color glyphColor: root ? root.dockForeground : Color.bar.text
  // Share of the icon box the glyph's larger side fills.
  property real glyphFill: 0.62
  signal pressed()
  signal middleClicked()
  signal menuRequested(real x, real y)

  property real homeCenter: 0
  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(btn.homeCenter)
    if (root.hoverEffect !== "zoom") return 1
    return area.containsMouse ? root.zoomPeak : 1
  }

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  width: root ? (root.iconSlot * (root.waveHover ? btn.magnifyScale : 1)) : 0
  height: root ? root.iconSlot : 0

  // Same artwork box as the app icons: sits on the icon line above the
  // indicator band and grows upward. The glyph is sized and centred by its
  // painted (tight) bounds, since icon fonts carry uneven side bearings and
  // sit low in their line box.
  // Drawn through DockIconArt so the dock's icon style (pixel, dot matrix…)
  // and icon shadow apply to the button like to every other icon.
  // With always-on plate labels the button wears a plate of its own (no
  // name), so the row reads as one set of buttons. Same fill, corners and
  // margins as the label plates (DockLabel); it lifts with the glyph.
  Rectangle {
    id: buttonPlate
    readonly property var style: root ? root.labelStyle("app") : null
    readonly property real art: root ? root.baseIconArt : 28
    readonly property real artTop: root ? btn.height - root.iconArtBottom - art : 0
    readonly property real vMargin: Style.space(4)
    property real level: area.containsMouse ? 1 : 0
    Behavior on level { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    visible: !!root && root.labelMode === "always" && root.labelBackground === "plate"
    x: 0
    width: btn.width - Style.space(1)
    y: artTop - vMargin
    height: art + vMargin * 2
    radius: style ? Math.min(height * 0.32, DockLabels.labelRadius(style.shape, height, style.dockRatio)) : 0
    color: style ? Util.alpha(style.fill, 0.55 + 0.25 * level) : "transparent"
    transform: Translate { y: (root && root.hoverEffect === "lift") ? -buttonPlate.art * 0.16 * buttonPlate.level : 0 }
  }

  DockIconArt {
    id: glyphBox
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root ? root.iconArtBottom : 0
    width: root ? root.baseIconArt : 28
    height: width
    scale: btn.magnifyScale * (area.pressed ? 0.92 : 1.0)
    transformOrigin: Item.Bottom
    iconStyle: root ? root.iconStyle : "original"
    tint: root ? root.iconTintColor : Color.bar.text
    grid: root ? root.iconGrid : 16
    outputScale: root ? root.outputScale : 1
    contrast: root ? root.iconContrast : 0
    strength: root ? root.iconStrength : 1
    dropShadow: root ? root.iconShadow : false
    shadowStrength: root ? root.shadowStrength : 0.4
    showOriginal: root ? (root.iconHoverOriginal && area.containsMouse) : false
    hovered: area.containsMouse
    hoverFx: root ? root.hoverFx : null

    // Probe at a fixed size to learn the glyph's ink-to-em ratio.
    TextMetrics {
      id: probeMetrics
      font.family: "omarchy"
      font.pixelSize: 100
      text: btn.glyph
    }

    TextMetrics {
      id: glyphMetrics
      font: glyphText.font
      text: btn.glyph
    }

    Text {
      id: glyphText
      readonly property real inkRatio: Math.max(0.01, Math.max(probeMetrics.tightBoundingRect.width, probeMetrics.tightBoundingRect.height) / 100)
      text: btn.glyph
      textFormat: Text.PlainText
      font.family: "omarchy"
      font.pixelSize: Math.max(1, Math.round(glyphBox.width * btn.glyphFill / inkRatio))
      color: area.containsMouse ? Color.accent
        : ((glyphBox.shownStyle === "mono" || glyphBox.shownStyle === "dots") ? glyphBox.tint : btn.glyphColor)
      x: Math.round(glyphBox.width / 2 - (glyphMetrics.tightBoundingRect.x + glyphMetrics.tightBoundingRect.width / 2))
      y: Math.round(glyphBox.height / 2 - (glyphText.baselineOffset + glyphMetrics.tightBoundingRect.y + glyphMetrics.tightBoundingRect.height / 2))
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var targetWin = root ? root.contentItemRef : null
        var pt = targetWin ? btn.mapToItem(targetWin, btn.width / 2, 0) : null
        var gx = pt ? pt.x : (btn.width / 2)
        btn.menuRequested(gx, 0)
      } else if (mouse.button === Qt.MiddleButton) {
        btn.middleClicked()
      } else {
        btn.pressed()
      }
    }
  }

  HoverTooltip {
    dockRoot: root
    text: btn.tooltip
    hovered: area.containsMouse
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
  }
}
