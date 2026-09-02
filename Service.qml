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

  // A byte cap enforced by the producer (docker itself, piped through
  // `head -c`), not just by BoundedProcess after the fact — see the "ps"
  // and "logs" commands below and BoundedProcess.qml's header comment.
  readonly property int producerByteCap: 600000

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
    // dockerPath is only set once the resolved binary has passed
    // validation (see resolver below); before that, or if validation ever
    // failed, there is nothing safe to run yet.
    if (root.dockerPath === "") return
    if (sudoCheck.running || psProcess.running || resolver.busy) return
    root.loading = true
    // Revalidated immediately before use, not just once at startup: the
    // file at dockerPath could have been replaced since the last check.
    resolver.recheck(function(ok) {
      if (!ok) {
        root._handleBinaryChanged()
        return
      }
      sudoCheck.start()
    })
  }

  function _handleBinaryChanged() {
    root.dockerPath = ""
    root.dockerAvailable = false
    root.loading = false
    root.errorKind = "unsafe-binary"
    root.errorMessage = "The Docker binary changed since it was last validated; re-checking."
    resolver.resolveAndValidate()
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
    if (root.dockerPath === "" || logsProcess.running || resolver.busy) return
    if (!Model.isValidContainerId(id)) {
      root.logsText = "Could not read logs: invalid container id."
      return
    }
    root.logsLoading = true
    root.logsContainerId = id
    root.logsText = ""
    resolver.recheck(function(ok) {
      if (!ok) {
        root.logsLoading = false
        root.logsText = "Could not read logs: Docker binary failed revalidation."
        root._handleBinaryChanged()
        return
      }
      // Piped through `head -c` so the byte cap is enforced by the
      // producer side (a real OS pipe), not only after full buffering —
      // id is regex-validated above before ever reaching this shell
      // string, and dockerPath/logTailLines are our own
      // validated/clamped values, never raw user text.
      var shellCmd = root.dockerPath + " logs --tail " + String(root.logTailLines) +
        " --timestamps " + id + " | /usr/bin/head -c " + String(root.producerByteCap)
      logsProcess.command = ["/bin/sh", "-c", shellCmd]
      logsProcess.start()
    })
  }

  function clearLogs() {
    root.logsContainerId = ""
    root.logsText = ""
  }

  function stopContainer(id) { runAction([root.dockerPath, "stop", id], "stop container") }
  function startContainer(id) { runAction([root.dockerPath, "start", id], "start container") }

  function removeContainer(id) {
    if (root.dockerPath === "") return
    if (!Model.isValidContainerId(id)) {
      root.actionErrorMessage = "Could not remove container: invalid id."
      return
    }
    if (actionProcess.running || preRemoveCheck.running) {
      root.actionErrorMessage = "Another action is still running; try again in a moment."
      return
    }
    root.actionErrorMessage = ""
    // Bind the destructive command to a fresh daemon query, not the
    // (possibly several-seconds-stale) cached poll list: confirm this
    // exact full id still exists right before firing rm -f.
    preRemoveCheck._pendingId = id
    preRemoveCheck.command = [root.dockerPath, "inspect", "--format", "{{.Id}}", id]
    preRemoveCheck.start()
  }

  function runAction(command, label) {
    if (root.dockerPath === "") return
    if (actionProcess.running) {
      // A prior action (e.g. "stop", which can hold the process for a full
      // 10s grace period) is still in flight. Say so instead of silently
      // dropping this one — the old behavior looked like a missed click.
      root.actionErrorMessage = "Another action is still running; try again in a moment."
      return
    }
    if (resolver.busy) {
      root.actionErrorMessage = "Try again in a moment."
      return
    }
    root.actionErrorMessage = ""
    resolver.recheck(function(ok) {
      if (!ok) {
        root.actionErrorMessage = "Could not " + label + ": Docker binary failed revalidation."
        root._handleBinaryChanged()
        return
      }
      actionProcess._label = label
      actionProcess.command = command
      actionProcess.start()
    })
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

  // Resolves "docker" from a fixed list of trusted absolute paths (never
  // PATH/`which`) and validates the whole path chain before first use —
  // see BinaryResolver.qml. Every later invocation uses this literal
  // path, and every invocation revalidates it first (see refresh()/
  // fetchLogs()/runAction() above), since PATH is attacker-influenceable
  // and this is a root-equivalent context.
  BinaryResolver {
    id: resolver
    candidatePaths: ["/usr/bin/docker", "/usr/local/bin/docker"]
    onResolved: function(path) {
      root.dockerPath = path
      root.dockerAvailable = true
      root.refresh()
    }
    onFailed: function(reason) {
      root.dockerAvailable = false
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
      // --no-trunc: full ids throughout, never a truncated one passed to
      // a later destructive command. Piped through `head -c` so a
      // pathological container list (or one absurdly long field) is
      // capped at the source, not just after full buffering.
      var shellCmd = root.dockerPath + " ps -a --no-trunc --format '{{json .}}' | /usr/bin/head -c " + String(root.producerByteCap)
      psProcess.command = ["/bin/sh", "-c", shellCmd]
      psProcess.start()
    }
  }

  BoundedProcess {
    id: psProcess
    timeoutMs: 10000
    maxOutChars: 700000
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
    id: preRemoveCheck
    timeoutMs: 10000
    maxOutChars: 4096
    maxErrChars: 4096
    property string _pendingId: ""
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        // `docker inspect` fails non-zero when the container is gone —
        // that's the signal, not an error to surface as one.
        root.actionErrorMessage = "Container is already gone; nothing removed."
        root.refresh()
        return
      }
      var confirmedId = stdoutText.trim().toLowerCase()
      if (confirmedId.indexOf(preRemoveCheck._pendingId.toLowerCase()) !== 0) {
        root.actionErrorMessage = "Could not remove container: identity mismatch on revalidation."
        return
      }
      root.runAction([root.dockerPath, "rm", "-f", preRemoveCheck._pendingId], "remove container")
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
    maxOutChars: 700000
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

  Component.onCompleted: resolver.resolveAndValidate()
}
