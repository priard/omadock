pragma Singleton
import QtQuick

// The dock's strings, in the language picked under Setup > Language
// (`omarchy language`). Omarchy 4.5 ships Commons.Translations, which reads
// the catalogs in i18n/ and follows the language live. A shell from before
// it has no such type, and naming it outright would stop the dock loading
// there at all, so it is created by name when the shell has it. Without it
// nothing is translated: every call carries its English text, and that is
// what comes back.
//
//   Tr.t("menu.unpin", "Unpin from Dock")
//   Tr.t("menu.windowsCount", "Windows (%1)").arg(n)
//   Tr.tn("menu.groupApps", n, n === 1 ? "%1 App" : "%1 Apps").arg(n)
QtObject {
  id: tr

  property var shared: null

  function t(key, fallback) {
    return tr.shared ? tr.shared.t(key, fallback) : fallback
  }

  function tn(key, count, fallback) {
    return tr.shared ? tr.shared.tn(key, count, fallback) : fallback
  }

  Component.onCompleted: {
    var translations = null
    try {
      translations = Qt.createQmlObject("import qs.Commons\nTranslations {}", tr, "omadock-strings")
      translations.directory = Qt.resolvedUrl("../../i18n")
      tr.shared = translations
    } catch (e) {
      tr.shared = null
    }
  }
}
