import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Hover bubble for an item: shows after tooltipDelay, above its parent, in
// its own popup surface (TooltipWindow), so the dock layer needs no room
// for it. The item itself has no size; place it anywhere inside the target.
Item {
  id: bubble

  property string text: ""
  property bool hovered: false
  property bool blocked: false
  property bool shown: false

  property bool showTooltips: true
  property int tooltipDelay: 450
  property string contextAppId: ""

  width: 0
  height: 0

  onHoveredChanged: {
    if (bubble.hovered) dwell.restart()
    else {
      dwell.stop()
      bubble.shown = false
    }
  }

  onBlockedChanged: if (bubble.blocked) {
    dwell.stop()
    bubble.shown = false
  }

  Timer {
    id: dwell
    interval: bubble.tooltipDelay
    onTriggered: bubble.shown = true
  }

  // The popup window exists only while the bubble is shown.
  LazyLoader {
    active: bubble.shown && bubble.text !== "" && bubble.showTooltips && !bubble.blocked && bubble.contextAppId === ""

    TooltipWindow {
      target: bubble.parent
      gap: Style.space(8)
      shown: true
      body: bubbleSurface

      BorderSurface {
        id: bubbleSurface
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius
        padding: Style.space(4)
        width: bubbleLabel.implicitWidth + contentLeftInset + contentRightInset
        height: bubbleLabel.implicitHeight + contentTopInset + contentBottomInset

        Text {
          id: bubbleLabel
          x: bubbleSurface.contentLeftInset
          y: bubbleSurface.contentTopInset
          text: bubble.text
          textFormat: Text.PlainText
          color: Color.tooltip.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

}
