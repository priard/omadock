// Characterization tests for the icon helpers: the folder-icon name a path
// maps to, the drive icon a device name resolves to, and the icon-index scan's
// output parsed into a name -> path map.
//
// These were written against DockModel.js, which owned them; the extraction to
// DockIcons.js moved the functions without touching a single assertion, so the
// expected values below are the ones that code produced before the move.
//
// The files are loaded into one vm context, so the assertions name the helper,
// not the module it lives in: the only edit the move needs is the FILES list.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const root = new URL("../../", import.meta.url)
// The map is built inside the vm realm, so its prototype is that realm's: a
// strict deep comparison needs the same JSON round-trip every other suite uses.
const plain = value => JSON.parse(JSON.stringify(value))
const FILES = ["DockIcons.js"]
const ctx = vm.createContext({ console, Quickshell: { iconPath: () => "" } })
for (const file of FILES)
  vm.runInContext(readFileSync(new URL(file, root), "utf8"), ctx)

test("a folder path maps to the themed folder icon name", () => {
  assert.equal(ctx.folderIconFor("/home/suva", ""), "user-home")
  assert.equal(ctx.folderIconFor("/home/suva/", ""), "user-home")
  assert.equal(ctx.folderIconFor("/home/suva/Downloads", ""), "folder-download")
  assert.equal(ctx.folderIconFor("/mnt/d/Pictures", ""), "folder-pictures")
  assert.equal(ctx.folderIconFor("/tmp/Videos", ""), "folder-videos")
  assert.equal(ctx.folderIconFor("/opt/Desktop", ""), "user-desktop")
  assert.equal(ctx.folderIconFor("/srv/Templates", ""), "folder-templates")
  assert.equal(ctx.folderIconFor("/var/Public", ""), "folder-publicshare")
  assert.equal(ctx.folderIconFor("/x/Trash", ""), "user-trash")
  assert.equal(ctx.folderIconFor("/x/other", ""), "folder")
  assert.equal(ctx.folderIconFor("", ""), "folder")
  // An explicitly chosen icon wins over the path.
  assert.equal(ctx.folderIconFor("/a/b", "custom-icon"), "custom-icon")
  // A path deeper than a home directory is not the home icon.
  assert.equal(ctx.folderIconFor("/home/suva/Pictures", ""), "folder-pictures")
})

test("a device icon name resolves through the theme, then the Yaru fallback", () => {
  const library = { iconSource: name => name === "usb-pendrive" ? "file:///theme/usb.svg" : "" }
  const adwaita = "file:///usr/share/icons/Adwaita/symbolic/devices/"
  const yaru = "file:///usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png"
  // Yaru keeps the colour artwork; every other theme (and Yaru's grey variant)
  // follows the folder colour into Adwaita's monochrome outlines.
  assert.equal(ctx.resolveDriveIcon("drive-removable-media-usb", "Yaru", library, "theme"), yaru)
  assert.equal(ctx.resolveDriveIcon("drive-removable-media-usb", "Yaru-gray", library, "theme"),
    adwaita + "media-removable-symbolic.svg")
  assert.equal(ctx.resolveDriveIcon("drive-removable-media-usb", "vantablack", library, "theme"),
    adwaita + "media-removable-symbolic.svg")
  assert.equal(ctx.resolveDriveIcon("drive-removable-media-usb", "Yaru", library, "symbolic"),
    adwaita + "media-removable-symbolic.svg")
  assert.equal(ctx.resolveDriveIcon("media-optical", "Yaru", library, "black"),
    adwaita + "media-optical-symbolic.svg")
  // Absolute paths and file URIs pass through untouched.
  assert.equal(ctx.resolveDriveIcon("/abs/icon.svg", "Yaru", library, "theme"), "/abs/icon.svg")
  assert.equal(ctx.resolveDriveIcon("file:///f.png", "Yaru", library, "theme"), "file:///f.png")
  // A name the library knows wins over the hardcoded fallback.
  assert.equal(ctx.resolveDriveIcon("usb-pendrive", "Yaru", library, "theme"), "file:///theme/usb.svg")
  // An unknown name and an empty one both land on the removable-media default.
  assert.equal(ctx.resolveDriveIcon("unknown-icon", "Yaru", library, "theme"), yaru)
  assert.equal(ctx.resolveDriveIcon("", "Yaru", library, "theme"), yaru)
})

test("the icon scan's output parses to one path per name, first path winning", () => {
  assert.deepEqual(plain(ctx.parseIconIndex("/t/apps/a.svg\n/t/pix/a.png\n\n/t/x/firefox.svg\n/t/y/noext\n")),
    { a: "/t/apps/a.svg", firefox: "/t/x/firefox.svg", noext: "/t/y/noext" })
  assert.deepEqual(plain(ctx.parseIconIndex("")), {})
  assert.deepEqual(plain(ctx.parseIconIndex(null)), {})
  assert.deepEqual(plain(ctx.parseIconIndex("   \n  \n")), {})
})

