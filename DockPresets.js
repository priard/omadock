// The looks OmaDock offers out of the box, beside the presets a user saves.
//
// A shipped preset is a preset as DockModel keeps one -- an id, a name and a
// look -- except that its look lists only the keys that differ from
// DockModel.DEFAULT_LOOK: merge() fills the rest from DEFAULT_LOOK through the
// caller's fill (DockModel.pickLook), so a look key added after this file was
// written gets its default instead of leaking whatever the dock happens to
// hold (the rule PR #48 pinned for saved presets).
//
// Shipping them here, not in the config, is what makes them survive: a fresh
// install has no omadock.json, and merge([], ...) still returns every entry
// below. They are read-only -- DockConfigLogic refuses to rename, update or
// delete one -- so the list a user edits is always the list they saved.
//
// Every look below is built from options this repository's pull requests
// contributed, and from what their authors said they look like:
//
//   thepathless:ristretto  the owner's own look on the maintainer's desktop
//                          (dot-matrix icons, forest gradient, grain, long
//                          custom dividers, glitch hover, no rim or shadow)
//   Glass                  gradient fill (PR #13, 7ab8e81) with film grain
//                          (#13, 172407b) and a rim that stays visible over it
//                          (#45, a9fe92c), long theme-coloured dividers
//                          (#17, bbd672b) and the Lift hover (#19, 8f46e06)
//   Pixel                  the pixel icon style with a B/W tint and a coarse
//                          grid, plus the tone controls that keep a poster-like
//                          icon readable (#13, ef69eb5 and 9e34022)
//   Mono                   the transparent dock -- icons only, no card, border
//                          or panel (#12, 23ab907) -- in monochrome with the
//                          accent tint (#13) and the Glow hover (#19, fb70a80)
//                          that was drawn for exactly these glyph-like icons
//   Panels                 Split sections (#14, afb82a6 and b721251): one panel
//                          per dock section over a quiet Mono gradient, with the
//                          panel gap #13 taught to snap to the pixel grid
//
// Deliberately not shipped as presets: Wave magnification and launch bounce
// (#2) and side labels (#47) are motion and text, not the look a preset holds;
// divider geometry and the panel layout (#49) are reachable from any look.

var SHIPPED = [
  {
    id: "builtin_thepathless_ristretto",
    name: "thepathless:ristretto",
    look: {
      bgFill: "gradient", gradientPreset: "forest", gradientStrength: 0.25, grain: 0.2,
      dividerGeometry: "long", dividerStyle: "custom",
      iconStyle: "dots", iconGrid: 8, iconContrast: 0.4, iconStrength: 0.45, iconSize: 34,
      hoverEffect: "glitch", opacity: "theme", shape: "theme", showBorder: false, showShadow: false
    }
  },
  {
    id: "builtin_glass",
    name: "Glass",
    look: {
      bgFill: "gradient", gradientPreset: "aurora", gradientStrength: 0.55, grain: 0.18,
      shadowStrength: 0.5, dividerGeometry: "long", dividerStyle: "theme",
      hoverEffect: "lift", itemSpacing: 6
    }
  },
  {
    id: "builtin_pixel",
    name: "Pixel",
    look: { iconStyle: "pixel", iconTint: "bw", iconGrid: 12, iconContrast: 0.5 }
  },
  {
    id: "builtin_mono",
    name: "Mono",
    look: {
      showBackground: false, showBorder: false, shadowStrength: 0.45,
      iconStyle: "mono", iconTint: "accent", iconContrast: 0.5, iconHoverReveal: true,
      hoverEffect: "glow", itemSpacing: 8, sectionSpacing: 20
    }
  },
  {
    id: "builtin_panels",
    name: "Panels",
    look: {
      bgFill: "gradient", gradientPreset: "mono", gradientStrength: 0.4, grain: 0.12,
      splitSections: true, sectionSpacing: 14, hoverEffect: "zoom"
    }
  }
]

// The list the dock shows and applies: the shipped looks first, then the ones
// the user saved. `fillLook` is DockModel.pickLook, which completes each
// shipped look and drops anything a look could not hold.
function merge(userPresets, fillLook) {
  var out = []
  for (var i = 0; i < SHIPPED.length; i++) {
    var p = SHIPPED[i]
    out.push({ id: p.id, name: p.name, look: fillLook(p.look), builtin: true })
  }
  var list = Array.isArray(userPresets) ? userPresets : []
  for (var j = 0; j < list.length; j++) out.push(list[j])
  return out
}

// The presets a config may hold: everything the list carries that did not ship
// with the dock. Writes go through this, so a shipped look is never saved into
// a user's omadock.json.
function userOnly(presets) {
  var out = []
  var list = Array.isArray(presets) ? presets : []
  for (var i = 0; i < list.length; i++) if (!list[i] || list[i].builtin !== true) out.push(list[i])
  return out
}

// How many presets the user saved, against DockModel.MAX_PRESETS.
function userCount(presets) {
  return userOnly(presets).length
}
