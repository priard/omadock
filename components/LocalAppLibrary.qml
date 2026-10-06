import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../DockModel.js" as DockModel

// Fallback standalone application library for host capability gates (e.g.
// Omarchy 4.x scoped plugins) plus the absolute-path icon index (see
// AGENTS.md "Icon Resolution"). Non-visual helper component: the dock root
// passes itself as rootRef; the scan process and its coalescing watcher are
// private to this component.

  Item {
    id: localAppLibrary

    property var rootRef: null
    width: 0
    height: 0

    signal appsChanged()

    // Absolute-path icon index, mirroring the host AppLibrary. Qt's themed
    // lookup resolves against the *configured* icon theme, so a theme that is
    // named but not installed (e.g. Omarchy's vantablack -> "Yaru-gray", which
    // yaru-icon-theme no longer ships) makes Quickshell.iconPath() return ""
    // for every name and the dock renders blank slots. The host's own menu
    // survives that because it consults this index first; the fallback library
    // has to do the same or it is strictly more fragile than the host.
    property var iconIndex: ({})

    function sortedEntries(query) {
      try {
        var values = DesktopEntries.applications.values
        if (!values) return []
        return values.filter(function(e) { return !e.noDisplay })
      } catch (e) {
        console.warn("[omadock] Failed reading desktop entries:", e)
        return []
      }
    }

    function entryName(entry) {
      if (!entry) return ""
      var target = (entry && entry.entry) ? entry.entry : entry
      var n = String(target.name || "")
      return n !== "" ? n : String(target.id || "")
    }

    function iconSource(icon) {
      var value = String(icon || "")
      if (value === "") return localAppLibrary.fallbackIcon()
      if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
      if (value.charAt(0) === "/") return Util.fileUrl(value)
      // Reading iconIndex registers the dependency, so swapping the property
      // after a scan re-evaluates every binding that called through here.
      var found = localAppLibrary.iconIndex[value]
      if (found) return Util.fileUrl(found)
      var themed = ""
      try {
        themed = Quickshell.iconPath(value, true)
      } catch (e) {
        console.warn("[omadock] Failed resolving themed icon path:", value, e)
      }
      if (themed && themed.length > 0) return themed
      return localAppLibrary.fallbackIcon()
    }

    // Generic placeholder, resolved through the same index so it survives a
    // broken theme too. Returns "" only if nothing at all is on disk, which
    // callers already treat as "draw nothing".
    function fallbackIcon() {
      var found = localAppLibrary.iconIndex["application-x-executable"]
      if (found) return Util.fileUrl(found)
      var themed = ""
      try {
        themed = Quickshell.iconPath("application-x-executable", true)
      } catch (e) {
        console.warn("[omadock] Failed resolving fallback icon path:", e)
      }
      return themed || ""
    }

    function refreshIcons() {
      if (!iconIndexScan.running) iconIndexScan.running = true
    }

    // SVGs before PNGs so the first hit per name is the scalable one; awk
    // keeps only that first hit, so QML parses ~2 300 lines instead of ~23 600.
    function iconIndexScanCommand() {
      return [
        'dirs="$HOME/.icons $HOME/.local/share/icons";',
        'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
        '{ for ext in svg png; do',
        '  for base in $dirs; do',
        '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/places/*" -o -path "*/mimetypes/*" \\) -name "*.$ext" 2>/dev/null;',
        '  done;',
        '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
        'done; } | awk -F/ \'{ n = $NF; sub(/\\.[^.]*$/, "", n); if (!(n in seen)) { seen[n] = 1; print } }\''
      ].join(' ')
    }

    function launch(desktopId, name) {
      var id = String(desktopId || "")
      if (id === "") return
      // Always append .desktop — DesktopEntry.id strips the extension, so
      // ids like org.telegram.desktop need it re-added to resolve correctly.
      // Redirect stdout and stderr to /dev/null so spawned applications don't inherit
      // transient QProcess pipes that close when gtk-launch exits (causing EPIPE crashes).
      var args = ["bash", "-c", "exec uwsm-app -- gtk-launch -- \"$1\" >/dev/null 2>&1", "_", id + ".desktop"]
      var desktop = DockModel.entryFor(rootRef.appRows, id)
      // GTK's generic terminal launch loses the CLI app-id, so a known CLI
      // product would come back wearing its terminal's identity. Route only
      // those two through Omarchy's TUI wrapper with the already parsed argv;
      // every other terminal entry keeps its normal launch path.
      if (desktop && DockModel.isKnownCli(id) && desktop.runInTerminal && desktop.command && desktop.command.length > 0) {
        var tuiCommand = ["omarchy-launch-tui", "--app-id=org.omarchy." + id].concat(DockModel.toArray(desktop.command))
        args = ["bash", "-c", 'cd -- "$1" || exit; shift; exec "$@" >/dev/null 2>&1',
                "_", desktop.workingDirectory || Quickshell.env("HOME")].concat(tuiCommand)
      }
      // gtk-launch exits non-zero up front when the desktop file no longer
      // resolves (stale pin, uninstalled app), but execDetached cannot
      // observe exit codes. Launches run through launchProc so failures
      // surface a notification instead of bouncing silently. The overlap
      // fallback keeps rare concurrent clicks fire-and-forget; the probe
      // itself exits within milliseconds.
      if (launchProc.running) {
        Quickshell.execDetached(args)
        return
      }
      launchProc.pendingName = String(name || id)
      launchProc.command = args
      launchProc.running = true
    }

    // One-shot scans only: started on load, on app-list changes and on theme
    // changes. Nothing polls, so the dock stays at 0% CPU when idle.
    Process {
      id: iconIndexScan
      command: ["bash", "-c", localAppLibrary.iconIndexScanCommand()]
      // One collected read, parsed once: a callback per line cost ~23 600
      // GUI-thread calls on every start and theme change.
      stdout: StdioCollector { id: iconIndexOut; waitForEnd: true }
      onExited: {
        localAppLibrary.iconIndex = DockModel.parseIconIndex(iconIndexOut.text)
        localAppLibrary.appsChanged()
      }
    }

    // Coalesces bursts of app-list changes (one package install touches many
    // entries) into a single rescan.
    Timer {
      id: iconIndexDebounce
      interval: 750
      onTriggered: localAppLibrary.refreshIcons()
    }

    Connections {
      target: (rootRef.appLibrary === localAppLibrary && typeof DesktopEntries !== "undefined") ? DesktopEntries : null
      function onApplicationsChanged() {
        iconIndexDebounce.restart()
        localAppLibrary.appsChanged()
      }
    }
}
