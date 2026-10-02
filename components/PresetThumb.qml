import QtQuick
import qs.Commons
import qs.Ui

// A small drawing of a preset's look, built from its values: backdrop,
// dock body (shape, fill or gradient, opacity, border, shadow, split
// panels), placeholder icons in the icon style, dividers and indicator
// dots. It shows the character of a look, not an exact copy; theme colours
// come from the current Omarchy theme, as the dock would use them.
Item {
  id: thumb

  property var rootRef: null
  readonly property var dock: rootRef
  property var look: ({})

  implicitWidth: Style.space(168)
  implicitHeight: Style.space(64)

  function val(key, fallback) {
    return (thumb.look && thumb.look[key] !== undefined) ? thumb.look[key] : fallback
  }
  function safeColor(s, fallback) {
    try { return Qt.color(s) } catch (e) { return fallback }
  }

  // The dock sits at the bottom of a small "screen", as on the desktop.
  readonly property real bodyHeight: Math.round(thumb.height * 0.48)
  // Scale from the real dock (about 60 px tall) to this drawing.
  readonly property real k: thumb.bodyHeight / 60
  readonly property real iconSize: Math.round(thumb.bodyHeight * 0.6)
  readonly property real iconGap: Style.space(3)
  readonly property real sectionPad: Style.space(4)

  readonly property string bg: String(val("bgColor", "theme"))
  readonly property real opacityValue: {
    var o = val("opacity", "theme")
    if (o === "theme" || typeof o !== "number") return Color.bar.background.a
    return Math.max(0, Math.min(1, o))
  }
  readonly property color fillColor: bg === "none" ? Qt.rgba(0, 0, 0, 0.25)
    : (bg.charAt(0) === "#" ? safeColor(bg, Color.bar.background) : Color.bar.background)
  readonly property color fg: bg.charAt(0) === "#" && dock ? dock.blackOrWhiteOn(fillColor) : Color.bar.text
  readonly property bool showBg: val("showBackground", true) !== false
  readonly property bool gradient: showBg && val("bgFill", "solid") === "gradient"
  readonly property var gradientColors: {
    var wanted = String(val("gradientPreset", "theme"))
    var list = dock ? dock.gradientPresets : []
    for (var i = 0; i < list.length; i++) if (list[i].id === wanted) return list[i].colors
    return dock ? dock.themeGradientColors : [Color.accent, Color.accent, Color.accent]
  }
  readonly property real rimAlpha: {
    var b = val("borderOpacity", "theme")
    if (typeof b === "number") return Math.max(0, Math.min(1, b))
    return (opacityValue < 0.25 || bg === "none") ? 0.48 : Math.max(0.24, opacityValue * 0.35)
  }
  readonly property bool border: val("showBorder", true) !== false
  readonly property real borderW: border ? Math.max(1, Number(val("borderWidth", 1.5)) * k) : 0
  readonly property bool split: val("splitSections", false) === true
  function radiusFor(h) {
    var s = String(val("shape", "rounded"))
    if (s === "round" || s === "pill") return h / 2
    if (s === "square") return 0
    var r = Number(val("cornerRadius", -1))
    if (s === "rounded" && r >= 0) return Math.min(h / 2, r * k)
    return Math.min(h / 2, 14 * k)
  }
  readonly property string iconStyle: String(val("iconStyle", "original"))
  readonly property color tint: {
    var t = String(val("iconTint", "text"))
    if (t === "accent") return Color.accent
    if (t === "bw" && dock) return dock.blackOrWhiteOn(fillColor)
    return fg
  }
  // Stand-ins for colourful app icons in the original and pixel styles.
  readonly property var iconColors: ["#e5534b", "#3d8bfd", "#46a758", "#e0a526", "#8e6ad8", "#2fb5c2"]
  // A 5x5 symbol per placeholder icon, so the styles have something to
  // render: ring, diamond, cross, frame, plus, grid.
  readonly property var glyphs: [
    ".###.#...##...##...#.###.", "..#...###.#####.###...#..", "#...#.#.#...#...#.#.#...#",
    "######...##.#.##...######", "..#....#..#####..#....#..", ".#.#.#####.#.#.#####.#.#."
  ]
  function num(key, fallback, lo, hi) {
    var v = Number(val(key, fallback))
    if (!isFinite(v)) v = fallback
    return Math.max(lo, Math.min(hi, v))
  }
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  // Whether cell (r, c) of a g x g grid falls on icon n's symbol.
  function glyphAt(n, r, c, g) {
    var pattern = thumb.glyphs[n % thumb.glyphs.length]
    return pattern.charAt(Math.floor(r * 5 / g) * 5 + Math.floor(c * 5 / g)) === "#"
  }
  readonly property real effectStrength: num("iconStrength", 1, 0, 1)
  readonly property real effectContrast: num("iconContrast", 0, 0, 1)
  // "Pixels/Dots across" (8..32), scaled to what reads at this size.
  readonly property int cellsAcross: Math.max(4, Math.min(7, Math.round(num("iconGrid", 16, 8, 32) / 3)))
  readonly property string dividerStyle: String(val("dividerStyle", "simple"))
  readonly property color dividerColor: dividerStyle === "theme" ? Util.alpha(fg, rimAlpha)
    : dividerStyle === "custom" ? Util.alpha(fg, Number(val("dividerOpacity", 0.4)))
    : Util.alpha(fg, 0.3)
  readonly property real dividerW: dividerStyle === "theme" ? Math.max(1, Number(val("borderWidth", 1.5)) * k)
    : dividerStyle === "custom" ? Math.max(1, Number(val("dividerWidth", 1.5)) * k) : 1
  readonly property real dividerH: thumb.bodyHeight * Math.max(0.2, Math.min(1, Number(val("dividerHeight", 70)) / 100))

  // One dock panel: shadow, fill or gradient, rim. Loaded behind the whole
  // row, or behind each section when sections are split.
  Component {
    id: panelComp
    Item {
      readonly property real r: thumb.radiusFor(height)
      Rectangle {
        visible: thumb.val("showShadow", true) !== false
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: -2
        radius: parent.r
        color: Qt.rgba(0, 0, 0, 0.35 * Number(thumb.val("shadowStrength", 0.4)))
      }
      Rectangle {
        anchors.fill: parent
        radius: parent.r
        visible: thumb.showBg && !thumb.gradient
        color: thumb.bg === "none" ? thumb.fillColor : Util.alpha(thumb.fillColor, thumb.opacityValue)
      }
      // Created only for a gradient, as in DockSurface.
      Loader {
        anchors.fill: parent
        active: thumb.gradient
        sourceComponent: ShaderEffect {
          property color base: Util.alpha(Color.bar.background, thumb.opacityValue)
          property color c1: thumb.gradientColors[0] || Color.accent
          property color c2: thumb.gradientColors[1] || c1
          property color c3: thumb.gradientColors[2] || c2
          property real count: thumb.gradientColors.length > 2 ? 3 : 2
          property real strength: Number(thumb.val("gradientStrength", 0.6))
          property real radius: thumb.radiusFor(height)
          property size size: Qt.size(width, height)
          fragmentShader: Qt.resolvedUrl("../shaders/gradient.frag.qsb")
        }
      }
      Rectangle {
        anchors.fill: parent
        radius: parent.r
        color: "transparent"
        border.width: thumb.borderW
        border.color: Util.alpha(thumb.fg, thumb.rimAlpha)
      }
    }
  }

  // The "screen": a soft wallpaper from the theme's accent into its
  // background, so opacity and a missing background show, with a thin edge
  // that keeps it apart from the panel behind it.
  Rectangle {
    anchors.fill: parent
    radius: Style.space(8)
    gradient: Gradient {
      GradientStop { position: 0; color: thumb.mix(Color.menu.background, Color.accent, 0.55) }
      GradientStop { position: 0.6; color: thumb.mix(Color.menu.background, Color.accent, 0.2) }
      GradientStop { position: 1; color: Qt.darker(Color.menu.background, 1.15) }
    }
    border.width: 1
    border.color: Util.alpha(Color.menu.text, 0.12)
  }

  Loader {
    active: !thumb.split
    anchors.fill: sections
    sourceComponent: panelComp
  }

  // Three sections of placeholder icons (3, 2, 1), with dividers between
  // them, or each on its own panel when split.
  Row {
    id: sections
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(5)
    height: thumb.bodyHeight
    spacing: thumb.split ? Style.space(4) : 0

    Repeater {
      model: [{ first: 0, count: 3 }, { first: 3, count: 2 }, { first: 5, count: 1 }]
      delegate: Row {
        id: sectionSlot
        required property var modelData
        required property int index
        height: thumb.bodyHeight

        Item {
          visible: sectionSlot.index > 0 && !thumb.split
          width: Style.space(5)
          height: parent.height
          Rectangle {
            anchors.centerIn: parent
            width: thumb.dividerW
            height: thumb.dividerH
            color: thumb.dividerColor
          }
        }

        Item {
          width: sectionSlot.modelData.count * thumb.iconSize
            + (sectionSlot.modelData.count - 1) * thumb.iconGap + 2 * thumb.sectionPad
          height: parent.height

          Loader {
            active: thumb.split
            anchors.fill: parent
            sourceComponent: panelComp
          }

          Row {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Style.space(1)
            spacing: thumb.iconGap
            Repeater {
              model: sectionSlot.modelData.count
              delegate: Item {
                id: iconItem
                required property int index
                readonly property int n: sectionSlot.modelData.first + index
                readonly property color own: thumb.iconColors[n % thumb.iconColors.length]
                // Mono and dot matrix: the tint, blended with the icon's own
                // colour as far as Strength leaves it.
                readonly property color ink: thumb.mix(own, thumb.tint, thumb.effectStrength)
                readonly property bool gridStyle: thumb.iconStyle === "pixel" || thumb.iconStyle === "dots"
                width: thumb.iconSize
                height: thumb.iconSize

                // Original: a coloured tile. Mono: a faint tile that Contrast
                // fades out. Pixel and dot matrix draw their own cells.
                Rectangle {
                  visible: !iconItem.gridStyle
                  anchors.fill: parent
                  radius: width * 0.25
                  color: thumb.iconStyle === "mono"
                    ? Util.alpha(iconItem.ink, 0.22 * (1 - thumb.effectContrast))
                    : iconItem.own
                }

                Grid {
                  id: cells
                  readonly property int g: iconItem.gridStyle ? thumb.cellsAcross : 5
                  readonly property real inset: iconItem.gridStyle ? 0 : parent.width * 0.2
                  readonly property real gap: thumb.iconStyle === "dots" ? parent.width / g * 0.22 : 0
                  readonly property real cell: (parent.width - 2 * inset - (g - 1) * gap) / g
                  anchors.centerIn: parent
                  columns: g
                  spacing: gap
                  Repeater {
                    model: cells.g * cells.g
                    delegate: Rectangle {
                      required property int index
                      readonly property int r: Math.floor(index / cells.g)
                      readonly property int c: index % cells.g
                      readonly property bool on: thumb.glyphAt(iconItem.n, r, c, cells.g)
                      readonly property bool corner: (r === 0 || r === cells.g - 1) && (c === 0 || c === cells.g - 1)
                      width: cells.cell
                      height: cells.cell
                      radius: thumb.iconStyle === "dots" ? width / 2 : 0
                      color: {
                        if (thumb.iconStyle === "original") return on ? Qt.rgba(1, 1, 1, 0.85) : "transparent"
                        if (thumb.iconStyle === "mono") return on ? iconItem.ink : "transparent"
                        if (corner) return "transparent"
                        if (thumb.iconStyle === "pixel") return on ? Qt.lighter(iconItem.own, 1.55) : iconItem.own
                        return on ? iconItem.ink : Util.alpha(iconItem.ink, 0.28 * (1 - thumb.effectContrast))
                      }
                    }
                  }
                }
                Rectangle {
                  visible: parent.n === 0 || parent.n === 3
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.bottom
                  anchors.topMargin: Style.space(1)
                  width: Style.space(3)
                  height: width
                  radius: thumb.val("indicatorShape", "theme") === "square" ? 0 : width / 2
                  color: thumb.fg
                }
              }
            }
          }
        }
      }
    }
  }
}
