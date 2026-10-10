import QtQuick
import "../DockKeys.js" as DockKeys

// A ListModel of string keys kept in step with a list by moves, inserts and
// per-row updates. A Repeater over a plain JS array rebuilds every delegate
// whenever the array is replaced, which re-creates (and re-decodes) every
// icon on any change; over this model the delegates of keys that stay are
// kept, and they look their data up by key.
//
// A key that goes away stays for exitMs, marked leaving, so its delegate can
// animate out (DockKeys.target); the first sync marks nothing fresh, so the
// dock does not animate in at startup. Roles: key, leaving, fresh, slot.
ListModel {
  id: model

  property int exitMs: 0
  property int liveCount: 0
  property var _rows: []
  property bool _synced: false

  property Timer _expiry: Timer {
    onTriggered: model._apply(DockKeys.expire(model._rows, Date.now()))
  }

  function sync(keys) {
    model._apply(DockKeys.target(model._rows, keys || [], !model._synced, Date.now(), model.exitMs))
    model._synced = true
  }

  function _apply(rows) {
    // Remove what is gone, then move/insert into order, then update roles.
    var keep = {}
    for (var i = 0; i < rows.length; i++) keep[rows[i].key] = true
    for (var r = model.count - 1; r >= 0; r--) {
      if (!keep[model.get(r).key]) model.remove(r)
    }
    for (var j = 0; j < rows.length; j++) {
      var row = rows[j]
      if (!(j < model.count && model.get(j).key === row.key)) {
        var at = -1
        for (var k = j + 1; k < model.count; k++) {
          if (model.get(k).key === row.key) { at = k; break }
        }
        if (at >= 0) model.move(at, j, 1)
        else model.insert(j, { key: row.key, leaving: row.leaving, fresh: row.fresh, slot: row.slot })
      }
      if (model.get(j).leaving !== row.leaving) model.setProperty(j, "leaving", row.leaving)
      if (model.get(j).slot !== row.slot) model.setProperty(j, "slot", row.slot)
    }
    model._rows = rows
    var live = 0
    for (var c = 0; c < rows.length; c++) if (!rows[c].leaving) live++
    model.liveCount = live
    var next = DockKeys.nextExpiry(rows)
    if (next < 0) model._expiry.stop()
    else {
      model._expiry.interval = Math.max(1, next - Date.now())
      model._expiry.restart()
    }
  }
}
