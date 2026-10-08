import QtQuick
import qs.Commons
import qs.Ui

// A context-menu row that turns into a name field in place: Enter saves,
// Escape cancels, and a blank name restores the default (the owner decides
// what that is; committed() gets ""). While the field is showing the dock's
// layer surface takes the keyboard (dockRoot.contextRenaming), the same way
// the app group popup does for its title. The flag follows what is on screen:
// the page above this row switches with View As / Sort By (and the row itself
// is hidden over a command button), which hides the editor without ending the
// edit - a field that is not showing must not hold the keyboard.
Item {
  id: rename

  property var dockRoot: null
  property string text: "Rename…"
  // The name the field opens with, and the default shown when it is blank.
  property string current: ""
  property string placeholder: ""
  property int maximumLength: 40
  property bool editing: false
  signal committed(string name)

  // The row's own gate (a command button hides it) and the page's, which
  // hides while a sub-page is open. The popup's focus grab reads this: the
  // keyboard is held only while the editor is actually on screen, and comes
  // back with it when the page returns.
  readonly property bool rowVisible: rename.visible && (!rename.parent || rename.parent.visible)
  readonly property bool holdsKeyboard: rename.editing && rename.rowVisible
  onHoldsKeyboardChanged: if (rename.dockRoot) rename.dockRoot.contextRenaming = rename.holdsKeyboard

  width: row.width
  implicitWidth: row.implicitWidth
  height: row.height

  function startEdit() {
    rename.editing = true
    input.text = rename.current
    Qt.callLater(function() {
      input.forceActiveFocus()
      input.selectAll()
    })
  }

  function finish(save) {
    if (!rename.editing) return
    rename.editing = false
    if (save) rename.committed(input.text.trim())
  }

  Component.onDestruction: if (rename.editing && rename.dockRoot) rename.dockRoot.contextRenaming = false

  ContextRow {
    id: row
    visible: !rename.editing
    text: rename.text
    onTriggered: rename.startEdit()
  }

  Rectangle {
    visible: rename.editing
    anchors.fill: parent
    anchors.margins: Style.space(2)
    radius: Style.cornerRadius
    color: Util.alpha(Color.menu.background, 0.5)
    border.color: Color.accent
    border.width: 1

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: TextInput.AlignVCenter
      color: Color.menu.text
      selectionColor: Util.alpha(Color.accent, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      maximumLength: rename.maximumLength
      clip: true
      selectByMouse: true
      Keys.onReturnPressed: rename.finish(true)
      Keys.onEnterPressed: rename.finish(true)
      Keys.onEscapePressed: rename.finish(false)

      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: input.text === ""
        text: rename.placeholder
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.4)
        font: input.font
        elide: Text.ElideRight
      }
    }
  }
}
