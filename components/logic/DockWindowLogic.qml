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

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  function hyprToplevelFor(root, toplevel) {
    if (!toplevel || !Hyprland.toplevels) return null
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].wayland === toplevel) return list[i]
    return null
  }

  // Accepts a toplevel handle or a raw address string; every address-keyed lookup goes
  // through here (and through Plan.normalizeAddress, its pure twin) so "574e…" and
  // "0x574e…" can never diverge.
  function windowAddress(root, handle) {
    return Plan.normalizeAddress(handle && handle.address !== undefined ? handle.address : handle)
  }

  function luaString(root, value) {
    return String(value == null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  // Hyprland 0.56 moved dispatchers to Lua; Quickshell reports which syntax
  // the running compositor speaks.
  function hyprDispatch(root, lua, legacy) {
    Hyprland.dispatch(Hyprland.usingLua ? lua : legacy)
  }

  function workspaceTarget(root, workspace) {
    if (!workspace) return ""
    var name = String(workspace.name || "")
    return name !== "" ? name : String(workspace.id)
  }

  // What a *move* dispatch needs. Hyprland reaches a named workspace as "name:foo"
  // while its IPC reports the bare name (and a negative id), so a move written with the
  // bare name goes to a workspace that does not exist and the window stays parked.
  // Recorded values and every comparison stay bare: only the dispatch is named.
  // Found by tests/live/place-restore.sh.
  function workspaceDispatch(root, target) {
    var value = String(target == null ? "" : target)
    if (value === "" || value.indexOf("special:") === 0) return value
    if (/^[0-9]+$/.test(value)) return value
    return "name:" + value
  }

  function liveToplevelForAddress(root, addr) {
    if (!addr) return null
    var want = root.windowAddress(addr)
    try {
      var tops = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
      for (var i = 0; i < tops.length; i++) {
        var top = tops[i]
        if (!top) continue
        var h = root.hyprToplevelFor(top)
        if (root.windowAddress(h) === want) return top
      }
    } catch (e) {
      console.warn("[omadock] Failed resolving live toplevel for address:", e)
    }
    return null
  }

  function liveHyprToplevelForAddress(root, addr) {
    if (!addr) return null
    var want = root.windowAddress(addr)
    try {
      var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
      for (var i = 0; i < tops.length; i++) {
        var h = tops[i]
        if (h && root.windowAddress(h) === want) return h
      }
    } catch (e) {
      console.warn("[omadock] Failed resolving live Hyprland toplevel for address:", e)
    }
    return null
  }

  function focusWindowByAddress(root, addr, appId) {
    if (!addr) return
    root.clearUrgentApp(appId || "", addr)
    var handle = root.liveHyprToplevelForAddress(addr)
    var top = root.liveToplevelForAddress(addr)

    if (handle) {
      var workspace = handle.workspace
      if (workspace && workspace.name === root.minimizedWorkspace) {
        root.restoreWindow(addr, appId)
        return
      }
      root.withoutPointerWarp(function() {
        var live = root.liveToplevelForAddress(addr)
        var h = root.liveHyprToplevelForAddress(addr)
        if (!live) return
        DockModel.focusWindow(live)
        var ws = h ? h.workspace : null
        if (ws && Hyprland.focusedWorkspace && ws.id !== Hyprland.focusedWorkspace.id) {
          var targetWs = root.workspaceTarget(ws)
          if (targetWs) {
            root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                              "workspace " + targetWs)
          }
        }
      })
    } else if (top) {
      root.focusToplevel(top, appId)
    }
  }

  // Brings a window forward cleanly. Native Wayland activation hands over focus
  // and brings the window forward without desynchronizing layer-shell input
  // state; withoutPointerWarp keeps Hyprland from moving the pointer to it.
  // Switches workspace when target is on another workspace.
  function focusToplevel(root, toplevel, appId) {
    if (!toplevel) return
    var handle = root.hyprToplevelFor(toplevel)
    var addr = root.windowAddress(handle)
    if (!addr) {
      DockModel.focusWindow(toplevel)
      return
    }
    var aid = appId || (toplevel.appId ? DockModel.normalizeId(toplevel.appId) : "")
    root.clearUrgentApp(aid, addr)
    var workspace = handle ? handle.workspace : null

    if (workspace && workspace.name === root.minimizedWorkspace) {
      root.restoreWindow(handle, aid)
      return
    }

    // Resolve by address after the subprocess: a window may close meanwhile.
    root.withoutPointerWarp(function() {
      var live = addr ? root.liveToplevelForAddress(addr) : null
      if (!live) return
      DockModel.focusWindow(live)
      var h = root.liveHyprToplevelForAddress(addr)
      var ws = h ? h.workspace : null
      if (ws && Hyprland.focusedWorkspace && ws.id !== Hyprland.focusedWorkspace.id) {
        var targetWs = root.workspaceTarget(ws)
        if (targetWs) {
          root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                            "workspace " + targetWs)
        }
      }
    })
  }

  // focusNext names the app window that should take focus once this one is
  // parked — the click contract's "step to the app's next window". appId
  // carries the urgent-clear context for focusing it.
  function minimizeToplevel(root, topOrAddr, focusNext, appId) {
    var address = root.windowAddress(typeof topOrAddr === "string" ? topOrAddr : root.hyprToplevelFor(topOrAddr))
    if (!address) return false

    var wasFocused = root.activeWindowAddress === address
    var handle = root.liveHyprToplevelForAddress(address)
    var origin = (handle && handle.workspace) ? root.workspaceTarget(handle.workspace) : root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!origin || origin === root.minimizedWorkspace) origin = root.workspaceTarget(Hyprland.focusedWorkspace)
    if (origin === root.minimizedWorkspace) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    origins[address] = origin
    root.minimizedOrigins = origins

    var parkedTimes = DockModel.copyMap(root.parkedAt)
    parkedTimes[address] = Date.now()
    root.parkedAt = parkedTimes

    // Where the window sat, recorded before the move: Hyprland has no memory of
    // it and re-inserts a parked window as a new tiling window, so the place
    // has to be won back on restore.
    root.recordParkSlot(address, origin)

    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(root.minimizedWorkspace) + '", follow = false })',
      "movetoworkspacesilent " + root.minimizedWorkspace + ",address:" + address)
    if (wasFocused) root.handoffFocusAfterPark(address, focusNext || null, appId || "")
    return true
  }

  // The window to take focus when a park emptied its workspace: the most
  // recently focused window still standing, else any standing window. A parked
  // window still accepts typing, so the keyboard must never stay on one.
  function standingWindowAfterPark(root, exceptAddress) {
    var i, a
    for (i = 0; i < root.focusOrder.length; i++) {
      a = root.focusOrder[i]
      if (!a || a === exceptAddress) continue
      var h = root.liveHyprToplevelForAddress(a)
      if (h && !root.isWinParkedLive(h)) return h
    }
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (i = 0; i < list.length; i++) {
      a = root.windowAddress(list[i])
      if (!a || a === exceptAddress) continue
      if (!root.isWinParkedLive(list[i])) return list[i]
    }
    return null
  }

  // Window rectangles, keyed by address, read from hyprctl (see clientRects on
  // the root). Quickshell's per-toplevel ipc object only carries at/size for
  // windows that existed when the shell started, so the geometry of windows
  // opened since has to come from Hyprland itself.

  // Windows on a workspace in visual order — left to right, then top to bottom,
  // which is the order dwindle tiles them in.

  // Badge-proof geometry helpers: a tiling rectangle is only ever "the same"
  // within a couple of pixels (gaps, rounding, an odd pixel of the bar).

  // The window standing in a recorded rectangle right now. Overlap, not
  // equality: whatever shape the tree took while the window was parked, the
  // window covering that rectangle is the one to trade places with.

  // The state of a workspace as one string, to notice a swap that undoes a
  // previous one (a cycle) instead of getting closer.

  // The first window of the workspace (in visual order) that is not back in the
  // rectangle it was parked in.

  // Focus a window and flip its split. This is the only dispatch that changes
  // the *shape* of the tree instead of the order of its leaves, and a changed
  // shape is what parking a master leaves behind.

  // The window whose recorded rectangle is this one. Tiling rectangles are
  // distinct, so a rectangle identifies exactly one window.

  // The swaps that put every window back into the rectangle it was parked in.
  // Measured on Hyprland 0.56.2: parking and restoring is a permutation of the
  // same rectangles in every case but one — the tree assigns the wrong window to
  // each slot, but the set of slots is unchanged. A permutation is sorted with
  // n-1 exchanges, computed once: no searching, and no way to cycle. Returns []
  // when some rectangle has no owner, i.e. the tree really did change shape.

  // One pass for one window: at most one action, then the caller looks again once
  // the layout has settled. Returns true when the window is done with.

  // Runs the queue the dock root owns: returns how many windows are still
  // waiting, so the caller can come back for one more look at the layout.


  // Getting rid of the keyboard without moving the user. A parked window still
  // accepts typing (measured with wtype on Hyprland 0.56.2), so the keyboard
  // must be let go of — but handing it to a window on another workspace is what
  // made a minimize look like a workspace jump. Focusing the now empty
  // workspace is not enough either: the parked window keeps the keyboard. Two
  // focus dispatches in one Lua statement are: the empty workspace, then the
  // origin one. Both land in the same compositor frame, so the desktop never
  // visibly changes and no window holds the keyboard.

  // A window of the same workspace, most recently focused first.

  // Parking must never leave the keyboard inside the parking lot, and must
  // never move the user. The click contract says parking one of several windows
  // "hands focus straight to a sibling"; Windows keeps that sibling on the
  // workspace you are on, and so does this. Focus is dispatched, not Wayland-
  // activated: dispatchers queue in the compositor behind the park move, so
  // this deterministically beats the compositor's own handoff (an activation
  // arrived out of order and lost that race on busy workspaces).

  function restoreWindow(root, targetRef, appId, useOrigin) {
    var address = root.windowAddress(targetRef)
    if (!address) return false

    // The config decides where a plain restore lands (Windows: where the window
    // came from). Call sites that mean something specific pass it explicitly.
    if (useOrigin === undefined) useOrigin = root.restoreWorkspace === "origin"

    // Default restore target is the workspace the user is on right now;
    // useOrigin=true sends the window back to where it was parked from.
    var target = ""
    if (useOrigin && root.minimizedOrigins[address]) target = root.minimizedOrigins[address]
    if (!target) target = root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!target) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    delete origins[address]
    root.minimizedOrigins = origins

    var parkedTimes = DockModel.copyMap(root.parkedAt)
    delete parkedTimes[address]
    root.parkedAt = parkedTimes

    // Silent move (follow = false): a dispatcher-driven window focus would
    // warp the mouse pointer into the restored window's center. The workspace
    // switch plus native Wayland activation below focus the window cleanly
    // and leave the cursor exactly where the user left it.
    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(workspaceDispatch(root, target)) + '", follow = false })',
      "movetoworkspacesilent " + target + ",address:" + address)
    root.withoutPointerWarp(function() {
      root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(target) + '" })',
                        "workspace " + target)

      var top = root.liveToplevelForAddress(address)
      if (top) {
        DockModel.focusWindow(top)
      }
    })

    // Win the recorded place back once the layout has settled — only when the
    // window actually went home; a "restore here" has no place to win back.
    var slot = (root.parkSlots || {})[address]
    if (slot && root.restoreSlot && String(slot.workspace) === String(target)) root.scheduleSlotFix(address)
    else root.dropParkSlot(address)
    return true
  }

  // Restores a group of windows in one compositor transaction:
  // all moves are dispatched silently first, then workspace focus and window
  // activation happen exactly once. This prevents the "one-by-one fullscreen"
  // flash that occurs when restoreWindow() is called in a loop (each call
  // previously triggered its own focus switch and Wayland activation).
  //
  // primaryAddress: the window to focus after all moves. When null/undefined,
  // the most-recently-parked window (highest parkedAt timestamp) is chosen.
  //
  // useOrigin: when true, each window returns to the workspace it was parked
  // from (minimizedOrigins). Default restores everything onto the user's
  // currently active workspace.
  function restoreWindowBatch(root, wins, primaryAddress, useOrigin) {
    if (!wins || wins.length === 0) return

    if (useOrigin === undefined) useOrigin = root.restoreWorkspace === "origin"

    // Single-copy the maps — O(n) instead of O(n²) individual copies.
    var origins = DockModel.copyMap(root.minimizedOrigins)
    var parkedTimes = DockModel.copyMap(root.parkedAt)
    // Where each window was actually sent, collected while the maps are still
    // populated (they are emptied as we go).
    var targets = {}

    var focusAddr = null
    var focusTarget = null
    var bestTime = -1

    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (!w || !w.address) continue
      var address = w.address

      var target = ""
      if (useOrigin && origins[address]) target = origins[address]
      if (!target) target = root.workspaceTarget(Hyprland.focusedWorkspace)
      if (!target) continue

      var t = parkedTimes[address] !== undefined ? parkedTimes[address] : 0
      targets[address] = String(target)
      delete origins[address]
      delete parkedTimes[address]

      // Silent move only — no workspace switch or window focus per iteration.
      root.hyprDispatch(
        'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
          + root.luaString(workspaceDispatch(root, target)) + '", follow = false })',
        "movetoworkspacesilent " + target + ",address:" + address)

      // Track which window to focus: explicit override first, then most-recently-parked.
      if (primaryAddress && address === primaryAddress) {
        focusAddr = address
        focusTarget = target
        bestTime = Infinity
      } else if (bestTime !== Infinity && t >= bestTime) {
        bestTime = t
        focusAddr = address
        focusTarget = target
      }
    }

    // Commit map mutations once.
    root.minimizedOrigins = origins
    root.parkedAt = parkedTimes

    // Same deal as a single restore: recorded places are won back, and
    // windows that went somewhere else drop their record.
    for (var j = 0; j < wins.length; j++) {
      var wj = wins[j]
      if (!wj || !wj.address) continue
      var slot2 = (root.parkSlots || {})[wj.address]
      if (!slot2) continue
      var want = targets[wj.address] || ""
      if (want && root.restoreSlot && String(slot2.workspace) === want) root.scheduleSlotFix(wj.address)
      else root.dropParkSlot(wj.address)
    }

    // Single workspace switch + single window activation after all moves.
    if (focusTarget) {
      root.withoutPointerWarp(function() {
        root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(focusTarget) + '" })',
                          "workspace " + focusTarget)
        var top = root.liveToplevelForAddress(focusAddr)
        if (top) DockModel.focusWindow(top)
      })
    }
  }

  // The workspace a window sits on right now. Model primitives freeze state at
  // rebuild time, and Quickshell's Hyprland handle can lag silent moves onto
  // the special workspace, so park/visibility decisions resolve live at click
  // time and fall back to the cached name only while no handle exists.
  function liveWsNameOf(root, win) {
    var cached = win ? String(win.workspaceName || "") : ""
    var addr = win ? root.windowAddress(win) : ""
    var h = addr ? root.liveHyprToplevelForAddress(addr) : null
    if (h && h.workspace) return String(h.workspace.name || h.workspace.id || "")
    if (addr && root.minimizedOrigins && root.minimizedOrigins[addr] !== undefined)
      return root.minimizedWorkspace
    return cached
  }

  function isWinParkedLive(root, win) {
    return root.liveWsNameOf(win) === root.minimizedWorkspace
  }

  // The window an app should act on: the one it was last focused in, as long as
  // it is still around and not parked.
  function windowByAddress(root, windows, address) {
    if (!address) return null
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win) continue
      if (win.address === address) {
        return !root.isWinParkedLive(win) ? win : null
      }
    }
    return null
  }

  // The app's windows that are still on screen, in window order.
  function visibleWindows(root, windows) {
    var out = []
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win) continue
      if (!root.isWinParkedLive(win)) out.push(win)
    }
    return out
  }

  // Which of these windows holds the focus, if any.
  function focusedIndex(root, windows) {
    if (!root.activeWindowAddress) return -1
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].address && windows[i].address === root.activeWindowAddress) return i
    }
    return -1
  }

  // A window of this app on the workspace you are looking at.
  function windowHere(root, windows) {
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      var wsName = root.liveWsNameOf(win)
      if (win && (wsName === String(root.focusedWorkspaceId) || wsName === root.focusedWorkspaceName)) {
        return win
      }
    }
    return null
  }

  function wheelStep(root, key, angleDelta) {
    if (!angleDelta) return 0
    var now = Date.now()
    var st = root.wheelState[key] || { acc: 0, lastEvent: 0, lastStep: 0 }
    if (now - st.lastEvent > 400 || (st.acc !== 0 && (st.acc > 0) !== (angleDelta > 0))) st.acc = 0
    st.lastEvent = now
    st.acc += angleDelta
    var step = 0
    if (Math.abs(st.acc) >= 120) {
      if (now - st.lastStep >= root.wheelStepDelay) {
        step = st.acc > 0 ? -1 : 1
        st.lastStep = now
      }
      st.acc = 0
    }
    // Reuse one slot per current target rather than retaining every app ever scrolled.
    root.wheelState = ({})
    root.wheelState[key] = st
    return step
  }

  // One step around the app's windows from wherever the focus is.
  function stepWindow(root, windows, direction) {
    if (windows.length === 0) return null
    if (windows.length === 1) return windows[0]

    var step = direction < 0 ? -1 : 1
    var at = root.focusedIndex(windows)
    if (at < 0) return windows[step > 0 ? 0 : windows.length - 1]
    return windows[(at + step + windows.length) % windows.length]
  }

  // Handles of this app's parked windows, in window order. Nothing is
  // remembered for this: the workspace a window sits on is the answer, so a
  // shell restart cannot lose track of one.
  function parkedWindows(root, windows) {
    var out = []
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (win && root.isWinParkedLive(win)) out.push(win)
    }
    return out
  }

  // The app's parked window that has been waiting the shortest time — the tail of
  // the chronological FIFO. Windows parked most recently sort first.
  function recentParked(root, parked) {
    if (!parked || parked.length <= 1) return (parked && parked[0]) || null
    var best = parked[0]
    var bestTime = (best && best.address && root.parkedAt[best.address] !== undefined) ? root.parkedAt[best.address] : 0
    for (var i = 1; i < parked.length; i++) {
      var p = parked[i]
      var t = (p && p.address && root.parkedAt[p.address] !== undefined) ? root.parkedAt[p.address] : 0
      if (t > bestTime) {
        best = p
        bestTime = t
      }
    }
    return best
  }

  // The app's parked window that has been waiting the longest — the head of
  // the chronological FIFO. Windows parked before this shell session have no
  // timestamp and sort first, matching the "recover the oldest" expectation.
  function oldestParked(root, parked) {
    if (!parked || parked.length <= 1) return (parked && parked[0]) || null
    var best = parked[0]
    var bestTime = (best && best.address && root.parkedAt[best.address] !== undefined) ? root.parkedAt[best.address] : 0
    for (var i = 1; i < parked.length; i++) {
      var p = parked[i]
      var t = (p && p.address && root.parkedAt[p.address] !== undefined) ? root.parkedAt[p.address] : 0
      if (t < bestTime) {
        best = p
        bestTime = t
      }
    }
    return best
  }

  function recentWindow(root, appId, windows) {
    return root.windowByAddress(windows, root.appRecentWindow[appId])
  }

  function minimizeAllWindows(root, entry) {
    var windows = entry ? (entry.windowList || []) : []
    var parked = false
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win || !win.address) continue
      if (!root.isWinParkedLive(win) && root.minimizeToplevel(win.address))
        parked = true
    }
    return parked
  }

  // The one window this app should put away: the focused one, else the one it
  // was last focused in, else the first that is still on screen.
  function minimizeOneWindow(root, entry) {
    var windows = entry ? (entry.windowList || []) : []
    var target = null

    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].address && windows[i].address === root.activeWindowAddress) {
        target = windows[i]
        break
      }
    }
    if (!target) target = root.recentWindow(entry ? entry.appId : "", windows)
    if (!target) {
      for (var j = 0; j < windows.length; j++) {
        if (windows[j] && !root.isWinParkedLive(windows[j])) {
          target = windows[j]
          break
        }
      }
    }

    return (target && target.address)
      ? root.minimizeToplevel(target.address, root.stepWindow(root.visibleWindows(windows), 1), entry ? entry.appId : "")
      : false
  }

  function minimizeApp(root, entry) {
    return root.minimizeMode === "all"
      ? root.minimizeAllWindows(entry)
      : root.minimizeOneWindow(entry)
  }

  // ------------------------------------------------- external keybind hooks
  // Hyprland plugins cannot register compositor binds directly, but these IPC
  // targets expose dock actions to `qs -p /usr/share/omarchy/shell ipc call omadock <fn>`
  // so users can bind them in ~/.config/hypr/bindings.lua, e.g.:
  //   o.bind("SUPER + M", "Minimize focused",
  //     "exec qs -p /usr/share/omarchy/shell ipc call omadock minimizeActive")
  function minimizeActive(root) {
    var addr = root.activeWindowAddress
    if (addr !== "") root.minimizeToplevel(addr)
  }

  // Returns whether a window was restored, so DockHost can fall through to the
  // next monitor's dock when this one has nothing parked.
  function restoreLast(root) {
    var parked = []
    var all = root.pinnedSection.concat(root.runningSection)
    for (var i = 0; i < all.length; i++) {
      if (!all[i]) continue
      parked = parked.concat(root.parkedWindows(all[i].windowList || []))
    }
    if (parked.length === 0) return false
    return root.restoreWindow(root.oldestParked(parked), "")
  }

  // ------------------------------------------------- what a click means
  //
  // A left click says "give me this app". Everything below is decided from live
  // state only — which windows exist, which are parked, whether the focus is
  // already inside the app — so there is nothing to remember and nothing to go
  // stale:
  //
  //   no windows                      launch it
  //   focus elsewhere, something parked   bring the parked one back
  //   focus elsewhere                  focus it, preferring this workspace
  //   focus inside, mode "all"         park the whole app
  //   focus inside, several open       step to the app's next window
  //   focus inside, one open           park it, when parking is on
  //
  // Two of those rules carry the weight. Preferring a window on the current
  // workspace keeps a click from teleporting you while the app is already in
  // front of you. Stepping through windows is what makes every click on a
  // multi-window app do something visible: parking one of several hands focus
  // straight to a sibling, so the app never stops being active, and both a
  // park-first and a restore-first rule end up stuck — one parks forever, the
  // other toggles one window forever. Stepping has no such corner, and a
  // specific window can still be parked from the context menu.
  function activate(root, appId) {
    if (!root.appLibrary) return

    var entry = root.entryForId(appId)
    var windows = entry ? (entry.windowList || []) : []
    if (!entry || !entry.running || windows.length === 0) {
      root.launchApp(appId, entry)
      return
    }

    var visible = root.visibleWindows(windows)
    var parked = root.parkedWindows(windows)
    var focusedIdx = root.focusedIndex(visible)


    // Check if this application has any urgent windows or is currently bouncing
    var hadUrgency = false
    var urgentWin = null
    for (var u = 0; u < visible.length; u++) {
      var ua = visible[u] ? visible[u].address : ""
      if (ua && root.urgentMap[ua]) {
        urgentWin = visible[u]
        hadUrgency = true
        break
      }
    }

    var urgentParked = null
    for (var p = 0; p < parked.length; p++) {
      var pa = parked[p] ? parked[p].address : ""
      if (pa && root.urgentMap[pa]) {
        urgentParked = parked[p]
        hadUrgency = true
        break
      }
    }

    // Clear urgency map entries for this application immediately on click
    if (root.urgentMap[appId]) hadUrgency = true
    root.clearUrgentApp(appId, "")

    // If an urgent window is parked/minimized: restore it directly to its origin workspace
    if (urgentParked) {
      root.restoreWindow(urgentParked.address || urgentParked, appId, true)
      return
    }

    // If this app was urgent and not yet focused on screen, focus or restore directly without minimizing
    if (hadUrgency && focusedIdx < 0) {
      if (urgentWin && urgentWin.address) {
        root.focusWindowByAddress(urgentWin.address, appId)
        return
      }
      if (parked.length > 0) {
        root.restoreWindow(root.oldestParked(parked), appId, true)
        return
      }
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
      return
    }


    // 1. If an active window of this application is currently focused
    if (focusedIdx >= 0) {
      if (hadUrgency) {
        // Attention Priority Rule: Clicking an urgent app acknowledges attention and keeps the app in front without minimizing.
        return
      }

      if (root.minimizeMode === "all") {
        root.minimizeAllWindows(entry)
        return
      }
      if (root.minimizeMode === "active") {
        if (visible[focusedIdx] && visible[focusedIdx].address) {
          root.minimizeToplevel(visible[focusedIdx].address, root.stepWindow(visible, 1), appId)
        } else {
          root.minimizeOneWindow(entry)
        }
        return
      }
      // If minimize is disabled ("off"), cycle through visible windows
      if (visible.length > 1) {
        var next = root.stepWindow(visible, 1)
        if (next && next.address) root.focusWindowByAddress(next.address, appId)
        return
      }
      return
    }

    // 2. Nothing focused: bring a visible window of this app forward
    // (preferring current workspace, then recent, then first).
    if (visible.length > 0) {
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
    } else if (parked.length > 0) {
      // Restore the window (preferring most recently parked, or oldest)
      root.restoreWindow(root.recentParked(parked) || root.oldestParked(parked), appId)
    }
  }

  // Menu rows name the workspace a window sits on, including the parked ones.
  function windowRowLabel(root, window) {
    var title = String((window && window.title) || "Window")
    var wsName = root.liveWsNameOf(window)
    var isMin = wsName === root.minimizedWorkspace
    var label = isMin ? "minimized" : (wsName !== "" ? wsName : "")
    return label !== "" ? "[" + label + "] " + title : title
  }
}
