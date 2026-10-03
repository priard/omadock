import QtQuick
import QtQuick.Effects
import qs.Commons

// Hover effects that keep an item's size, drawn around whatever it hosts (an
// icon, a group tile, a window preview). hoverFx.effect picks one:
//
//   lift    the content rises over a soft shadow left on the floor
//   glow    a halo in the accent colour that follows the content's shape,
//           with a ripple leaving it once as the pointer arrives
//           (shaders/hoverglow.frag)
//   glitch  a short RGB-split burst with jumping bands as the pointer
//           arrives (shaders/hoverglitch.frag)
//
// Any other value draws the content as is. hoverFx is the dock's object
// (Dock.qml), so every item follows the setting without plumbing of its own.
//
// Content goes inside, or is reparented into contentItem by an item that
// must keep its place in the caller's tree (and its indentation).
Item {
  id: fx

  property bool hovered: false
  property var hoverFx: null

  default property alias content: body.data
  readonly property Item contentItem: body

  readonly property string effect: fx.hoverFx ? fx.hoverFx.effect : ""
  readonly property real minSide: Math.min(fx.width, fx.height)

  // 0..1, follows hovered; the effects scale with it.
  property real hoverLevel: fx.hovered ? 1 : 0
  Behavior on hoverLevel { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  // One-shot animations started as the pointer arrives.
  property real ring: 0
  property real glitchT: 0
  property real glitchSeed: 0
  readonly property bool glitching: fx.effect === "glitch" && glitchAnim.running
  onHoveredChanged: {
    if (!fx.hovered) return
    if (fx.effect === "glow") ringAnim.restart()
    if (fx.effect === "glitch") {
      fx.glitchSeed = Math.random() * 10
      glitchAnim.restart()
    }
  }
  NumberAnimation { id: ringAnim; target: fx; property: "ring"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
  NumberAnimation { id: glitchAnim; target: fx; property: "glitchT"; from: 0; to: 1; duration: 320 }

  // Lift: the shadow stays on the floor while the content rises.
  Rectangle {
    visible: fx.effect === "lift" && fx.hoverLevel > 0.01
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.bottom
    width: fx.width * (0.78 - 0.18 * fx.hoverLevel)
    height: Math.max(2, fx.minSide * 0.07)
    radius: height / 2
    color: "#000000"
    opacity: 0.35 * fx.hoverLevel
    layer.enabled: visible
    layer.effect: MultiEffect {
      blurEnabled: true
      blur: 0.7
      blurMax: 16
      autoPaddingEnabled: true
    }
  }

  Item {
    anchors.fill: parent
    transform: Translate { y: fx.effect === "lift" ? -fx.minSide * 0.16 * fx.hoverLevel : 0 }

    // Glow, behind the content: the content rendered with a margin into a
    // small texture, blurred into the halo by the shader.
    Loader {
      id: glowLoader
      readonly property real pad: fx.minSide * 0.4
      active: fx.effect === "glow" && (fx.hoverLevel > 0.001 || ringAnim.running)
      anchors.fill: parent
      anchors.margins: -pad
      sourceComponent: Item {
        ShaderEffectSource {
          id: glowSource
          visible: false
          sourceItem: body
          sourceRect: Qt.rect(-glowLoader.pad, -glowLoader.pad, glowLoader.width, glowLoader.height)
          textureSize: Qt.size(48, Math.max(8, Math.round(48 * glowLoader.height / Math.max(1, glowLoader.width))))
          smooth: true
          live: true
        }
        ShaderEffect {
          anchors.fill: parent
          property variant source: glowSource
          property color glow: fx.hoverFx ? fx.hoverFx.glow : Color.accent
          // Blur radius in texture coordinates, the same in pixels on both axes.
          property point spread: Qt.point(fx.minSide * 0.234 / Math.max(1, glowLoader.width),
                                          fx.minSide * 0.234 / Math.max(1, glowLoader.height))
          property real ring: fx.ring
          property real level: fx.hoverLevel
          fragmentShader: Qt.resolvedUrl("../shaders/hoverglow.frag.qsb")
        }
      }
    }

    Item {
      id: body
      anchors.fill: parent
    }

    // Glitch: replaces the content while the burst runs. Reads a margin
    // around it too, so parts drawn past its edges split along with it.
    Loader {
      id: glitchLoader
      readonly property real bleed: Math.round(fx.minSide * 0.15)
      active: fx.glitching
      anchors.fill: parent
      anchors.margins: -bleed
      sourceComponent: Item {
        ShaderEffectSource {
          id: glitchSource
          visible: false
          sourceItem: body
          sourceRect: Qt.rect(-glitchLoader.bleed, -glitchLoader.bleed, glitchLoader.width, glitchLoader.height)
          hideSource: fx.glitching
          live: true
        }
        ShaderEffect {
          anchors.fill: parent
          visible: fx.glitching
          property variant source: glitchSource
          property real t: fx.glitchT
          property real seed: fx.glitchSeed
          fragmentShader: Qt.resolvedUrl("../shaders/hoverglitch.frag.qsb")
        }
      }
    }
  }
}
