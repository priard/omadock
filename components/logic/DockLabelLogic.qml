import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../../DockLabels.js" as DockLabels

// Logic module: name-label policy for dock tiles (apps, app groups,
// folders). style() is everything one DockLabel needs; the width registry
// (root.labelExtras) is what lets zoom/wave centres and the card's hover
// anchor account for labels. Helpers with no Qt in them live in DockLabels.js.

QtObject {
  function style(root, kind) {
    var show = !!root && DockLabels.labelVisible(root.labelMode, root.labelKind, kind)
    var pixel = !!root && root.labelFont === "pixel"
    var base = Style.font.caption
    // Silkscreen is drawn on an 8 px grid; other fonts follow the theme scale.
    var sizes = pixel ? { small: 8, medium: 12, large: 16 } : { small: base - 2, medium: base, large: base + 2 }
    // Auto: black or white, whichever reads on what is actually behind the
    // icons (a gradient's palette, a custom colour, the theme's bar).
    var ink = root ? root.blackOrWhiteOn(root.iconBackdropColor) : Color.bar.text
    if (root && root.labelColor === "theme") ink = root.dockForeground
    else if (root && root.labelColor === "accent") ink = Color.accent
    var inkLight = root ? root.isLight(Qt.color(ink)) : true
    var weights = { regular: Font.Normal, medium: Font.Medium, bold: Font.Bold }
    var dockH = (root && root.dockCard) ? root.dockCard.height : 0
    return {
      show: show,
      hover: !!root && root.labelMode === "hover",
      mirror: !!root && root.alignment === "right",
      fontPx: sizes[root ? root.labelSize : "medium"] || sizes.medium,
      weight: pixel ? Font.Normal : (weights[root ? root.labelWeight : "medium"] || Font.Medium),
      family: pixel ? "Silkscreen" : ((root && root.labelFont === "sans") ? "sans-serif" : Style.font.family),
      ink: ink,
      // Backgrounds and outlines take the side of the scale opposite the ink.
      fill: inkLight ? Util.alpha("#141414", 0.62) : Util.alpha("#f2f2f2", 0.72),
      halo: inkLight ? "#000000" : "#ffffff",
      // A lighter accent: themes often fill the dock from the same palette,
      // and a plain accent glow vanishes into it.
      glow: Qt.lighter(Color.accent, 1.6),
      background: root ? root.labelBackground : "none",
      shape: root ? root.labelShape : "dock",
      dockRatio: (root && dockH > 0) ? root.effectiveCardRadius / dockH : 0.25,
      reveal: root ? root.labelReveal : "slide",
      effect: root ? root.labelEffect : "none",
      maxWidth: root ? root.labelMaxWidth : 140
    }
  }

  // The user's name wins; an app without a desktop entry (its name is its
  // class id) gets a readable one.
  function displayName(root, appId, name) {
    var custom = (root && appId && root.labelNames) ? root.labelNames[appId] : undefined
    if (typeof custom === "string" && custom !== "") return custom
    if (appId && (name === "" || name === appId)) return DockLabels.prettyAppId(appId)
    return name
  }

  function tooltipNeeded(root, kind, hasWindows, hasStateHint, shortened) {
    var shown = !!root && DockLabels.labelVisible(root.labelMode, root.labelKind, kind)
    return DockLabels.tooltipNeeded(shown, hasWindows, hasStateHint, shortened)
  }

  // Label width before a slot's icon; on a right-aligned dock a tile's own
  // label sits before its icon too.
  function extraBefore(root, slot, ownLabel) {
    if (!root) return 0
    return DockLabels.homeExtra(root.labelExtras, slot, ownLabel !== false && root.alignment === "right")
  }

  function setExtra(root, slot, owner, width) {
    if (!root || slot < 0) return
    var next = DockLabels.withExtra(root.labelExtras, slot, owner, width)
    if (next !== root.labelExtras) root.labelExtras = next
  }

  // Hover-mode label widths, which the card leaves out of its centring.
  function hoverExtra(root) {
    return (root && root.labelMode === "hover") ? DockLabels.extrasTotal(root.labelExtras) : 0
  }

  function setName(root, appId, name) {
    root.labelNames = DockLabels.withLabelName(root.labelNames, appId, name)
    root.saveConfig()
  }

  // Apps the Labels page lists: pinned first, then running, once each.
  function nameRows(root) {
    var rows = []
    var seen = {}
    var lists = [root.dockModel.pinned || [], root.dockModel.running || []]
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var e = lists[l][i]
        if (!e || !e.appId || seen[e.appId]) continue
        seen[e.appId] = true
        var auto = (e.name === "" || e.name === e.appId) ? DockLabels.prettyAppId(e.appId) : e.name
        rows.push({ appId: e.appId, auto: auto })
      }
    }
    return rows
  }
}
