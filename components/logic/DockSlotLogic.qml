import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../../Plan.js" as Plan

// Logic extracted from DockWindowLogic: everything about the place a parked window
// occupied. Hyprland has no minimize and no memory of the layout, so the place is
// recorded here and won back on restore. Stateless functions, the dock root owns
// all state; bodies are verbatim from DockWindowLogic and Dock.qml.

QtObject {
  // hyprctl's client list is read by a Process in Dock.qml; the parsing itself is pure
  // and lives in Plan.js with its tests.
  function parseClientRects(root, text) { return Plan.parseClientRects(text) }

  function isAddressOnWorkspace(root, address, name) {
    var rect = Plan.rectFor(root.clientRects, address)
    if (rect) return String(rect.workspace) === String(name)
    var h = root.liveHyprToplevelForAddress(address)
    if (!h || !h.workspace) return false
    return String(h.workspace.name || h.workspace.id) === String(name)
  }
  function reshapeAt(root, address) {
    if (!address) return
    root.withoutPointerWarp(function() {
      root.hyprDispatch('hl.dsp.focus({ window = "address:' + address + '" })',
                        "focuswindow address:" + address)
      root.hyprDispatch('hl.dsp.layout("togglesplit")', "layoutmsg togglesplit")
    })
  }
  function recordParkSlot(root, address, origin) {
    if (!address || !origin || origin === root.minimizedWorkspace) return
    var rows = Plan.windowsOnWorkspace(root.clientRects, origin)
    // The whole workspace is recorded, not just the parked window: parking one
    // window makes its neighbours grow, and Hyprland rebuilds the tree on the
    // way back, so they can return shuffled. Every rectangle is what has to be
    // restored, and the rectangles are the only thing both layouts agree on.
    var layout = {}
    var own = null
    for (var i = 0; i < rows.length; i++) {
      layout[rows[i].address] = { x: rows[i].rect.x, y: rows[i].rect.y, w: rows[i].rect.w, h: rows[i].rect.h }
      if (rows[i].address === address) own = layout[rows[i].address]
    }
    // No geometry yet (the hyprctl snapshot is a beat behind): the window is
    // simply restored the way it was before this feature existed.
    if (!own) return
    var slots = {}
    for (var k in root.parkSlots) slots[k] = root.parkSlots[k]
    slots[address] = { workspace: String(origin), rect: own, layout: layout, attempts: 0 }
    root.parkSlots = slots
  }
  function applySlotFix(root, address) {
    var slot = (root.parkSlots || {})[address]
    if (!slot) return true
    var rows = Plan.windowsOnWorkspace(root.clientRects, slot.workspace)
    var mine = null
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].address === address) mine = rows[i].rect
    }
    if (!mine) return true                       // the window is gone
    var wrong = Plan.firstWrongRect(rows, slot.layout)
    if (!wrong) return true                      // everything is home

    // 1. The usual case: same rectangles, wrong assignment. Sort the assignment
    //    in one go — the exchanges all land in the same compositor transaction.
    if (!slot.planTried) {
      slot.planTried = true
      var plan = Plan.slotSwapPlan(rows, slot.layout)
      if (plan.length > 0) {
        var code = []
        for (var p = 0; p < plan.length; p++) {
          code.push('hl.dispatch(hl.dsp.window.swap({ window = "address:' + plan[p][0]
            + '", target = "address:' + plan[p][1] + '" }))')
        }
        Quickshell.execDetached(["hyprctl", "eval", code.join("; ")])
        return false
      }
    }

    // 2. The tree took another shape while the window was parked (no rectangle
    //    matches an owner): only flipping a split can reshape it. Which window
    //    to flip is not deducible, so each window that is out of place gets one
    //    try before the dock gives up and leaves the layout as Hyprland made it.
    if (!(slot.tried instanceof Array)) slot.tried = []
    var candidate = ""
    for (var w = 0; w < rows.length; w++) {
      var a = rows[w].address
      var want = slot.layout[a]
      if (!want || Plan.rectsClose(rows[w].rect, want)) continue
      if (slot.tried.indexOf(a) >= 0) continue
      candidate = a
      break
    }
    if (!candidate) return true                  // every reshape tried: give up
    slot.tried.push(candidate)
    reshapeAt(root, candidate)
    return false
  }
  function runSlotFixes(root) {
    var queue = root.pendingSlotFixes ? root.pendingSlotFixes.slice() : []
    if (queue.length === 0) return 0
    var slots = {}
    for (var k in root.parkSlots) slots[k] = root.parkSlots[k]
    var left = []
    for (var i = 0; i < queue.length; i++) {
      var address = queue[i]
      var slot = slots[address]
      if (!slot) continue
      var done = applySlotFix(root, address)
      var attempts = (slot.attempts || 0) + 1
      if (done || attempts >= 16) {
        delete slots[address]
      } else {
        slot.attempts = attempts
        left.push(address)
      }
    }
    root.parkSlots = slots
    root.pendingSlotFixes = left
    if (left.length > 0) {
      console.warn("[omadock] Tiling place not restored for", left.length, "window(s) — layout changed while parked")
    } else if (root.slotFixFocus) {
      // Reshaping focuses windows of its own; the user is looking at the window
      // they restored, so that is where the focus goes back to.
      var back = root.slotFixFocus
      root.slotFixFocus = ""
      root.withoutPointerWarp(function() {
        root.hyprDispatch('hl.dsp.focus({ window = "address:' + back + '" })',
                          "focuswindow address:" + back)
      })
    }
    return left.length
  }
  function otherWorkspaceWithWindows(root, exceptName) {
    if (!Hyprland.workspaces) return ""
    var list = Hyprland.workspaces.values || []
    for (var i = 0; i < list.length; i++) {
      var ws = list[i]
      if (!ws) continue
      var name = String(ws.name || "")
      if (name === "") name = String(ws.id)
      if (name === "" || name.indexOf("special:") === 0) continue
      if (String(exceptName) === name) continue
      if (Plan.windowCountOnWorkspace(root.clientRects, name) <= 0) continue
      return name
    }
    return ""
  }
  function releaseKeyboard(root, name) {
    var rest = otherWorkspaceWithWindows(root, name)
    if (!rest) {
      root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(name) + '" })',
                        "workspace " + name)
      return
    }
    if (Hyprland.usingLua) {
      Quickshell.execDetached(["hyprctl", "eval",
        'hl.dispatch(hl.dsp.focus({ workspace = "' + root.luaString(rest) + '" }));'
          + ' hl.dispatch(hl.dsp.focus({ workspace = "' + root.luaString(name) + '" }))'])
    } else {
      root.hyprDispatch("", "workspace " + rest)
      root.hyprDispatch("", "workspace " + name)
    }
  }
  function standingWindowOnWorkspace(root, name, exceptAddress) {
    var i, a
    for (i = 0; i < root.focusOrder.length; i++) {
      a = root.focusOrder[i]
      if (!a || a === exceptAddress) continue
      var h = root.liveHyprToplevelForAddress(a)
      if (h && !root.isWinParkedLive(h) && isAddressOnWorkspace(root, a, name)) return h
    }
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (i = 0; i < list.length; i++) {
      a = root.windowAddress(list[i])
      if (!a || a === exceptAddress) continue
      if (root.isWinParkedLive(list[i])) continue
      if (isAddressOnWorkspace(root, a, name)) return list[i]
    }
    return null
  }
  function handoffFocusAfterPark(root, address, focusNext, appId) {
    // The origin workspace is bookkeeping the dock already keeps
    // (minimizedOrigins); the recorded place adds the rank on top, and is only
    // available once that window's geometry is readable.
    var name = String((root.minimizedOrigins && root.minimizedOrigins[address]) || "")
    if (!name) {
      var slot = (root.parkSlots || {})[address]
      name = slot ? String(slot.workspace) : ""
    }
    var target = ""

    // 1. The app's own next window, when it sits on the same workspace.
    if (name && focusNext && focusNext.address && root.windowAddress(focusNext) !== address
        && isAddressOnWorkspace(root, root.windowAddress(focusNext), name))
      target = root.windowAddress(focusNext)

    // 2. Any standing window on that same workspace.
    if (!target && name) {
      var sibling = standingWindowOnWorkspace(root, name, address)
      if (sibling) target = root.windowAddress(sibling)
    }

    if (target) {
      root.withoutPointerWarp(function() {
        root.hyprDispatch('hl.dsp.focus({ window = "address:' + root.luaString(target) + '" })',
                          "focuswindow address:" + target)
      })
      return
    }

    // 3. Nothing left on that workspace: hand the keyboard back to the desktop.
    if (name) {
      releaseKeyboard(root, name)
      return
    }

    // No recorded workspace (unreadable geometry): keep the old behaviour
    // rather than leave the keyboard parked.
    var prev = root.standingWindowAfterPark(address)
    if (!prev) return
    var target2 = root.windowAddress(prev)
    if (!target2) return
    root.withoutPointerWarp(function() {
      root.hyprDispatch('hl.dsp.focus({ window = "address:' + root.luaString(target2) + '" })',
                        "focuswindow address:" + target2)
    })
  }}
