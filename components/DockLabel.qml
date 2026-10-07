import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "../DockLabels.js" as DockLabels

// The name beside a dock tile's icon (apps, app groups, folders). Policy
// comes from root.labelStyle() (DockLabelLogic); this item shortens the name
// to the max width in its own font, animates the reveal, and reports the
// width it adds to the tile (extra) to the dock's registry, which feeds the
// zoom/wave centres and the card's hover anchor. No input handling: hover,
// drag and clicks belong to the tile.
Item {
  id: label

  property var rootRef: null
  readonly property var root: rootRef
  property string kind: "app"
  property string appId: ""
  property string name: ""
  property bool hovered: false
  property Item iconBox: null
  property int slot: -1
  // The tile's own indicator row, mirrored into a column on the plate when
  // indicators sit beside the art; and the tile's faint "running without a
  // window" mark.
  property Item marksFrom: null
  property bool backgroundMarks: false
  // A folder's open-stack bar.
  property bool openMark: false

  readonly property var style: root ? root.labelStyle(label.kind) : null
  readonly property string fullText: root ? root.labelName(label.appId, label.name) : label.name
  readonly property bool shown: !!label.style && label.style.show && label.fullText !== ""
  readonly property bool mirror: !!label.style && label.style.mirror

  // ---- text and width
  property string shortText: ""
  property bool shortened: false
  readonly property real pad: (label.style && label.style.background !== "none") ? Style.space(6) : Style.space(2)
  readonly property bool plate: !!label.style && label.style.background === "plate"
  // Indicators in a column at the plate's edge, before the icon or after the
  // name; the column's room is kept whether or not anything runs.
  readonly property bool sideMarks: label.plate && label.shown && label.style.marks !== "under"
  readonly property bool marksAfter: label.sideMarks && label.style.marks === "after"
  readonly property real markRoom: Style.space(7)
  // Before the icon, the column's room is kept ahead of the art: the tile
  // shifts its icon by this much (constant, so nothing moves with state).
  readonly property real lead: (label.sideMarks && !label.marksAfter) ? Math.round(label.progress * label.markRoom) : 0
  // Empty room between the icon slot's edge and the drawn art.
  readonly property real artMargin: label.root ? (label.root.iconSlot - label.root.baseIconArt) / 2 : Style.space(7)
  // The name is placed from the art's edge, not the slot's: bare text and a
  // pill sit 4 px off the art, a plate's text 6 px. Negative gaps reach
  // back into the slot's empty margin.
  readonly property real gap: (label.plate ? 0 : label.style && label.style.background === "pill" ? Style.space(4) : Style.space(2)) - label.artMargin
  // An icon carries its slot padding on both sides, plus the empty margin
  // inside its art; the name ends with about the same room, so a label
  // keeps the spacing an icon would before the next item, a divider or the
  // dock's edge. A plate is its own frame and needs only a little.
  readonly property real trail: label.plate ? Style.space(1) + (label.marksAfter ? label.markRoom + Style.space(3) : 0) : label.artMargin + Style.space(3)
  readonly property real naturalWidth: label.shown && label.shortText !== ""
    ? Math.ceil(textWidth.advanceWidth) + label.pad * 2 + label.gap + label.trail : 0

  // The bundled pixel font registers only while it is the chosen one.
  Loader {
    active: !!label.style && label.style.family === "Silkscreen"
    sourceComponent: FontLoader { source: Qt.resolvedUrl("../fonts/Silkscreen-Regular.ttf") }
  }
  TextMetrics { id: probe; font: textItem.font }
  TextMetrics { id: textWidth; font: textItem.font; text: label.shortText }

  function reshorten() {
    if (!label.style) return
    var limit = label.style.maxWidth - label.pad * 2 - label.gap - label.trail
    var r = DockLabels.shortenName(label.fullText, function(t) { probe.text = t; return probe.advanceWidth <= limit })
    label.shortText = r.text
    label.shortened = r.shortened
  }
  onFullTextChanged: Qt.callLater(label.reshorten)
  onStyleChanged: Qt.callLater(label.reshorten)

  // ---- open state. Hover mode opens after a short dwell so a sweep across
  // the dock does not ripple; with another label still open or closing it
  // switches at once. Never during a drag.
  property bool dwelled: false
  readonly property bool dragFree: label.root ? !label.root.dockDragActive : true
  readonly property bool wantOpen: label.shown
    && (!label.style.hover || (label.hovered && label.dwelled && label.dragFree))
  Timer {
    id: dwell
    interval: (label.root && label.root.labelsOpen > 0) ? 1 : 150
    onTriggered: label.dwelled = true
  }

  // Counted while open or closing, so the next icon skips the dwell.
  readonly property bool counts: !!label.style && label.style.hover && label.progress > 0.02
  property bool counted: false
  onCountsChanged: {
    if (!label.root || label.counts === label.counted) return
    label.root.labelsOpen += label.counts ? 1 : -1
    label.counted = label.counts
  }
  property real progress: label.wantOpen ? 1 : 0
  Behavior on progress { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  readonly property real extra: Math.round(label.progress * label.naturalWidth) + label.lead

  // ---- width registry
  readonly property string owner: String(label)
  property int _slot: -1
  function syncExtra() {
    if (!label.root) return
    if (label._slot >= 0 && label._slot !== label.slot) label.root.setLabelExtra(label._slot, label.owner, 0)
    label._slot = label.slot
    // The part ahead of the icon: a mirrored label, or the indicator lead.
    if (label.slot >= 0) label.root.setLabelExtra(label.slot, label.owner, label.extra, label.mirror ? label.extra - label.lead : label.lead)
  }
  onExtraChanged: label.syncExtra()
  onSlotChanged: label.syncExtra()
  Component.onCompleted: { label.reshorten(); label.syncExtra() }
  Component.onDestruction: {
    if (label.root && label._slot >= 0) label.root.setLabelExtra(label._slot, label.owner, 0)
    if (label.root && label.counted) label.root.labelsOpen -= 1
  }

  // ---- reveal (typewriter / scramble swap the text; slide just grows)
  property real revealT: 1
  property string revealStyle: "slide"
  property real seed: 0
  readonly property string drawnText: DockLabels.revealFrame(label.shortText, label.revealStyle, label.revealT, label.seed)
  NumberAnimation {
    id: revealAnim
    target: label; property: "revealT"; from: 0; to: 1
    duration: Math.min(300, 25 * Math.max(1, label.shortText.length))
  }
  function reveal(styleName) {
    label.revealStyle = styleName
    label.seed = Math.random() * 100
    eraseAnim.stop()
    revealAnim.restart()
  }
  // Typewriter labels erase as they close.
  NumberAnimation { id: eraseAnim; target: label; property: "revealT"; to: 0; duration: 160 }
  onWantOpenChanged: {
    if (!label.style) return
    if (label.wantOpen) label.reveal(label.style.reveal)
    else if (label.style.reveal === "typewriter") { revealAnim.stop(); label.revealStyle = "typewriter"; eraseAnim.restart() }
  }
  onShortTextChanged: if (label.wantOpen && label.style && label.revealT >= 1 && !revealAnim.running) label.reveal(label.style.reveal)

  // ---- hover sync with the icon's HoverFx
  property real hoverLevel: label.hovered ? 1 : 0
  Behavior on hoverLevel { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  readonly property string hoverEffect: label.root ? label.root.hoverEffect : ""
  readonly property real liftY: label.hoverEffect === "lift" && label.root ? -label.root.baseIconArt * 0.16 * label.hoverLevel : 0
  onHoveredChanged: {
    if (label.hovered) dwell.restart()
    else { dwell.stop(); label.dwelled = false }
    // Hover mode: the card keeps this icon under the pointer from now on.
    if (label.hovered && label.style && label.style.hover && label.root && label.root.dockCardComp)
      label.root.dockCardComp.anchorLabel(label.parent)
    if (label.hovered && label.hoverEffect === "glitch" && label.progress > 0.5) label.reveal("scramble")
  }
  readonly property real glowLevel: !label.style ? 0
    : Math.max(label.style.effect === "glow" ? 0.55 + 0.45 * label.hoverLevel : 0,
               label.hoverEffect === "glow" ? label.hoverLevel : 0)

  // ---- geometry: beside the icon, the whole tile height
  x: label.mirror ? 0 : (label.iconBox ? label.iconBox.x + label.iconBox.width : 0)
  width: label.extra - label.lead
  height: parent ? parent.height : 0
  visible: label.extra > 0

  // Plate: one surface behind icon and name. The art gets the same margin
  // on its leading side as the name on the trailing one, and the window
  // indicators under the art get the same room below as the art has above,
  // so they sit inside. Its corners stop short of a full pill so the curve
  // never cuts into the icon.
  Rectangle {
    id: plateRect
    visible: label.plate
    readonly property real artSize: label.root ? label.root.baseIconArt : 0
    readonly property real artTop: label.root ? label.height - label.root.iconArtBottom - artSize : 0
    readonly property real vMargin: Style.space(4)
    readonly property real iconW: label.iconBox ? label.iconBox.width : 0
    readonly property real edge: Style.space(1)
    // Side margin: matches the name's padding plus trail (a glyph's own
    // trailing bearing makes that side read wider), up to the slot's edge.
    readonly property real hMargin: Math.min(label.pad + label.trail, label.artMargin)
    y: artTop - vMargin
    // Indicators end Style.space(1) plus the lift above the slot floor.
    // With indicators beside the art (or none), the art gets the same
    // margin below as above.
    height: (label.sideMarks ? artTop + artSize : label.height - Style.space(1) - (label.root ? label.root.indicatorLift : 0)) + vMargin - y
    x: label.mirror ? edge : -iconW - label.lead + label.artMargin - hMargin
    width: label.mirror
      ? label.width + label.artMargin + artSize + hMargin + label.lead - edge
      : label.width - edge - x
    radius: label.style ? Math.min(height * 0.32, DockLabels.labelRadius(label.style.shape, height, label.style.dockRatio)) : 0
    color: label.style ? Util.alpha(label.style.fill, 0.55 + 0.25 * label.hoverLevel) : "transparent"
    opacity: label.progress
  }

  // Side indicators: the tile's marks as a column in the plate's margin,
  // centred on the art, before the icon or after the name.
  Item {
    id: markColumn
    visible: label.sideMarks
    opacity: label.progress
    readonly property real artSize: label.root ? label.root.baseIconArt : 0
    readonly property real iconW: label.iconBox ? label.iconBox.width : 0
    // Centred between the plate's edge and the art (before) or the name (after).
    readonly property real hMargin: plateRect.hMargin
    readonly property real centreX: label.marksAfter
      ? (label.mirror ? (Style.space(1) + label.trail + label.pad) / 2
                      : (label.width - label.trail - label.pad + label.width - Style.space(1)) / 2)
      : (label.mirror ? label.width + label.artMargin + artSize + (label.lead + hMargin) / 2
                      : -markColumn.iconW + label.artMargin - (label.lead + hMargin) / 2)
    readonly property real centreY: label.root ? label.height - label.root.iconArtBottom - artSize / 2 : 0
    x: centreX
    y: centreY

    DockIndicatorRow {
      rootRef: label.rootRef
      vertical: true
      x: -width / 2
      y: -height / 2
      windows: label.marksFrom ? label.marksFrom.windows : []
      running: label.marksFrom ? label.marksFrom.running : false
      focused: label.marksFrom ? label.marksFrom.focused : false
      allMinimized: label.marksFrom ? label.marksFrom.allMinimized : false
      urgent: label.marksFrom ? label.marksFrom.urgent : false
      pulse: label.marksFrom ? label.marksFrom.pulse : 1
    }

    DockIndicator {
      rootRef: label.rootRef
      visible: label.openMark
      vertical: true
      x: -width / 2
      y: -height / 2
      kind: "active"
    }

    DockIndicator {
      rootRef: label.rootRef
      visible: label.backgroundMarks && !(label.marksFrom && label.marksFrom.running)
      x: -width / 2
      y: -height / 2
      kind: "background"
    }
  }

  Item {
    id: clipBox
    // Reaches back over the slot margin a negative gap uses.
    anchors.fill: parent
    anchors.leftMargin: label.mirror ? 0 : Math.min(0, label.gap)
    anchors.rightMargin: label.mirror ? Math.min(0, label.gap) : 0
    clip: label.progress < 0.999

    Item {
      id: content
      x: (label.mirror ? label.trail : label.gap) - (label.mirror ? 0 : Math.min(0, label.gap))
      width: Math.max(0, label.naturalWidth - label.gap - label.trail)
      height: textItem.implicitHeight + Style.space(2)
      // Centred on the icon art, which sits on the dock floor.
      y: label.root ? Math.round(label.height - label.root.iconArtBottom - label.root.baseIconArt / 2 - height / 2) : 0
      opacity: label.progress
      transform: Translate { y: label.liftY }

      Rectangle {
        visible: !!label.style && label.style.background === "pill"
        anchors.fill: parent
        radius: label.style ? DockLabels.labelRadius(label.style.shape, height, label.style.dockRatio) : 0
        color: label.style ? label.style.fill : "transparent"
      }

      // Glow: a lightly blurred copy of the name behind it, under an outline
      // in the same light accent. A wide blur would thin a caption-sized
      // stroke to nothing.
      Text {
        anchors.fill: textItem
        visible: label.glowLevel > 0.01
        text: textItem.text
        textFormat: Text.PlainText
        font: textItem.font
        color: label.style ? label.style.glow : Color.accent
        horizontalAlignment: textItem.horizontalAlignment
        verticalAlignment: Text.AlignVCenter
        opacity: Math.min(1, label.glowLevel * 1.8)
        layer.enabled: visible
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 0.25
          blurMax: 8
          autoPaddingEnabled: true
        }
      }

      Text {
        id: textItem
        anchors.fill: parent
        anchors.leftMargin: label.pad
        anchors.rightMargin: label.pad
        text: label.drawnText
        textFormat: Text.PlainText
        color: label.style ? label.style.ink : Color.bar.text
        font.family: label.style ? label.style.family : Style.font.family
        font.pixelSize: label.style ? label.style.fontPx : Style.font.caption
        font.weight: label.style ? label.style.weight : Font.Medium
        horizontalAlignment: label.mirror ? Text.AlignRight : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        // A name with no background always gets a faint outline so it reads
        // on any dock fill; Outline makes it strong, Glow tints it.
        readonly property bool bare: !!label.style && label.style.background === "none"
        style: (label.style && (bare || label.style.effect !== "none")) ? Text.Outline : Text.Normal
        styleColor: !label.style ? "transparent"
          : label.style.effect === "glow" ? Util.alpha(label.style.glow, 0.5 + 0.4 * label.glowLevel)
          : label.style.effect === "outline" ? Util.alpha(label.style.halo, 0.85)
          : Util.alpha(label.style.halo, 0.35)
      }
    }
  }
}
