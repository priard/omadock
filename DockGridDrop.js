// Where an app dragged out of Omarchy's app grid lands in the pinned run
// (AppGridHost). Plain JS, node-tested like the other modules.
//
// row: the dock's pinned run (DockModel.pinnedRow: { kind, appId } apps and
// groups); id: the app's desktop id; pinned: whether pinnedIds hold it,
// in the run or inside a group; idx: the run's insert index, -1 when the
// run is empty. Returns { pin: true } to pin it the usual way (togglePin
// validates the entry), { row } with the run to apply, or {} for nothing.
function gridDrop(row, id, pinned, idx, stripDesktop) {
  if (idx < 0) return pinned ? {} : { pin: true }
  var from = -1
  for (var r = 0; r < row.length; r++)
    if (row[r].kind === "app" && stripDesktop(row[r].appId) === id) { from = r; break }
  // Pinned inside a group: the group keeps it.
  if (from < 0 && pinned) return {}
  if (from < 0) {
    var next = row.slice()
    next.splice(idx, 0, { kind: "app", appId: id })
    return { row: next }
  }
  var to = Math.max(0, Math.min(row.length, idx))
  if (to === from || to === from + 1) return {}
  var moved = row.slice()
  var item = moved.splice(from, 1)[0]
  moved.splice(to > from ? to - 1 : to, 0, item)
  return { row: moved }
}
