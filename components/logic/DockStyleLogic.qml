import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  // Slot index of running entry idx among VISIBLE icons only. Fully-tiled
  // entries collapse to zero width, so they must not consume a slot in the
  // wave home-center arithmetic — every icon after one would drift by a
  // full slot. Same predicate as visibleRunningCount, so they never disagree.
  function visibleRunningSlotBefore(root, idx) {
    var n = 0
    for (var i = 0; i < idx && i < root.runningSection.length; i++) {
      var e = root.runningSection[i]
      if (!(root.showMinimizedTiles && e && DockModel.allWindowsMinimized(e.windowList, root.liveWsNameOf, root.minimizedWorkspace))) n++
    }
    return n
  }

  function slotHomeCenter(root, elementIndex, slotsBefore, sepCount, extraLeftWidth) {
    var seps = (typeof sepCount === "number") ? sepCount : (sepCount ? 1 : 0)
    return root.baseRowLeft
      + elementIndex * root.gapWidth
      + slotsBefore * root.iconSlot
      + seps * root.separatorWidth
      + (extraLeftWidth || 0)
      + root.iconSlot / 2
  }

  function magnifyAt(root, homeCenter) {
    if (!root.waveHover) return 0
    var distance = root.pointerX - homeCenter
    if (Math.abs(distance) >= root.magnifyRange) return 0
    return 0.5 * (1 + Math.cos(Math.PI * distance / root.magnifyRange))
  }

  function magnifyScaleAt(root, homeCenter) {
    return 1 + (root.magnifyPeak - 1) * root.magnifyAt(homeCenter)
  }

  // Layout slot expansion handles spacing naturally; manual translation nudges are deprecated.
  function waveOffsetAt(root, homeCenter) {
    return 0
  }

  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(root, value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  function cardRadius(root, height) {
    return root.effectiveCardRadius
  }

  // Keys and lookups for the keyed Repeater models (KeyedListModel), which
  // keep the delegates of items that stay when these lists are replaced.
  function pinnedRowKey(root, item) {
    return item.kind === "group" ? "group:" + item.id : "app:" + item.appId
  }

  // Tint for an iconTint mode ("text", "accent", "bw") over a backdrop.
  function tintFor(root, mode, textColor, backdrop) {
    if (mode === "bw") return root.blackOrWhiteOn(backdrop)
    return root.readableOn(mode === "accent" ? Color.accent : textColor, backdrop)
  }

  // Near black or near white, whichever contrasts more with the backdrop.
  function blackOrWhiteOn(root, backdrop) {
    var dark = Qt.color("#141414")
    var light = Qt.color("#f2f2f2")
    return root.contrastRatio(dark, backdrop) >= root.contrastRatio(light, backdrop) ? dark : light
  }

  // WCAG relative luminance and contrast ratio.
  function luminance(root, c) {
    function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }

  function contrastRatio(root, a, b) {
    var la = root.luminance(a), lb = root.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // A colour with the given hue and saturation, moved in lightness away
  // from the backdrop (darker on a light one, lighter on a dark one) until
  // it reaches a 3:1 contrast ratio, the WCAG minimum for graphics.
  function readableOn(root, color, backdrop) {
    var c = Qt.color(color)
    var bg = Qt.color(backdrop)
    if (root.contrastRatio(c, bg) >= 3) return c
    var darker = root.luminance(bg) > 0.18
    var h = c.hslHue < 0 ? 0 : c.hslHue
    var sat = c.hslSaturation
    var best = c
    for (var step = 1; step <= 20; step++) {
      var l = darker ? Math.max(0, c.hslLightness - step * 0.05) : Math.min(1, c.hslLightness + step * 0.05)
      best = Qt.hsla(h, sat, l, c.a)
      if (root.contrastRatio(best, bg) >= 3) break
    }
    return best
  }

  // Symbolic icon colour over a given backdrop: white or black when set,
  // for "bw" whichever of the two contrasts more with that backdrop (so a
  // folder can be dark on the dock and light in a dark stack popup), and
  // otherwise white or black to suit the theme.
  function symbolicColorOn(root, backdrop) {
    var c
    if (root.folderColor === "white") c = Qt.color("#ffffff")
    else if (root.folderColor === "black") c = Qt.color("#111111")
    else if (root.folderColor === "bw") c = root.blackOrWhiteOn(backdrop)
    else c = Qt.color((Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111")
    // Pure white glares next to the app icons; mix a little of the backdrop
    // into light glyphs so they sit in the panel instead.
    if (c.hslLightness > 0.5) {
      var bg = Qt.color(backdrop)
      var k = root.symbolicLightSoftening
      c = Qt.rgba(c.r + (bg.r - c.r) * k, c.g + (bg.g - c.g) * k, c.b + (bg.b - c.b) * k, 1)
    }
    return c
  }

  function isWindowFocused(root, win) {
    if (!win || !win.address || !root.activeWindowAddress) return false
    return win.address === root.activeWindowAddress
  }

  function isWindowParked(root, win) {
    if (!win) return false
    return root.isWinParkedLive(win)
  }
}
