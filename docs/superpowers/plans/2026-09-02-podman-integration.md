# Podman Engine Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Podman as a second container engine with feature parity to Docker (list, start, stop, remove, logs), sharing the polling/timeout/backoff machinery instead of duplicating it, with zero UI changes this phase.

**Architecture:** Extract a generic `ContainerEngine.qml` (replaces `Service.qml`) parameterized by an engine-name property; it delegates everything engine-specific — binary name, command building, JSON parsing, error classification — to a pair of plain-JS modules, `engines/docker.js` and `engines/podman.js`, that share small common helpers via `engines/shared.js`. Path resolution/validation is extracted into a reusable `BinaryResolver.qml`.

**Tech Stack:** QML (Quickshell.Io `Process`), plain JS modules dual-loaded by QML `import` and Node `require()` (existing `Model.js` pattern), `node --test`.

**Spec:** `docs/superpowers/specs/2026-09-02-podman-integration-design.md`

## Global Constraints

- No UI changes: `Panel.qml` gets exactly one mechanical edit (component rename); no Podman UI element, no manifest/README changes.
- Every file created or rewritten in this plan targets ≤ ~200 lines.
- `engines/docker.js` and `engines/podman.js` must each be loadable two ways: `import "engines/docker.js" as X` from QML, and `require('../engines/docker.js')` from Node tests — confirmed empirically that `.pragma library`/`.import` (needed for JS-file-importing-JS-file) breaks Node's `require()`, so cross-file sharing between these engine modules and `engines/shared.js` is done by **passing `Shared` in as an explicit function argument**, never a file-level import between the two `.js` files.
- Podman's `ps` must use `--format json` (top-level array flag), not `--format '{{json .}}'` — confirmed live that only the array form populates `Status`. Its `parseContainerList` therefore does one `JSON.parse` of the whole stdout, not a newline-split loop.
- Action command timeouts stay as already tuned for Docker (20s actions / 10s ps / 15s logs / 5s path resolution) — confirmed live that Podman's `stop` has the same 10s SIGTERM-then-SIGKILL grace period, no engine-specific tuning needed.
- Podman spec: `needsAccessCheck: false` (rootless, no daemon-socket privilege boundary); `healthStatus` always `"none"` (not available from `podman ps`).

---

### Task 1: `engines/shared.js` — extract engine-agnostic helpers

**Files:**
- Create: `engines/shared.js`
- Test: `tests/shared.test.js`

**Interfaces:**
- Produces (used by Tasks 2, 3, 5): `clamp(value, maxLen)`, `sortContainers(containers)`, `formatPortsDisplay(ports)`, `statusColorFor(container)`, and constants `MAX_FIELD_LEN=256`, `MAX_PORTS=64`, `MAX_CONTAINERS=500`, `MAX_LINE_LEN=65536`. All exported via `if (typeof module !== "undefined") module.exports = {...}` (same dual-use guard `Model.js` already uses).

- [ ] **Step 1: Write the failing test**

`tests/shared.test.js`:
```js
const test = require('node:test')
const assert = require('node:assert/strict')
const Shared = require('../engines/shared.js')

test('clamp truncates to maxLen', () => {
  assert.equal(Shared.clamp('x'.repeat(300), Shared.MAX_FIELD_LEN).length, Shared.MAX_FIELD_LEN)
})

test('clamp treats null/undefined as empty string', () => {
  assert.equal(Shared.clamp(null, 10), '')
})

test('sortContainers puts running first, then sorts by name', () => {
  const containers = [
    { name: 'zeta', isRunning: false },
    { name: 'alpha', isRunning: true },
    { name: 'beta', isRunning: true }
  ]
  assert.deepEqual(Shared.sortContainers(containers).map(c => c.name), ['alpha', 'beta', 'zeta'])
})

test('formatPortsDisplay renders host arrows and bare container ports', () => {
  const ports = [
    { hostPort: null, containerPort: 443, protocol: 'tcp' },
    { hostPort: 5050, containerPort: 80, protocol: 'tcp' }
  ]
  assert.equal(Shared.formatPortsDisplay(ports), '443, 5050→80')
})

test('statusColorFor classifies running, unhealthy, and stopped containers', () => {
  assert.equal(Shared.statusColorFor({ isRunning: true, healthStatus: 'none' }), 'running')
  assert.equal(Shared.statusColorFor({ isRunning: true, healthStatus: 'unhealthy' }), 'unhealthy')
  assert.equal(Shared.statusColorFor({ isRunning: false, healthStatus: 'none' }), 'stopped')
  assert.equal(Shared.statusColorFor(null), 'stopped')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/shared.test.js`
