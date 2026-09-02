# Container Hub — Design

## Purpose

A minimal, icon-based Omarchy bar widget for monitoring and managing local
containers, so a fullstack developer working across several projects
doesn't have to drop to a terminal just to check what's running, tail logs,
or stop/remove a container.

MVP scope was Docker only. Podman now runs underneath as a second engine
(see "Engine abstraction" below) but is not yet exposed in the UI —
`Panel.qml` only ever shows the Docker engine this phase.

## Scope

Shown containers: all containers (running + stopped), not just running ones.
Delete and log-viewing are useful on stopped containers too; the bar badge
shows the running count so an at-a-glance state stays meaningful.

Per-container actions, contextual to state:

- **Stop** — running containers only
- **Start** — stopped containers only
- **Remove** — always available, behind a confirmation dialog (`rm -f`)
- **View logs** — always available (see Logs below)
- **Ports** — shown inline; clicking a published host port opens
  `http://localhost:<port>` in the default browser

Logs are a one-shot tail (`logs --tail N --timestamps <id>`), not a live
stream. The shell is a single long-running process shared by the whole bar;
an unbounded `logs -f` piped into it could wedge the UI for everyone.
Instead: a manual-refresh tail view inline, plus an **"Open in
lazydocker"** button that shells out to Omarchy's existing
`omarchy-launch-docker-tui` for anything beyond that (live follow, exec,
stats, restart) — Docker only; Podman has no equivalent button yet since it
has no UI at all this phase.

Docker-unreachable is a first-class state with several distinguishable
causes: not installed, access not set up (the proactive `omarchy-sudo-docker`
check, before any `docker` command is even attempted), permission denied
(the reactive fallback if that check is unavailable), daemon not running, or
the resolved `docker` binary failing its safety check. Each gets a one-line
actionable message — never a bare spinner or a crash. The access-not-set-up
state gets an extra affordance: a button that opens
`omarchy-setup-security-sudoless-docker` in a terminal, Omarchy's own
guarded, confirmation-gated way to grant that (root-equivalent) access —
Container Hub never elevates or edits group membership itself. Podman here
is rootless (no daemon socket), so it has no equivalent access-gate state —
see Engine abstraction.

## Files

```
manifest.json
Panel.qml            # bar button + panel UI; manifest entry point
ContainerEngine.qml   # Process orchestration: polling, actions, logs — generic over engine
BinaryResolver.qml     # Absolute-path resolve+validate (namei chain, dev:ino recheck)
ActionRunner.qml        # Runs one start/stop/remove command + a fresh pre-remove existence check
LogsRunner.qml            # Fetches one container's log tail, with a deadline
BoundedProcess.qml         # Process wrapper: setsid, group kill, deadline, output caps
engines/
  shared.js                  # clamp/cap constants, sortContainers, formatPortsDisplay, statusColorFor, id validation
  docker.js                   # Docker command builders + ps-JSON -> container mapping
  podman.js                    # Podman command builders + ps-JSON -> container mapping
ContainerIcon.qml    # vector icon (QtQuick.Shapes), theme-colored
README.md
docs/design.md    # this file
docs/superpowers/specs/2026-09-02-podman-integration-design.md
tests/shared.test.js
tests/docker.test.js
tests/podman.test.js
```

`Panel.qml` is the sole manifest entry point (the same pattern the built-in
Dropbox plugin uses): its root component extends the shell's `Panel` base,
which already provides `open()`/`close()`/`toggle()`/`opened` — no separate
`BarWidget.qml` file is needed.

## Engine abstraction

