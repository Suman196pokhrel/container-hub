# Container Hub

The best Omarchy plugin for container monitoring: a clean bar panel for
watching and managing local containers without dropping to a terminal.

Container Hub is actively in development. Docker and Podman are both
supported: listing, status, ports, logs, start, stop, and remove all work
on either engine, with a one-click tab to switch between them. Next up is
final polish, performance work, and reliability optimizations.

## Preview

![Container Hub on the Omarchy desktop](docs/assets/container-hub-desktop.png?v=2)

![Container Hub popup](docs/assets/container-hub-popup.png?v=2)

## Features

- Docker and Podman side by side — a tab in the panel switches between
  them, both keep polling in the background so switching is instant
- Lists all containers (running and stopped) with status and ports
- Start / stop / remove containers with one click
- View recent logs inline, or (Docker only — no Podman equivalent exists
  yet) open the container in `lazydocker` for anything more involved
- Click a published port to open it in the browser
- Bar badge shows the running container count across both engines

## Install

```bash
omarchy plugin add https://github.com/Suman196pokhrel/container-hub.git --enable
```

This clones the plugin into `~/.config/omarchy/plugins/io.github.suman196pokhrel.container-hub`
and enables it on the bar. Say no to the enable prompt (or omit `--enable`)
to install without adding it to the bar yet — add it later with:

```bash
omarchy plugin enable io.github.suman196pokhrel.container-hub --section right
```

## Docker access

Container Hub talks to the Docker CLI, which talks to the Docker daemon
socket. **Daemon access is root-equivalent** — anything that can reach the
socket can run `docker run -v /:/host ...` and read/write the whole machine
as root. Omarchy does not put your user in the `docker` group by default for
exactly this reason; without it, this widget will show a "Docker access
needs setup" message with a button that opens the same guarded setup command
Omarchy already ships:

```bash
omarchy-setup-security-sudoless-docker
```

That command explains the trade-off and asks for confirmation before doing
anything — Container Hub never runs it, or any privileged command, on your
behalf. Prefer not to grant that? "Open in lazydocker" still works from the
same no-access state: Omarchy's `omarchy-launch-docker-tui` reaches the
socket through a one-off `pkexec` prompt instead.

Podman has no equivalent setup step: rootless Podman (the default) has no
daemon socket to guard, so its tab works immediately if Podman is
installed, with no group membership or privilege prompt involved at all.

## Configuration

Available via Omarchy's plugin settings UI, or directly in
`~/.config/omarchy/shell.json`:

| Setting | Default | Description |
|---|---|---|
| `refreshIntervalOpenSec` | 3 | Poll interval while the panel is open |
| `refreshIntervalClosedSec` | 15 | Poll interval while the panel is closed |
| `logTailLines` | 200 | Lines fetched when viewing logs |

## Removal

```bash
omarchy plugin remove io.github.suman196pokhrel.container-hub
```

See [`docs/design.md`](docs/design.md) for the full design.

## License

MIT
