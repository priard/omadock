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
  // Restores the sticky badge session after a shell restart: counts and the
  // rows already counted, bounded and sanitized on the way in.
  function loadBadgeState(root) {
    if (root._savingBadges) return
    var st = DockModel.parseBadgeState(DockModel.readCapped(root.badgeFileRef.text, DockModel.MAX_BADGE_BYTES))
    root.notificationBadges = st.counts
    root._notifSeenKeys = st.seenKeys
    root._notifSeenOrder = st.seenOrder
  }

  function scheduleBadgeSave(root) {
    root.badgeSaveDebounceRef.restart()
  }

  function flushBadgeState(root) {
    root._savingBadges = true
    root.badgeFileRef.setText(DockModel.serializeBadgeState(root.notificationBadges, root._notifSeenOrder))
    Qt.callLater(function() { root._savingBadges = false })
  }

  function loadPinned(root) {
    root.pinnedIds = DockModel.parsePinned(DockModel.readCapped(root.dockFileRef.text, DockModel.MAX_DOCK_JSON_BYTES))
  }

  function saveConfig(root) {
    // configBase returns null for a file holding anything other than a JSON
    // object (a typo, an array, an oversize paste): rewriting from {} would
    // silently drop every key the dock does not own, so skip the save.
    var conf = root.configFileRef.oversized ? null
      : DockModel.configBase(DockModel.readCapped(root.configFileRef.text, DockModel.MAX_CONFIG_BYTES))
    if (conf === null) {
      console.warn("[omadock] omadock.json is not a readable JSON object (or is over the size cap); not saving so its other keys survive. Fix the file to save settings again.")
      return
    }
    conf = root.buildConfig(conf)
    root._savingConfig = true
    root.configFileRef.setText(JSON.stringify(conf, null, 2))
    Qt.callLater(function() { root._savingConfig = false })
  }
}
