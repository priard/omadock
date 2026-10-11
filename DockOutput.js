// Whether the dock's output can take window captures (minimized-tile and
// tooltip previews). Hyprland 0.56 aborts when a toplevel capture starts
// while its output is gone (CScreenshareSession::init after "Connector
// disconnected"): a monitor that drops its link in standby, with the dock
// reloading and its tiles asking for frames, took the compositor down. So
// captures wait for an output that is there, enabled and powered. Plain JS,
// node-tested like the other modules.
//
// screenName: the dock's screen (Quickshell); monitor: Hyprland's monitor
// for it (HyprlandMonitor, or null). Before Hyprland's first monitor
// refresh lastIpcObject is empty: the monitor exists, so it is trusted.
function outputAwake(screenName, monitor) {
  var name = String(screenName || "")
  if (name === "" || name === "FALLBACK" || !monitor) return false
  if (String(monitor.name || "") !== name) return false
  var ipc = monitor.lastIpcObject || {}
  if (ipc.disabled === true) return false
  if (ipc.dpmsStatus === false) return false
  return true
}