Expected: FAIL — `Cannot find module '../engines/shared.js'`

- [ ] **Step 3: Write `engines/shared.js`**

Copy `MAX_FIELD_LEN`/`MAX_PORTS`/`MAX_CONTAINERS`/`MAX_LINE_LEN`/`clamp`/`sortContainers`/`formatPortsDisplay`/`statusColorFor` verbatim from today's `Model.js` (lines 1–14, 41–46, 71–82, 94–99). Drop `parsePorts`, `parseContainerLine`, `parseContainerList`, `classifyDockerError` — those move into `engines/docker.js` (Task 2), since they're Docker-shaped (string ports, Docker's stderr vocabulary). Keep the same `module.exports` guard pattern at the bottom, exporting all four functions plus the four constants.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/shared.test.js`
Expected: PASS, 5/5

- [ ] **Step 5: Commit**

```bash
git add engines/shared.js tests/shared.test.js
git commit -m "Extract engine-agnostic helpers into engines/shared.js"
```

---

### Task 2: `engines/docker.js` — Docker engine spec module

**Files:**
- Create: `engines/docker.js`
- Test: `tests/docker.test.js` (replaces `tests/model.test.js`)

**Interfaces:**
- Consumes: `engines/shared.js`'s exports, passed in as a parameter (never `require`d or `.import`ed from within this file — see Global Constraints).
- Produces (used by Task 5): `binaryName` ("docker"), `needsAccessCheck` (true), `psCommand(binaryPath)`, `logsCommand(binaryPath, id, tailLines)`, `actionCommand(binaryPath, verb, id)` (verb: `"stop"|"start"|"remove"`), `parseContainerList(rawStdout, shared)`, `classifyError(available, stderrText)`.

- [ ] **Step 1: Write the failing test**

`tests/docker.test.js` (start from today's `tests/model.test.js`, adapt names):
```js
const test = require('node:test')
const assert = require('node:assert/strict')
const Shared = require('../engines/shared.js')
const Docker = require('../engines/docker.js')

test('psCommand builds the argv for listing', () => {
  assert.deepEqual(Docker.psCommand('/usr/bin/docker'), ['/usr/bin/docker', 'ps', '-a', '--format', '{{json .}}'])
})

test('logsCommand builds the argv for tailing logs', () => {
  assert.deepEqual(Docker.logsCommand('/usr/bin/docker', 'abc123', 200), ['/usr/bin/docker', 'logs', '--tail', '200', '--timestamps', 'abc123'])
})

test('actionCommand maps verbs to the right flags', () => {
  assert.deepEqual(Docker.actionCommand('/usr/bin/docker', 'stop', 'abc123'), ['/usr/bin/docker', 'stop', 'abc123'])
  assert.deepEqual(Docker.actionCommand('/usr/bin/docker', 'start', 'abc123'), ['/usr/bin/docker', 'start', 'abc123'])
  assert.deepEqual(Docker.actionCommand('/usr/bin/docker', 'remove', 'abc123'), ['/usr/bin/docker', 'rm', '-f', 'abc123'])
})

test('parseContainerList parses ps JSON lines and clamps fields', () => {
  const running = JSON.stringify({ ID: '1', Image: 'x', Names: 'zzz-running', State: 'running', Status: 'Up', HealthStatus: 'none', Ports: '0.0.0.0:5050->80/tcp', CreatedAt: '' })
  const stopped = JSON.stringify({ ID: '2', Image: 'x', Names: 'aaa-stopped', State: 'exited', Status: 'Exited', HealthStatus: 'none', Ports: '', CreatedAt: '' })
  const list = Docker.parseContainerList(running + '\n' + stopped + '\n', Shared)
  assert.equal(list.length, 2)
  assert.equal(list[0].name, 'zzz-running')
  assert.equal(list[0].ports.length, 1)
  assert.equal(list[1].name, 'aaa-stopped')
})

test('parseContainerList clamps oversized fields', () => {
  const huge = 'x'.repeat(Shared.MAX_FIELD_LEN + 5000)
  const line = JSON.stringify({ ID: '1', Image: huge, Names: huge, State: 'running', Status: huge, HealthStatus: 'none', Ports: '', CreatedAt: '' })
  const result = Docker.parseContainerList(line, Shared)[0]
  assert.equal(result.image.length, Shared.MAX_FIELD_LEN)
  assert.equal(result.name.length, Shared.MAX_FIELD_LEN)
})

test('parseContainerList caps the number of containers', () => {
  const lines = Array.from({ length: Shared.MAX_CONTAINERS + 50 }, (_, i) =>
    JSON.stringify({ ID: String(i), Image: 'x', Names: 'c' + i, State: 'running', Status: 'Up', HealthStatus: 'none', Ports: '', CreatedAt: '' })
  ).join('\n')
  assert.equal(Docker.parseContainerList(lines, Shared).length, Shared.MAX_CONTAINERS)
})

test('classifyError reports not-installed when the binary is missing', () => {
  assert.equal(Docker.classifyError(false, '').kind, 'not-installed')
})

test('classifyError reports permission-denied', () => {
  assert.equal(Docker.classifyError(true, 'permission denied while trying to connect to the Docker daemon socket').kind, 'permission-denied')
})

test('classifyError reports daemon-down', () => {
  assert.equal(Docker.classifyError(true, 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?').kind, 'daemon-down')
})

test('classifyError falls back to unknown, truncated', () => {
  const result = Docker.classifyError(true, 'some other failure')
  assert.equal(result.kind, 'unknown')
  assert.equal(result.message, 'some other failure')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/docker.test.js`
Expected: FAIL — `Cannot find module '../engines/docker.js'`

- [ ] **Step 3: Write `engines/docker.js`**

Move `parsePorts` and (renamed) `classifyDockerError` → `classifyError` verbatim from `Model.js`. `parseContainerLine` becomes a private (non-exported) helper taking `shared` as a second parameter, using `shared.clamp`/`shared.MAX_FIELD_LEN`/`shared.MAX_LINE_LEN` in place of the old bare references. `parseContainerList(rawStdout, shared)` keeps the same newline-split loop, capping at `shared.MAX_CONTAINERS`, sorting via `shared.sortContainers`. Add the three command builders and `binaryName`/`needsAccessCheck` constants. Export everything through the same `module.exports` guard.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/docker.test.js`
Expected: PASS, all cases

- [ ] **Step 5: Commit**

```bash
git add engines/docker.js tests/docker.test.js
git commit -m "Add engines/docker.js: Docker engine spec module"
```

---

### Task 3: `engines/podman.js` — Podman engine spec module

**Files:**
- Create: `engines/podman.js`
- Test: `tests/podman.test.js`

**Interfaces:** same shape as Task 2's `engines/docker.js` — `binaryName` ("podman"), `needsAccessCheck` (false), `psCommand`, `logsCommand`, `actionCommand`, `parseContainerList(rawStdout, shared)`, `classifyError`.

**Fixture data** (schema confirmed live against podman 6.1.0 during design research — see spec doc's comparison table; values below are synthetic, not the real captured containers, to keep no personal project data in the test file):

```js
const RUNNING_JSON = JSON.stringify([{
  Id: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f601',
  Names: ['myapp-web'],
  Image: 'docker.io/library/nginx:latest',
  State: 'running',
  Status: 'Up 3 minutes',
  Ports: [{ host_ip: '127.0.0.1', host_port: 8080, container_port: 80, protocol: 'tcp' }],
  CreatedAt: '3 minutes ago'
}])

const STOPPED_JSON = JSON.stringify([{
  Id: 'b1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f602',
  Names: ['myapp-worker'],
  Image: 'docker.io/library/alpine:latest',
  State: 'exited',
  Status: 'Exited (0) 5 minutes ago',
  Ports: [],
  CreatedAt: '10 minutes ago'
}])
```

- [ ] **Step 1: Write the failing test**

`tests/podman.test.js`:
```js
const test = require('node:test')
const assert = require('node:assert/strict')
const Shared = require('../engines/shared.js')
const Podman = require('../engines/podman.js')

// (RUNNING_JSON / STOPPED_JSON fixtures as above, plus a combined two-element
// array fixture, RUNNING_AND_STOPPED_JSON, built the same way with both
// objects in one array — this is what a real `podman ps -a --format json`
// call returns for a multi-container list.)

test('psCommand uses the array-form --format json, not the row template', () => {
  // Only this form reliably populates Status — see the design spec.
  assert.deepEqual(Podman.psCommand('/usr/bin/podman'), ['/usr/bin/podman', 'ps', '-a', '--format', 'json'])
})

test('logsCommand builds the argv for tailing logs', () => {
  assert.deepEqual(Podman.logsCommand('/usr/bin/podman', 'abc123', 200), ['/usr/bin/podman', 'logs', '--tail', '200', '--timestamps', 'abc123'])
})

test('actionCommand maps verbs to the right flags', () => {
  assert.deepEqual(Podman.actionCommand('/usr/bin/podman', 'remove', 'abc123'), ['/usr/bin/podman', 'rm', '-f', 'abc123'])
})

test('parseContainerList parses the whole-array JSON form', () => {
  const list = Podman.parseContainerList(RUNNING_AND_STOPPED_JSON, Shared)
  assert.equal(list.length, 2)
  const running = list.find(c => c.name === 'myapp-web')
  assert.equal(running.isRunning, true)
  assert.equal(running.id.length, 12) // truncated to Docker-style short id
  assert.equal(running.image, 'docker.io/library/nginx:latest')
  assert.equal(running.statusText, 'Up 3 minutes')
  assert.deepEqual(running.ports, [{ hostPort: 8080, containerPort: 80, protocol: 'tcp' }])
})

test('parseContainerList reads Names as an array, taking the first element', () => {
  const list = Podman.parseContainerList(STOPPED_JSON, Shared)
  assert.equal(list[0].name, 'myapp-worker')
})

test('parseContainerList defaults healthStatus to none (not available from ps)', () => {
  const list = Podman.parseContainerList(RUNNING_JSON, Shared)
  assert.equal(list[0].healthStatus, 'none')
})

test('parseContainerList handles an empty list', () => {
  assert.deepEqual(Podman.parseContainerList('[]', Shared), [])
})

test('parseContainerList handles unparseable stdout without throwing', () => {
  assert.deepEqual(Podman.parseContainerList('not json', Shared), [])
})

test('classifyError reports not-installed when the binary is missing', () => {
  assert.equal(Podman.classifyError(false, '').kind, 'not-installed')
})

test('classifyError falls back to unknown, truncated', () => {
  const result = Podman.classifyError(true, 'some other failure')
  assert.equal(result.kind, 'unknown')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/podman.test.js`
Expected: FAIL — `Cannot find module '../engines/podman.js'`

- [ ] **Step 3: Write `engines/podman.js`**

```js
// Podman's `ps` only fully populates Status through the top-level
// --format json (whole-array) flag, not the per-row {{json .}} template
// Docker uses — confirmed live against podman 6.1.0. That means the whole
// stdout is one JSON array, not one JSON object per line, so this file's
// parseContainerList parses the full text in one JSON.parse rather than
// splitting on newlines the way engines/docker.js does.
var binaryName = "podman"
var needsAccessCheck = false // rootless: no daemon-socket privilege boundary

function psCommand(binaryPath) {
  return [binaryPath, "ps", "-a", "--format", "json"]
}

function logsCommand(binaryPath, id, tailLines) {
  return [binaryPath, "logs", "--tail", String(tailLines), "--timestamps", id]
}

function actionCommand(binaryPath, verb, id) {
  if (verb === "remove") return [binaryPath, "rm", "-f", id]
  return [binaryPath, verb, id]
}

// Podman's Ports are already structured objects (unlike Docker's
// comma-joined string), so no regex is needed — just dedupe and cap.
function mapPorts(rawPorts, shared) {
  var seen = {}
  var result = []
  var list = (rawPorts || []).slice(0, shared.MAX_PORTS)
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
    // Podman's Id is the full 64-char hash; truncate to Docker's 12-char
    // convention since every action command accepts either length.
    id: shared.clamp(String(raw.Id || "").substring(0, 12), shared.MAX_FIELD_LEN),
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
  module.exports = { binaryName, needsAccessCheck, psCommand, logsCommand, actionCommand, parseContainerList, classifyError }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/podman.test.js`
Expected: PASS, all cases

- [ ] **Step 5: Commit**

```bash
git add engines/podman.js tests/podman.test.js
git commit -m "Add engines/podman.js: Podman engine spec module"
```

---

### Task 4: `BinaryResolver.qml` — reusable absolute-path resolve+validate

**Files:**
- Create: `BinaryResolver.qml`

**Interfaces:**
- Consumes: `BoundedProcess.qml` (existing, unchanged).
- Produces (used by Task 5): `property string binaryName`, `function resolveAndValidate()`, `signal resolved(string path)`, `signal failed(string reason)` (`reason` is the literal string `"not-found"`, or a human-readable message for an unsafe-binary failure).

- [ ] **Step 1: Write `BinaryResolver.qml`**

```qml
import QtQuick

// Resolves a binary off PATH once, then validates the resolved path is a
// root-owned, non-group/other-writable regular file before it is ever used
// — extracted from Service.qml's Docker-only version so both engines share
// it. PATH is attacker-influenceable, so re-resolving on every call instead
// of caching the validated absolute path would be a TOCTOU gap.
Item {
  id: root

  property string binaryName: ""
  property int timeoutMs: 5000

  signal resolved(string path)
  signal failed(string reason)

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
```

- [ ] **Step 2: Lint**

Run: `qmllint BinaryResolver.qml`
Expected: exit 0, no output

- [ ] **Step 3: Commit**

```bash
git add BinaryResolver.qml
git commit -m "Extract BinaryResolver.qml: reusable absolute-path resolve+validate"
```

---

### Task 5: `ContainerEngine.qml` — generic engine runner (replaces `Service.qml`)

**Files:**
- Create: `ContainerEngine.qml`
- Delete: `Service.qml`

**Interfaces:**
- Consumes: `BinaryResolver.qml`, `BoundedProcess.qml`, `engines/shared.js`, `engines/docker.js`, `engines/podman.js` (Tasks 1–4).
- Produces (used by Task 6): identical public surface to today's `Service.qml` — `property string engineName` (new), `settings`, `panelOpen`, `errorKind`, `errorMessage`, `actionErrorMessage`, `containers`, `runningCount`, `loading`, `logsText`, `logsContainerId`, `logsLoading`, `refresh()`, `fetchLogs(id)`, `clearLogs()`, `stopContainer(id)`, `startContainer(id)`, `removeContainer(id)`, `containerExists(id)`. Two properties are renamed for genericness (`dockerAvailable`→`available`, `dockerPath`→`enginePath`) — grep confirmed `Panel.qml` never references either by name, so this is safe.

- [ ] **Step 1: Write `ContainerEngine.qml`**

Base it on today's `Service.qml` (already read in full this session), with these changes:
- Add `import "engines/shared.js" as Shared`, `import "engines/docker.js" as DockerEngine`, `import "engines/podman.js" as PodmanEngine`.
- Add `property string engineName: "docker"` and `function spec() { return root.engineName === "podman" ? PodmanEngine : DockerEngine }`.
- Replace the `pathResolver`/`pathValidator` `BoundedProcess` pair with a single `BinaryResolver { id: resolver; binaryName: root.spec().binaryName }`, wired as:
  ```qml
  BinaryResolver {
    id: resolver
    binaryName: root.spec().binaryName
    onResolved: function(path) {
      root.enginePath = path
      root.available = true
      root.refresh()
    }
    onFailed: function(reason) {
      root.available = false
      root.loading = false
      if (reason === "not-found") {
        root.applyError("")
      } else {
        root.errorKind = "unsafe-binary"
        root.errorMessage = reason
      }
    }
  }
  ```
  `Component.onCompleted: resolver.resolveAndValidate()` replaces `pathResolver.start()`.
- `refresh()`: when `spec().needsAccessCheck` is false, skip `sudoCheck` entirely and go straight to `psProcess`:
  ```qml
  function refresh() {
    if (root.enginePath === "") return
    if (sudoCheck.running || psProcess.running) return
    root.loading = true
    if (spec().needsAccessCheck) {
      sudoCheck.start()
    } else {
      psProcess.command = spec().psCommand(root.enginePath)
      psProcess.start()
    }
  }
  ```
- `sudoCheck.onFinished`'s fallthrough branch becomes `psProcess.command = spec().psCommand(root.enginePath); psProcess.start()` (was hardcoded Docker argv).
- `applyContainers(stdout)`: `root.containers = spec().parseContainerList(stdout, Shared)` (was `Model.parseContainerList(stdout)`).
- `applyError(stderrText)`: `var classified = spec().classifyError(root.available, stderrText)` (was `Model.classifyDockerError(root.dockerAvailable, stderrText)`).
- `fetchLogs(id)`: `logsProcess.command = spec().logsCommand(root.enginePath, id, root.logTailLines)` (was a hardcoded Docker argv).
- `stopContainer`/`startContainer`/`removeContainer`: build commands via `spec().actionCommand(root.enginePath, "stop"|"start"|"remove", id)` instead of hardcoded `[root.dockerPath, "stop", id]` etc.
- Every other line (settings helpers, `containerExists`, `runAction`, `refreshTimer`, `psProcess`/`actionProcess`/`logsProcess` `BoundedProcess` blocks and their comments) carries over unchanged except `root.dockerPath`→`root.enginePath` and `root.dockerAvailable`→`root.available`.

- [ ] **Step 2: Delete the old file**

```bash
git rm Service.qml
```

- [ ] **Step 3: Lint**

Run: `qmllint ContainerEngine.qml`
Expected: exit 0, no output

Run: `wc -l ContainerEngine.qml` — if meaningfully over ~200, move `runAction`/`stopContainer`/`startContainer`/`removeContainer`/`containerExists` into a small pure-JS `engines/actions.js` (taking the same `spec()`-returned engine module plus an injected process-runner callback) and note the split in `docs/design.md`.

- [ ] **Step 4: Functional verification (standalone harness, not committed)**

Write a throwaway `_test_harness.qml` in the plugin root (same pattern used for the Docker security-review verification earlier this project):
```qml
import QtQuick
import Quickshell

ShellRoot {
  ContainerEngine {
    id: docker
    engineName: "docker"
    onErrorKindChanged: console.log("[docker] errorKind=" + errorKind + " " + errorMessage)
    onContainersChanged: console.log("[docker] containers=" + containers.length)
  }
  ContainerEngine {
    id: podman
    engineName: "podman"
    onErrorKindChanged: console.log("[podman] errorKind=" + errorKind + " " + errorMessage)
    onContainersChanged: console.log("[podman] containers=" + containers.length)
    onActionErrorMessageChanged: console.log("[podman] actionErrorMessage=" + JSON.stringify(actionErrorMessage))
    onLogsTextChanged: console.log("[podman] logsText=" + JSON.stringify(logsText.substring(0, 200)))
  }
  Timer { interval: 4000; running: true; onTriggered: console.log("[podman] running before actions: " + JSON.stringify(podman.containers.map(c => c.name))) }
  Timer { interval: 20000; running: true; onTriggered: Qt.quit() }
}
```
Before running: `podman run -d --name chub-podman-verify alpine:latest sleep 300`. Run: `timeout 22 quickshell -p _test_harness.qml`. Confirm: both engines populate `containers` with no errors; podman's list includes `chub-podman-verify`. Then manually drive one round of stop/start/logs/remove against `chub-podman-verify` the same way Task 5 of the earlier Docker hardening work did — extend the harness with `Timer`s calling `podman.stopContainer(...)`/`startContainer(...)`/`fetchLogs(...)`/`removeContainer(...)` on the real container id (read it from `podman.containers[0].id` in a `Timer` callback), and confirm each logs a success transition with no `actionErrorMessage`.
Clean up: `docker rm -f chub-podman-verify 2>/dev/null; podman rm -f chub-podman-verify 2>/dev/null; rm -f _test_harness.qml`.

- [ ] **Step 5: Commit**

```bash
git add ContainerEngine.qml
git commit -m "Add ContainerEngine.qml: generic polling/actions runner, replacing Service.qml"
```

---

### Task 6: Wire `Panel.qml` to `ContainerEngine` (mechanical rename only)

**Files:**
- Modify: `Panel.qml` (the `Service { id: docker; ... }` block only)

**Interfaces:**
- Consumes: `ContainerEngine.qml` (Task 5) — no other `Panel.qml` code changes since every `docker.*` reference it uses (`containers`, `errorKind`, `errorMessage`, `actionErrorMessage`, `loading`, `runningCount`, `logsText`, `logsLoading`, `logsContainerId`, `panelOpen`, `settings`, `refresh()`, `clearLogs()`, `fetchLogs()`, `stopContainer()`, `startContainer()`, `removeContainer()`, `containerExists()`) is unchanged in `ContainerEngine.qml`.

- [ ] **Step 1: Edit `Panel.qml`**

```qml
  ContainerEngine {
    id: docker
    engineName: "docker"
    settings: root.settings
  }
```
(replaces the existing `Service { id: docker; settings: root.settings }` block)

- [ ] **Step 2: Lint**

Run: `qmllint Panel.qml`
Expected: exit 0

- [ ] **Step 3: Live verification**

```bash
omarchy plugin validate .
omarchy-shell shell rescanPlugins
```
Check `journalctl -t omarchy-shell --since "30 seconds ago"` for any error/TypeError/ReferenceError (excluding the known-benign `IpcHandler` warnings). Open the panel via `quickshell -n -p "$OMARCHY_PATH/shell" ipc call io.github.suman196pokhrel.container-hub open`, screenshot with `grim`, confirm the Docker container list renders exactly as before (same containers, same actions), then close it via the same IPC call with `close`.

- [ ] **Step 4: Commit**

```bash
git add Panel.qml
git commit -m "Wire Panel.qml to ContainerEngine (Docker), replacing Service"
```

---

### Task 7: Remove superseded files, update design docs, final full verification

**Files:**
- Delete: `Model.js`, `tests/model.test.js`
- Modify: `docs/design.md`

- [ ] **Step 1: Remove superseded files**

```bash
git rm Model.js tests/model.test.js
```
(Confirm nothing still references them: `grep -rn "Model.js\|Model\." --include=*.qml .` should return nothing outside of files already deleted/rewritten.)

- [ ] **Step 2: Update `docs/design.md`**

Add a short section (after "Data flow", before "UI") describing the engine abstraction:
```markdown
## Engine abstraction

`ContainerEngine.qml` (was Docker-only `Service.qml`) is parameterized by
`engineName: "docker" | "podman"` and delegates command-building, JSON
parsing, and error classification to `engines/docker.js` / `engines/podman.js`
— both export the same function set (`psCommand`, `logsCommand`,
`actionCommand`, `parseContainerList`, `classifyError`, `binaryName`,
`needsAccessCheck`), sharing small common helpers via `engines/shared.js`.
Podman is rootless here (no daemon socket, no group-membership privilege
boundary), so its `needsAccessCheck` is `false` and it skips the
`omarchy-sudo-docker`-style disclosure step Docker uses. Absolute-path
resolution+validation (`BinaryResolver.qml`) is shared by both.

This phase adds no UI: `Panel.qml` only ever instantiates the Docker
engine. A future phase adds a switcher; see
`docs/superpowers/specs/2026-09-02-podman-integration-design.md`.
```

- [ ] **Step 3: Full verification sweep**

```bash
node --test tests/
qmllint ContainerEngine.qml BinaryResolver.qml Panel.qml BoundedProcess.qml
omarchy plugin validate .
```
All must pass clean (all tests green, zero lint output, validate exit 0).

- [ ] **Step 4: Commit**

```bash
git add docs/design.md
git commit -m "Remove superseded Model.js/model.test.js; document the engine abstraction"
```
