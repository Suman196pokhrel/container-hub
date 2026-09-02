// Podman engine spec — same shape as engines/docker.js, but Podman's `ps`
// JSON is genuinely different (confirmed live against podman 6.1.0; see
// docs/superpowers/specs/2026-09-02-podman-integration-design.md):
//   - Only the top-level `--format json` (whole-array) flag populates
//     Status; the per-row `{{json .}}` template Docker uses leaves it
//     empty. That means the *entire* stdout is one JSON array, not one
//     JSON object per line, so parseContainerList here does a single
//     JSON.parse instead of Docker's newline-split loop.
//   - Id is already the full 64-char hash by default (unlike Docker,
//     which truncates unless told not to), Names is an array, and Ports
//     is already structured objects instead of a comma-joined string
//     needing regex.
// Podman here is rootless: no daemon socket, so no docker-group-style
// access check is needed (needsAccessCheck: false).

var binaryName = "podman"
var binaryCandidates = ["/usr/bin/podman", "/usr/local/bin/podman"]
var needsAccessCheck = false

// Piped through `head -c <byteCap>` for the same reason as Docker's (see
// engines/docker.js): the byte cap needs to be enforced by the producer,
// not only after BoundedProcess has already buffered everything.
function psCommand(binaryPath, byteCap) {
  return ["/bin/sh", "-c", binaryPath + " ps -a --no-trunc --format json | /usr/bin/head -c " + String(byteCap)]
}

function logsCommand(binaryPath, id, tailLines, byteCap) {
  return ["/bin/sh", "-c", binaryPath + " logs --tail " + String(tailLines) + " --timestamps " + id + " | /usr/bin/head -c " + String(byteCap)]
}

function actionCommand(binaryPath, verb, id) {
  if (verb === "remove") return [binaryPath, "rm", "-f", id]
  return [binaryPath, verb, id]
}

function inspectCommand(binaryPath, id) {
  return [binaryPath, "inspect", "--format", "{{.Id}} {{.State.Status}}", id]
}

// Already structured (unlike Docker's string form), so just dedupe + cap.
function mapPorts(rawPorts, shared) {
  var list = (rawPorts || []).slice(0, shared.MAX_PORTS)
  var seen = {}
  var result = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var entry = { hostPort: p.host_port || null, containerPort: p.container_port || 0, protocol: p.protocol || "tcp" }
    var key = entry.hostPort + ":" + entry.containerPort + ":" + entry.protocol
    if (seen[key]) continue
    seen[key] = true
    result.push(entry)
  }
  return result
}

function mapContainer(raw, shared) {
  var state = shared.clamp(String(raw.State || "").toLowerCase(), shared.MAX_FIELD_LEN)
  var names = raw.Names || []
  return {
    // Full id, not truncated — a previously-truncated id was the exact
    // thing flagged as eligible to reach a destructive rm -f.
    id: shared.clamp(String(raw.Id || ""), shared.MAX_FIELD_LEN),
    name: shared.clamp(names[0] || "", shared.MAX_FIELD_LEN),
    image: shared.clamp(raw.Image, shared.MAX_FIELD_LEN),
    state: state,
    statusText: shared.clamp(raw.Status, shared.MAX_FIELD_LEN),
    healthStatus: "none", // not exposed by `podman ps`; would need a per-container `inspect` call
    isRunning: state === "running",
    ports: mapPorts(raw.Ports, shared),
    createdAt: shared.clamp(raw.CreatedAt, shared.MAX_FIELD_LEN)
  }
}

function parseContainerList(rawStdout, shared) {
  var text = String(rawStdout || "").trim()
  if (!text) return []
  var raw
  try {
    raw = JSON.parse(text)
  } catch (e) {
    return []
  }
  if (!Array.isArray(raw)) return []
  var containers = []
  for (var i = 0; i < raw.length && containers.length < shared.MAX_CONTAINERS; i++) {
    containers.push(mapContainer(raw[i], shared))
  }
  return shared.sortContainers(containers)
}

function classifyError(available, stderrText) {
  if (!available) {
    return { kind: "not-installed", message: "Podman is not installed or not on PATH." }
  }
  var text = String(stderrText || "")
  var lowered = text.toLowerCase()
  if (lowered.indexOf("permission denied") !== -1) {
    return { kind: "permission-denied", message: "Permission denied running Podman." }
  }
  var trimmed = text.replace(/\s+/g, " ").trim()
  return { kind: "unknown", message: trimmed.length > 0 ? trimmed.substring(0, 140) : "Could not read Podman status." }
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
    parseContainerList: parseContainerList,
    classifyError: classifyError
  }
}
