# Podman integration — design

Branch: `podman-integration`. Backend-only phase: no UI changes. Panel.qml
keeps rendering the Docker engine exactly as it does today; Podman support
is built and verified underneath it, ready for a future engine-switcher UI.

## Purpose

Add Podman as a second, first-class container engine with feature parity to
what Docker already has (list, start, stop, remove, logs), without
duplicating the polling/subprocess-safety work already done for Docker
(hard deadlines, output caps, absolute-path validation, backoff — see the
2026-09 marketplace security review response). A future phase adds a
switcher UI to pick which engine's list is shown; that is explicitly out of
scope here.

## Why Podman is not a drop-in second Docker

Confirmed live against Podman 6.1.0 (rootless, installed on this machine)
against a real running container:

| | Docker `ps -a --format '{{json .}}'` | Podman |
|---|---|---|
| ID | `"ID"`, short (12 char) | `"Id"`, full 64-char hash |
| Name | `"Names"`: `"foo"` (string) | `"Names"`: `["foo"]` (array, first element used) |
| Image | `"Image"`: `"alpine:latest"` | `"Image"`: `"docker.io/library/alpine:latest"` (registry-qualified) |
| Status | `"Up 24 minutes"` | **empty string** — only populated when Podman is invoked with the top-level `--format json` (whole-array) form instead of the per-row `{{json .}}` template |
| Ports | `"0.0.0.0:5050->80/tcp"` (comma-joined string, needs regex) | `[{"host_ip":"...","host_port":N,"container_port":N,"protocol":"tcp"}]` (structured array, no regex needed) |
| CreatedAt | absolute timestamp string | relative string ("37 seconds ago"), via the array-form command only |
| Health | `"HealthStatus"` field present | not present in `ps` output at all; would need a separate `podman inspect` call per container — **out of scope this phase**, `healthStatus` defaults to `"none"` for every Podman container |

Action verbs are unaffected: `podman stop/start/rm -f/logs --tail --timestamps`
all behave identically to their Docker counterparts, including the same 10s
SIGTERM-then-SIGKILL grace period on `stop` (confirmed live) — the existing
20s action deadline needs no per-engine tuning.

Podman here is rootless (`podman info --format '{{.Host.Security.Rootless}}'`
→ `true`): no daemon socket, no `docker`-group-style root-equivalent
privilege boundary. The "needs sudo / disclose root-equivalence" state built
for Docker does not apply to the common rootless case and is not
replicated for Podman. The absolute-path resolve+validate step (`which` +
`stat -L`, regular file / root-owned / non-writable) *is* still applied to
the podman binary too, for architectural consistency and because it's
cheap — even though the stakes of a hijacked rootless binary are lower than
a hijacked root-daemon client.

## Architecture

One generic engine runner, `ContainerEngine.qml` (replaces today's
`Service.qml`), owns everything that's identical between engines: the
`BoundedProcess`-based polling loop, backoff on repeated failure, action
dispatch (start/stop/remove) with failure surfacing and pre-exec identity
recheck, and log fetching. It's parameterized by an **engine spec** — a
plain JS object supplied by `engines/docker.js` or `engines/podman.js` —
that supplies only what differs per engine:

```js
// shape both engines/docker.js and engines/podman.js export
{
  name: "docker" | "podman",
  binaryName: "docker",                 // resolved via `which`
  psCommand(binaryPath) -> string[],     // argv for listing
  logsCommand(binaryPath, id, tailLines) -> string[],
  actionCommand(binaryPath, verb, id) -> string[], // verb: stop/start/remove
  parseContainerList(rawStdout) -> normalizedContainer[],
  classifyError(binaryAvailable, stderrText) -> { kind, message },
  needsAccessCheck: bool,                 // true only for Docker today
}
```

`parseContainerList` takes the *entire* raw stdout, not one line at a time
— found during spec review, not an arbitrary choice: Docker's `ps` emits
one JSON object per line (`{{json .}}`, newline-delimited), but Podman only
gets a populated `Status` field from the top-level `--format json` flag,
which prints the whole result as a single pretty-printed JSON *array*
across multiple lines. A shared "split stdout on newlines, parse each line"
loop in `ContainerEngine.qml` can't handle both shapes, so each engine
spec owns its own framing: `engines/docker.js`'s `parseContainerList` does
the newline-split-and-parse-each-line loop (unchanged from today's
`Model.parseContainerList`), `engines/podman.js`'s does one
`JSON.parse(rawStdout || "[]")` and maps the array. `ContainerEngine.qml`
itself just hands the whole stdout string to whichever spec is active.

