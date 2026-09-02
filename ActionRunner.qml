import QtQuick

// Runs one start/stop/remove command at a time, with the same deadline and
// failure-surfacing every other subprocess in this plugin gets, extracted
// out of ContainerEngine.qml since "run one action, report the result" is
// a self-contained unit.
Item {
  id: root

  readonly property bool running: process.running
  readonly property bool checking: preCheck.running
  property string errorMessage: ""

  signal finished()

  function run(command, label) {
    if (process.running) {
      // A prior action (e.g. "stop", which can hold the process for a full
      // 10s grace period) is still in flight. Say so instead of silently
      // dropping this one — the old behavior looked like a missed click.
      root.errorMessage = "Another action is still running; try again in a moment."
      return
    }
    root.errorMessage = ""
    process._label = label
    process.command = command
    process.start()
  }

  // Fresh existence check ahead of a destructive command, binding it to
  // the daemon's current state instead of a possibly-stale cached list.
  // `callback(exists)` — an inspect failure (non-zero exit, timeout, or an
  // id in the output that doesn't match) all collapse to "gone", since
  // there is nothing sensible to do differently for any of those cases.
  function checkExists(command, expectedId, callback) {
    if (preCheck.running) { callback(false); return }
    preCheck._expectedId = expectedId
    preCheck._callback = callback
    preCheck.command = command
    preCheck.start()
  }

  BoundedProcess {
    id: process
    timeoutMs: 20000
    maxOutChars: 8192
    maxErrChars: 8192
    property string _label: ""
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        var reason = timedOut ? "timed out" : (stderrText || stdoutText || "unknown error").trim()
        root.errorMessage = "Could not " + process._label + ": " + reason.substring(0, 200)
      } else {
        root.errorMessage = ""
      }
      root.finished()
    }
  }

  BoundedProcess {
    id: preCheck
    timeoutMs: 10000
    maxOutChars: 4096
    maxErrChars: 4096
    property string _expectedId: ""
    property var _callback: null
    onFinished: {
      var cb = preCheck._callback
      preCheck._callback = null
      if (!cb) return
      if (failedToSpawn || timedOut || exitCode !== 0) { cb(false); return }
      var confirmedId = (stdoutText.trim().split(/\s+/)[0] || "").toLowerCase()
      cb(confirmedId === preCheck._expectedId.toLowerCase())
    }
  }
}
