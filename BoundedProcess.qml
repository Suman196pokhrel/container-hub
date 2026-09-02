import QtQuick
import Quickshell.Io

// A Process wrapper that enforces what the bare Quickshell.Io.Process does
// not: a hard wall-clock deadline (SIGTERM, then SIGKILL if it ignores that)
// and a hard cap on how much stdout/stderr text is ever stored. Every Docker
// invocation in Service.qml goes through this instead of touching Process
// directly.
//
// Caveat: Quickshell's public QML IO API (StdioCollector/SplitParser) has no
// byte-limited reader — it buffers internally until the process exits. The
// cap here truncates what we keep once the process ends; it bounds storage
// and, via the deadline, bounds *time*, but it cannot cap peak memory during
// a run that writes one enormous unterminated line inside the deadline
// window. That's a Quickshell IO-layer limitation, not something reachable
// from this QML layer.
Item {
  id: root

  property alias command: proc.command
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
    proc.running = true
    root.running = true
    watchdog.restart()
  }

  function _clip(text, maxChars) {
    return text.length > maxChars
      ? { text: text.substring(0, maxChars), truncated: true }
      : { text: text, truncated: false }
  }

  Timer {
    id: watchdog
    interval: root.timeoutMs
    repeat: false
    onTriggered: {
      if (!proc.running) return
      root.timedOut = true
      proc.signal(15)
      killTimer.restart()
    }
  }

  Timer {
    id: killTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (proc.running) proc.signal(9)
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
    if (proc.running) proc.signal(9)
  }
}
