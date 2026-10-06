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
    var ink = root ? root.dockForeground : Color.bar.text
    if (root && root.labelColor === "high") ink = root.blackOrWhiteOn(Color.bar.background)
    else if (root && root.labelColor === "accent") ink = Color.accent
    return {
      show: show,
      hover: !!root && root.labelMode === "hover",
      mirror: !!root && root.alignment === "right",
      fontPx: sizes[root ? root.labelSize : "small"] || sizes.small,
      family: pixel ? "Silkscreen" : ((root && root.labelFont === "sans") ? "sans-serif" : Style.font.family),
      ink: ink,
      background: root ? root.labelBackground : "none",
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

  function extraBefore(root, slot) {
    return root ? DockLabels.extrasBefore(root.labelExtras, slot) : 0
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

  function openRename(root, appId) {
    root.labelEditAppId = appId
    root.settingsPanelPage = "labels"
    root.openSettingsPanel()
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
        rows.push({ appId: e.appId, name: root.labelNames[e.appId] || "", auto: auto })
      }
    }
    return rows
  }
}
