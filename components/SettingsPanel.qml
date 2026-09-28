import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Full-screen overlay holding the dock settings: a sidebar of categories and
// a scrollable page of controls. Every control writes straight through the
// dock's setters, so the dock underneath previews each change live.
PanelWindow {
  id: panel

  property var rootRef: null
  readonly property var root: rootRef

  property string page: root ? root.settingsPanelPage : "appearance"

  readonly property var pages: [
    { id: "appearance", label: "Appearance", glyph: "󰏘" },
    { id: "placement", label: "Placement", glyph: "󰍹" },
    { id: "behavior", label: "Behavior", glyph: "󰒓" },
    { id: "effects", label: "Effects", glyph: "󰨙" },
    { id: "size", label: "Size & Spacing", glyph: "󰩨" },
    { id: "folders", label: "Folders", glyph: "󰉋" },
    { id: "groups", label: "App Groups", glyph: "󰀻" }
  ]


  function close() {
    if (root) root.closeSettingsPanel()
  }

  screen: root ? root.dockScreen : null
  color: "transparent"
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omadock-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // ------------------------------------------------------------ building blocks

  component SectionLabel: Text {
    width: parent ? parent.width : implicitWidth
    topPadding: Style.spacing.xxl
    bottomPadding: Style.spacing.sm
    text: ""
    color: Util.alpha(Color.menu.text, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
  }

  // Label + optional hint on the left, the control on the right.
  component SettingRow: Item {
    id: settingRow
    property string label: ""
    property string hint: ""
    default property alias control: slot.data

    width: parent ? parent.width : Style.space(420)
    implicitHeight: Math.max(Style.space(44), texts.implicitHeight + Style.spacing.lg * 2, slot.childrenRect.height + Style.spacing.md * 2)

    Column {
      id: texts
      anchors.left: parent.left
      anchors.right: slot.left
      anchors.rightMargin: Style.spacing.xxl
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        text: settingRow.label
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: settingRow.hint !== ""
        text: settingRow.hint
        color: Util.alpha(Color.menu.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Item {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: Util.alpha(Color.menu.text, 0.10)
    }
  }

  component SwitchRow: SettingRow {
    id: switchRow
    property bool checked: false
    signal toggled()

    ToggleSwitch {
      checked: switchRow.checked
      foreground: Color.menu.text
      onToggled: switchRow.toggled()
    }
  }

  component ChoiceRow: SettingRow {
    id: choiceRow
    property var options: []
    property string value: ""
    signal picked(string value)

    ButtonGroup {
      options: choiceRow.options
      value: choiceRow.value
      foreground: Color.menu.text
      background: Color.menu.background
      focusable: false
      onChanged: function(v) { choiceRow.picked(v) }
    }
  }

  component SliderRow: SettingRow {
    id: sliderRow
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property string suffix: ""
    property real displayScale: 1
    signal committed(real value)

    // PanelSlider reads its palette from a bar-shaped object.
    QtObject {
      id: sliderPalette
      property color foreground: Color.menu.text
      property color background: Color.menu.background
    }

    Row {
      spacing: Style.spacing.lg

      PanelSlider {
        id: slider
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(180)
        bar: sliderPalette
        minimum: sliderRow.minimum
        maximum: sliderRow.maximum
        step: sliderRow.step
        integer: sliderRow.step >= 1
        value: sliderRow.value
        onReleased: function(v) { sliderRow.committed(v) }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(52)
        horizontalAlignment: Text.AlignRight
        text: Math.round(slider.liveValue * sliderRow.displayScale) + sliderRow.suffix
        color: Util.alpha(Color.menu.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  component Swatch: Rectangle {
    id: swatch
    property bool selected: false
    signal picked()

    width: Style.space(26)
    height: Style.space(26)
    radius: Math.min(Style.space(6), Style.cornerRadius > 0 ? Style.space(6) : 0)
    border.width: selected ? 2 : 1
    border.color: selected ? Color.accent : Util.alpha(Color.menu.text, 0.3)

    Rectangle {
      visible: swatch.selected
      anchors.centerIn: parent
      width: Style.space(8)
      height: width
      radius: width / 2
      color: Color.accent
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: swatch.picked()
    }
  }

  // ------------------------------------------------------------ scrim

  Rectangle {
    anchors.fill: parent
    color: Util.alpha("#000000", 0.35)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: panel.close()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: panel.close()
  }

  // Focus has to be taken again once the surface is actually mapped.
  onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  Component.onCompleted: Qt.callLater(function() { keyCatcher.forceActiveFocus() })

  Shortcut {
    sequence: "Escape"
    context: Qt.WindowShortcut
    onActivated: panel.close()
  }

  // ------------------------------------------------------------ card

  BorderSurface {
    id: card

    width: Math.min(parent.width - Style.space(48), Style.space(820))
    height: Math.min(parent.height - Style.space(48), Style.space(600))
    anchors.centerIn: parent
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
    radius: Style.cornerRadius

    // Swallow clicks so they never reach the scrim.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    }

    // ---------------------------------------------------------- sidebar
    Rectangle {
      id: sidebar
      x: card.contentLeftInset
      y: card.contentTopInset
      width: Style.space(200)
      height: card.height - card.contentTopInset - card.contentBottomInset
      color: Util.alpha(Color.menu.text, 0.035)
      radius: Math.max(0, Style.cornerRadius - 1)

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.xxl
        spacing: Style.spacing.xs

        Text {
          text: "Omadock"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          text: "Dock settings"
          color: Util.alpha(Color.menu.text, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          bottomPadding: Style.spacing.xxl
        }

        Repeater {
          model: panel.pages
          delegate: Rectangle {
            id: navItem
            required property var modelData
            readonly property bool current: panel.page === modelData.id

            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius > 0 ? Style.space(6) : 0
            color: current ? Util.alpha(Color.accent, 0.18)
              : (navMouse.containsMouse ? Util.alpha(Color.menu.text, 0.07) : "transparent")

            // Glyph centred on its painted (tight) bounds, not its line box:
            // icon fonts sit low in the line, which left them under the label.
            Item {
              id: navIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.xl
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: Style.space(18)

              TextMetrics {
                id: navGlyphMetrics
                font: navGlyph.font
                text: navGlyph.text
              }

              Text {
                id: navGlyph
                text: navItem.modelData.glyph
                color: navItem.current ? Color.accent : Util.alpha(Color.menu.text, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
                x: Math.round(navIcon.width / 2 - (navGlyphMetrics.tightBoundingRect.x + navGlyphMetrics.tightBoundingRect.width / 2))
                y: Math.round(navIcon.height / 2 - (navGlyph.baselineOffset + navGlyphMetrics.tightBoundingRect.y + navGlyphMetrics.tightBoundingRect.height / 2))
              }
            }

            Text {
              anchors.left: navIcon.right
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: navItem.modelData.label
              color: navItem.current ? Color.accent : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
            }

            MouseArea {
              id: navMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root) root.settingsPanelPage = navItem.modelData.id
                pageFlick.contentY = 0
              }
            }
          }
        }
      }
    }

    // ---------------------------------------------------------- header
    Item {
      id: header
      anchors.left: sidebar.right
      anchors.leftMargin: Style.spacing.huge
      anchors.right: parent.right
      anchors.rightMargin: card.contentRightInset + Style.spacing.xxl
      y: card.contentTopInset + Style.spacing.xxl
      height: Style.space(32)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          for (var i = 0; i < panel.pages.length; i++)
            if (panel.pages[i].id === panel.page) return panel.pages[i].label
          return ""
        }
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }

      Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        foreground: Color.menu.text
        tooltipText: "Close (Esc)"
        onClicked: panel.close()
      }
    }

    // ---------------------------------------------------------- page
    Flickable {
      id: pageFlick
      anchors.left: header.left
      anchors.right: header.right
      anchors.top: header.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.contentBottomInset + Style.spacing.xxl
      contentWidth: width
      contentHeight: pageColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      WheelHandler {
        target: pageFlick
        onWheel: function(event) {
          if (event.angleDelta.y === 0) return
          var dy = event.angleDelta.y > 0 ? -Style.space(48) : Style.space(48)
          pageFlick.contentY = Math.max(0, Math.min(pageFlick.contentHeight - pageFlick.height, pageFlick.contentY + dy))
        }
      }

      Column {
        id: pageColumn
        width: pageFlick.width

        // ================================================= Appearance
        Column {
          width: parent.width
          visible: panel.page === "appearance"

          SectionLabel { text: "Surface" }

          SwitchRow {
            label: "Background"
            hint: "Fill behind the icons. Off leaves the icons floating."
            checked: root ? root.showBackground : true
            onToggled: root.setOption("showBackground", !root.showBackground)
          }
          SwitchRow {
            label: "Shadow"
            hint: "Soft drop shadow under the dock."
            checked: root ? root.showShadow : true
            onToggled: root.setOption("showShadow", !root.showShadow)
          }
          SwitchRow {
            label: "Border"
            hint: "Thin rim around the dock."
            checked: root ? root.showBorder : true
            onToggled: root.setOption("showBorder", !root.showBorder)
          }

          SectionLabel { text: "Shape" }

          ChoiceRow {
            label: "Corners"
            options: [
              { value: "theme", label: "Theme" },
              { value: "rounded", label: "Rounded" },
              { value: "round", label: "Pill" },
              { value: "square", label: "Square" }
            ]
            value: {
              if (!root) return "theme"
              var s = root.dockShape
              if (s === "auto") return "theme"
              if (s === "pill") return "round"
              return s
            }
            onPicked: function(v) { root.setDockShape(v) }
          }

          SectionLabel { text: "Background" }

          SwitchRow {
            label: "Opacity from theme"
            hint: "Follow the bar opacity of the current Omarchy theme."
            checked: root ? root.dockOpacity < 0 : true
            onToggled: root.setDockOpacity(root.dockOpacity < 0 ? 1.0 : -1.0)
          }
          SliderRow {
            label: "Opacity"
            visible: root ? root.dockOpacity >= 0 : false
            minimum: 0
            maximum: 1
            step: 0.05
            displayScale: 100
            suffix: "%"
            value: root ? Math.max(0, root.dockOpacity) : 1
            onCommitted: function(v) { root.setDockOpacity(Math.round(v * 100) / 100) }
          }

          SettingRow {
            label: "Color"
            hint: "Theme, none, or a fixed preset."

            Row {
              spacing: Style.spacing.sm

              Button {
                text: "Theme"
                foreground: Color.menu.text
                bordered: true
                selected: root ? (root.dockBgColor === "theme" || !root.dockBgColor) : true
                onClicked: root.setDockBgColor("theme")
              }
              Button {
                text: "None"
                foreground: Color.menu.text
                bordered: true
                selected: root ? root.dockBgColor === "none" : false
                onClicked: root.setDockBgColor("none")
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            topPadding: Style.spacing.lg
            bottomPadding: Style.spacing.lg

            Repeater {
              model: [
                "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827",
                "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155"
              ]
              delegate: Swatch {
                required property string modelData
                color: modelData
                selected: root ? root.dockBgColor === modelData : false
                onPicked: root.setDockBgColor(modelData)
              }
            }
          }
        }

        // ================================================= Placement
        Column {
          width: parent.width
          visible: panel.page === "placement"

          SectionLabel { text: "Position" }

          ChoiceRow {
            label: "Alignment"
            options: [
              { value: "left", label: "Left" },
              { value: "center", label: "Center" },
              { value: "right", label: "Right" }
            ]
            value: root ? (root.alignment || "center") : "center"
            onPicked: function(v) { root.setDockAlignment(v) }
          }

          SectionLabel { text: "Monitors" }

          SwitchRow {
            label: "Show on all monitors"
            hint: "One dock per connected monitor."
            checked: root ? root.multiMonitor : false
            onToggled: root.setOption("multiMonitor", !root.multiMonitor)
          }
          SwitchRow {
            label: "Only this monitor's apps"
            hint: "Each dock lists the windows on its own monitor; pinned apps show everywhere."
            visible: root ? root.multiMonitor : false
            checked: root ? root.perMonitorApps : true
            onToggled: root.setOption("perMonitorApps", !root.perMonitorApps)
          }
          SettingRow {
            label: root && root.multiMonitor ? "Primary monitor" : "Monitor"
            hint: root && root.multiMonitor
              ? "Plays the alert sounds."
              : "Automatic picks the first connected output."

            Dropdown {
              width: Style.space(200)
              showLabel: false
              options: {
                var list = [{ value: "", label: "Automatic" }]
                var screens = root ? root.realScreens : []
                for (var i = 0; i < screens.length; i++)
                  list.push({ value: screens[i].name, label: screens[i].name + (screens[i].model ? " — " + screens[i].model : "") })
                if (root && root.screenName && !root.screenForName(root.screenName))
                  list.push({ value: root.screenName, label: root.screenName + " (disconnected)" })
                return list
              }
              value: root ? root.screenName : ""
              onChanged: function(v) { root.setDockScreen(v) }
            }
          }
        }

        // ================================================= Behavior
        Column {
          width: parent.width
          visible: panel.page === "behavior"

          SectionLabel { text: "Visibility" }

          ChoiceRow {
            label: "Autohide"
            hint: "Intelligent hides only when a window overlaps the dock."
            options: [
              { value: "always", label: "Always show" },
              { value: "intelligent", label: "Intelligent" },
              { value: "autohide", label: "Autohide" }
            ]
            value: root ? (!root.autohide ? "always" : (root.intelligentAutohide ? "intelligent" : "autohide")) : "always"
            onPicked: function(v) { root.setAutohideMode(v) }
          }
          SliderRow {
            label: "Reveal delay"
            hint: "How long the pointer rests on the edge before the dock slides in."
            enabled: root ? root.autohide : false
            opacity: enabled ? 1 : 0.45
            minimum: 0
            maximum: 1000
            step: 10
            suffix: " ms"
            value: root ? root.revealDelay : 160
            onCommitted: function(v) { root.setOption("revealDelay", Math.round(v)) }
          }

          SectionLabel { text: "Clicking an app" }

          ChoiceRow {
            label: "Minimize on click"
            hint: "Clicking the focused app's icon parks its windows."
            options: [
              { value: "off", label: "Off" },
              { value: "active", label: "Active window" },
              { value: "all", label: "All windows" }
            ]
            value: root ? root.minimizeMode : "active"
            onPicked: function(v) { root.setOption("minimizeMode", v) }
          }

          SectionLabel { text: "Attention" }

          SwitchRow {
            label: "Urgent highlights"
            hint: "Mark apps whose windows ask for attention."
            checked: root ? root.showUrgentHint : true
            onToggled: root.setOption("showUrgentHint", !root.showUrgentHint)
          }
          SwitchRow {
            label: "Urgent on notification"
            hint: "A notification from an app marks its icon."
            checked: root ? root.urgentOnNotification : true
            onToggled: root.setOption("urgentOnNotification", !root.urgentOnNotification)
          }
          SettingRow {
            label: "Urgent sound"

            Dropdown {
              width: Style.space(200)
              showLabel: false
              options: [
                { value: "bell", label: "Bell" },
                { value: "message-new-instant", label: "Message chime" },
                { value: "complete", label: "Complete ding" },
                { value: "dialog-information", label: "Information pop" },
                { value: "dialog-warning", label: "Warning alert" },
                { value: "phone-incoming-call", label: "Phone ring" },
                { value: "alarm-clock-elapsed", label: "Alarm beeps" },
                { value: "none", label: "Mute" }
              ]
              value: root ? (root.urgentSound ? root.urgentSoundName : "none") : "bell"
              onChanged: function(v) { root.setUrgentSoundName(v) }
            }
          }
        }

        // ================================================= Effects
        Column {
          width: parent.width
          visible: panel.page === "effects"

          SectionLabel { text: "Motion" }

          ChoiceRow {
            label: "Hover effect"
            options: [
              { value: "zoom", label: "Zoom" },
              { value: "wave", label: "Wave" },
              { value: "off", label: "None" }
            ]
            value: root ? root.hoverEffect : "zoom"
            onPicked: function(v) { root.setHoverEffect(v) }
          }
          SwitchRow {
            label: "Launch bounce"
            hint: "Bounce the icon while an app is starting."
            checked: root ? root.launchBounce : true
            onToggled: root.setOption("launchBounce", !root.launchBounce)
          }

          SectionLabel { text: "Tooltips & previews" }

          SwitchRow {
            label: "Tooltips"
            checked: root ? root.showTooltips : true
            onToggled: root.setOption("showTooltips", !root.showTooltips)
          }
          SliderRow {
            label: "Tooltip delay"
            enabled: root ? root.showTooltips : true
            opacity: enabled ? 1 : 0.45
            minimum: 0
            maximum: 2000
            step: 50
            suffix: " ms"
            value: root ? root.tooltipDelay : 450
            onCommitted: function(v) { root.setOption("tooltipDelay", Math.round(v)) }
          }
          SwitchRow {
            label: "Window previews"
            hint: "Live thumbnails of an app's windows in its tooltip."
            checked: root ? root.advancedTooltips : true
            onToggled: root.setOption("advancedTooltips", !root.advancedTooltips)
          }
          SwitchRow {
            label: "Minimized window tiles"
            hint: "Show parked windows as preview tiles in the dock."
            checked: root ? root.showMinimizedTiles : true
            onToggled: root.setOption("showMinimizedTiles", !root.showMinimizedTiles)
          }
        }

        // ================================================= Size & spacing
        Column {
          width: parent.width
          visible: panel.page === "size"

          SectionLabel { text: "Icons" }

          SliderRow {
            label: "Icon size"
            minimum: 24
            maximum: 64
            step: 2
            suffix: " px"
            value: root ? root.iconSize : 36
            onCommitted: function(v) { root.setIconSize(Math.round(v)) }
          }
          SliderRow {
            label: "Spacing"
            hint: "Gap between icons."
            minimum: 0
            maximum: 16
            step: 1
            suffix: " px"
            value: root ? root.itemSpacing : 4
            onCommitted: function(v) { root.setItemSpacing(Math.round(v)) }
          }

          SectionLabel { text: "Items" }

          SwitchRow {
            label: "Omarchy button"
            hint: "The launcher at the start of the dock. Without it, right-click the dock background to reach these settings."
            checked: root ? root.showAppsButton : true
            onToggled: root.setOption("showAppsButton", !root.showAppsButton)
          }
        }

        // ================================================= Folders
        Column {
          width: parent.width
          visible: panel.page === "folders"

          SectionLabel { text: "Pinned folders" }

          Repeater {
            model: [
              { path: "~/Downloads", name: "Downloads", icon: "folder-download" },
              { path: "~/Documents", name: "Documents", icon: "folder-documents" },
              { path: "~/Pictures", name: "Pictures", icon: "folder-pictures" },
              { path: "~/Projects", name: "Projects", icon: "folder-development" },
              { path: "~/Music", name: "Music", icon: "folder-music" },
              { path: "~/Videos", name: "Videos", icon: "folder-videos" },
              { path: "~", name: "Home", icon: "user-home" }
            ]
            delegate: SwitchRow {
              required property var modelData
              label: modelData.name
              hint: modelData.path
              checked: root ? (root.pinnedFolders, root.isFolderPinned(modelData.path)) : false
              onToggled: root.toggleFolderPin(modelData.path, modelData.name, modelData.icon)
            }
          }

          Repeater {
            model: {
              if (!root) return []
              var presets = ["~/Downloads", "~/Documents", "~/Pictures", "~/Projects", "~/Music", "~/Videos", "~"]
              var out = []
              for (var i = 0; i < root.pinnedFolders.length; i++)
                if (presets.indexOf(root.pinnedFolders[i].path) < 0) out.push(root.pinnedFolders[i])
              return out
            }
            delegate: SettingRow {
              required property var modelData
              label: modelData.name || "Folder"
              hint: modelData.path

              Button {
                text: "Remove"
                foreground: Color.menu.text
                bordered: true
                onClicked: root.toggleFolderPin(modelData.path, modelData.name, modelData.icon)
              }
            }
          }

          SettingRow {
            label: "Custom folder"
            hint: "Pick any directory to pin as a stack."

            Button {
              text: "Add folder…"
              foreground: Color.menu.text
              bordered: true
              onClicked: {
                panel.close()
                if (root.customFolderPickerProc) root.customFolderPickerProc.running = true
              }
            }
          }

          SectionLabel { text: "Folder color" }

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            bottomPadding: Style.spacing.lg

            Button {
              text: "Theme"
              foreground: Color.menu.text
              bordered: true
              selected: root ? (root.folderColor === "theme" || !root.folderColor) : true
              onClicked: root.setFolderColor("theme")
            }

            Repeater {
              model: [
                { id: "white", color: "#ffffff" },
                { id: "black", color: "#111111" },
                { id: "Yaru-sage", color: "#61895a" },
                { id: "Yaru-olive", color: "#878846" },
                { id: "Yaru-blue", color: "#3d7ab8" },
                { id: "Yaru-purple", color: "#775aa6" },
                { id: "Yaru-magenta", color: "#b3497d" },
                { id: "Yaru-red", color: "#c73838" },
                { id: "Yaru-yellow", color: "#d9a13b" },
                { id: "Yaru-wartybrown", color: "#8a583e" },
                { id: "Yaru-prussiangreen", color: "#2d7f7b" },
                { id: "Yaru-dark", color: "#3c3b37" }
              ]
              delegate: Swatch {
                required property var modelData
                color: modelData.color
                selected: root ? root.folderColor === modelData.id : false
                onPicked: root.setFolderColor(modelData.id)
              }
            }
          }

          SectionLabel { text: "Devices" }

          SwitchRow {
            label: "Removable drives"
            hint: "Show mounted USB drives at the end of the dock."
            checked: root ? root.showRemovableDrives : true
            onToggled: {
              root.setOption("showRemovableDrives", !root.showRemovableDrives)
              root.scanRemovableDrives()
            }
          }
        }

        // ================================================= App groups
        Column {
          width: parent.width
          visible: panel.page === "groups"

          SectionLabel { text: "Groups" }

          Text {
            width: parent.width
            visible: !root || root.appGroups.length === 0
            topPadding: Style.spacing.lg
            bottomPadding: Style.spacing.lg
            text: "No groups yet. Drag one dock icon onto another, or create one from the apps that are running now."
            color: Util.alpha(Color.menu.text, 0.55)
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root ? root.appGroups : []
            delegate: SettingRow {
              required property var modelData
              label: modelData.name || "Group"
              hint: (modelData.apps ? modelData.apps.length : 0) + " apps"

              Button {
                text: "Remove"
                foreground: Color.menu.text
                bordered: true
                onClicked: root.removeAppGroup(modelData.id)
              }
            }
          }

          Item { width: 1; height: Style.spacing.xxl }

          Button {
            text: "Create group from running apps"
            foreground: Color.menu.text
            bordered: true
            onClicked: root.createAppGroupFromRunning()
          }
        }
      }
    }
  }
}
