import QtQuick
import Quickshell.Io
import "engines/shared.js" as Shared
import "engines/docker.js" as DockerEngine
import "engines/podman.js" as PodmanEngine

Item {
  id: root

  property string engineName: "docker" // "docker" | "podman"
  property var settings: ({})
  property bool panelOpen: false

  property bool available: true
  property string enginePath: ""
  property string errorKind: ""
  property string errorMessage: ""
  property string actionErrorMessage: ""
  property var containers: []
  property int runningCount: 0
  property bool loading: false

  property int consecutiveFailures: 0
  readonly property int backoffMultiplier: Math.min(5, 1 + root.consecutiveFailures)

  readonly property int refreshIntervalOpenSec: intSetting("refreshIntervalOpenSec", 3, 1, 60)
  readonly property int refreshIntervalClosedSec: intSetting("refreshIntervalClosedSec", 15, 5, 300)

  readonly property int logTailLines: intSetting("logTailLines", 200, 50, 1000)

  readonly property alias logsText: logs.text
  readonly property alias logsContainerId: logs.containerId
  readonly property alias logsLoading: logs.loading

  // Picks the active engine module — both export the same function set
  // (see docs/superpowers/specs/2026-09-02-podman-integration-design.md)
  // so everything below calls through this instead of hardcoding one engine.
  function spec() { return root.engineName === "podman" ? PodmanEngine : DockerEngine }

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
    // enginePath is only set once the resolved binary has passed validation
    // (see the BinaryResolver below); before that, or if validation ever
    // failed, there is nothing safe to run yet.
    if (root.enginePath === "") return
    if (sudoCheck.running || psProcess.running) return
    root.loading = true
    if (spec().needsAccessCheck) {
      sudoCheck.start()
    } else {
      // Podman today: rootless, no daemon-socket privilege boundary to
      // check ahead of time, so go straight to listing.
      psProcess.command = spec().psCommand(root.enginePath)
      psProcess.start()
    }
  }

  function applyContainers(stdout) {
    root.containers = spec().parseContainerList(stdout, Shared)
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
    var classified = spec().classifyError(root.available, stderrText)
    root.errorKind = classified.kind
    root.errorMessage = classified.message
  }

  function containerExists(id) {
    for (var i = 0; i < root.containers.length; i++) {
      if (root.containers[i].id === id) return true
    }
    return false
  }

  function fetchLogs(id) {
    if (root.enginePath === "") return
    logs.fetch(spec().logsCommand(root.enginePath, id, root.logTailLines), id)
  }

  function clearLogs() { logs.clear() }

  function stopContainer(id) { runAction(spec().actionCommand(root.enginePath, "stop", id), "stop container") }
  function startContainer(id) { runAction(spec().actionCommand(root.enginePath, "start", id), "start container") }
  function removeContainer(id) { runAction(spec().actionCommand(root.enginePath, "remove", id), "remove container") }

  function runAction(command, label) {
    if (root.enginePath === "") return
    actions.run(command, label)
  }

  onPanelOpenChanged: refreshTimer.restart()

  Timer {
    id: refreshTimer
    // Repeated poll failures (daemon down, socket unreachable) back off up
    // to 5x the configured interval instead of retrying unbounded at full
    // speed; a single success resets it.
    interval: (root.panelOpen ? root.refreshIntervalOpenSec : root.refreshIntervalClosedSec) * 1000 * root.backoffMultiplier
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BinaryResolver {
    id: resolver
    binaryName: root.spec().binaryName
    onResolved: function(path) {
      root.enginePath = path
      root.available = true
      root.refresh()
    }
    onFailed: function(reason) {
      root.available = false
      root.loading = false
      if (reason === "not-found") {
        root.applyError("")
      } else {
        root.errorKind = "unsafe-binary"
        root.errorMessage = reason
      }
    }
  }

  // Omarchy deliberately keeps users out of the (root-equivalent) docker
  // group by default; this is a cheap local check with no daemon call and
  // no prompt, so it is safe to run ahead of every poll. Podman's spec sets
  // needsAccessCheck to false and skips this entirely (see refresh()).
  BoundedProcess {
    id: sudoCheck
    command: ["omarchy-sudo-docker"]
    timeoutMs: 5000
    onFinished: {
      if (!failedToSpawn && !timedOut && exitCode === 0) {
        root.loading = false
        root.containers = []
        root.runningCount = 0
        root.errorKind = "needs-docker-access"
        root.errorMessage = "Docker access needs one-time setup: your user isn't in the docker group. Omarchy keeps that opt-in because it's root-equivalent."
        root.consecutiveFailures = 0
        return
      }
      // Helper missing or inconclusive: fall through to the direct attempt,
      // whose own permission-denied classification is the fallback signal.
      psProcess.command = spec().psCommand(root.enginePath)
      psProcess.start()
    }
  }

  BoundedProcess {
    id: psProcess
    timeoutMs: 10000
    maxOutChars: 400000
    maxErrChars: 16384
    onFinished: {
      root.loading = false
      if (!failedToSpawn && !timedOut && exitCode === 0) {
        root.applyContainers(stdoutText)
        root.consecutiveFailures = 0
      } else {
        root.consecutiveFailures = Math.min(root.consecutiveFailures + 1, 20)
        if (failedToSpawn) {
          root.available = false
          root.applyError("")
        } else if (timedOut) {
          // A direct state, not routed through spec().classifyError: that
          // classifier pattern-matches the engine's own stderr text, and
          // this message is ours, not the engine's.
          root.containers = []
          root.runningCount = 0
          root.errorKind = "timeout"
          root.errorMessage = "Did not respond in time."
        } else {
          root.applyError(stderrText || stdoutText || "")
        }
      }
    }
  }

  ActionRunner {
    id: actions
    onErrorMessageChanged: root.actionErrorMessage = errorMessage
    onFinished: root.refresh()
  }

  LogsRunner {
    id: logs
  }

  Component.onCompleted: resolver.resolveAndValidate()
}
