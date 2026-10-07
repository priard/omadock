import QtQuick
import qs.Commons
import qs.Ui

// The running-indicator row under a dock item: one mark per window — the
// focused window's mark turns into the accent bar, parked windows become
// hollow dots — with dense marks and a compact "+N" pill past five. Apps
// and app groups draw through this one row, so a foldered app's marks can
// never drift from a pinned app's.
//
// Mark count runs on windowList: an app that runs with no window (a launch
// race, a tray-bound player) still shows one mark via `running`.
Item {
  id: marks

  property var rootRef: null
  readonly property var root: rootRef
  property var windows: []
  property bool running: false
  // Fallback for a mark with no window to name: the first mark shows the
  // active bar while the item (or an app group's member) holds the focus.
  property bool focused: false
  // Fallback minimized state for the same case: every window parked.
  property bool allMinimized: false
  property bool urgent: false
  // 0..1 breathing for urgent marks, driven by the item.
  property real pulse: 1.0
  // A column instead of a row (side indicators on a label plate).
  property bool vertical: false
  // Ink when the marks stand on a label plate (transparent: the dock's own).
  property color markInk: "transparent"

  readonly property int totalWindowCount: (marks.windows && marks.windows.length > 0) ? marks.windows.length : (marks.running ? 1 : 0)
  readonly property int maxVisibleDots: marks.totalWindowCount > 5 ? 4 : Math.min(marks.totalWindowCount, 5)
  readonly property real dynamicSpacing: marks.totalWindowCount >= 5 ? Style.space(2) : Style.space(3)

  visible: marks.running
  width: indicatorRow.width
  height: indicatorRow.height

  function isWinMinimized(w) {
    if (!w || !marks.root) return marks.allMinimized
    return (w.isMinimized === true) || (marks.root.liveWsNameOf(w) === marks.root.minimizedWorkspace)
  }

  function isWinActive(w) {
    if (!w || !w.address || !marks.root || !marks.root.activeWindowAddress) return false
    return w.address === marks.root.activeWindowAddress
  }

  Grid {
    id: indicatorRow
    spacing: marks.dynamicSpacing
    columns: marks.vertical ? 1 : 8
    rows: marks.vertical ? 8 : 1
    flow: marks.vertical ? Grid.TopToBottom : Grid.LeftToRight
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    Repeater {
      model: marks.maxVisibleDots
      // Active window: accent bar; open window: dot; minimized: hollow dot.
      delegate: DockIndicator {
        readonly property var winObj: (marks.windows && marks.windows.length > index) ? marks.windows[index] : null
        readonly property bool winMinimized: winObj ? marks.isWinMinimized(winObj) : marks.allMinimized
        readonly property bool winActive: !winMinimized && ((winObj && winObj.address) ? marks.isWinActive(winObj) : (index === 0 && marks.focused))

        rootRef: marks.rootRef
        vertical: marks.vertical
        inkOverride: marks.markInk
        kind: winActive ? "active" : (winMinimized ? "minimized" : "window")
        dense: marks.totalWindowCount >= 5
        urgent: marks.urgent
        pulse: marks.pulse
      }
    }

    // Compact overflow pill when 6+ windows are open
    Rectangle {
      visible: marks.totalWindowCount > 5
      width: overflowText.implicitWidth + Style.space(4)
      height: Style.space(5)
      radius: (marks.root && marks.root.indicatorSquare) ? 0 : height / 2
      color: Util.alpha(marks.root ? marks.root.dockForeground : Color.bar.text, 0.20)
      border.color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 1

      Text {
        id: overflowText
        anchors.centerIn: parent
        text: "+" + (marks.totalWindowCount - marks.maxVisibleDots)
        textFormat: Text.PlainText
        color: marks.markInk.a > 0 ? marks.markInk : (marks.root ? marks.root.dockForeground : Color.bar.text)
        font.family: Style.font.family
        font.pixelSize: Math.max(7, Style.font.caption - 4)
        font.bold: true
      }
    }
  }
}
