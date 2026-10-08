import QtQuick
import qs.Commons
import qs.Ui

// Settings page: visibility, click behaviour, attention and tooltip rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Visibility" }

  ChoiceRow {
    key: "autohide"
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
    key: "revealDelay"
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
    key: "minimizeMode"
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
  SwitchRow {
    key: "keepPointer"
    label: "Keep pointer in place"
    hint: "Don't move the mouse pointer onto the window a click brings up."
    checked: root ? root.keepPointer : true
    onToggled: root.setOption("keepPointer", !root.keepPointer)
  }
  ChoiceRow {
    key: "restoreWorkspace"
    label: "Restore on"
    hint: "Where a minimized window comes back to. Windows restores it to the workspace it was minimized from."
    options: [
      { value: "current", label: "Current workspace" },
      { value: "origin", label: "Original workspace" }
    ]
    value: root ? root.restoreWorkspace : "current"
    onPicked: function(v) { root.setOption("restoreWorkspace", v) }
  }
  SwitchRow {
    key: "restoreSlot"
    label: "Restore original slot"
    hint: "Put the window back in the place it held in the tiling layout, not at the end. Only when the layout has not changed in the meantime."
    checked: root ? root.restoreSlot : false
    onToggled: root.setOption("restoreSlot", !root.restoreSlot)
  }
  SliderRow {
    key: "wheelStepDelay"
    label: "Wheel step delay"
    hint: "Scrolling over an app flips through its windows; this paces the steps."
    minimum: 0
    maximum: 500
    step: 10
    suffix: " ms"
    value: root ? root.wheelStepDelay : 150
    onCommitted: function(v) { root.setOption("wheelStepDelay", Math.round(v)) }
  }

  SectionLabel { text: "Attention" }

  SwitchRow {
    key: "badges"
    label: "Notification badges"
    hint: "Count active notification popups on pinned apps; clears on dismissal or expiry."
    checked: root ? root.showNotificationBadges : true
    onToggled: root.setOption("showNotificationBadges", !root.showNotificationBadges)
  }
  ChoiceRow {
    key: "badgeStyle"
    label: "Badge style"
    hint: "A count pill or a plain dot on the icon."
    options: [
      { value: "count", label: "Count" },
      { value: "dot", label: "Dot" }
    ]
    value: root ? root.badgeStyle : "count"
    enabled: root ? root.showNotificationBadges : false
    opacity: enabled ? 1 : 0.45
    onPicked: function(v) { root.setOption("badgeStyle", v) }
  }
  ChoiceRow {
    key: "badgePosition"
    label: "Badge position"
    hint: "The corner of the icon the badge sits on."
    options: [
      { value: "top-right", label: "Top right" },
      { value: "top-left", label: "Top left" },
      { value: "bottom-right", label: "Bottom right" },
      { value: "bottom-left", label: "Bottom left" }
    ]
    value: root ? root.badgePosition : "top-right"
    enabled: root ? root.showNotificationBadges : false
    opacity: enabled ? 1 : 0.45
    onPicked: function(v) { root.setOption("badgePosition", v) }
  }
  ChoiceRow {
    key: "badgeColor"
    label: "Badge color"
    hint: "Accent, urgent red, or a neutral pill."
    options: [
      { value: "accent", label: "Accent" },
      { value: "urgent", label: "Urgent" },
      { value: "neutral", label: "Neutral" }
    ]
    value: root ? root.badgeColor : "accent"
    enabled: root ? root.showNotificationBadges : false
    opacity: enabled ? 1 : 0.45
    onPicked: function(v) { root.setOption("badgeColor", v) }
  }
  SwitchRow {
    key: "urgentHint"
    label: "Urgent highlights"
    hint: "Mark apps whose windows ask for attention."
    checked: root ? root.showUrgentHint : true
    onToggled: root.setOption("showUrgentHint", !root.showUrgentHint)
  }
  SwitchRow {
    key: "urgentOnNotification"
    label: "Urgent on notification"
    hint: "A notification from an app marks its icon."
    checked: root ? root.urgentOnNotification : true
    onToggled: root.setOption("urgentOnNotification", !root.urgentOnNotification)
  }
  SettingRow {
    key: "urgentSound"
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

  SectionLabel { text: "Previews & Tooltips" }

  SwitchRow {
    key: "tooltips"
    label: "Tooltips"
    checked: root ? root.showTooltips : true
    onToggled: root.setOption("showTooltips", !root.showTooltips)
  }
  SliderRow {
    key: "tooltipDelay"
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
    key: "windowPreviews"
    label: "Window previews"
    hint: "Thumbnails of an app's windows in its tooltip; scroll over the icon to flip through them."
    checked: root ? root.advancedTooltips : true
    onToggled: root.setOption("advancedTooltips", !root.advancedTooltips)
  }
  SwitchRow {
    key: "minimizedTiles"
    label: "Minimized window tiles"
    hint: "Show parked windows as preview tiles in the dock."
    checked: root ? root.showMinimizedTiles : true
    onToggled: root.setOption("showMinimizedTiles", !root.showMinimizedTiles)
  }
}
