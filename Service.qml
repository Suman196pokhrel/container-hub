import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool dockerAvailable: true
  property string errorKind: ""
  property string errorMessage: ""
  property var containers: []
  property int runningCount: 0
  property bool loading: false

  readonly property int refreshIntervalOpenSec: intSetting("refreshIntervalOpenSec", 3, 1, 60)
  readonly property int refreshIntervalClosedSec: intSetting("refreshIntervalClosedSec", 15, 5, 300)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (psProcess.running) return
    root.loading = true
    psProcess._exitedNormally = false
    psProcess.running = true
  }

  function applyContainers(stdout) {
    root.containers = Model.parseContainerList(stdout)
    var running = 0
    for (var i = 0; i < root.containers.length; i++) {
      if (root.containers[i].isRunning) running++
    }
    root.runningCount = running
    root.errorKind = ""
    root.errorMessage = ""
  }

  function applyError(stderrText) {
    root.containers = []
    root.runningCount = 0
    var classified = Model.classifyDockerError(root.dockerAvailable, stderrText)
    root.errorKind = classified.kind
    root.errorMessage = classified.message
  }

  onPanelOpenChanged: refreshTimer.restart()

  Timer {
    id: refreshTimer
    interval: (root.panelOpen ? root.refreshIntervalOpenSec : root.refreshIntervalClosedSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: whichProcess
    command: ["which", "docker"]
    onExited: function(exitCode) {
      root.dockerAvailable = exitCode === 0
      root.refresh()
    }
  }

  Process {
    id: psProcess
    running: false
    command: ["docker", "ps", "-a", "--format", "{{json .}}"]
    property bool _exitedNormally: false
    stdout: StdioCollector { id: psStdout; waitForEnd: true }
    stderr: StdioCollector { id: psStderr; waitForEnd: true }
    onExited: function(exitCode) {
      psProcess._exitedNormally = true
      root.loading = false
      if (exitCode === 0) root.applyContainers(psStdout.text || "")
      else root.applyError(psStderr.text || psStdout.text || "")
    }
    onRunningChanged: {
      if (!running && !psProcess._exitedNormally) {
        // Quickshell's Process never emits `exited` when the command itself
        // fails to spawn (e.g. the "docker" binary is missing) — only
        // `runningChanged` fires in that case. Without this branch, a
        // missing Docker install would leave `loading` stuck true forever
        // with no error ever shown, since nothing else observes that path.
        root.dockerAvailable = false
        root.loading = false
        root.applyError("")
      }
    }
  }

  Component.onCompleted: whichProcess.running = true
}
