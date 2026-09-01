function parsePorts(portsRaw) {
  var text = String(portsRaw || "").trim()
  if (!text) return []
  var tokens = text.split(",").map(function(t) { return t.trim() }).filter(function(t) { return t.length > 0 })
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

function formatPortsDisplay(ports) {
  if (!ports || ports.length === 0) return ""
  return ports.map(function(p) {
    return p.hostPort === null ? String(p.containerPort) : (p.hostPort + "→" + p.containerPort)
  }).join(", ")
}

function parseContainerLine(line) {
  var text = String(line || "").trim()
  if (!text) return null
  var raw
  try {
    raw = JSON.parse(text)
  } catch (e) {
    return null
  }
  var state = String(raw.State || "").toLowerCase()
  return {
    id: String(raw.ID || ""),
    name: String(raw.Names || ""),
    image: String(raw.Image || ""),
    state: state,
    statusText: String(raw.Status || ""),
    healthStatus: String(raw.HealthStatus || "none"),
    isRunning: state === "running",
    ports: parsePorts(raw.Ports),
    createdAt: String(raw.CreatedAt || "")
  }
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

function parseContainerList(rawStdout) {
  var lines = String(rawStdout || "").split("\n")
  var containers = []
  for (var i = 0; i < lines.length; i++) {
    var parsed = parseContainerLine(lines[i])
    if (parsed) containers.push(parsed)
  }
  return sortContainers(containers)
}

function statusColorFor(container) {
  if (!container) return "stopped"
  if (container.isRunning && container.healthStatus === "unhealthy") return "unhealthy"
  if (container.isRunning) return "running"
  return "stopped"
}

function classifyDockerError(dockerAvailable, stderrText) {
  if (!dockerAvailable) {
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
    parsePorts: parsePorts,
    formatPortsDisplay: formatPortsDisplay,
    parseContainerLine: parseContainerLine,
    sortContainers: sortContainers,
    parseContainerList: parseContainerList,
    statusColorFor: statusColorFor,
    classifyDockerError: classifyDockerError
  }
}
