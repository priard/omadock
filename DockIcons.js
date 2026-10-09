// Icon resolution for folders, removable drives and the icon index the shell
// scan writes out.
//
// Extracted verbatim from DockModel.js, which owned these three: they are the
// icon side of the model and nothing else in DockModel.js called them. The
// module imports nothing (root JS modules in this repo never import each
// other; QML is the composition layer) and holds no state.

// Icon name -> file from the icon scan's output, one path per line. The
// name is the file name without its extension; the first path for a name
// wins (the scan lists SVGs before PNGs).
function parseIconIndex(text) {
  var index = {}
  var lines = String(text == null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var value = lines[i].trim()
    if (!value) continue
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name && index[name] === undefined) index[name] = value
  }
  return index
}


function folderIconFor(path, explicitIcon) {
  if (explicitIcon) return explicitIcon
  var clean = String(path || "").trim().replace(/\/+$/, "")
  var norm = clean.toLowerCase()
  if (norm === "~" || (norm.indexOf("/home/") === 0 && norm.split("/").length <= 3)) return "user-home"
  var baseName = norm.split("/").pop() || ""
  if (baseName.indexOf("download") >= 0) return "folder-download"
  if (baseName.indexOf("document") >= 0) return "folder-documents"
  if (baseName.indexOf("picture") >= 0) return "folder-pictures"
  if (baseName.indexOf("music") >= 0) return "folder-music"
  if (baseName.indexOf("video") >= 0) return "folder-videos"
  if (baseName.indexOf("desktop") >= 0) return "user-desktop"
  if (baseName.indexOf("template") >= 0) return "folder-templates"
  if (baseName.indexOf("public") >= 0) return "folder-publicshare"
  if (baseName.indexOf("trash") >= 0) return "user-trash"
  return "folder"
}


function resolveDriveIcon(iconName, themeName, appLibrary, folderColorMode) {
  var name = String(iconName || "drive-removable-media-usb").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // Drives follow the folder colour, so they sit next to the folders in the
  // same style: wherever folders use Adwaita's monochrome outlines (white,
  // black, black-or-white or symbolic, or a theme with no Yaru colour),
  // drives do too.
  var theme = String(themeName || "").trim()
  var yaruTheme = theme === "Yaru" || (theme.indexOf("Yaru-") === 0 && theme !== "Yaru-gray" && theme !== "Yaru-grey")
  var mode = String(folderColorMode || "theme")
  if (mode === "white" || mode === "black" || mode === "bw" || mode === "symbolic"
      || ((mode === "theme" || mode === "auto") && !yaruTheme)) {
    var symbolicMap = {
      "drive-removable-media-usb": "media-removable",
      "usb-pendrive": "media-removable",
      "drive-removable-media": "drive-removable-media",
      "media-removable": "media-removable",
      "drive-harddisk-usb": "drive-harddisk-usb",
      "media-optical": "media-optical"
    }
    return "file:///usr/share/icons/Adwaita/symbolic/devices/" + (symbolicMap[name] || "drive-removable-media") + "-symbolic.svg"
  }

  // Try iconIndex/theme resolution first for theme resilience
  if (appLibrary) {
    var src = appLibrary.iconSource(name)
    if (src && src.length > 0) return src
  }

  // Hardcoded Yaru fallback for known device icons
  var devMap = {
    "drive-removable-media-usb": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png",
    "usb-pendrive": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png",
    "drive-removable-media": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media.png",
    "media-removable": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media.png",
    "drive-harddisk-usb": "/usr/share/icons/Yaru/256x256/devices/drive-harddisk-usb.png",
    "media-optical": "/usr/share/icons/Yaru/256x256/devices/media-optical.png"
  }

  if (devMap[name]) {
    return "file://" + devMap[name]
  }

  return "file:///usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png"
}
