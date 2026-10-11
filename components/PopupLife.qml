import QtQuick

// The life of one dock popup (menu, folder stack, opened group), like
// TooltipLife: `want` is the caller's open condition; `alive` keeps the
// popup's window (its LazyLoader) until the fade-out ends; `closing` tells
// the window to show its frozen last frame, since the popup's own state
// (contextAppId, activeStackFolder, ...) clears the moment it closes.
Item {
  id: life

  property var dockRoot: null
  property bool want: false
  readonly property var motion: dockRoot ? dockRoot.motion : null

  property bool alive: false
  // 0 = gone, 1 = open; drives the window's opacity and the small rise.
  property real level: 0
  readonly property bool closing: life.alive && !life.want
  // The easing reads the Behavior's target, which is set before the
  // animation starts; bound to `want` it could start with the old one.
  Behavior on level {
    id: levelMotion
    NumberAnimation {
      duration: life.motion ? life.motion.base : 0
      easing.type: levelMotion.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
    }
  }

  width: 0
  height: 0

  onWantChanged: {
    if (life.want) {
      life.alive = true
      life.level = 1
    } else if (!life.motion || life.motion.base <= 0) {
      life.level = 0
      life.alive = false
    } else {
      life.level = 0
      // Opened and closed within one turn: the level never left 0, so no
      // change will come to end the life.
      if (life.level === 0) life.alive = false
    }
  }
  onLevelChanged: if (life.level === 0 && !life.want) life.alive = false
}
