import QtQuick
import qs.Commons
import qs.Ui
import "../../DockLabels.js" as DockLabels

// Settings page: name labels beside the dock icons — when they show, how
// they look, and per-app names. Instantiated by SettingsPanel, which injects
// root (the Dock) and panel.

Column {
  id: labelsPage
  property var root: null
  property var panel: null
  width: parent.width

  SectionLabel { text: "Labels" }

  ChoiceRow {
    key: "labelMode"
    label: "Labels"
    hint: "Names beside the icons: always, or slid out while the pointer rests on an icon."
    options: [
      { value: "off", label: "Off" },
      { value: "always", label: "Always" },
      { value: "hover", label: "On hover" }
    ]
    value: root ? root.labelMode : "off"
    onPicked: function(v) { root.setOption("labelMode", v) }
  }

  Column {
    width: parent.width
    visible: root ? root.labelMode !== "off" : false

    ChoiceRow {
      key: "labelKind"
      label: "Show on"
      options: [
        { value: "all", label: "All" },
        { value: "apps", label: "Apps" },
        { value: "groups", label: "App groups" },
        { value: "folders", label: "Folders" }
      ]
      value: root ? root.labelKind : "all"
      onPicked: function(v) { root.setOption("labelKind", v) }
    }

    SectionLabel { text: "Look" }

    ChoiceRow {
      key: "labelFont"
      label: "Font"
      options: [
        { value: "theme", label: "Theme" },
        { value: "sans", label: "Sans" },
        { value: "pixel", label: "Pixel" }
      ]
      value: root ? root.labelFont : "theme"
      onPicked: function(v) { root.setOption("labelFont", v) }
    }
    ChoiceRow {
      key: "labelSize"
      label: "Size"
      options: [
        { value: "small", label: "Small" },
        { value: "medium", label: "Medium" },
        { value: "large", label: "Large" }
      ]
      value: root ? root.labelSize : "small"
      onPicked: function(v) { root.setOption("labelSize", v) }
    }
    ChoiceRow {
      key: "labelColor"
      label: "Color"
      hint: "High picks black or white for the dock background."
      options: [
        { value: "theme", label: "Theme" },
        { value: "high", label: "High contrast" },
        { value: "accent", label: "Accent" }
      ]
      value: root ? root.labelColor : "theme"
      onPicked: function(v) { root.setOption("labelColor", v) }
    }
    ChoiceRow {
      key: "labelBackground"
      label: "Background"
      hint: "Plate puts icon and name on one surface, like a button."
      options: [
        { value: "none", label: "None" },
        { value: "pill", label: "Pill" },
        { value: "plate", label: "Plate" }
      ]
      value: root ? root.labelBackground : "none"
      onPicked: function(v) { root.setOption("labelBackground", v) }
    }
    ChoiceRow {
      key: "labelReveal"
      label: "Reveal"
      options: [
        { value: "slide", label: "Slide" },
        { value: "typewriter", label: "Typewriter" },
        { value: "scramble", label: "Scramble" }
      ]
      value: root ? root.labelReveal : "slide"
      onPicked: function(v) { root.setOption("labelReveal", v) }
    }
    ChoiceRow {
      key: "labelEffect"
      label: "Effect"
      options: [
        { value: "none", label: "None" },
        { value: "glow", label: "Accent glow" },
        { value: "shadow", label: "Outline" }
      ]
      value: root ? root.labelEffect : "none"
      onPicked: function(v) { root.setOption("labelEffect", v) }
    }
    SliderRow {
      key: "labelMaxWidth"
      label: "Max width"
      hint: "Longer names drop subtitles, then trailing words, then end in an ellipsis."
      minimum: DockLabels.LABEL_MAX_WIDTH_MIN
      maximum: DockLabels.LABEL_MAX_WIDTH_MAX
      step: 10
      suffix: " px"
      value: root ? root.labelMaxWidth : 140
      onCommitted: function(v) { root.setOption("labelMaxWidth", Math.round(v)) }
    }

    SectionLabel { text: "Names"; visible: root ? root.labelKind === "all" || root.labelKind === "apps" : false }

    Repeater {
      model: (root && (root.labelKind === "all" || root.labelKind === "apps")) ? root.labelNameRows() : []
      delegate: Item {
        id: nameRow
        required property var modelData
        width: labelsPage.width
        implicitHeight: Style.space(44)

        // The context menu's "Rename Label…" lands here with this app.
        readonly property bool wanted: !!labelsPage.root && labelsPage.visible
          && labelsPage.root.labelEditAppId === nameRow.modelData.appId
        onWantedChanged: if (nameRow.wanted) Qt.callLater(function() {
          nameField.forceActiveFocus()
          nameField.selectAll()
          labelsPage.root.labelEditAppId = ""
        })

        Text {
          anchors.left: parent.left
          anchors.right: nameField.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: nameRow.modelData.auto
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        TextField {
          id: nameField
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(220)
          text: nameRow.modelData.name
          placeholderText: nameRow.modelData.auto
          maximumLength: DockLabels.MAX_LABEL_NAME
          foreground: Color.menu.text
          function commit() {
            if (text !== nameRow.modelData.name) labelsPage.root.setLabelName(nameRow.modelData.appId, text)
          }
          Keys.onReturnPressed: { commit(); labelsPage.panel.refocus() }
          Keys.onEnterPressed: { commit(); labelsPage.panel.refocus() }
          onActiveFocusChanged: if (!activeFocus) commit()
        }
      }
    }
  }
}
