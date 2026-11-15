import QtQuick
import qs.Ui

TextField {
  id: root

  // Qt reads clipboard text on clipboard changes in an editable TextInput.
  // Keep the native input read-only at all times. Edit from key text only.
  readOnly: true
  maximumLength: 256
  selectByMouse: true
  cursorVisible: activeFocus
  Accessible.name: placeholderText
  Accessible.description: "Type to search. Clipboard paste is unavailable."
  Accessible.editable: true
  Accessible.readOnly: false
  Accessible.searchEdit: true

  function replaceSelection(value) {
    const start = selectionStart === selectionEnd ? cursorPosition : selectionStart
    const end = selectionStart === selectionEnd ? cursorPosition : selectionEnd
    const available = maximumLength - (text.length - (end - start))
    let addition = String(value).slice(0, available)
    if (/[\uD800-\uDBFF]$/.test(addition)) addition = addition.slice(0, -1)
    if (value !== "" && addition === "") return
    remove(start, end)
    insert(start, addition)
    cursorPosition = start + addition.length
    deselect()
  }

  function erase(backward, word) {
    if (selectionStart !== selectionEnd) {
      replaceSelection("")
      return
    }
    let start = cursorPosition
    let end = start
    if (backward) {
      if (word) start = text.slice(0, start).replace(/\S+\s*$|\s+$/, "").length
      else if (start > 0) {
        start--
        if (start > 0 && /[\uDC00-\uDFFF]/.test(text.charAt(start))) start--
      }
    } else {
      if (word) end += (text.slice(end).match(/^\s*\S+\s*/) || [""])[0].length
      else if (end < text.length) {
        end++
        if (end < text.length && /[\uD800-\uDBFF]/.test(text.charAt(end - 1))) end++
      }
    }
    remove(start, end)
    cursorPosition = start
  }

  Keys.onPressed: function (event) {
    if (event.matches(StandardKey.Paste)) {
      event.accepted = true
    } else if (event.matches(StandardKey.Cut)) {
      root.copy()
      root.replaceSelection("")
      event.accepted = true
    } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
      root.erase(event.key === Qt.Key_Backspace, !!(event.modifiers & Qt.ControlModifier))
      event.accepted = true
    } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
               && event.text !== "" && !/[\x00-\x1F\x7F]/.test(event.text)) {
      root.replaceSelection(event.text)
      event.accepted = true
    } else {
      event.accepted = false
    }
  }
}
