import QtQuick 6.11
import qs.Commons
import "../DockLabels.js" as DockLabels

// The dock's fit to its screen (DockFit.js). This holds what the planner
// reads from the labels: each one's full, unshortened width
// (DockLabels.withNatural), keyed by label slot.
Item {
  id: host
  property var dockRoot: null
  readonly property var root: dockRoot
  width: 0
  height: 0

  property var labelNaturals: ({})
  function setNatural(slot, owner, entry) {
    if (slot < 0) return
    var next = DockLabels.withNatural(host.labelNaturals, slot, owner, entry)
    if (next !== host.labelNaturals) host.labelNaturals = next
  }
}
