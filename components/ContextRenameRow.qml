import QtQuick 6.11
import qs.Commons
import qs.Ui
import "strings"

// A context-menu row that turns into a name field in place: Enter saves,
// Escape cancels, and a blank name restores the default (the owner decides
// what that is; committed() gets ""). While the field is showing the dock's
// layer surface takes the keyboard (dockRoot.contextRenaming), the same way
// the app group popup does for its title. The flag follows what is on screen:
// the page above this row switches with View As / Sort By (and the row itself
// is hidden over a command button), which hides the editor without ending the
// edit - a field that is not showing must not hold the keyboard.
//
// The field is built by `editor` ONLY while `editing` is true. A TextInput
// that is merely displayed still takes Qt's clipboard subscription, and on
// Wayland that subscription reads a foreign offer: measured with the dock's
// menu open on a headless output, a 12-byte offer set by an outside client was
// read 15-17 ms later with no paste gesture, the shell grew 6-9 MB and one
// state IPC call took ~0.5 s instead of ~24 ms; destroying the open menu's six
// TextInputs (same menu, same offer) left no read at all and no stall (3 of 3
// trials each, interleaved). So the surface comes into existence on Rename and
// goes away with finish(), which is also what the reviewer's report described.
Item {
  id: rename

  property var dockRoot: null
  property string text: Tr.t("menu.rename", "Rename…")
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
    // editor.item may not exist until the Loader has built it; onLoaded seeds
    // the field either way, and when the item is there already this is the
    // same seeding the old always-instantiated field did. The editor's own
    // root is the bordered Rectangle, not the TextInput (the menu suite reads
    // the field's border off input.parent), so its text and focus are reached
    // through the functions it exposes.
    var field = editor.item
    if (!field) return
    field.setText(rename.current)
    // The field can be gone before this runs (Escape in the same event loop),
    // so the reference is only used while it is still the Loader's item.
    Qt.callLater(function() {
      if (!rename.editing || editor.item !== field) return
      field.focusField()
    })
  }

  function finish(save) {
    if (!rename.editing) return
    var field = editor.item
    var name = field ? field.fieldText() : ""
    rename.editing = false
    if (save) rename.committed(name.trim())
  }

  Component.onDestruction: if (rename.editing && rename.dockRoot) rename.dockRoot.contextRenaming = false

  ContextRow {
    id: row
    visible: !rename.editing
    text: rename.text
    onTriggered: rename.startEdit()
  }

  // Built on Rename, destroyed on finish: no TextInput exists while the row is
  // only being displayed.
  Loader {
    id: editor
    anchors.fill: parent
    active: rename.editing

    onLoaded: {
      item.setText(rename.current)
      item.focusField()
    }

    sourceComponent: Component {
      Rectangle {
        // The editor's own root; text and focus live on the TextInput below.
        // Functions, not a `text` alias: a Rectangle that answered `text`
        // would read as a Text item to anything walking the menu (and its
        // translucent panel colour is not one of the theme's text colours).
        function setText(value) { input.text = value }
        function fieldText() { return input.text }
        function focusField() { input.forceActiveFocus(); input.selectAll() }

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
  }
}
