import QtQuick
import Quickshell.Io

// Capped, regular-file-gated replacement for FileView on watched mutable files.
//
// Why this exists: Quickshell's FileView loads a file's entire contents into
// shell memory at the read boundary (it allocates a buffer of file.size() and
// reads into it) before any QML can inspect the bytes. A hostile large file
// can therefore bloat the long-lived shell, and a non-regular file (FIFO)
// swapped in at the path can stall a reader — a post-hoc byte ceiling like
// DockModel.readCapped(FileView.text()) is applied too late. The cap has to
// apply BEFORE the file is loaded into QML.
//
// Mechanism: FileView here is a change *watcher* only (preload: false and no
// reload()/text()/data() call ever, so it never loads content). Content enters
// QML exclusively through the gate below — a one-shot process that first
// verifies the path is a readable regular file and then reads it bounded by
// maxBytes + 1, so it can tell "within the cap" from "over it" by counting the
// bytes it actually read. The reader is additionally bounded in time
// (timeout), so a FIFO swapped past the check can never hold a worker.
//
// The size is never taken from a stat() of the path and then trusted. Watched
// files are written atomically (FileView atomicWrites: temp file + one
// rename) and they grow as the user works, so a size read a moment before the
// rename describes the OLD file: reading exactly that many bytes of the new
// one emitted a truncated prefix of it. For omadock.json that prefix is not
// JSON, and the dock's answer to a parse failure is defaults — which emptied
// the preset list it held in memory right after a preset was saved.
//
// Behavior parity with the old FileView path:
//   - missing / non-regular / unreadable -> nothing happens (FileView's
//     loadFailed also left state untouched and never fired onLoaded)
//   - oversized regular file -> text becomes "" and loaded() fires (matches
//     DockModel.readCapped, which yields "" for over-cap input)
//   - small regular file -> text = contents, loaded() fires
//
// Writes never read the file (FileView.setText writes exactly what it is
// given), so they stay on the internal FileView: setText() passes through.
//
// A read is never applied when it is older than a write this object made. The
// write is asynchronous and the file is replaced in one rename, so a gated
// read that started before it lands after it holding the file as it was — and
// applying that undoes the save (a preset that vanished from the list right
// after being saved, pins that came back). Content read back is therefore
// accepted only when it carries the pending write, or when the retries below
// are spent, so an edit made outside the dock still wins in the end.
Item {
  id: root

  property string path: ""
  property int maxBytes: 65536
  property bool watchChanges: true
  property bool atomicWrites: true

  // Last accepted file content ("" for empty, oversized, or never-loaded).
  property string text: ""
  // The last read was refused for size: text is "" but the file is not
  // empty, so a writer must not treat it as a blank file.
  property bool oversized: false

  // The content of the last write this object made, until a read carries it;
  // see the header. Empty means no write is waiting to be confirmed.
  property string _writePending: ""
  property int _writeRetries: 0

  signal loaded()
  signal fileChanged()

  // One-shot gated read. Safe to call at any time: a superseded in-flight
  // read is terminated and re-queued. It is asynchronous: text is still the
  // previous content when reload() returns, so read it from onLoaded only.
  function reload() {
    if (!root.path) return
    gate.running = false
    gate.running = true
  }

  // The file now holds exactly content, so text follows it at once; a caller
  // merging into text (saveConfig) must not see the content from before.
  function setText(content) {
    watcher.setText(content)
    root.text = content
    // Memory follows the write at once - the caller is entitled to read it
    // back - and reads that do not carry it are held off until they do.
    root._writePending = content
    root._writeRetries = 0
  }

  // A pending write needs a moment to land, so a discarded read asks again
  // rather than spinning. Four tries is under half a second.
  Timer {
    id: writeRetry
    interval: 60
    repeat: false
    onTriggered: root.reload()
  }

  Component.onCompleted: root.reload()

  // Watcher only — see header. printErrors stays off: a missing watched file
  // is a normal desktop state (e.g. theme files), not a shell error.
  FileView {
    id: watcher
    path: root.path
    preload: false
    watchChanges: root.watchChanges
    atomicWrites: root.atomicWrites
    printErrors: false
    onFileChanged: root.fileChanged()
  }

  // $1 = path, $2 = byte ceiling. Exit 0 = content on stdout (<= $2 bytes),
  // 2 = missing / non-regular / unreadable, 3 = oversized (parity: empty).
  //
  // One read of at most $2 + 1 bytes settles both questions: the count is of
  // the bytes that actually came out, so a file replaced mid-read yields the
  // new file whole rather than a prefix of it, and the shell still never
  // receives more than $2 bytes of content. The bytes are staged in a
  // temporary file so they can be counted before any is emitted; reload()
  // stops an in-flight gate when a newer read supersedes it, so the trap is
  // what removes that staging file when this process is killed mid-read, and
  // a temporary directory that cannot be written falls back to /tmp rather
  // than leaving the dock unable to read its own config.
  readonly property string gateScript: [
    '[ -f "$1" ] && [ -r "$1" ] || exit 2',
    't=$(mktemp "${TMPDIR:-/tmp}/omadock-read.XXXXXX" 2>/dev/null || mktemp /tmp/omadock-read.XXXXXX) || exit 2',
    'trap "rm -f -- $t" EXIT',
    'timeout 2 head -c "$(( $2 + 1 ))" -- "$1" > "$t" || { rm -f -- "$t"; exit 2; }',
    'n=$(wc -c < "$t" | tr -d "[:space:]") || { rm -f -- "$t"; exit 2; }',
    '[ "$n" -le "$2" ] || { rm -f -- "$t"; exit 3; }',
    'cat -- "$t"; e=$?; rm -f -- "$t"; exit $e',
  ].join("\n")

  Process {
    id: gate
    command: ["sh", "-c", root.gateScript, "omadock-capped-read", root.path, String(root.maxBytes)]
    stdout: StdioCollector {
      id: gateOut
      waitForEnd: true
    }

    // Process flushes the stdout collector (streamEnded) before emitting
    // exited, so gateOut.text is complete here.
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        var content = gateOut.text
        // Held off: this read was started before our own write, so it is the
        // file as it was. Memory already holds the write, so applying the old
        // content would be the save undoing itself. The retries spend out and
        // an outside edit is applied as it always was.
        if (root._writePending !== "" && content !== root._writePending) {
          if (root._writeRetries < 4) {
            root._writeRetries += 1
            writeRetry.restart()
            return
          }
        }
        root._writePending = ""
        root._writeRetries = 0
        root.oversized = false
        root.text = content
        root.loaded()
      } else if (exitCode === 3) {
        root.oversized = true
        root.text = ""
        root.loaded()
      }
      // Anything else (exit 2 / reader killed by timeout / crash) leaves
      // state untouched, matching FileView's loadFailed behavior.
    }
  }
}
