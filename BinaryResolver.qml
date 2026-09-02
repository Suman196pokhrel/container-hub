import QtQuick

// Resolves a binary from a fixed list of trusted absolute candidate paths
// — never PATH/`which`, which is itself attacker-influenceable and was
// the exact gap in the previous version of this check. Validates the
// ENTIRE path chain (every directory component plus the final target) is
// root-owned and not group/other-writable, via one `namei -l` call — also
// invoked by hardcoded absolute path, so the validator tool itself can't
// be fooled by a hijacked PATH. The validated (device, inode) pair is
// cached and re-checked via recheck() immediately before every subsequent
// exec, not just once at startup: the file could otherwise be replaced
// between validation and use (TOCTOU) even though the path string stays
// the same.
Item {
  id: root

  property var candidatePaths: []
  property int timeoutMs: 5000

  property string validatedPath: ""
  property string validatedDevIno: ""
  // A caller must check this before calling recheck() again: a second
  // call while one is already in flight would overwrite _recheck's
  // pending callback and silently drop the first caller's.
  readonly property bool busy: _namei.running || _commit.running || _recheck.running

  signal resolved(string path)
  signal failed(string reason) // "not-found", or a human message for an unsafe binary

  function resolveAndValidate() {
    root.validatedPath = ""
    root.validatedDevIno = ""
    _tryCandidate(0)
  }

  // Call immediately before every exec of the resolved binary. `callback`
  // is invoked with true/false — never assume success, always wait for it.
  function recheck(callback) {
    if (root.validatedPath === "" || _recheck.running) { callback(false); return }
    _recheck._pending = callback
    _recheck.command = ["/usr/bin/stat", "-L", "-c", "%d:%i", root.validatedPath]
    _recheck.start()
  }

  function _tryCandidate(index) {
    if (index >= root.candidatePaths.length) {
      root.failed("not-found")
      return
    }
    _namei._index = index
    _namei.command = ["/usr/bin/namei", "-l", root.candidatePaths[index]]
    _namei.start()
  }

  // namei -l prints one line per path component (dirs, then the final
  // target), each "<mode> <owner> <group> <name>". Every component must
  // be owned by root and not group/other-writable — a validated file is
  // only trustworthy if nothing upstream in its path could redirect it.
  function _chainIsSafe(nameiOutput) {
    var lines = nameiOutput.split("\n").slice(1) // drop the "f: <path>" query line
    var sawFile = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      var parts = line.split(/\s+/)
      if (parts.length < 4) return false
      var mode = parts[0]
      var owner = parts[1]
      if (owner !== "root") return false
      if (mode.charAt(5) === "w" || mode.charAt(8) === "w") return false // group/other write
      if (mode.charAt(0) === "-") sawFile = true
    }
    return sawFile
  }

  BoundedProcess {
    id: _namei
    timeoutMs: root.timeoutMs
    property int _index: 0
    onFinished: {
      var candidate = root.candidatePaths[_namei._index]
      if (!failedToSpawn && !timedOut && exitCode === 0 && root._chainIsSafe(stdoutText)) {
        _commit._candidate = candidate
        _commit.command = ["/usr/bin/stat", "-L", "-c", "%d:%i", candidate]
        _commit.start()
      } else {
        root._tryCandidate(_namei._index + 1)
      }
    }
  }

  BoundedProcess {
    id: _commit
    timeoutMs: root.timeoutMs
    property string _candidate: ""
    onFinished: {
      var devIno = stdoutText.trim()
      if (!failedToSpawn && !timedOut && exitCode === 0 && devIno !== "") {
        root.validatedPath = _commit._candidate
        root.validatedDevIno = devIno
        root.resolved(_commit._candidate)
      } else {
        // namei approved this candidate but the immediate follow-up stat
        // failed (e.g. removed between the two calls) — fail closed
        // rather than looping back through the candidate list, which
        // could cycle if a candidate flaps between the two checks.
        root.failed("Could not verify " + _commit._candidate + ".")
      }
    }
  }

  BoundedProcess {
    id: _recheck
    timeoutMs: root.timeoutMs
    property var _pending: null
    onFinished: {
      var ok = !failedToSpawn && !timedOut && exitCode === 0 && stdoutText.trim() === root.validatedDevIno
      var cb = _recheck._pending
      _recheck._pending = null
      if (cb) cb(ok)
    }
  }
}
