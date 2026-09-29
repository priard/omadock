import QtQuick
import QtQuick.Effects
import qs.Commons

// One icon, drawn in the dock's icon style:
//
//   original  the icon as shipped
//   mono      the icon in one theme colour, its tone kept as ink density
//   pixel     the icon rendered on a coarse grid and scaled up unsmoothed
//   dots      a dot matrix: one round dot per grid cell, ordered-dithered
//             from the icon's brightness, in one theme colour
//
// dropShadow adds a soft shadow that follows the drawn shape, used when the
// dock has no background card to cast one.
//
// Instead of an image source, the icon can be any item declared inside
// (e.g. a font glyph). Such content is already one colour, so "mono" shows it
// as is (the caller colours it with the tint); "pixel" and "dots" work from
// its rendering.
Item {
  id: art

  property url source
  property string iconStyle: "original"
  property color tint: Color.bar.text
  // Cells across the icon for the pixel and dots styles.
  property int grid: 16
  property bool dropShadow: false
  property real shadowStrength: 0.4
  // Size (logical px) the icon is decoded at. Keep it fixed: tying it to the
  // animated width makes every zoom frame decode the icon again, and with
  // asynchronous loading the icon blinks out between frames. Callers pass
  // their largest on-screen size so zoom stays crisp.
  property real renderSize: 64

  readonly property bool usesGrid: art.iconStyle === "pixel" || art.iconStyle === "dots"
  // Declared content (a font glyph) is drawn with thin strokes; a fine grid
  // leaves them a sparse dotted outline that barely differs from the glyph,
  // so such content is capped at a coarser grid.
  readonly property int cells: Math.max(6, Math.min(art.hasCustom ? 14 : 48, art.grid))
  readonly property int status: img.status

  default property alias content: custom.data
  readonly property bool hasCustom: custom.children.length > 0
  // The item the grid styles read from.
  readonly property Item styleSource: art.hasCustom ? custom : img

  Item {
    id: canvas
    anchors.fill: parent

    layer.enabled: art.dropShadow
    layer.smooth: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#000000"
      shadowOpacity: art.shadowStrength
      shadowBlur: 0.45
      shadowVerticalOffset: Math.max(1, Math.round(art.height * 0.05))
      autoPaddingEnabled: true
    }

    Image {
      id: img
      anchors.fill: parent
      source: art.source
      // The pixel style decodes straight onto its grid; unsmoothed scaling
      // then keeps every cell a hard square.
      sourceSize: art.iconStyle === "pixel"
        ? Qt.size(art.cells, art.cells)
        : Qt.size(Math.max(16, art.renderSize * Screen.devicePixelRatio), Math.max(16, art.renderSize * Screen.devicePixelRatio))
      fillMode: Image.PreserveAspectFit
      smooth: art.iconStyle !== "pixel"
      mipmap: art.iconStyle !== "pixel"
      asynchronous: true
      visible: !art.hasCustom && (art.iconStyle === "original" || art.iconStyle === "pixel")
    }

    Item {
      id: custom
      anchors.fill: parent
      visible: art.iconStyle === "original" || art.iconStyle === "mono"
    }

    // Declared content has no decode size to shrink, so the pixel style
    // renders it onto the grid instead and scales that up unsmoothed.
    ShaderEffectSource {
      anchors.fill: parent
      visible: art.hasCustom && art.iconStyle === "pixel"
      sourceItem: visible ? custom : null
      textureSize: Qt.size(art.cells, art.cells)
      smooth: false
      live: true
    }

    // Monochrome and dot matrix share one shader (shaders/iconstyle.frag),
    // built only while one of them is selected.
    Loader {
      anchors.fill: parent
      active: art.iconStyle === "dots" || (art.iconStyle === "mono" && !art.hasCustom)
      sourceComponent: Item {
        // The dot matrix reads one texel per cell, so the icon is first
        // reduced to two texels per cell with smoothing: each cell then
        // averages its area instead of point-sampling one detail.
        ShaderEffectSource {
          id: styleTexture
          visible: false
          sourceItem: art.styleSource
          textureSize: art.iconStyle === "dots"
            ? Qt.size(art.cells * 2, art.cells * 2)
            : Qt.size(Math.max(16, art.renderSize * Screen.devicePixelRatio), Math.max(16, art.renderSize * Screen.devicePixelRatio))
          smooth: true
          live: true
        }

        ShaderEffect {
          anchors.fill: parent
          property variant source: styleTexture
          property color tint: art.tint
          property real grid: art.cells
          property real dotFill: 0.72
          property real dimLevel: art.iconStyle === "dots" ? 0.22 : 0.35
          property real invert: art.tint.hslLightness < 0.5 ? 1.0 : 0.0
          property real dots: art.iconStyle === "dots" ? 1.0 : 0.0
          // Thin glyph strokes cover only part of a cell; count them in.
          property real alphaCut: art.hasCustom ? 0.12 : 0.35
          fragmentShader: Qt.resolvedUrl("../shaders/iconstyle.frag.qsb")
        }
      }
    }
  }
}
