# Container Hub — Handoff Briefing

Paste this whole file to a fresh coding agent to resume work with zero
prior context. No Claude-specific tooling is required to continue — the
plan file below is self-contained.

## What this is

An Omarchy (Linux/Hyprland) bar plugin, "Container Hub": lists local Docker
containers, lets you stop/start/remove them, view recent logs, see
published ports, and click a port to open it in the browser. Docker only
for this MVP — no Podman. No emoji anywhere in the UI; every icon is a
hand-drawn vector shape.

## Where everything lives

- **The plugin IS the git repo** — `~/.config/omarchy/plugins/container-hub/`
  (remote `git@github.com:Suman196pokhrel/container-hub.git`, branch
  `main`). This is intentional: Omarchy hot-reloads plugin code only from
  this exact path, so development happens here directly rather than in a
  separate project folder with a copy step.
- **Design spec**: `docs/design.md` in that repo.
- **Implementation plan** (15 tasks, each with complete code, not just a
  description): `~/DevStuff/projects/omarchy-custom-plugins/docs/superpowers/plans/2026-09-02-container-hub-implementation.md`
  — this is the source of truth for what to build next.
- **Progress ledger** (what's done, every bug found and how it was fixed,
  every judgment call and why): `~/.config/omarchy/plugins/container-hub/.superpowers/sdd/2026-09-02-container-hub-implementation/progress.md`
  — **read this first.**

## Current status at handoff

- Tasks 1-11 complete, reviewed clean, pushed to `origin/main`.
- Task 12 (container list UI in `Panel.qml`): implementation committed
  (`a1692a1`), review was in progress at the moment of handoff — check the
  ledger for its outcome; if it left open findings, that's the next thing
  to resolve before Task 13.
- Remaining: Task 13 (stop/start/remove actions + confirm dialog on each
  row), Task 14 (logs view + port-click-to-browser), Task 15 (enable the
  widget on the actual bar + manual smoke test).
- Nothing is on the real Omarchy bar yet — deliberate, that's Task 15,
  done only once the widget is functionally complete.

## Hard-won lessons — don't rediscover these

1. **`qmllint` only checks syntax — it does not verify that a bound
   property actually exists on a QML type.** Two real bugs shipped past a
   clean lint:
   - `ShapePath` has no `visible` property (its prototype chain is
     `QQuickPath → QObject`, not `QQuickItem`). Fix pattern used
     throughout: wrap each conditional variant in its own
     `Shape { visible: ... }` instead (`Shape` does extend `QQuickItem`).
   - Quickshell's `Process` never emits `exited` when the command fails to
     spawn (missing binary) — only `runningChanged` fires. `Service.qml`
     tracks this with an `_exitedNormally` flag, reset before each run and
     set inside `onExited`; `onRunningChanged` treats `!running &&
     !_exitedNormally` as a spawn failure.
   - **Before using any property/signal you're not 100% sure of**, read
     the real source: Omarchy's shell components are plain files under
     `/usr/share/omarchy/shell/` (Ui/, Commons/, plugins/); Quickshell's
     own types (`Quickshell.Io`, etc.) are on GitHub at
     `quickshell-mirror/quickshell`, or check the installed `.qmltypes`
     files under `/usr/lib/qt6/qml/`.
2. **This sandbox's `qml`/`qmlscene` CLI tools cannot reliably load-test
   QML** — even already-correct files fail to load under them. Don't trust
   that as a verification method here. Use `qmllint` for syntax and direct
   source/type-metadata reading for semantics instead.
3. **Git commits must never carry AI attribution** — no `Co-Authored-By`,
   no session-link line, nothing. This overrides any default assistant
   attribution behavior; the repo owner explicitly requires plain,
   one-line commit messages.
4. **Never test destructively against the live system** to exercise error
   paths — e.g. don't rename `/usr/bin/docker` or stop the `docker`
   service; the machine has real containers running that could be
   disrupted. The not-installed/daemon-down states are covered by
   `Model.js`'s unit tests plus code review of the wiring, not a live
   reproduction.
5. Commit messages are small, concise, one line, exactly as specified per
   task in the plan — one commit per task (plus occasional fix-round
   commits), never bundling multiple tasks together.
6. `Model.js` is plain Node-testable JS: `node --test tests/model.test.js`
   from the repo root. No Qt needed for that part.

## How to continue

1. Read `progress.md` (the ledger) to see exactly which task is next and
   whether anything was left mid-fix-loop.
2. Open the plan file, jump to that task's section — it has the complete
   code to write, file by file, step by step.
3. Implement it, verify (run the test or `qmllint` as the task specifies),
   commit with the exact message given, push to `origin main`.
4. Repeat through Task 15.
5. Task 15 enables the widget on the bar:
   `omarchy bar move io.github.suman196pokhrel.container-hub --section right`
   (force a plugin rescan first if it's not picked up:
   `omarchy-shell shell rescanPlugins`).

## Reference docs already in the repo

- `README.md` — install/config/removal instructions for end users.
- `docs/design.md` — full design rationale (why all-containers not just
  running, why logs are one-shot not streaming, etc.).