// The app library double: it knows one cached scan path and answers nothing
// else, which is how the fallbacks below get to run.
const lib = { iconSource: name => name === "image-x-generic" ? "file:///idx/image-x-generic.svg" : "" }

// Values captured from DockModel.js before the move, asserted here after it.
test("a place icon resolves through the theme, the colour mode, then Adwaita", () => {
  const yaru = "file:///usr/share/icons/Yaru/256x256/places/"
  const symbol = "file:///usr/share/icons/Adwaita/symbolic/places/"
  assert.equal(ctx.resolveThemedFolderIcon("folder", "Yaru", "theme", lib), yaru + "folder.png")
  assert.equal(ctx.resolveThemedFolderIcon("folder-download", "Yaru", "theme", lib),
    yaru + "folder-download.png")
  assert.equal(ctx.resolveThemedFolderIcon("user-home", "Yaru", "theme", lib), yaru + "user-home.png")
  // No colour Yaru variant (vantablack, Yaru-gray): the monochrome outline,
  // never the icon index, so the B&W themes keep their look.
  assert.equal(ctx.resolveThemedFolderIcon("folder", "Yaru-gray", "theme", lib), symbol + "folder-symbolic.svg")
  assert.equal(ctx.resolveThemedFolderIcon("folder", "vantablack", "theme", lib), symbol + "folder-symbolic.svg")
  assert.equal(ctx.resolveThemedFolderIcon("folder", "Yaru", "white", lib), symbol + "folder-symbolic.svg")
  // An explicit colour variant wins, whether it is the theme or the setting.
  assert.equal(ctx.resolveThemedFolderIcon("folder-music", "Yaru-Yellow", "theme", lib),
    "file:///usr/share/icons/Yaru-Yellow/256x256/places/folder-music.png")
  assert.equal(ctx.resolveThemedFolderIcon("folder-music", "Yaru", "Yaru-Yellow", lib),
    "file:///usr/share/icons/Yaru-Yellow/256x256/places/folder-music.png")
  // Names outside the place whitelist, and the aliases folded into it, are the
  // plain folder rather than a path that does not exist.
  assert.equal(ctx.resolveThemedFolderIcon("folder-weird", "Yaru", "theme", lib), yaru + "folder.png")
  assert.equal(ctx.resolveThemedFolderIcon("folder-development", "Yaru", "theme", lib), yaru + "folder.png")
  assert.equal(ctx.resolveThemedFolderIcon("file:///abs/f.svg", "Yaru", "theme", lib), "file:///abs/f.svg")
  assert.equal(ctx.resolveThemedFolderIcon("/abs/p.png", "Yaru", "theme", lib), "/abs/p.png")
})

test("a file item's icon: places and mimetypes, the scan, then text-x-generic", () => {
  const yaru = "file:///usr/share/icons/Yaru/256x256/"
  assert.equal(ctx.resolveFileItemIcon("folder", "Yaru", "theme", lib), yaru + "places/folder.png")
  assert.equal(ctx.resolveFileItemIcon("folder-pictures", "Yaru", "theme", lib),
    yaru + "places/folder-pictures.png")
  assert.equal(ctx.resolveFileItemIcon("user-trash", "Yaru", "theme", lib), yaru + "places/user-trash.png")
  assert.equal(ctx.resolveFileItemIcon("text-x-generic", "Yaru", "theme", lib),
    yaru + "mimetypes/text-x-generic.png")
  assert.equal(ctx.resolveFileItemIcon("application-pdf", "Yaru", "theme", lib),
    yaru + "mimetypes/application-pdf.png")
  // A name the scan knows wins over the hardcoded fallback.
  assert.equal(ctx.resolveFileItemIcon("image-x-generic", "Yaru", "theme", lib),
    "file:///idx/image-x-generic.svg")
  assert.equal(ctx.resolveFileItemIcon("file:///f.svg", "Yaru", "theme", lib), "file:///f.svg")
  // With no library at all, an unknown or empty name lands on the generic text
  // icon rather than an empty source.
  assert.equal(ctx.resolveFileItemIcon("unknown-thing", "Yaru", "theme", null),
    yaru + "mimetypes/text-x-generic.png")
  assert.equal(ctx.resolveFileItemIcon("", "Yaru", "theme", null), yaru + "mimetypes/text-x-generic.png")
  // A library that answers "" for everything leaves an unknown name blank:
  // it is the caller's library, and the dock's real one never does this.
  assert.equal(ctx.resolveFileItemIcon("unknown-thing", "Yaru", "theme", lib), "")
})
