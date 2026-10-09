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
