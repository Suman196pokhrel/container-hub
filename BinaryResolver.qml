import QtQuick

// Resolves a binary off PATH once, then validates the resolved path is a
// root-owned, non-group/other-writable regular file before it is ever
// used — extracted from the Docker-only version of this logic so both
// engines share it. PATH is attacker-influenceable, so re-resolving on
// every call instead of caching the validated absolute path would be a
// TOCTOU gap.
Item {
  id: root

  property string binaryName: ""
  property int timeoutMs: 5000

  signal resolved(string path)
  signal failed(string reason) // "not-found", or a human message for an unsafe binary

  function resolveAndValidate() {
    which.command = ["which", root.binaryName]
    which.start()
  }

  BoundedProcess {
    id: which
    timeoutMs: root.timeoutMs
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        root.failed("not-found")
        return
      }
      var candidate = (stdoutText.split("\n")[0] || "").trim()
      if (candidate === "" || candidate.charAt(0) !== "/") {
        root.failed("not-found")
        return
      }
      validator._candidate = candidate
      validator.command = ["stat", "-L", "-c", "%F|%u|%a", candidate]
      validator.start()
    }
  }

  BoundedProcess {
    id: validator
    timeoutMs: root.timeoutMs
    property string _candidate: ""
    onFinished: {
      if (failedToSpawn || timedOut || exitCode !== 0) {
        root.failed("Could not verify the " + root.binaryName + " binary at " + validator._candidate + ".")
        return
      }
      var parts = stdoutText.trim().split("|")
      var kind = parts[0] || ""
      var uid = parts[1] || ""
      var mode = parseInt(parts[2] || "0", 8)
      var ownedByRoot = uid === "0"
      var notGroupOrOtherWritable = (mode & 0o022) === 0
      if (kind !== "regular file" || !ownedByRoot || !notGroupOrOtherWritable) {
        root.failed(root.binaryName + " binary at " + validator._candidate + " failed a safety check (expected a root-owned, non-writable regular file).")
        return
      }
      root.resolved(validator._candidate)
    }
  }
}
