// Body for tests/live/label-metrics.sh (probe.sh's PROBE_BODY hook): the real
// dock, plus a fixture that reaches into it.
//
// It proves the statement at components/DockLabel.qml:97 - the shortening
// search that writes into the label's own TextMetrics - keeps working when
// those metrics are gone while the label itself is still alive. That is the
// state the wild fault logged today (7 occurrences in the quickshell logs,
// every one at DockLabel.qml:97: "TypeError: Value is null and could not be
// converted to an object (exception occurred during delayed function
// evaluation)"): a queued reshorten landing in the window where a delegate's
// children are destroyed and the label is not.
//
// The fixture manufactures that window on demand instead of waiting for it:
// destroy() is a deferred delete, so the metrics are taken away, the event
// loop is given two turns to deliver the deletion, and reshorten() is then
// called directly. destroy() is called only on the two TextMetrics objects,
// found by their own properties - nothing else of the dock is touched.
//
// Markers, read by the test script:
//   LM-INTACT   the ordinary path: a long name, shortened by reshorten()
//   LM-METRICS  the two metrics asked to destroy themselves
//   LM-AFTER    what the label's children look like once the deletion landed
//   LM-THREW    the statement threw (fail); LM-RESHORTEN ok is the pass
//   LM-DONE     the fixture finished and the probe may be stopped
//
// Imports live at the top of the generated file, so this body holds only what
// belongs inside ShellRoot.

  Od.DockHost { id: host }

  // The first DockLabel in the dock's object tree: the component is the only
  // thing in this tree with a reshorten() function.
  function firstLabel(o, depth) {
    if (!o || depth > 16) return null
    if (typeof o.reshorten === "function") return o
    var ch = o.children || []
    for (var i = 0; i < ch.length; i++) {
      var found = firstLabel(ch[i], depth + 1)
      if (found) return found
    }
    return null
  }

  Timer {
    interval: 4000; running: true; repeat: false
    onTriggered: {
      var docks = host.orderedDocks ? host.orderedDocks() : []
      var dock = docks.length > 0 ? docks[0] : null
      var label = dock ? firstLabel(dock.contentItemRef, 0) : null
      if (!label) { console.log("LM-FOUND none"); finishFixture(); return }
      // A name long enough to be cut at the default max width, so the ordinary
      // path is exercised before the metrics are taken away.
      label.name = "A Deliberately Long Application Name"
      label.reshorten()
      console.log("LM-INTACT full=" + label.fullText + " short=" + label.shortText
        + " shortened=" + label.shortened + " data=" + label.data.length)
      var kids = []
      for (var i = 0; i < label.data.length; i++) kids.push(label.data[i])
      var killed = 0
      for (var j = 0; j < kids.length; j++) {
        var kid = kids[j]
        if (kid && kid.advanceWidth !== undefined && kid.font !== undefined) { kid.destroy(); killed++ }
      }
      console.log("LM-METRICS killed=" + killed + " data=" + label.data.length)
      // Two turns: the deferred deletion is delivered before the inner call.
      Qt.callLater(function() { Qt.callLater(function() { afterDestroy(label, killed) }) })
    }
  }

  function afterDestroy(label, killed) {
    var n = -1
    try { n = label.data.length } catch (e) { console.log("LM-GONE " + e); finishFixture(); return }
    console.log("LM-AFTER killed=" + killed + " data=" + n)
    var threw = ""
    try { label.reshorten() } catch (e) { threw = String(e) }
    if (threw !== "") console.log("LM-THREW " + threw)
    else console.log("LM-RESHORTEN ok short=" + label.shortText)
    finishFixture()
  }

  function finishFixture() { Qt.callLater(function() { console.log("LM-DONE"); Qt.quit() }) }