`ContainerEngine.qml` (was Docker-only `Service.qml`) is parameterized by
`engineName: "docker" | "podman"` and delegates command-building, JSON
parsing, and error classification to `engines/docker.js` / `engines/podman.js`
via `spec()` — both export the same function set (`binaryName`,
`binaryCandidates`, `needsAccessCheck`, `psCommand`, `logsCommand`,
`actionCommand`, `inspectCommand`, `parseContainerList`, `classifyError`),
sharing small common helpers (`clamp`, `sortContainers`,
`formatPortsDisplay`, `statusColorFor`, `isValidContainerId`) via
`engines/shared.js`. Podman's `ps` JSON is not a drop-in match for Docker's:
only the top-level `--format json` (whole-array) flag populates `Status`,
so `engines/podman.js`'s `parseContainerList` parses the entire stdout as
one JSON array, while `engines/docker.js`'s splits on newlines (Docker's
`{{json .}}` prints one object per line). Podman here is rootless — no
daemon socket, so its `needsAccessCheck` is `false` and it skips the
`omarchy-sudo-docker`-style disclosure step Docker uses. Full details and
the exact schema differences: `docs/superpowers/specs/2026-09-02-podman-integration-design.md`.

Every hardening measure below (absolute-path chain validation,
per-invocation revalidation, process-group kill, producer-side byte
limiting, full untruncated ids, fresh pre-remove existence check) applies
uniformly to both engines through this shared `ContainerEngine.qml` — it
was written once, in response to a marketplace security review of the
Docker-only version, and Podman inherits it by construction rather than
needing a second, parallel implementation.

This phase adds no UI: `Panel.qml` only ever instantiates the Docker engine
(`ContainerEngine { engineName: "docker" }`). A future phase adds a
switcher.

## Data flow

On startup, `BinaryResolver.qml` checks a fixed list of trusted absolute
candidate paths per engine (`engines/*.js`'s `binaryCandidates`, e.g.
`/usr/bin/docker`, `/usr/local/bin/docker` — never `PATH`/`which`, which is
itself attacker-influenceable) and validates the *entire* path chain —
every directory component plus the final binary — is root-owned and not
group/other-writable, via one `namei -l` call (also invoked by hardcoded
absolute path). The validated (device, inode) pair is cached and
**re-checked immediately before every subsequent ps/logs/action
invocation** via `recheck()`, not just once at startup: the file at that
path could otherwise be replaced between validation and use (TOCTOU). If a
recheck ever fails, the plugin drops `enginePath`, refuses to run anything,
and re-resolves from scratch.

Every subprocess runs through `BoundedProcess.qml`, not `Quickshell.Io.Process`
directly: the inner command is wrapped in `setsid` (which execs in place
here rather than forking, verified live, so the tracked pid is also the new
process group's id) and a hard wall-clock deadline sends `TERM` then `KILL`
to that *whole group* — via a short-lived `kill -SIG -<pid>`, not
`Process.signal()` on the single tracked process — reaching any children the
tracked process spawns, not just itself; verified against a pipeline that
cannot terminate on its own from either side. `ps` and `logs` additionally
pipe through `/usr/bin/head -c <cap>` (`<engine> <cmd> | head -c N`), so the
byte cap is enforced by a real OS pipe at the source, not only after
`StdioCollector` has already buffered the full output — verified live: an
8MB single-line container log was read with under 5MB peak RSS for the
entire plugin process, and no leftover process survived a forced kill. The
container id embedded in that shell string is regex-validated
(`Shared.isValidContainerId`, plain lowercase hex) before it ever reaches
the string; `enginePath` and the (already-clamped) tail-line count are the
only other values interpolated, and both are our own validated/fixed data,
never raw external text.

`ContainerEngine.qml` polls its engine's container list (`ps --no-trunc`,
full untruncated ids throughout — a truncated id was previously eligible to
reach a destructive `rm -f`), two-speed:

- fast (`refreshIntervalOpenSec`, default 3s) while the panel is open
- slow (`refreshIntervalClosedSec`, default 15s) while closed, so the bar
  badge stays live without hammering the daemon

`refresh()` is guarded (`if (proc.running) return`) and re-triggered
immediately after any action settles (stop/start/remove). Consecutive poll
failures back the interval off up to 5x the configured value; a single
success resets it. Before every poll (Docker only — see Engine abstraction),
a cheap local check (`omarchy-sudo-docker`, no daemon call, no prompt) asks
whether Docker needs elevated access right now; if so, the poll is skipped
in favor of the access-not-set-up state instead of hammering `ps` into a
guaranteed permission error.

