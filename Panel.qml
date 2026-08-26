import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "CreatorsModel.js" as Model

Panel {
  id: root

  moduleName: "renews.creators"
  ipcTarget: moduleName

  readonly property var monitor: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color live: "#bf616a"
  readonly property color youtube: "#e06c75"
  readonly property color twitch: "#b48ead"
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // How many rows the pickers draw at once. A subscription list runs to four
  // figures; the search field is the way through it, not a longer list.
  readonly property int pickerLimit: 50

  property string page: "feed"
  property string youtubeQuery: ""
  property string twitchQuery: ""
  property bool youtubeSelectedOnly: false
  property bool twitchSelectedOnly: false
  property bool settingsApplied: false
  property real nowMs: Date.now()

  readonly property var youtubeSelection: Model.normalizeIds(setting("youtubeChannels", []))
  readonly property var twitchSelection: Model.normalizeIds(setting("twitchChannels", []))

  readonly property var youtubeSorted: Model.sortForPicker(
    monitor ? monitor.youtubeCatalog : [], youtubeSelection)
  readonly property var twitchSorted: Model.sortForPicker(
    monitor ? monitor.twitchCatalog : [], twitchSelection)
  readonly property var youtubeMatches: Model.filterChannels(
    youtubeSorted, youtubeQuery, youtubeSelection, youtubeSelectedOnly)
  readonly property var twitchMatches: Model.filterChannels(
    twitchSorted, twitchQuery, twitchSelection, twitchSelectedOnly)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------------------
  // settings plumbing
  // ---------------------------------------------------------------------------

  function settingsSnapshot() {
    return {
      refreshIntervalSec: Model.clampInterval(setting("refreshIntervalSec", 300)),
      youtubeChannels: youtubeSelection,
      twitchChannels: twitchSelection,
      youtubeEnabled: setting("youtubeEnabled", true) !== false,
      twitchEnabled: setting("twitchEnabled", true) !== false,
      cookieBrowser: String(setting("cookieBrowser", "auto")),
      twitchClientId: Model.twitchClientId(setting("twitchClientId", "")),
      soundEnabled: setting("soundEnabled", true) !== false,
      notificationsEnabled: setting("notificationsEnabled", true) !== false,
      notificationTimeoutSec: parseInt(String(setting("notificationTimeoutSec", 12)), 10),
      clickAction: String(setting("clickAction", "Browser")),
      pipPosition: Model.normalizePosition(setting("pipPosition", "bottom-right")),
      pipSize: Model.normalizeSize(setting("pipSize", "medium")),
      youtubeSoundPath: String(setting("youtubeSoundPath", "bundled")),
      twitchSoundPath: String(setting("twitchSoundPath", "bundled"))
    }
  }

  function configureService() {
    // Settings start as an empty object and fill in once the shell hydrates the
    // layout entry. Configuring from manifest defaults in the meantime is what
    // makes a freshly added widget start polling without a toggle first.
    if (!monitor || !settings) return
    monitor.configure(settingsSnapshot())
    settingsApplied = true
  }

  function persistSetting(name, value) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(function (config) {
      const layout = config && config.bar ? config.bar.layout : null
      if (!layout) return
      const sections = ["left", "center", "right"]
      for (let sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
        const entries = layout[sections[sectionIndex]]
        if (!Array.isArray(entries)) continue
        for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
          const entry = entries[entryIndex]
          if (entry && String(entry.id || "") === moduleName) {
            entry[name] = value
            return
          }
        }
      }
    })
  }

  function toggleYoutube(channelId) {
    persistSetting("youtubeChannels", Model.toggleSelection(youtubeSelection, channelId))
  }

  function toggleTwitch(login) {
    persistSetting("twitchChannels", Model.toggleSelection(twitchSelection, login))
  }

  function setPipPosition(position) {
    persistSetting("pipPosition", position)
    if (monitor) monitor.movePip(position)
  }

  function setPipSize(size) {
    persistSetting("pipSize", size)
    if (monitor) monitor.resizePip(size)
  }

  // ---------------------------------------------------------------------------
  // presentation helpers
  // ---------------------------------------------------------------------------

  function itemIcon(item) {
    return String((item || {}).kind) === "twitch" ? "\udb81\udd43" : "\udb81\uddc3"
  }

  function itemColor(item) {
    return String((item || {}).kind) === "twitch" ? root.twitch : root.youtube
  }

  function itemMeta(item) {
    const entry = item || {}
    if (entry.kind === "twitch") {
      const parts = []
      if (entry.game) parts.push(String(entry.game))
      if (entry.viewers) parts.push(Model.compactCount(entry.viewers) + " watching")
      parts.push("live " + Model.liveFor(entry.publishedAt, root.nowMs))
      return parts.join(" · ")
    }
    return String(entry.channelName || "") + " · " + Model.relativeTime(entry.publishedAt, root.nowMs)
  }

  function statusText() {
    if (!monitor) return "Service unavailable"
    if (monitor.state === "loading") return "Checking for new videos and streams"
    return monitor.message
  }

  function heroMeta() {
    if (!monitor) return "OMARCHY CREATORS"
    if (monitor.liveCount > 0) return monitor.liveCount + " LIVE NOW"
    if (monitor.unseenCount > 0) return monitor.unseenCount + " NEW"
    return "OMARCHY CREATORS"
  }

  // The bar widget is text-only, so an empty string here collapses it to zero
  // width and the plugin vanishes from the bar. Idle still shows the bell.
  function barText() {
    if (!monitor) return "\udb80\udc9a"
    if (monitor.liveCount > 0) return "\udb81\udf1d " + monitor.liveCount
    if (monitor.unseenCount > 0) return "\udb80\udc9a " + monitor.unseenCount
    return "\udb80\udc9a"
  }

  function tooltip() {
    if (!monitor) return "Stream alerts"
    if (monitor.liveCount === 0 && monitor.unseenCount === 0) return "Stream alerts\n" + monitor.message
    const lines = []
    for (let i = 0; i < monitor.live.length && i < 6; i++) {
      lines.push(monitor.live[i].channelName + " · " + String(monitor.live[i].game || "live"))
    }
    if (monitor.unseenCount > 0) lines.push(monitor.unseenCount + " new since you last looked")
    return lines.join("\n")
  }

  Component.onCompleted: configureService()
  onSettingsChanged: configureService()
  onYoutubeSelectionChanged: configureService()
  onTwitchSelectionChanged: configureService()
  onMonitorChanged: configureService()

  // The service may mount a beat after the widget; keep offering until it takes.
  Timer {
    interval: 100
    repeat: true
    running: !!root.monitor && !root.settingsApplied
    onTriggered: root.configureService()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    configureService()
    if (monitor) {
      monitor.clearUnseen()
      if (monitor.youtubeCatalogState === "idle") monitor.refreshYoutubeCatalog(false)
      if (monitor.twitchCatalogState === "idle") monitor.refreshTwitchCatalog()
    }
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    active: root.monitor && (root.monitor.liveCount > 0 || root.monitor.unseenCount > 0)
    activeColor: root.monitor && root.monitor.liveCount > 0 ? root.live : root.foreground
    fontSize: Style.font.body
    horizontalMargin: 4
    tooltipText: root.tooltip()
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.monitor) root.monitor.checkNow()
      } else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (text) {
        if (text === "r" || text === "R") { if (root.monitor) root.monitor.checkNow() }
        else if (text === "/") {
          if (root.page === "youtube") youtubeSearch.forceActiveFocus()
          else if (root.page === "twitch") twitchSearch.forceActiveFocus()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Omarchy Creators"
            meta: root.heroMeta()
            detail: root.statusText()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.monitor && root.monitor.liveCount > 0 ? "\udb81\udf1d" : "\udb80\udc9a"
                color: root.monitor && root.monitor.liveCount > 0 ? root.live : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.monitor && root.monitor.warnings.length > 0
            width: parent.width
            text: root.monitor ? root.monitor.warnings.slice(0, 4).join("\n") : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "Feed"
              selected: root.page === "feed"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.page = "feed"
            }
            Button {
              text: "YouTube"
              selected: root.page === "youtube"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.page = "youtube"
            }
            Button {
              text: "Twitch"
              selected: root.page === "twitch"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.page = "twitch"
            }
            Button {
              text: "Player"
              selected: root.page === "player"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.page = "player"
            }
            Item { width: Math.max(0, parent.width - 340); height: 1 }
            Button {
              iconText: "󰑐"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconSpinning: !!root.monitor && root.monitor.loading
              tooltipText: "Check now"
              onClicked: if (root.monitor) root.monitor.checkNow()
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------------------------------------------------------------- feed
          Column {
            visible: root.page === "feed"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              visible: root.monitor && root.monitor.liveCount > 0
              text: "LIVE NOW  ·  " + (root.monitor ? root.monitor.liveCount : 0)
              foreground: root.live
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.monitor ? root.monitor.live : []
              FeedRow {
                required property var modelData
                width: parent ? parent.width : 0
                item: modelData
              }
            }

            PanelSeparator {
              visible: root.monitor && root.monitor.liveCount > 0
              foreground: root.foreground
            }

            PanelSectionHeader {
              text: "RECENT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: !root.monitor || root.monitor.feed.length === 0
              width: parent.width
              text: root.monitor && root.monitor.watchedCount > 0
                ? "Nothing new yet. Alerts fire from the moment you switch a channel on."
                : "Switch channels on in the YouTube and Twitch tabs to start watching them."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(24)
              bottomPadding: Style.space(24)
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.monitor ? root.monitor.feed.slice(0, 40) : []
              FeedRow {
                required property var modelData
                width: parent ? parent.width : 0
                item: modelData
              }
            }
          }

          // ------------------------------------------------------------- youtube
          Column {
            visible: root.page === "youtube"
            width: parent.width
            spacing: Style.space(8)

            Toggle {
              width: parent.width
              label: "Watch YouTube"
              description: "Check subscribed channels for new uploads"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              checked: root.setting("youtubeEnabled", true) !== false
              onClicked: root.persistSetting("youtubeEnabled",
                !(root.setting("youtubeEnabled", true) !== false))
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "SUBSCRIPTIONS  ·  " + root.youtubeSelection.length + " ON"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: youtubeSearch
              width: parent.width
              foreground: root.foreground
              placeholderText: "Search your subscriptions"
              text: root.youtubeQuery
              onTextChanged: root.youtubeQuery = text
              Keys.onEscapePressed: function (event) {
                root.youtubeQuery = ""
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Toggle {
                width: parent.width - youtubeReload.implicitWidth - parent.spacing
                label: "Enabled only"
                description: root.monitor && root.monitor.youtubeCatalog.length > 0
                  ? root.youtubeMatches.length + " of " + root.monitor.youtubeCatalog.length + " channels shown"
                  : "Hide channels you are not watching"
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                checked: root.youtubeSelectedOnly
                onClicked: root.youtubeSelectedOnly = !root.youtubeSelectedOnly
              }

              Button {
                id: youtubeReload
                iconText: "󰑐"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                tooltipText: "Re-read subscriptions from your browser"
                onClicked: if (root.monitor) root.monitor.refreshYoutubeCatalog(true)
              }
            }

            Text {
              visible: root.monitor && root.monitor.youtubeCatalogState === "loading"
              width: parent.width
              text: "Reading your subscriptions from the browser session…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(16)
            }

            Text {
              visible: root.monitor && (root.monitor.youtubeCatalogState === "error"
                || root.monitor.youtubeCatalogState === "signed-out"
                || root.monitor.youtubeCatalogState === "missing-tool")
              width: parent.width
              text: root.monitor ? root.monitor.youtubeCatalogMessage : ""
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.youtubeMatches.slice(0, root.pickerLimit)
              Toggle {
                required property var modelData
                width: parent ? parent.width : 0
                label: modelData.name
                description: String(modelData.handle || "")
                  + (modelData.subscribers ? " · " + Model.compactCount(modelData.subscribers) + " subscribers" : "")
                foreground: root.foreground
                accent: root.youtube
                fontFamily: root.fontFamily
                checked: root.youtubeSelection.indexOf(String(modelData.id)) !== -1
                onClicked: root.toggleYoutube(modelData.id)
              }
            }

            Text {
              visible: root.youtubeMatches.length > root.pickerLimit
              width: parent.width
              text: "+ " + (root.youtubeMatches.length - root.pickerLimit)
                + " more — narrow it down with the search field"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // -------------------------------------------------------------- twitch
          Column {
            visible: root.page === "twitch"
            width: parent.width
            spacing: Style.space(8)

            Toggle {
              width: parent.width
              label: "Watch Twitch"
              description: "Alert when a followed channel goes live"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              checked: root.setting("twitchEnabled", true) !== false
              onClicked: root.persistSetting("twitchEnabled",
                !(root.setting("twitchEnabled", true) !== false))
            }

            PanelSeparator { foreground: root.foreground }

            // Sign-in card, shown until Twitch has actually answered with follows.
            Column {
              visible: !root.monitor || root.monitor.twitchAuthState !== "connected"
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "CONNECT TWITCH"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: text !== ""
                width: parent.width
                text: {
                  if (!root.monitor) return ""
                  // Author-facing: only ever visible in a build that shipped
                  // without a Client ID baked into the manifest default.
                  if (!root.monitor.twitchReady)
                    return "DEV: missing Client ID. Register an app at dev.twitch.tv/console/apps (Public client, redirect http://localhost) and set twitchClientId."
                  if (root.monitor.twitchAuthState === "pending")
                    return "Enter this code in the browser tab that just opened, then come back."
                  return "Twitch keeps follow lists behind an authorised session, so the plugin signs in once with a device code. Nothing is stored but the token, in a private file."
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                visible: !!root.monitor && root.monitor.twitchUserCode !== ""
                width: parent.width
                text: root.monitor ? root.monitor.twitchUserCode : ""
                color: root.twitch
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
              }

              Row {
                spacing: Style.space(8)
                Button {
                  text: root.monitor && root.monitor.twitchAuthState === "pending"
                    ? "Waiting for approval…" : "Connect Twitch"
                  iconText: "\udb81\udd43"
                  bordered: true
                  foreground: root.twitch
                  fontFamily: root.fontFamily
                  enabled: !!root.monitor && root.monitor.twitchReady
                  onClicked: if (root.monitor) root.monitor.connectTwitch()
                }
                Button {
                  text: "Open activation page"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  visible: !!root.monitor && root.monitor.twitchAuthState === "pending"
                  onClicked: if (root.monitor) root.monitor.openInBrowser(root.monitor.twitchVerificationUri)
                }
              }
            }

            Column {
              visible: !!root.monitor && root.monitor.twitchAuthState === "connected"
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "FOLLOWED CHANNELS  ·  " + root.twitchSelection.length + " ON"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              TextField {
                id: twitchSearch
                width: parent.width
                foreground: root.foreground
                placeholderText: "Search the channels you follow"
                text: root.twitchQuery
                onTextChanged: root.twitchQuery = text
                Keys.onEscapePressed: function (event) {
                  root.twitchQuery = ""
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Toggle {
                  width: parent.width - twitchReload.implicitWidth - disconnectTwitch.implicitWidth - parent.spacing * 2
                  label: "Enabled only"
                  description: root.monitor && root.monitor.twitchCatalog.length > 0
                    ? root.twitchMatches.length + " of " + root.monitor.twitchCatalog.length + " channels shown"
                    : "Hide channels you are not watching"
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  checked: root.twitchSelectedOnly
                  onClicked: root.twitchSelectedOnly = !root.twitchSelectedOnly
                }

                Button {
                  id: twitchReload
                  iconText: "󰑐"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  tooltipText: "Reload follows"
                  onClicked: if (root.monitor) root.monitor.refreshTwitchCatalog()
                }

                Button {
                  id: disconnectTwitch
                  iconText: "󰍃"
                  bordered: true
                  foreground: root.urgent
                  fontFamily: root.fontFamily
                  tooltipText: "Disconnect Twitch"
                  onClicked: if (root.monitor) root.monitor.disconnectTwitch()
                }
              }

              Repeater {
                model: root.twitchMatches.slice(0, root.pickerLimit)
                Toggle {
                  required property var modelData
                  width: parent ? parent.width : 0
                  label: modelData.name
                  description: "@" + String(modelData.login || "")
                  foreground: root.foreground
                  accent: root.twitch
                  fontFamily: root.fontFamily
                  checked: root.twitchSelection.indexOf(String(modelData.login)) !== -1
                  onClicked: root.toggleTwitch(modelData.login)
                }
              }

              Text {
                visible: root.twitchMatches.length > root.pickerLimit
                width: parent.width
                text: "+ " + (root.twitchMatches.length - root.pickerLimit)
                  + " more — narrow it down with the search field"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          // -------------------------------------------------------------- player
          Column {
            visible: root.page === "player"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "WHEN A NOTIFICATION IS CLICKED"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              spacing: Style.space(8)
              Button {
                text: "Open in browser"
                iconText: "󰖟"
                bordered: true
                selected: !Model.isPip(root.setting("clickAction", "Browser"))
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.persistSetting("clickAction", "Browser")
              }
              Button {
                text: "Picture in picture"
                iconText: "󰹑"
                bordered: true
                selected: Model.isPip(root.setting("clickAction", "Browser"))
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.persistSetting("clickAction", "Picture in picture")
              }
            }

            Text {
              width: parent.width
              text: "Clicking the notification does this. In the Feed tab a left click follows the same choice and a right click takes the other route, so both are always one click away."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "PICTURE-IN-PICTURE POSITION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // A 3x3 map of the screen: press a cell to snap the player there.
            Grid {
              columns: 3
              spacing: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter

              Repeater {
                model: Model.POSITIONS
                Rectangle {
                  required property var modelData
                  readonly property bool current:
                    Model.normalizePosition(root.setting("pipPosition", "bottom-right")) === modelData
                  width: Style.space(74)
                  height: Style.space(46)
                  radius: Style.cornerRadius
                  color: current
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                              cellMouse.containsMouse ? 0.14 : 0.05)
                  border.width: current ? Style.normalBorderWidth : 0
                  border.color: Color.accent

                  Text {
                    anchors.centerIn: parent
                    text: "󰹑"
                    color: current ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setPipPosition(modelData)
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "SIZE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              spacing: Style.space(8)
              Repeater {
                model: Model.SIZES
                Button {
                  required property var modelData
                  text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                  bordered: true
                  selected: Model.normalizeSize(root.setting("pipSize", "medium")) === modelData
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.setPipSize(modelData)
                }
              }
              Button {
                iconText: "\udb80\udd56"
                bordered: true
                foreground: root.urgent
                fontFamily: root.fontFamily
                tooltipText: "Close the player"
                onClicked: if (root.monitor) root.monitor.closePip()
              }
            }

            Text {
              width: parent.width
              text: "The player floats and stays pinned across workspaces. Drag it anywhere with Super + left mouse, resize with Super + right mouse."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "CHIMES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Play a chime"
              description: "One chime per batch, distinct per service"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              checked: root.setting("soundEnabled", true) !== false
              onClicked: root.persistSetting("soundEnabled",
                !(root.setting("soundEnabled", true) !== false))
            }

            Row {
              spacing: Style.space(8)
              Button {
                text: "Test YouTube"
                iconText: "\udb81\uddc3"
                bordered: true
                foreground: root.youtube
                fontFamily: root.fontFamily
                onClicked: if (root.monitor) root.monitor.testSound("youtube")
              }
              Button {
                text: "Test Twitch"
                iconText: "\udb81\udd43"
                bordered: true
                foreground: root.twitch
                fontFamily: root.fontFamily
                onClicked: if (root.monitor) root.monitor.testSound("twitch")
              }
            }
          }
        }
      }
    }
  }

  component FeedRow: Rectangle {
    id: feedRow
    property var item: ({})

    implicitHeight: feedContent.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: feedMouse.containsMouse
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)

    MouseArea {
      id: feedMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      // Left click follows the configured default; right click always takes
      // the other route, so both are reachable without opening settings.
      onClicked: function (mouse) {
        if (!root.monitor) return
        const pip = Model.isPip(root.monitor.clickAction)
        const wantsPip = mouse.button === Qt.RightButton ? !pip : pip
        if (wantsPip) root.monitor.openInPip(feedRow.item.url, feedRow.item.channelName)
        else root.monitor.openInBrowser(feedRow.item.url)
        root.close()
      }
    }

    RowLayout {
      id: feedContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(8)
      spacing: Style.space(10)

      Text {
        text: root.itemIcon(feedRow.item)
        color: root.itemColor(feedRow.item)
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: String(feedRow.item.title || "Untitled")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: root.itemMeta(feedRow.item)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: String(feedRow.item.kind) === "twitch"
        Layout.alignment: Qt.AlignVCenter
        text: "LIVE"
        color: root.live
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}