Only one `ContainerEngine` instance runs inside the live shell this phase —
the existing Docker one, kept exactly as-is behaviorally. `Panel.qml`
needs a mechanical one-line change (`Service { id: docker }` →
`ContainerEngine { id: docker; engine: DockerEngine.spec }`) to keep
compiling against the renamed component; nothing else in `Panel.qml`
changes, and no Podman instance is added there. The Podman engine is
proven entirely through the standalone verification harness described
under Testing — not left running in the production shell — so no Omarchy
user picks up a background Podman poller before there's any UI to show for
it.

`ContainerEngine.qml` resolves and validates its own binary path once at
startup via a new `BinaryResolver.qml` (extracted from today's
`Service.qml` path-resolution logic, unchanged behavior, now reusable per
engine instance).

## File layout

```
engines/
  shared.js        # clamp()/MAX_* caps, sortContainers, formatPortsDisplay,
                    # statusColorFor — engine-agnostic, used by both
  docker.js         # Docker engine spec (moves Docker-specific bits out of
                    # today's Model.js)
  podman.js          # Podman engine spec
BinaryResolver.qml   # which + stat -L validation, reusable
ContainerEngine.qml  # was Service.qml; generic polling/actions/backoff
BoundedProcess.qml   # unchanged
tests/
  docker.test.js      # today's model.test.js, adapted to engines/docker.js
  podman.test.js       # new; fixtures are the real JSON captured from this
                        # machine's podman 6.1.0 during design research
```

`Model.js` and `tests/model.test.js` are removed once their contents have
moved to `engines/shared.js` + `engines/docker.js` + the corresponding
tests — no dangling duplicate copy left behind.

Every file above is written to land at or under ~200 lines. If
`ContainerEngine.qml` is still too large after the extraction above, the
action-handling block (`runAction`/`stopContainer`/`startContainer`/
`removeContainer`/`containerExists`) is a natural second split
(`ContainerActions.js`, pure logic returning argv arrays, or a QML
sub-component) — decided during implementation if needed, not pre-committed
here.

`Panel.qml` gets only the one-line mechanical rename described under
Architecture (`Service` → `ContainerEngine`) — no new UI elements, no
Podman instance added there. `manifest.json` and `README.md` are not
touched at all: no user-facing surface exists yet for Podman, so nothing to
describe. `docs/design.md` gets a short addition noting the engine
abstraction now exists and that Podman runs underneath without UI exposure
yet.

## Error handling

Each engine spec's `classifyError` mirrors today's `classifyDockerError`
shape (`{ kind, message }`) but matches that engine's own vocabulary.
Docker keeps its existing states (`not-installed`, `permission-denied`,
`daemon-down`, `needs-docker-access`, `unsafe-binary`, `timeout`,
`unknown`). Podman's rootless path realistically only needs
`not-installed`, `unsafe-binary`, `timeout`, and `unknown` — no
`needs-docker-access` equivalent, since `needsAccessCheck: false` for the
Podman spec skips that step in `ContainerEngine.qml` entirely.

## Testing

- `node --test tests/` covers both engine specs' pure-JS parsing
  (`parseContainerList`, ports, error classification) with fixtures —
  Podman's fixtures are the exact JSON this design captured live, not
  hand-guessed shapes.
- Functional verification follows the same pattern used for the Docker
  hardening work: a standalone `quickshell -p <harness>.qml` script that
  instantiates `ContainerEngine.qml` directly (bypassing Panel.qml/the
  live shell) against real, disposable `chub-*`-prefixed containers created
  and torn down by the harness — never the user's real containers. The
  harness file is deleted after use, not committed.
- `omarchy plugin validate .` and `qmllint` on every touched/new file, as
  before.

## Out of scope this phase

- Any UI: no switcher, no Podman rows in `Panel.qml`, no manifest/README
  changes.
- Podman health status (`podman inspect` per container) — defaults to
  `"none"`.
- Podman rootful mode / `podman --remote` — only the default rootless local
  case is handled.
- Merging Docker and Podman containers into one list — each engine's state
  stays independent until the switcher UI decides how to present them.
