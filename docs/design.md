# Container Hub — Design

## Purpose

A minimal, icon-based Omarchy bar widget for monitoring and managing local
Docker containers, so a fullstack developer working across several projects
doesn't have to drop to a terminal just to check what's running, tail logs,
or stop/remove a container.

MVP scope is Docker only (no Podman).

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

Docker-unreachable is a first-class state with three distinguishable causes:
not installed, permission denied (user not in the `docker` group), daemon
not running. Each gets a one-line actionable message — never a bare spinner
or a crash.

## Files

```
manifest.json
Panel.qml         # bar button + panel UI; manifest entry point
Service.qml       # Process orchestration: polling, stop/start/rm/logs
Model.js          # pure JS: parse `docker ps` JSON, ports, sorting, errors
ContainerIcon.qml # vector icon (QtQuick.Shapes), theme-colored
README.md
docs/design.md    # this file
tests/model.test.js
```

`Panel.qml` is the sole manifest entry point (the same pattern the built-in
Dropbox plugin uses): its root component extends the shell's `Panel` base,
which already provides `open()`/`close()`/`toggle()`/`opened` — no separate
`BarWidget.qml` file is needed.

## Data flow

`Service.qml` polls `docker ps -a --format '{{json .}}'` via a `Quickshell.Io
Process`, two-speed:

- fast (`refreshIntervalOpenSec`, default 3s) while the panel is open
- slow (`refreshIntervalClosedSec`, default 15s) while closed, so the bar
  badge stays live without hammering the daemon

`refresh()` is guarded (`if (proc.running) return`) and re-triggered
immediately after any action settles (stop/start/remove).

`Model.js` turns each JSON line into:

```js
{
  id, name, image, state, statusText, isRunning,
  ports: [{ hostPort, containerPort, protocol }],
  createdAt
}
```

`.Ports` from `docker ps` duplicates entries for IPv4 and IPv6
(`0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp`) — `Model.js` dedupes those
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

`Model.js` carries a `module.exports` guard (same pattern the stock plugins
use) so its parsing/formatting/classification logic is covered by
`node --test` — no Qt required for that part. UI and process wiring are
verified manually against real local containers by enabling the widget in
the bar.

## Out of scope for MVP

- Podman support
- Live-streaming logs into the shell process
- Container creation / image management / compose project awareness
- Exec-into-container
