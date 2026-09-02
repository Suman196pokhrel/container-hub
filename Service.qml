import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool dockerAvailable: true
  property string dockerPath: ""
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

  property string logsText: ""
  property string logsContainerId: ""
  property bool logsLoading: false

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
    // dockerPath is only set once the resolved binary has passed validation
    // (see pathResolver/pathValidator below); before that, or if validation
    // ever failed, there is nothing safe to run yet.
    if (root.dockerPath === "") return
    if (sudoCheck.running || psProcess.running) return
    root.loading = true
    sudoCheck.start()
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

  function containerExists(id) {
    for (var i = 0; i < root.containers.length; i++) {
      if (root.containers[i].id === id) return true
    }
    return false
  }

  function fetchLogs(id) {
    if (root.dockerPath === "" || logsProcess.running) return
    root.logsLoading = true
    root.logsContainerId = id
    root.logsText = ""
    logsProcess.command = [root.dockerPath, "logs", "--tail", String(root.logTailLines), "--timestamps", id]
    logsProcess.start()
  }

  function clearLogs() {
    root.logsContainerId = ""
    root.logsText = ""
  }

  function stopContainer(id) { runAction([root.dockerPath, "stop", id], "stop container") }
  function startContainer(id) { runAction([root.dockerPath, "start", id], "start container") }
  function removeContainer(id) { runAction([root.dockerPath, "rm", "-f", id], "remove container") }

  function runAction(command, label) {
    if (root.dockerPath === "") return
    if (actionProcess.running) {
      // A prior action (e.g. "stop", which can hold the process for a full
      // 10s grace period) is still in flight. Say so instead of silently
      // dropping this one — the old behavior looked like a missed click.
      root.actionErrorMessage = "Another action is still running; try again in a moment."
      return
    }
    root.actionErrorMessage = ""
    actionProcess._label = label
    actionProcess.command = command
    actionProcess.start()
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

  // Startup: resolve "docker" off PATH once, then validate the resolved
  // path is a root-owned, non-group/other-writable regular file before it
  // is ever used. Every later invocation uses this literal absolute path,
  // never a bare "docker" lookup, since PATH is attacker-influenceable and
  // the daemon this binary talks to is root-equivalent.
  BoundedProcess {
    id: pathResolver
    command: ["which", "docker"]
    timeoutMs: 5000
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        root.dockerAvailable = false
        root.loading = false
        root.applyError("")
        return
      }
      var candidate = (stdoutText.split("\n")[0] || "").trim()
      if (candidate === "" || candidate.charAt(0) !== "/") {
        root.dockerAvailable = false
        root.loading = false
        root.applyError("")
        return
      }
      pathValidator._candidate = candidate
      pathValidator.command = ["stat", "-L", "-c", "%F|%u|%a", candidate]
      pathValidator.start()
    }
  }

  BoundedProcess {
    id: pathValidator
    timeoutMs: 5000
    property string _candidate: ""
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        root.dockerAvailable = false
        root.errorKind = "unsafe-binary"
        root.errorMessage = "Could not verify the Docker binary at " + pathValidator._candidate + "."
        root.loading = false
        return
      }
      var parts = stdoutText.trim().split("|")
      var kind = parts[0] || ""
      var uid = parts[1] || ""
      var mode = parseInt(parts[2] || "0", 8)
      var ownedByRoot = uid === "0"
      var notGroupOrOtherWritable = (mode & 0o022) === 0
      if (kind !== "regular file" || !ownedByRoot || !notGroupOrOtherWritable) {
        root.dockerAvailable = false
        root.errorKind = "unsafe-binary"
        root.errorMessage = "Docker binary at " + pathValidator._candidate + " failed a safety check (expected a root-owned, non-writable regular file)."
        root.loading = false
        return
      }
      root.dockerPath = pathValidator._candidate
      root.dockerAvailable = true
      root.refresh()
    }
  }

  // Omarchy deliberately keeps users out of the (root-equivalent) docker
  // group by default; this is a cheap local check with no daemon call and
  // no prompt, so it is safe to run ahead of every poll.
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
      psProcess.command = [root.dockerPath, "ps", "-a", "--format", "{{json .}}"]
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
          root.dockerAvailable = false
          root.applyError("")
        } else if (timedOut) {
          // A direct state, not routed through Model.classifyDockerError:
          // that classifier pattern-matches Docker's own stderr text, and
          // this message is ours, not Docker's.
          root.containers = []
          root.runningCount = 0
          root.errorKind = "timeout"
          root.errorMessage = "Docker did not respond in time."
        } else {
          root.applyError(stderrText || stdoutText || "")
        }
      }
    }
  }

  BoundedProcess {
    id: actionProcess
    timeoutMs: 20000
    maxOutChars: 8192
    maxErrChars: 8192
    property string _label: ""
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        var reason = timedOut ? "timed out" : (stderrText || stdoutText || "unknown error").trim()
        root.actionErrorMessage = "Could not " + actionProcess._label + ": " + reason.substring(0, 200)
      } else {
        root.actionErrorMessage = ""
      }
      root.refresh()
    }
  }

  BoundedProcess {
    id: logsProcess
    timeoutMs: 15000
    maxOutChars: 500000
    maxErrChars: 16384
    onFinished: {
      root.logsLoading = false
      if (!failedToSpawn && !timedOut && exitCode === 0) {
        var text = stdoutText || "(no output)"
        if (stdoutTruncated) text += "\n\n[output truncated]"
        root.logsText = text
      } else {
        var reason = timedOut ? "timed out" : (stderrText || stdoutText || "unknown error")
        root.logsText = "Could not read logs: " + reason
      }
    }
  }

  Component.onCompleted: pathResolver.start()
}
