# Container Hub — Design

## Purpose

A minimal, icon-based Omarchy bar widget for monitoring and managing local
containers, so a fullstack developer working across several projects
doesn't have to drop to a terminal just to check what's running, tail logs,
or stop/remove a container.

MVP scope was Docker only. Podman now runs underneath as a second engine
(see "Engine abstraction" below) but is not yet exposed in the UI — `Panel.qml`
only ever shows the Docker engine this phase.

## Scope

Shown containers: all containers (running + stopped), not just running ones.
Delete and log-viewing are useful on stopped containers too; the bar badge
shows the running count so an at-a-glance state stays meaningful.

Per-container actions, contextual to state:

- **Stop** — running containers only
- **Start** — stopped containers only
- **Remove** — always available, behind a confirmation dialog (`docker rm -f`)
- **View logs** — always available (see Logs below)
- **Ports** — shown inline; clicking a published host port opens
  `http://localhost:<port>` in the default browser

Logs are a one-shot tail (`docker logs --tail N --timestamps <id>`), not a
live stream. The shell is a single long-running process shared by the whole
bar; an unbounded `docker logs -f` piped into it could wedge the UI for
everyone. Instead: a manual-refresh tail view inline, plus an **"Open in
lazydocker"** button that shells out to Omarchy's existing
`omarchy-launch-docker-tui` for anything beyond that (live follow, exec,
stats, restart).

Docker-unreachable is a first-class state with several distinguishable
causes: not installed, access not set up (the proactive `omarchy-sudo-docker`
check, before any `docker` command is even attempted), permission denied
(the reactive fallback if that check is unavailable), daemon not running, or
the resolved `docker` binary failing its safety check. Each gets a one-line
actionable message — never a bare spinner or a crash. The access-not-set-up
state gets an extra affordance: a button that opens
`omarchy-setup-security-sudoless-docker` in a terminal, Omarchy's own
guarded, confirmation-gated way to grant that (root-equivalent) access —
Container Hub never elevates or edits group membership itself.

## Files

```
manifest.json
Panel.qml            # bar button + panel UI; manifest entry point
ContainerEngine.qml   # Process orchestration: polling, stop/start/rm/logs
BinaryResolver.qml    # absolute-path resolve+validate, shared by both engines
ActionRunner.qml       # runs one start/stop/remove command, with a deadline
LogsRunner.qml          # fetches one container's log tail, with a deadline
BoundedProcess.qml       # Process wrapper: hard deadline, kill, output caps
engines/
  shared.js               # clamp/cap constants, sortContainers, formatPortsDisplay, statusColorFor
  docker.js                # Docker command builders + ps-JSON -> container mapping
  podman.js                 # Podman command builders + ps-JSON -> container mapping
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
`needsAccessCheck`, `psCommand`, `logsCommand`, `actionCommand`,
`parseContainerList`, `classifyError`), sharing small common helpers
(`clamp`, `sortContainers`, `formatPortsDisplay`, `statusColorFor`) via
`engines/shared.js`. Podman's `ps` JSON is not a drop-in match for Docker's:
only the top-level `--format json` (whole-array) flag populates `Status`,
so `engines/podman.js`'s `parseContainerList` parses the entire stdout as
one JSON array, while `engines/docker.js`'s splits on newlines (Docker's
`{{json .}}` prints one object per line). Podman here is rootless — no
daemon socket, so its `needsAccessCheck` is `false` and it skips the
`omarchy-sudo-docker`-style disclosure step Docker uses. Full details and
the exact schema differences: `docs/superpowers/specs/2026-09-02-podman-integration-design.md`.

This phase adds no UI: `Panel.qml` only ever instantiates the Docker engine
(`ContainerEngine { engineName: "docker" }`). A future phase adds a
switcher.

## Data flow

On startup, `ContainerEngine.qml` resolves its engine's binary off `PATH`
once via `BinaryResolver.qml` (`which <binary>`), then validates the
resolved path (`stat -L`: must be a regular file, owned by root, not
group/other-writable) before storing it as `enginePath`. Every later
invocation uses that literal absolute path, never a bare binary-name
lookup — `PATH` is attacker-influenceable and the daemon behind Docker's
binary is root-equivalent, so re-resolving on every call would be a TOCTOU
gap.

Every subprocess (`ps`, `stop`/`start`/`rm`, `logs`) runs through
`BoundedProcess.qml`, not `Quickshell.Io.Process` directly: a hard wall-clock
deadline (SIGTERM, then SIGKILL if it's still alive 2s later) and a hard cap
on stored stdout/stderr, so a hung or misbehaving container can't wedge the
poll loop or grow memory unbounded. See that file's header comment for the
one real gap: Quickshell's IO layer has no byte-limited reader, so the cap
bounds *stored* output and, via the deadline, *time*, but not necessarily
peak memory during a single run that writes one huge unterminated line.

`ContainerEngine.qml` polls its engine's container list, two-speed:

- fast (`refreshIntervalOpenSec`, default 3s) while the panel is open
- slow (`refreshIntervalClosedSec`, default 15s) while closed, so the bar
  badge stays live without hammering the daemon

`refresh()` is guarded (`if (proc.running) return`) and re-triggered
immediately after any action settles (stop/start/remove). Consecutive poll
failures back the interval off up to 5x the configured value; a single
success resets it. Before every poll, a cheap local check
(`omarchy-sudo-docker`, no daemon call, no prompt) asks whether Docker needs
elevated access right now; if so, the poll is skipped in favor of the
access-not-set-up state instead of hammering `docker ps` into a guaranteed
permission error.

Removing a container re-checks the id is still present in the current list
immediately before firing `docker rm -f`, since time passes between opening
the confirm dialog and confirming it. Every action surfaces failure (non-zero
exit, timeout, or a container that's already gone) as a dismissible message
instead of silently refreshing either way.

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

All process commands are argv arrays (`["docker", "stop", id]`), never
shell-interpolated strings.

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

## Settings

Exposed via `manifest.json`'s `barWidget.schema` (editable from Omarchy's
plugin settings UI): `refreshIntervalOpenSec`, `refreshIntervalClosedSec`,
`logTailLines`.

## Testing

`engines/shared.js`, `engines/docker.js`, and `engines/podman.js` all carry
a `module.exports` guard (same pattern the stock plugins use) so their
parsing/formatting/classification logic is covered by `node --test` — no
Qt required for that part. Podman's fixtures are synthetic but
schema-accurate, matching a real podman 6.1.0 install verified live during
design (see the spec doc). QML process wiring is verified by hot-reloading
in the live shell against real containers, plus standalone
`quickshell -p <throwaway-harness>.qml` runs that instantiate
`ContainerEngine.qml` directly against real, disposable test containers —
never the user's real ones — with the harness file deleted afterward, not
committed.

## Out of scope for MVP

- A UI for Podman (engine/list switcher) — the engine itself works, nothing
  shows it yet
- Podman health status (`podman inspect` per container) — always `"none"`,
  since `podman ps` doesn't expose it
- Podman rootful mode / `podman --remote`
- Live-streaming logs into the shell process
- Container creation / image management / compose project awareness
- Exec-into-container
