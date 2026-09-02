// Docker engine spec: command builders + raw `docker ps` JSON -> normalized
// container mapping. Loaded two ways — QML `import "engines/docker.js" as
// DockerEngine`, and Node `require()` in tests — so it must stay plain JS
// with no QML-only syntax (`.pragma`/`.import`), and never import
// engines/shared.js directly: `shared` is passed in by the caller instead
// (see docs/superpowers/specs/2026-09-02-podman-integration-design.md).

var binaryName = "docker"
var binaryCandidates = ["/usr/bin/docker", "/usr/local/bin/docker"]
var needsAccessCheck = true // root-equivalent daemon socket; see ContainerEngine.qml

// ps/logs are piped through `head -c <byteCap>` so the byte cap is
// enforced by a real OS pipe at the source, not only after BoundedProcess
// has already buffered everything (see BoundedProcess.qml's header
// comment). This needs a shell for the pipe; binaryPath is our own
// validated candidate string, never external input, and id (logsCommand)
// must be pre-validated by the caller with shared.isValidContainerId —
// this file never validates it itself, since it has no access to `shared`.
function psCommand(binaryPath, byteCap) {
  return ["/bin/sh", "-c", binaryPath + " ps -a --no-trunc --format '{{json .}}' | /usr/bin/head -c " + String(byteCap)]
}

function logsCommand(binaryPath, id, tailLines, byteCap) {
  return ["/bin/sh", "-c", binaryPath + " logs --tail " + String(tailLines) + " --timestamps " + id + " | /usr/bin/head -c " + String(byteCap)]
}

// Plain argv, no shell — these don't need producer-side piping (their
// output is small and not attacker-length-controlled the way logs are).
function actionCommand(binaryPath, verb, id) {
  if (verb === "remove") return [binaryPath, "rm", "-f", id]
  return [binaryPath, verb, id]
}

// Used immediately before a destructive remove, to bind the command to a
// fresh daemon query instead of the polled list.
function inspectCommand(binaryPath, id) {
  return [binaryPath, "inspect", "--format", "{{.Id}} {{.State.Status}}", id]
}

function parsePorts(portsRaw) {
  var text = String(portsRaw || "").trim()
  if (!text) return []
  var tokens = text.split(",").slice(0, 64).map(function(t) { return t.trim() }).filter(function(t) { return t.length > 0 })
  var seen = {}
  var result = []
  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    var withHost = token.match(/^(?:\[?[0-9a-fA-F:.]*\]?:)?(\d+)->(\d+)\/(\w+)$/)
    var entry
    if (withHost) {
      entry = { hostPort: parseInt(withHost[1], 10), containerPort: parseInt(withHost[2], 10), protocol: withHost[3] }
    } else {
      var containerOnly = token.match(/^(\d+)\/(\w+)$/)
      if (!containerOnly) continue
      entry = { hostPort: null, containerPort: parseInt(containerOnly[1], 10), protocol: containerOnly[2] }
    }
    var key = entry.hostPort + ":" + entry.containerPort + ":" + entry.protocol
    if (seen[key]) continue
    seen[key] = true
    result.push(entry)
  }
  return result
}

function parseContainerLine(line, shared) {
  var text = String(line || "").trim()
  if (!text || text.length > shared.MAX_LINE_LEN) return null
  var raw
  try {
    raw = JSON.parse(text)
  } catch (e) {
    return null
  }
  var state = shared.clamp(String(raw.State || "").toLowerCase(), shared.MAX_FIELD_LEN)
  return {
    id: shared.clamp(raw.ID, shared.MAX_FIELD_LEN),
    name: shared.clamp(raw.Names, shared.MAX_FIELD_LEN),
    image: shared.clamp(raw.Image, shared.MAX_FIELD_LEN),
    state: state,
    statusText: shared.clamp(raw.Status, shared.MAX_FIELD_LEN),
    healthStatus: shared.clamp(raw.HealthStatus || "none", shared.MAX_FIELD_LEN),
    isRunning: state === "running",
    ports: parsePorts(raw.Ports),
    createdAt: shared.clamp(raw.CreatedAt, shared.MAX_FIELD_LEN)
  }
}

// Docker's `ps` prints one JSON object per line — split and parse each one.
// (Podman's array-form output needs a different framing; see engines/podman.js.)
function parseContainerList(rawStdout, shared) {
  var lines = String(rawStdout || "").split("\n")
  var containers = []
  for (var i = 0; i < lines.length && containers.length < shared.MAX_CONTAINERS; i++) {
    var parsed = parseContainerLine(lines[i], shared)
    if (parsed) containers.push(parsed)
  }
  return shared.sortContainers(containers)
}

function classifyError(available, stderrText) {
  if (!available) {
    return { kind: "not-installed", message: "Docker is not installed or not on PATH." }
  }
  var text = String(stderrText || "")
  var lowered = text.toLowerCase()
  if (lowered.indexOf("permission denied") !== -1) {
    return { kind: "permission-denied", message: "Permission denied. Add your user to the docker group and log back in." }
  }
  if (lowered.indexOf("cannot connect to the docker daemon") !== -1 || lowered.indexOf("is the docker daemon running") !== -1) {
    return { kind: "daemon-down", message: "Docker daemon is not running." }
  }
  var trimmed = text.replace(/\s+/g, " ").trim()
  return { kind: "unknown", message: trimmed.length > 0 ? trimmed.substring(0, 140) : "Could not read Docker status." }
}

if (typeof module !== "undefined") {
  module.exports = {
    binaryName: binaryName,
    binaryCandidates: binaryCandidates,
    needsAccessCheck: needsAccessCheck,
    psCommand: psCommand,
    logsCommand: logsCommand,
    actionCommand: actionCommand,
    inspectCommand: inspectCommand,
    parsePorts: parsePorts,
    parseContainerList: parseContainerList,
    classifyError: classifyError
  }
}
