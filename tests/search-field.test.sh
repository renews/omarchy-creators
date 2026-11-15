#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Use the Qt control directly. The Omarchy wrapper adds theme settings only.
sed 's/^import qs.Ui$/import QtQuick.Controls/' "$ROOT/SearchField.qml" > "$sandbox/SearchField.qml"
cat > "$sandbox/main.qml" <<'QML'
import QtQuick
SearchField {
  property string query: ""
  property int escapes: 0
  text: query
  onTextChanged: query = text
  Keys.onEscapePressed: function (event) {
    query = ""
    escapes++
    event.accepted = true
  }
}
QML

# The compiler flags come from the installed Qt development packages.
# shellcheck disable=SC2046
timeout 30s c++ -std=c++17 -fPIC "$ROOT/tests/search-field.test.cpp" -o "$sandbox/probe" \
  $(pkg-config --cflags --libs Qt6Gui Qt6Quick Qt6Qml Qt6Test)

QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
  QT_QUICK_CONTROLS_STYLE=Basic QML_DISABLE_DISK_CACHE=1 XDG_RUNTIME_DIR="$sandbox" \
  timeout --kill-after=1s 10s "$sandbox/probe" "$sandbox/main.qml"
