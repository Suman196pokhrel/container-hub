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

if (typeof module !== "undefined") {
  module.exports = {
    parsePorts: parsePorts,
    formatPortsDisplay: formatPortsDisplay
  }
}
