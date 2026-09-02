import QtQuick
import Quickshell
import Quickshell.Io

// A Process wrapper that enforces what the bare Quickshell.Io.Process does
// not: a hard wall-clock deadline (SIGTERM, then SIGKILL if it ignores
// that), delivered to the whole process group rather than one tracked pid,
// and a hard cap on how much stdout/stderr text is ever stored. Every
// Docker invocation in Service.qml goes through this instead of touching
// Process directly.
//
// Process-group kill: the inner command is wrapped in `setsid`, which (when
// the caller is not already a process-group leader — true here, verified
// live) execs in place rather than forking, so the tracked pid IS the new
// process group's id. Killing is then done by a short-lived `kill -SIG
// -<pid>` (negative pid = the whole group), not Process.signal() on the
// single tracked process — that reaches children the tracked process
// spawns too, not just the process itself. `setsid`/`kill` are invoked by
// hardcoded absolute path, matching Service.qml's binary validation: PATH
// is attacker-influenceable and this is a root-equivalent context.
//
// Caveat: Quickshell's public QML IO API (StdioCollector/SplitParser) has no
// byte-limited reader — it buffers internally until the process exits. For
// ps/logs (the two commands with attacker-influenceable output size),
// Service.qml pipes through a producer-side `head -c` limiter instead of
// relying on this cap alone, so THIS layer's cap is a backstop, not the
// primary defense, for those two. For action commands (stop/start/rm),
// whose output is inherently tiny, this cap is the only bound and that's
// sufficient.
Item {
  id: root

  property var command: []
  property bool running: false
  property int timeoutMs: 10000
  property int maxOutChars: 131072
  property int maxErrChars: 32768

  property string stdoutText: ""
  property string stderrText: ""
  property bool stdoutTruncated: false
  property bool stderrTruncated: false
  property bool timedOut: false
  property bool failedToSpawn: false
  property int exitCode: -1

  signal finished()

  function start() {
    if (proc.running) return
    root.stdoutText = ""
    root.stderrText = ""
    root.stdoutTruncated = false
    root.stderrTruncated = false
    root.timedOut = false
    root.failedToSpawn = false
    root.exitCode = -1
    proc._exited = false
    proc.command = ["/usr/bin/setsid"].concat(root.command)
    proc.running = true
    root.running = true
    watchdog.restart()
  }

  function _clip(text, maxChars) {
    return text.length > maxChars
      ? { text: text.substring(0, maxChars), truncated: true }
      : { text: text, truncated: false }
  }

  function _killGroup(signalName) {
    var pid = proc.processId
    if (!pid) return
    Quickshell.execDetached(["/usr/bin/kill", signalName, "-" + String(pid)])
  }

  Timer {
    id: watchdog
    interval: root.timeoutMs
    repeat: false
    onTriggered: {
      if (!proc.running) return
      root.timedOut = true
      root._killGroup("-TERM")
      killTimer.restart()
    }
  }

  Timer {
    id: killTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (proc.running) root._killGroup("-KILL")
    }
  }

  Process {
    id: proc
    running: false
    property bool _exited: false
    stdout: StdioCollector { id: outCol; waitForEnd: true }
    stderr: StdioCollector { id: errCol; waitForEnd: true }

    onExited: function(exitCode) {
      proc._exited = true
      watchdog.stop()
      killTimer.stop()
      var outClip = root._clip(outCol.text || "", root.maxOutChars)
      var errClip = root._clip(errCol.text || "", root.maxErrChars)
      root.stdoutText = outClip.text
      root.stdoutTruncated = outClip.truncated
      root.stderrText = errClip.text
      root.stderrTruncated = errClip.truncated
      root.exitCode = exitCode
      root.running = false
      root.finished()
    }
    onRunningChanged: {
      if (!running && !proc._exited) {
        // Same "never spawned" case Service.qml worked around before:
        // runningChanged fires with no exited signal when the command
        // itself can't start.
        watchdog.stop()
        killTimer.stop()
        root.failedToSpawn = true
        root.running = false
        root.finished()
      }
    }
  }

  Component.onDestruction: {
    watchdog.stop()
    killTimer.stop()
    if (proc.running) root._killGroup("-KILL")
  }
}
