import QtQuick
import Quickshell
import Quickshell.Io
import "CreatorsModel.js" as Model

Item {
  id: root

  // ---- configuration, pushed in by the panel from shell.json ---------------
  property var youtubeChannels: []
  property var twitchChannels: []
  property bool youtubeEnabled: true
  property bool twitchEnabled: true
  property int refreshIntervalSec: 300
  property string cookieBrowser: "auto"
  property string twitchClientId: ""
  property bool soundEnabled: true
  property real soundVolume: 1
  property bool notificationsEnabled: true
  property int notificationTimeoutSec: 12
  property string clickAction: "Browser"
  property string pipPosition: "bottom-right"
  property string pipSize: "medium"
  property string youtubeSoundPath: ""
  property string twitchSoundPath: ""
  property bool configured: false

  // ---- observable state ---------------------------------------------------
  property string state: "idle"
  property string message: "Pick channels to watch"
  property string checkedAt: ""
  property var feed: []
  property var live: []
  property var warnings: []
  property var youtubeCatalog: []
  property var twitchCatalog: []
  property string youtubeCatalogState: "idle"
  property string youtubeCatalogMessage: ""
  property string twitchCatalogState: "idle"
  property string twitchCatalogMessage: ""
  property string twitchAuthState: "idle"
  property string twitchUserCode: ""
  property string twitchVerificationUri: ""
  property int unseenCount: 0
  property var soundQueue: []
  property bool refreshQueued: false
  property bool offline: false

  readonly property string helperPath: localPath(Qt.resolvedUrl("creators"))
  readonly property string notifyPath: localPath(Qt.resolvedUrl("creators-notify"))
  readonly property string pipPath: localPath(Qt.resolvedUrl("creators-pip"))
  readonly property string bundledYoutubeSound: localPath(Qt.resolvedUrl("assets/youtube.wav"))
  readonly property string bundledTwitchSound: localPath(Qt.resolvedUrl("assets/twitch.wav"))
  readonly property int watchedCount: youtubeChannels.length + twitchChannels.length
  readonly property int liveCount: live.length
  readonly property bool loading: youtubeProcess.running || twitchProcess.running
  readonly property bool twitchReady: twitchClientId !== ""

  function localPath(url) {
    const value = String(url || "")
    return decodeURIComponent(value.indexOf("file://") === 0 ? value.slice(7) : value)
  }

  function soundPath(value, bundled) {
    const text = String(value || "")
    if (text === "" || text === "bundled") return bundled
    if (text.indexOf("~/") === 0) return (Quickshell.env("HOME") || "") + text.slice(1)
    return text
  }

  // -------------------------------------------------------------------------
  // configuration
  // -------------------------------------------------------------------------

  function configure(next) {
    const changedSelection =
      !Model.sameArray(youtubeChannels, next.youtubeChannels) ||
      !Model.sameArray(twitchChannels, next.twitchChannels) ||
      youtubeEnabled !== next.youtubeEnabled ||
      twitchEnabled !== next.twitchEnabled

    youtubeChannels = Model.normalizeIds(next.youtubeChannels)
    twitchChannels = Model.normalizeIds(next.twitchChannels)
    youtubeEnabled = next.youtubeEnabled !== false
    twitchEnabled = next.twitchEnabled !== false
    refreshIntervalSec = Model.clampInterval(next.refreshIntervalSec)
    cookieBrowser = String(next.cookieBrowser || "auto")
    twitchClientId = String(next.twitchClientId || "").trim()
    soundEnabled = next.soundEnabled !== false
    setSoundVolume(next.soundVolume)
    notificationsEnabled = next.notificationsEnabled !== false
    notificationTimeoutSec = Math.max(0, Math.min(120, parseInt(String(next.notificationTimeoutSec), 10) || 0))
    clickAction = String(next.clickAction || "Browser")
    pipPosition = Model.normalizePosition(next.pipPosition)
    pipSize = Model.normalizeSize(next.pipSize)
    youtubeSoundPath = soundPath(next.youtubeSoundPath, bundledYoutubeSound)
    twitchSoundPath = soundPath(next.twitchSoundPath, bundledTwitchSound)

    const first = !configured
    configured = true
    if (first) {
      refreshYoutubeCatalog(false)
      if (twitchReady) refreshTwitchCatalog()
    }
    if (first || changedSelection) Qt.callLater(checkNow)
  }

  // -------------------------------------------------------------------------
  // checks
  // -------------------------------------------------------------------------

  function checkNow() {
    if (!configured) return
    if (loading) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    warnings = []
    offline = false

    if (watchedCount === 0) {
      state = "ready"
      message = "Pick channels to watch"
      feed = []
      live = []
      return
    }

    state = "loading"
    message = "Checking for new videos and streams"
    if (youtubeEnabled && youtubeChannels.length > 0) startYoutubeCheck()
    if (twitchEnabled && twitchChannels.length > 0 && twitchReady) startTwitchCheck()
    if (!youtubeProcess.running && !twitchProcess.running) settle()
  }

  function startYoutubeCheck() {
    const command = [helperPath, "youtube", "check", "--commit"]
    for (let i = 0; i < youtubeChannels.length; i++) command.push("--channel", youtubeChannels[i])
    youtubeProcess.command = command
    youtubeProcess.running = true
  }

  function startTwitchCheck() {
    const command = [helperPath, "--client-id", twitchClientId, "twitch", "check", "--commit"]
    for (let i = 0; i < twitchChannels.length; i++) command.push("--login", twitchChannels[i])
    twitchProcess.command = command
    twitchProcess.running = true
  }

  function applyCheck(raw, kind) {
    let data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      warnings = warnings.concat([kind + ": unreadable response"])
      return
    }

    checkedAt = String(data.checkedAt || checkedAt)
    if (Array.isArray(data.warnings) && data.warnings.length > 0) {
      warnings = warnings.concat(data.warnings.map(function (line) { return kind + ": " + line }))
    }

    if (String(data.state || "") !== "ready") {
      // The machine is not on the network yet — after a reboot the first check
      // beats NetworkManager to it. That is not something to warn about, and
      // not a reason to make the user wait a full interval for the truth.
      if (data.state === "offline") {
        offline = true
        return
      }
      warnings = warnings.concat([kind + ": " + String(data.message || "check failed")])
      if (kind === "twitch" && data.state === "signed-out") twitchAuthState = "signed-out"
      return
    }
    if (kind === "twitch") {
      twitchAuthState = "connected"
      live = Array.isArray(data.items) ? data.items : []
      feed = feed.filter(function (item) { return item.kind !== "twitch" })
    } else {
      feed = Model.mergeFeed(feed, Array.isArray(data.items) ? data.items : [], 80)
    }
    announce(Array.isArray(data.fresh) ? data.fresh : [])
  }

  function settle() {
    if (youtubeProcess.running || twitchProcess.running) return
    state = warnings.length > 0 && feed.length === 0 ? "error" : "ready"
    message = offline ? "Waiting for the network" : summary()
    if (refreshQueued) {
      refreshQueued = false
      Qt.callLater(checkNow)
    }
  }

  function summary() {
    if (watchedCount === 0) return "Pick channels to watch"
    const parts = []
    if (youtubeEnabled && youtubeChannels.length > 0) parts.push(youtubeChannels.length + " on YouTube")
    if (twitchEnabled && twitchChannels.length > 0) parts.push(twitchChannels.length + " on Twitch")
    if (liveCount > 0) parts.push(liveCount + " live")
    return parts.join(" · ") + " · every " + Math.round(refreshIntervalSec / 60) + " min"
  }

  // -------------------------------------------------------------------------
  // alerting
  // -------------------------------------------------------------------------

  function setSoundVolume(value) {
    soundVolume = Model.normalizeChimeVolume(value)
  }

  function announce(fresh) {
    if (fresh.length === 0) return
    unseenCount += fresh.length
    if (soundEnabled) enqueueSounds(Model.soundsForBatch(fresh))
    if (!notificationsEnabled) return
    for (let i = 0; i < fresh.length; i++) {
      Quickshell.execDetached(Model.notifyCommand(notifyPath, fresh[i], {
        clickAction: clickAction, timeoutSec: notificationTimeoutSec,
        pipPosition: pipPosition, pipSize: pipSize
      }))
    }
  }

  function enqueueSounds(kinds) {
    const additions = []
    for (let i = 0; i < kinds.length; i++) {
      const path = kinds[i] === "twitch" ? twitchSoundPath : youtubeSoundPath
      if (path !== "") additions.push(path)
    }
    if (additions.length === 0) return
    soundQueue = soundQueue.concat(additions)
    playNextSound()
  }

  function playNextSound() {
    if (soundProcess.running || soundQueue.length === 0) return
    const path = soundQueue[0]
    soundQueue = soundQueue.slice(1)
    soundProcess.command = ["pw-play", "--volume", String(soundVolume), path]
    soundProcess.running = true
  }

  function testSound(kind) {
    enqueueSounds([kind])
  }

  function clearUnseen() {
    unseenCount = 0
  }

  // -------------------------------------------------------------------------
  // opening
  // -------------------------------------------------------------------------

  function openInBrowser(url) {
    if (String(url || "") === "") return
    Quickshell.execDetached(["omarchy-launch-browser", String(url)])
  }

  function openInPip(url, title) {
    if (String(url || "") === "") return
    Quickshell.execDetached([pipPath, "open", String(url),
      "--position", pipPosition, "--size", pipSize, "--title", String(title || "Stream PiP")])
  }

  function openItem(item) {
    const entry = item || {}
    if (Model.isPip(clickAction)) openInPip(entry.url, entry.channelName)
    else openInBrowser(entry.url)
  }

  function movePip(position) {
    pipPosition = Model.normalizePosition(position)
    Quickshell.execDetached([pipPath, "position", pipPosition])
  }

  function resizePip(size) {
    pipSize = Model.normalizeSize(size)
    Quickshell.execDetached([pipPath, "size", pipSize])
  }

  function closePip() {
    Quickshell.execDetached([pipPath, "close"])
  }

  // -------------------------------------------------------------------------
  // catalogs and Twitch sign-in
  // -------------------------------------------------------------------------

  function refreshYoutubeCatalog(force) {
    if (youtubeCatalogProcess.running) return
    youtubeCatalogState = "loading"
    youtubeCatalogMessage = ""
    const command = [helperPath, "youtube", "catalog", "--browser", cookieBrowser]
    if (force) command.push("--refresh")
    youtubeCatalogProcess.command = command
    youtubeCatalogProcess.running = true
  }

  function refreshTwitchCatalog() {
    if (twitchCatalogProcess.running) return
    if (!twitchReady) {
      twitchCatalogState = "no-client-id"
      twitchCatalogMessage = "Add a Twitch Client ID in settings to connect your account."
      return
    }
    twitchCatalogState = "loading"
    twitchCatalogMessage = ""
    twitchCatalogProcess.command = [helperPath, "--client-id", twitchClientId, "twitch", "catalog"]
    twitchCatalogProcess.running = true
  }

  function connectTwitch() {
    if (!twitchReady) {
      twitchCatalogState = "no-client-id"
      twitchCatalogMessage = "Add a Twitch Client ID in settings first."
      return
    }
    twitchAuthState = "starting"
    twitchLoginProcess.command = [helperPath, "--client-id", twitchClientId, "twitch", "login"]
    twitchLoginProcess.running = true
  }

  function disconnectTwitch() {
    Quickshell.execDetached([helperPath, "twitch", "logout"])
    twitchAuthState = "signed-out"
    twitchCatalog = []
    twitchUserCode = ""
  }

  function pollTwitchLogin() {
    if (twitchPollProcess.running) return
    twitchPollProcess.command = [helperPath, "--client-id", twitchClientId, "twitch", "login-poll"]
    twitchPollProcess.running = true
  }

  // -------------------------------------------------------------------------
  // processes
  // -------------------------------------------------------------------------

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.configured && root.watchedCount > 0
    repeat: true
    onTriggered: root.checkNow()
  }

  // A check that found no network is worth repeating in seconds rather than
  // minutes: the usual case is a machine that has just booted, and the network
  // arrives long before the next interval would.
  Timer {
    interval: 20000
    repeat: true
    running: root.offline && root.configured && root.watchedCount > 0
    onTriggered: root.checkNow()
  }

  // While a device-code sign-in is on screen, ask Twitch whether it has been
  // approved yet. Twitch's own interval floor is 5 seconds.
  Timer {
    interval: 5000
    repeat: true
    running: root.twitchAuthState === "pending"
    onTriggered: root.pollTwitchLogin()
  }

  Process {
    id: youtubeProcess
    stdout: StdioCollector { id: youtubeOut; waitForEnd: true }
    stderr: StdioCollector { id: youtubeErr; waitForEnd: true }
    onExited: {
      const output = String(youtubeOut.text || "")
      if (output.trim() !== "") root.applyCheck(output, "youtube")
      else root.warnings = root.warnings.concat(["youtube: " + (String(youtubeErr.text || "no output").trim())])
      root.settle()
    }
  }

  Process {
    id: twitchProcess
    stdout: StdioCollector { id: twitchOut; waitForEnd: true }
    stderr: StdioCollector { id: twitchErr; waitForEnd: true }
    onExited: {
      const output = String(twitchOut.text || "")
      if (output.trim() !== "") root.applyCheck(output, "twitch")
      else root.warnings = root.warnings.concat(["twitch: " + (String(twitchErr.text || "no output").trim())])
      root.settle()
    }
  }

  Process {
    id: youtubeCatalogProcess
    stdout: StdioCollector { id: youtubeCatalogOut; waitForEnd: true }
    onExited: {
      try {
        const data = JSON.parse(String(youtubeCatalogOut.text || ""))
        root.youtubeCatalogState = String(data.state || "error")
        root.youtubeCatalogMessage = String(data.message || "")
        root.youtubeCatalog = Array.isArray(data.channels) ? data.channels : []
      } catch (error) {
        root.youtubeCatalogState = "error"
        root.youtubeCatalogMessage = "Could not read your subscriptions."
      }
    }
  }

  Process {
    id: twitchCatalogProcess
    stdout: StdioCollector { id: twitchCatalogOut; waitForEnd: true }
    onExited: {
      try {
        const data = JSON.parse(String(twitchCatalogOut.text || ""))
        root.twitchCatalogState = String(data.state || "error")
        root.twitchCatalogMessage = String(data.message || "")
        root.twitchCatalog = Array.isArray(data.channels) ? data.channels : []
        if (root.twitchCatalogState === "ready") root.twitchAuthState = "connected"
        else if (root.twitchCatalogState === "signed-out") root.twitchAuthState = "signed-out"
      } catch (error) {
        root.twitchCatalogState = "error"
        root.twitchCatalogMessage = "Could not read your Twitch follows."
      }
    }
  }

  Process {
    id: twitchLoginProcess
    stdout: StdioCollector { id: twitchLoginOut; waitForEnd: true }
    onExited: {
      try {
        const data = JSON.parse(String(twitchLoginOut.text || ""))
        if (String(data.state || "") !== "ready") {
          root.twitchAuthState = "error"
          root.twitchCatalogMessage = String(data.message || "Twitch sign-in failed.")
          return
        }
        root.twitchUserCode = String(data.userCode || "")
        root.twitchVerificationUri = String(data.verificationUri || "https://www.twitch.tv/activate")
        root.twitchAuthState = "pending"
        root.openInBrowser(root.twitchVerificationUri)
      } catch (error) {
        root.twitchAuthState = "error"
        root.twitchCatalogMessage = "Twitch sign-in failed."
      }
    }
  }

  Process {
    id: twitchPollProcess
    stdout: StdioCollector { id: twitchPollOut; waitForEnd: true }
    onExited: {
      try {
        const data = JSON.parse(String(twitchPollOut.text || ""))
        if (data.authorized === true) {
          root.twitchAuthState = "connected"
          root.twitchUserCode = ""
          root.refreshTwitchCatalog()
          Qt.callLater(root.checkNow)
        } else if (String(data.state || "") !== "ready") {
          root.twitchAuthState = "error"
          root.twitchCatalogMessage = String(data.message || "Twitch sign-in failed.")
        }
      } catch (error) {
        root.twitchAuthState = "error"
      }
    }
  }

  Process {
    id: soundProcess
    onExited: root.playNextSound()
  }
}
