import QtQuick 6.11
import qs.Commons

// An app's icon as the dock draws it, for the copy of an app dragged out
// of an opened group (DockLift.beginIcon), which has no row element to show.
DockIconArt {
  property var dockRoot: null
  renderSize: dockRoot ? dockRoot.maxIconArt : 64
  iconStyle: dockRoot ? dockRoot.iconStyle : "original"
  tint: dockRoot ? dockRoot.iconTintColor : Color.bar.text
  grid: dockRoot ? dockRoot.iconGrid : 16
  outputScale: dockRoot ? dockRoot.outputScale : 1
  contrast: dockRoot ? dockRoot.iconContrast : 0
  strength: dockRoot ? dockRoot.iconStrength : 1
  dropShadow: dockRoot ? dockRoot.iconShadow : false
  shadowStrength: dockRoot ? dockRoot.shadowStrength : 0.4
}
