// Helpers shared by every engine module (engines/docker.js, engines/podman.js).
// Engine-specific parsing (raw JSON -> normalized container) stays in each
// engine's own file since the raw shapes differ; only what operates on the
// already-normalized shape lives here.

// Defense-in-depth caps on top of the bounded process reader in
// ContainerEngine.qml: a container's name/image/status/ports are
// attacker-influenced (an image tag, a container name, log-adjacent status
// text) and get stored + rendered, so each field is clamped independently
// of whatever byte budget the reader enforced upstream.
var MAX_FIELD_LEN = 256
var MAX_PORTS = 64
var MAX_CONTAINERS = 500
var MAX_LINE_LEN = 65536

function clamp(value, maxLen) {
  var text = String(value || "")
  return text.length > maxLen ? text.substring(0, maxLen) : text
}

function sortContainers(containers) {
  var list = (containers || []).slice()
  list.sort(function(a, b) {
    if (a.isRunning !== b.isRunning) return a.isRunning ? -1 : 1
    var an = String(a.name || "").toLowerCase()
    var bn = String(b.name || "").toLowerCase()
    if (an < bn) return -1
    if (an > bn) return 1
    return 0
  })
  return list
}

function formatPortsDisplay(ports) {
  if (!ports || ports.length === 0) return ""
  return ports.map(function(p) {
    return p.hostPort === null ? String(p.containerPort) : (p.hostPort + "→" + p.containerPort)
  }).join(", ")
}

function statusColorFor(container) {
  if (!container) return "stopped"
  if (container.isRunning && container.healthStatus === "unhealthy") return "unhealthy"
  if (container.isRunning) return "running"
  return "stopped"
}

if (typeof module !== "undefined") {
  module.exports = {
    clamp: clamp,
    sortContainers: sortContainers,
    formatPortsDisplay: formatPortsDisplay,
    statusColorFor: statusColorFor,
    MAX_FIELD_LEN: MAX_FIELD_LEN,
    MAX_PORTS: MAX_PORTS,
    MAX_CONTAINERS: MAX_CONTAINERS,
    MAX_LINE_LEN: MAX_LINE_LEN
  }
}
