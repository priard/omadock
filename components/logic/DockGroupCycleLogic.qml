import QtQuick
import Quickshell
import qs.Commons

// Logic module: scroll-routing and member cycling for an app group's window
// preview (the hover bubble's card stack). One owner for the behavior: tiles
// forward wheel events and preview clicks here as stateless calls; the dock
// root owns all state and reuses the existing wheel throttle (wheelStep) and
// window-focus cluster (focusWindowByAddress) instead of parallel paths.

QtObject {
  // Route one wheel tick to a new front-card index over the member windows.
  // root.wheelStep throttles and gives the direction (-1 wheel-up / +1 down)
  // under the group's own key; the index wraps around the list.
  function cycleFront(root, key, windows, frontIndex, angleDelta) {
    if (!windows || windows.length < 2) return frontIndex
    var dir = root.wheelStep(key, angleDelta)
    if (dir === 0) return frontIndex
    var n = windows.length
    return ((frontIndex + dir) % n + n) % n
  }

  // Focus the window the preview is showing, through the dock's existing
  // window-focus cluster (which restores a parked window in place).
  function focusPreviewed(root, windows, frontIndex) {
    if (!windows || frontIndex < 0 || frontIndex >= windows.length) return
    var win = windows[frontIndex]
    if (!win || !win.address) return
    root.focusWindowByAddress(win.address, win.appId || "")
  }
}