Removing a container queries the daemon fresh (`inspect`, via
`ActionRunner.checkExists()`) immediately before firing `rm -f`, rather than
trusting the polled list — that list can be several seconds stale, and time
also passes while the confirm dialog is open. Verified live: removing a
container that was deleted *outside* the plugin (so the cached list still
showed it as present) was correctly refused ("Container is already gone;
nothing removed") — the cache alone would have proceeded. Every action
surfaces failure (non-zero exit, timeout, or a container that's already
gone) as a dismissible message instead of silently refreshing either way.

Each engine's `parseContainerList` turns its raw `ps` output into the same
normalized shape regardless of source engine:

```js
{
  id, name, image, state, statusText, healthStatus, isRunning,
  ports: [{ hostPort, containerPort, protocol }],
  createdAt
}
```

Docker's `.Ports` duplicates entries for IPv4 and IPv6
(`0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp`); Podman's are already
structured objects instead of a string to regex-parse. Both engines dedupe
to one logical port mapping.

Every command is still an argv array, with one deliberate, narrow exception:
`ps` and `logs` go through `/bin/sh -c "<cmd> | head -c N"` for the
producer-side byte limiting described above, since Quickshell's `Process`
has no built-in piping. The only externally-influenced value ever placed in
that shell string (a container id) is regex-validated first — see
`Shared.isValidContainerId` and `tests/shared.test.js`; a value that doesn't
match is rejected before it ever reaches the string, never escaped-and-hoped.
`stop`/`start`/`rm`/`inspect` stay plain argv (no shell) since their output
isn't attacker-length-controlled the way logs are.

Colors come from the shell's own theme tokens (`Color.accent` for running,
`Color.muted` for stopped, `Color.urgent` for unhealthy/errors) so the
widget matches whatever Omarchy theme is active rather than hardcoding
colors.

## UI

- Bar button: `ContainerIcon` + running-count badge, built on the shared
  `BarWidget`/`WidgetButton` base.
- Panel: header with total/running counts and a manual refresh icon, then a
  scrollable list of container rows (name, image, status pill, ports,
  action icons via `PanelActionButton`), built on the shared
  `Panel`/`KeyboardPanel` base for keyboard nav, Escape-to-close, and popout
  switching.
- Remove uses the shared `ConfirmDialog` component.
- Logs is a second content state inside the same panel (a back action
  returns to the list) — not a separate window.
- Docker only this phase — see Engine abstraction.

## Settings

Exposed via `manifest.json`'s `barWidget.schema` (editable from Omarchy's
plugin settings UI): `refreshIntervalOpenSec`, `refreshIntervalClosedSec`,
`logTailLines`. Shared by both engines; no per-engine settings exist yet
since only Docker has a UI to configure them from.

## Testing

`engines/shared.js`, `engines/docker.js`, and `engines/podman.js` all carry
a `module.exports` guard (same pattern the stock plugins use) so their
parsing/formatting/classification/command-building logic is covered by
`node --test` — no Qt required for that part. Podman's fixtures are
synthetic but schema-accurate, matching a real podman 6.1.0 install verified
live during design. QML process wiring is verified by hot-reloading in the
live shell against real containers, plus standalone
`quickshell -p <throwaway-harness>.qml` runs that instantiate
`ContainerEngine.qml` directly (for both engines) against real, disposable
test containers — never the user's real ones — with the harness file
deleted afterward, not committed.

## Out of scope for MVP

- A UI for Podman (engine/list switcher) — the engine itself works, nothing
  shows it yet
- Podman health status (`inspect` per container beyond the pre-remove
  check) — always `"none"` in the list, since `ps` doesn't expose it
- Podman rootful mode / `podman --remote`
- Live-streaming logs into the shell process
- Container creation / image management / compose project awareness
- Exec-into-container
