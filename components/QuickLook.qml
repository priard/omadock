import QtQuick 6.11
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../DockIcons.js" as DockIcons

// Space over a file in an open folder shows it here, above the folder, like
// macOS Quick Look: an image at size, the start of a text file, otherwise the
// thumbnail a file manager left or the file's icon. Display only: it takes no
// input (the popup's input mask is the folder), Space or leaving closes it.
BorderSurface {
  id: look

  property var entry: null
  property var dockRoot: null
  // Room the popup surface has above the folder.
  property real maxW: 600
  property real maxH: 400

  readonly property string path: entry ? entry.path : ""
  readonly property string ext: {
    var m = /\.([^./]+)$/.exec(look.path.toLowerCase())
    return m ? m[1] : ""
  }
  readonly property bool isImage: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic", "tif", "tiff", "ico"].indexOf(ext) >= 0
  readonly property bool isText: !isImage && ["txt", "md", "json", "js", "mjs", "ts", "qml", "py", "sh", "bash", "zsh", "fish",
    "conf", "cfg", "ini", "toml", "yaml", "yml", "xml", "html", "css", "csv", "log", "lua", "c", "h", "cpp", "hpp",
    "rs", "go", "java", "kt", "rb", "php", "sql", "diff", "patch", "desktop", "service", "env", "srt", "tex"].indexOf(ext) >= 0
  readonly property string thumb: entry && entry.thumb ? entry.thumb : ""
  readonly property bool imageOk: (isImage || thumb !== "") && image.status !== Image.Error
  readonly property real captionH: caption.implicitHeight + Style.space(6)
  readonly property real innerW: maxW - contentLeftInset - contentRightInset
  readonly property real innerH: maxH - contentTopInset - contentBottomInset - captionH

  // Deferred: isText and the command binding update after this handler runs.
  onPathChanged: {
    reader.running = false
    reader.text = ""
    Qt.callLater(function() { if (look.isText && look.path !== "") reader.running = true })
  }

  function fileUrl(p) { return "file://" + String(p).split("/").map(encodeURIComponent).join("/") }

  visible: entry !== null
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(6)

  // Images keep their aspect, at most their own size; text and icons take a
  // page-like box.
  readonly property real artW: imageOk && image.implicitWidth > 0
    ? Math.min(innerW, image.implicitWidth, image.implicitHeight > 0 ? innerH * image.implicitWidth / image.implicitHeight : innerW)
    : isText ? Math.min(innerW, Style.space(560)) : Style.space(160)
  readonly property real artH: imageOk && image.implicitWidth > 0
    ? artW * image.implicitHeight / image.implicitWidth
    : isText ? Math.min(innerH, Style.space(420)) : Style.space(160)

  width: Math.max(artW, Math.min(innerW, caption.implicitWidth)) + contentLeftInset + contentRightInset
  height: artH + captionH + contentTopInset + contentBottomInset

  Item {
    id: art
    x: look.contentLeftInset + (look.width - look.contentLeftInset - look.contentRightInset - look.artW) / 2
    y: look.contentTopInset
    width: look.artW
    height: look.artH
    clip: true

    Image {
      id: image
      anchors.fill: parent
      visible: look.imageOk
      // The original for an image, else the cached thumbnail; capped decode.
      source: !look.entry ? "" : look.isImage ? look.fileUrl(look.path) : look.thumb !== "" ? look.fileUrl(look.thumb) : ""
      sourceSize: Qt.size(Math.round(look.maxW * 2), Math.round(look.maxH * 2))
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
    }

    Text {
      anchors.fill: parent
      visible: look.isText && !look.imageOk
      text: reader.text
      textFormat: Text.PlainText
      wrapMode: Text.NoWrap
      color: Color.menu.text
      font.family: "monospace"
      font.pixelSize: Style.font.caption
    }

    Image {
      anchors.centerIn: parent
      visible: !look.imageOk && !look.isText
      width: Style.space(128)
      height: Style.space(128)
      source: look.entry ? DockIcons.resolveFileItemIcon(look.entry.icon, look.dockRoot ? look.dockRoot.currentIconThemeName : "Yaru",
        look.dockRoot ? look.dockRoot.folderColor : "theme", look.dockRoot ? look.dockRoot.appLibrary : null) : ""
      sourceSize: Qt.size(Style.space(256), Style.space(256))
      fillMode: Image.PreserveAspectFit
    }
  }

  Text {
    id: caption
    anchors.horizontalCenter: parent.horizontalCenter
    y: art.y + art.height + Style.space(4)
    width: Math.min(implicitWidth, look.innerW)
    text: look.entry ? look.entry.name + (look.entry.size ? "  ·  " + look.entry.size : "") : ""
    textFormat: Text.PlainText
    elide: Text.ElideMiddle
    color: Util.alpha(Color.menu.text, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // The first 32 KiB only; timeout so a FIFO cannot hold the reader.
  Process {
    id: reader
    property string text: ""
    command: ["timeout", "2", "head", "-c", "32768", "--", look.path]
    stdout: StdioCollector { id: out; onStreamFinished: reader.text = out.text }
  }
}
