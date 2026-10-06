import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Logic module: the single owner of name-label rendering policy for dock
// items (apps, app groups, folders). Tiles pass the name they already show
// in their tooltip; one style() call gives the shared DockLabel visual
// everything it needs, and bandHeight() is what grows the dock card so
// labels never overlap the icons or leave the dock surface.

QtObject {
  // Everything one label needs: whether it shows at all (the labels toggle
  // plus the per-kind filter), the type size, the ink colour, whether a
  // rounded plate sits behind it, and which side of the tile it lives on.
  function style(root, kind) {
    var show = !!root && root.showLabels
      && (root.labelKind === "all" || root.labelKind === kind + "s")
    var base = Style.font.caption
    var fontPx = base - 2
    if (root && root.labelSize === "medium") fontPx = base
    else if (root && root.labelSize === "large") fontPx = base + 2
    // Contrast: theme follows the dock's own foreground; high picks black or
    // white for whatever the dock background is; pill keeps theme ink but
    // adds a dark plate, as on the window-preview counters.
    var ink = root ? root.dockForeground : Color.bar.text
    if (root && root.labelContrast === "high") ink = root.blackOrWhiteOn(Color.bar.background)
    return {
      show: show,
      fontPx: fontPx,
      ink: ink,
      pill: !!root && root.labelContrast === "pill",
      above: !!root && root.labelPlacement === "above",
      height: fontPx + Style.space(4)
    }
  }

  // The extra band the dock card grows by while any label can show: the
  // label's own height plus the gap that keeps it off the icon edge.
  function bandHeight(root) {
    if (!root || !root.showLabels) return 0
    return style(root, "app").height + Style.space(2)
  }
}
