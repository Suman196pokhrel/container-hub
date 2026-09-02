import QtQuick

// Fetches one container's log tail, with the same deadline/truncation
// every other subprocess in this plugin gets. Extracted out of
// ContainerEngine.qml for the same reason as ActionRunner.qml: a
// self-contained unit.
Item {
  id: root

  property string text: ""
  property string containerId: ""
  readonly property bool loading: process.running

  function fetch(command, id) {
    if (process.running) return
    root.containerId = id
    root.text = ""
    process.command = command
    process.start()
  }

  function clear() {
    root.containerId = ""
    root.text = ""
  }

  BoundedProcess {
    id: process
    timeoutMs: 15000
    maxOutChars: 500000
    maxErrChars: 16384
    onFinished: {
      if (!failedToSpawn && !timedOut && exitCode === 0) {
        var text = stdoutText || "(no output)"
        if (stdoutTruncated) text += "\n\n[output truncated]"
        root.text = text
      } else {
        var reason = timedOut ? "timed out" : (stderrText || stdoutText || "unknown error")
        root.text = "Could not read logs: " + reason
      }
    }
  }
}
