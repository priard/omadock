// Pinned button slots: a slot that runs a command instead of opening a folder.
//
// Plain JS with no Qt globals, like DockModel.js and SettingsSearch.js, so the unit
// tests run it in the same vm context. Bounded exactly like the model's other
// persisted collections: what reaches the dock from the config file is length-capped
// and shape-checked before it is used.
//
// A button is not a folder: a folder slot opens a file listing, a button slot runs a
// command, so the two live in separate config keys and only the rendering is shared
// (the dock's folder section draws both, folders first).

var MAX_PINNED_BUTTONS = 8
var MAX_BUTTON_COMMAND = 1024
var MAX_BUTTON_NAME = 120
var MAX_BUTTON_ICON = 120

function isList(value) {
  return Array.isArray(value)
}

function boundedStr(value, max) {
  if (typeof value !== "string") return ""
  return value.slice(0, max)
}

function boundList(value, max) {
  return isList(value) ? value.slice(0, max) : []
}

// Keeps the entries that carry a usable command, drops everything else, and caps
// counts and lengths. Returns a fresh array of plain objects: the config file can
// hold anything.
function boundPinnedButtons(arr) {
  return boundList(arr, MAX_PINNED_BUTTONS).filter(function(b) {
    if (!b || typeof b !== "object" || isList(b)) return false
    return boundedStr(b.command, MAX_BUTTON_COMMAND).trim() !== ""
  }).map(function(b) {
    var command = boundedStr(b.command, MAX_BUTTON_COMMAND).trim()
    return {
      command: command,
      name: boundedStr(b.name, MAX_BUTTON_NAME) || "Button",
      icon: boundedStr(b.icon, MAX_BUTTON_ICON) || "application-x-executable"
    }
  })
}
