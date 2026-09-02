import QtQuick

// Runs one start/stop/remove command at a time, with the same deadline and
// failure-surfacing every other subprocess in this plugin gets, extracted
// out of ContainerEngine.qml since "run one action, report the result" is
// a self-contained unit.
Item {
  id: root

  readonly property bool running: process.running
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
}
