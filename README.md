# Niri Workspace Manager

[![ci](https://github.com/garasnote/dms-workspace-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/garasnote/dms-workspace-manager/actions/workflows/ci.yml)

A DMS (Dux Modular Shell) plugin for managing niri workspaces and launching
"app templates" (sets of apps) on demand.

It provides three surfaces in one plugin:

- **daemon** — all logic + the `workspaceManager` IPC target
- **dash tab** — the manager UI (`Mod+Ctrl+W`): templates, live workspaces,
  capture/confirm, edit
- **launcher** — type `ws` in the launcher to search workspaces/templates

## Install / enable

The plugin lives at `~/.config/dms/plugins/workspaceManager/`.

```bash
dms ipc call plugin-scan scan
dms ipc call plugins enable workspaceManager
```

(or Settings → Plugins → scan + toggle)

## The manager UI

`Mod+Ctrl+W` toggles the **Workspaces** dash tab.

**Templates pane**

- Each template shows its emoji + name, target workspace, app count, and a
  **Launch (N)** button where N is how many of its apps are *not* open yet.
  - `Launch` only starts what is missing — it never duplicates a workspace or
    an app that is already running there.
  - `All open` means nothing to do.
  - The ↻ button next to it re-runs **every** app in the template.
- **Edit** expands the template: emoji, name, target workspace, and every app
  as an editable row (label + command).
  - ✕ removes an app, **Add** appends one.
  - The bolt button toggles `alwaysLaunch` for that app: with it on, the app is
    started even when a matching window is already open (useful for "open
    another agent shell").
  - **Save template** writes `templates.json`.

**Capture / confirm (top card)**

1. Type a name (e.g. `JobApp`) and optionally an emoji (e.g. `🧳`).
2. **Capture** snapshots the focused workspace: every window plus its process
   command line.
3. Review the list, remove anything you do not want, then **Save template**.

Nothing is written until you press Save. Recapturing with an existing name
overwrites that template.

**The dash, visually**

- **Live is the main tab.** Every workspace gets its own card: emoji + name,
  output/index/window count, then a **mini-map of that workspace**, then its
  actions directly underneath the preview — Focus, Save…, Rename, Close.
- The mini-map is drawn from niri's own layout data (`pos_in_scrolling_layout`,
  `tile_size`), so columns keep their relative widths and each tile shows the
  app icon plus the window title. The focused window is ringed. It redraws on
  every niri window/workspace event.
- **Empty workspaces are hidden.** niri always keeps one empty workspace at the
  bottom of each monitor, plus whatever empties you scrolled past; only
  workspaces with windows, or with a name, are listed. The header shows
  "N empty hidden". Settings → *Show empty workspaces* brings them back.
- **Templates is the secondary tab**: the capture/confirm card lives there,
  along with each template's icon strip (full colour = open, dimmed + ring =
  would be launched), Launch/Relaunch, Edit and Delete.
- Tiles show the app icon and the window title; pixel-accurate screencopies are
  not implemented, because capturing toplevels needs a compositor/DMS capability
  that niri with DMS 2.x does not expose (`WindowCaptureService` /
  ext-toplevel capture). The mini-map is a live *layout* preview, not a video.

## Launching a template puts its apps on its workspace

`Launch` diffs the template against every window, then starts whatever is not on
the target workspace yet. What an app does when it is started a second time is
not knowable in advance, so nothing is assumed:

- **Zen** opens a new window, but it inherits the workspace of the browser it
  already belongs to, not the focused one.
- **KeePassXC** opens nothing and raises the window it already had.
- **Ghostty** always forks a new process and maps on the focused workspace.
- Chat clients, Steam, and most Electron apps may do any of the three.

So the launch is *spawn, then reconcile*: focus the workspace, start the apps,
then ~4 s later look at what actually appeared. A window created by this launch
that mapped on another workspace is moved onto the target, and an app that
produced no window at all while one of its windows exists elsewhere has that
window adopted instead. Either way the template's workspace ends up holding its
apps.

A template app can opt out of that guesswork with `"gather": true` (always move
an existing window, never start a second copy) or `"alwaysLaunch": true` (always
start, and never chase windows around). Settings → *Fix up windows after a
launch* turns the reconcile pass off entirely.

## CI

Two workflows, both inert until this repo has a remote:

| workflow | trigger | does |
|---|---|---|
| `.github/workflows/ci.yml` | every push, PRs | `./scripts/ci.sh` |
| `.github/workflows/release.yml` | tag `v*.*.*` | checks, packs the loadable files, attaches zip + SHA-256 to the release |

`scripts/ci.sh` is the same thing run locally, so the pipeline cannot rot into
YAML-only theatre:

```bash
DUX_SHELL_DIR=~/src/dux-shell ./scripts/ci.sh
```

What it checks:

- **QML parses** — `qmllint` against a real `dux-shell` checkout, because
  `import qs.*` has to resolve to something. It exits non-zero with *no*
  diagnostic for a syntax error, which is why the script reports the filename.
- **Manifests agree** — `plugin.json` fields present and semver, components point
  at files that exist, `publish/registry-entry.json` id/name/author/requires_dms
  match `plugin.json`, repo/screenshot URLs are well-shaped.
- **Settings contract** — every `settingKey` in `WorkspaceSettings.qml` carries a
  `defaultValue`; a setting without one silently reads `undefined` in the daemon.
- **Templates** — `templates.json` version 1, every template has a name and apps,
  every app has a `cmd`.
- **Shell scripts** — `shellcheck -S warning` over `bench/` and `scripts/`.
- **Hygiene** — no `console.log`, no `[wsm]` debug tags left behind, no tabs.
  (`console.warn`/`console.error` stay: the daemon uses them to report real
  failures such as an unparseable `templates.json`.)

What CI cannot check, deliberately: niri behaviour, the clipboard handoff, the
dash rendering, template launches. Those need a compositor and a running shell, so
they stay manual — that is what `bench/` and the scenarios in this README are for.
The registry's own validators (`validate_links.py`) check live URLs and therefore
belong in the publishing runbook, not here.

## Architecture record (graphify)

`graphify-out/` is a committed knowledge graph of this plugin — 217 nodes, 348
edges, 20 communities, built from the QML, the bench scripts and the docs:

| file | what it is |
|---|---|
| `graphify-out/graph.json` | the graph (GraphRAG-ready), nodes carry file + line numbers |
| `graphify-out/graph.html` | interactive view — open it in a browser |
| `graphify-out/GRAPH_REPORT.md` | communities, hubs, god nodes, freshness (built from commit) |

QML is not in graphify's extension map, so `.graphifyrc` maps `.qml` to the
JavaScript extractor. The declarative half of QML shows up as a parse warning and
costs nodes; every `function` and its call edges is extracted (97% EXTRACTED, 3%
INFERRED, all with line numbers).

```bash
graphify update .          # rebuild after code changes, no API key needed
graphify explain "launchTemplate()"
graphify query "how does a launch gather windows onto its workspace"
graphify god-nodes --top 10
```

Most connected nodes: `launchTemplate()` (15), `publishLive()` (11), `niri()` (11),
`computeDiff()` (10), `niriAction()` (9), `pumpRehome()` (9) — which is a fair
summary of where this plugin's complexity actually lives.

## Performance

`bench/` holds an A/B harness and a report. Measured cost of the stills feature,
8 windows, medians of 3:

| | stills off | stills on, cache warm | stills on, cold open |
|---|---:|---:|---:|
| peak shell RSS while open | 51.8 MB | 66.6 MB | 72.6 MB |
| RSS added by the open | +0.1 MB | +0.0 MB | +17.5 MB |
| dms CPU per open | 0.02 s | 0.02 s | 0.16 s |
| niri CPU per 8 s open | 1.42 s | 1.42 s | 2.60 s |
| clipboard not yours | 0 ms | 0 ms | 176 ms |
| background CPU, panel shut | 0.25% core | 0.25% core | 0.25% core |

Compact rows vs full previews: identical shell CPU, niri ~15% lower while the panel
is open (fewer tiles to paint), memory within noise — collapsing rows is a layout
feature, not a performance one. A five-minute open panel captures nothing after the
first batch; the cache produces exactly one fresh batch once the 10-minute TTL
expires.

Background CPU is the shell's own baseline, identical with the feature on or off —
an earlier draft claimed "exactly 0" because of a harness bug that shellcheck caught.

Read `bench/RESULTS.md` for the method and the caveats — chiefly that the cold
arm's 389 ms panel-open latency is the dash tab's QML first-load, not captures
(the stills-off arm shows the same 430 ms on its first open after a restart).

## Clicking a tile focuses that window

Every window in a mini-map is a target: hover it and a ring appears, click it and
niri focuses that window — switching workspace if it lives on another one — while
the panel dismisses itself. Same path as everything else:

```bash
dms ipc call workspaceManager focusWindow 54
```

Empty tiles (a workspace with no windows, or a column gap) ignore clicks.

## Window stills

The mini-map tiles can show real pictures of each window instead of only the app
icon (Settings → *Window stills*, on by default).

They are *pulls*, not a stream. Nothing is captured while the panel is closed;
opening it asks for stills of any window without one newer than 10 minutes, one
window at a time (~60 ms each), and the tile fills in as they arrive. Files live
in `/tmp/wsm-stills`, decoded at tile size, and are pruned after 15 minutes.

niri's `screenshot-window --id` is the only way to get one window's pixels, and
it always also copies the screenshot to the clipboard — there is no flag to stop
it, and the coordinates needed to crop `grim` output are not published for tiled
windows (upstream niri issue #2381, closed as expected: keeping per-tile view
positions correct would mean updating every window to the right on each resize).
So each capture saves the clipboard first and restores it straight after, within
about 60 ms. Two consequences worth knowing:

- niri posts its usual "Screenshot captured" notification while a batch runs. It
  replaces itself, so you see one toast, not one per window.
- Only one mime type is restored, so a rich HTML/subset copy degrades to plain
  text. Text and images survive intact.

Turn it off and the tiles fall back to icons, with no clipboard involvement at
all.

**Compact rows** (setting, off by default): each workspace collapses to a single
line — emoji, name, output/index/window count, app chips and a chevron — so four
or five workspaces fit where two previews did. Click a row to open its preview
and actions.

**Live actions in detail**

- **Focus** — switch to that workspace.
- **Save…** — hand the workspace to the capture card in the Templates tab.
- **Rename** — set the niri workspace name and its emoji glyph (shown in the bar
  indicator); "Done" closes the editor.
- **Close** — asks first, then either *Close + N windows* (closes every window
  and removes the name, so the workspace is gone) or *Unname only* (keeps the
  windows, drops the name).

## Workspace indicator (top-left)

When a template's workspace is created or renamed, the plugin:

1. names the niri workspace (e.g. `JobApp`), and
2. registers its emoji as the workspace-name icon, so the bar shows the glyph.

Names are shown next to the glyph too (the plugin switched the bar widget's
"Names" option on):

```bash
dms ipc call workspaceManager showNames true|false
dms ipc call workspaceManager syncIcons   # re-apply emoji from templates.json
```

## IPC commands (keybinds / scripts)

```bash
dms ipc call workspaceManager <fn> [args]
```

| Command | Effect |
|---------|--------|
| `create "<name>"` | Create and focus a new workspace; names it when a name is given. |
| `activate "<name-or-index>"` | Focus a named workspace (by name or index), or launch the matching template. |
| `launch "<template>"` | Diff-aware launch: opens only the apps missing on the target workspace. |
| `launchAll "<template>"` | Re-runs every app in the template. |
| `diff "<template>"` | Recompute and publish the diff (shown as status text). |
| `previewRecord "<name>" "<emoji>"` | Snapshot the focused workspace into the capture card. |
| `previewWorkspace "<id>" "<name>" "<emoji>"` | Snapshot any workspace by id. |
| `saveTemplate '<json>'` | Create/update a template. Payload: `{originalName, template}`. |
| `deleteTemplate "<name>"` | Remove a template. |
| `record "<name>"` | Alias for `previewRecord` (capture without saving). |
| `name "<name>" "<emoji>"` | Rename the focused workspace + set its glyph. |
| `rename "<id>" "<name>" "<emoji>"` | Rename a workspace by id. |
| `closeWorkspace "<id>" "true\|false"` | Close a workspace: `true` also closes its windows, `false` only removes the name (windows stay). Named and empty workspaces disappear; unnamed ones only go when their windows are closed. |
| `forgetIcon "<name>"` | Remove a workspace-name icon (glyph) entry. |
| `focusId "<id>"` | Focus a workspace by niri id. |
| `syncIcons` | Re-apply template emoji to their workspaces. |
| `showNames "true\|false"` | Toggle the bar widget's workspace "Names" option. |
| `refreshLive` | Re-publish the live workspace list + diffs. |
| `reload` | Re-read `templates.json`. |
| `list` | Human-readable workspaces + templates. |
| `state` | JSON of templates, live workspaces, diffs, preview and status. |

## niri keybindings

In `~/.config/niri/config.kdl`:

```kdl
binds {
    Mod+Ctrl+N { spawn "dms" "ipc" "call" "workspaceManager" "create" ""; }
    Mod+Ctrl+D { spawn "dms" "ipc" "call" "workspaceManager" "activate" "Dev Work"; }
    Mod+Ctrl+G { spawn "dms" "ipc" "call" "workspaceManager" "activate" "Gaming"; }
    Mod+Ctrl+Z { spawn "dms" "ipc" "call" "workspaceManager" "activate" "Chill"; }
    Mod+Ctrl+J { spawn "dms" "ipc" "call" "workspaceManager" "activate" "JobApp"; }
    Mod+Ctrl+W { spawn "dms" "ipc" "call" "dash" "toggle" "plugin_workspaceManager"; }
}
```

These are already in this machine's `config.kdl`.

## Templates

`templates.json` is the source of truth:

```json
{
  "version": 1,
  "templates": [
    {
      "name": "JobApp",
      "emoji": "🧳",
      "workspace": "JobApp",
      "notes": "Job applications: Zen, KeePassXC, and herdr inside a terminal.",
      "apps": [
        { "name": "Zen Browser", "cmd": "/opt/zen-browser-bin/zen-bin", "appId": "zen" },
        { "name": "KeePassXC", "cmd": "keepassxc", "appId": "org.keepassxc.KeePassXC" },
        { "name": "herdr", "cmd": "ghostty -e herdr", "appId": "com.mitchellh.ghostty" }
      ]
    }
  ]
}
```

Fields:

- `name` — unique template name.
- `emoji` — glyph for the bar's workspace indicator.
- `workspace` — niri workspace to create/focus before launching. Empty means
  "current workspace".
- `notes` — human-only.
- `apps` — string (`"keepassxc"`) or object:
  - `cmd` — shell command (wrappers work: `mangohud %command%`, env vars, ...).
  - `name` — display label.
  - `appId` — niri `app_id` hint for matching (e.g. `zen`).
  - `alwaysLaunch` — always start this app, even if a match is open.

Apps are spawned through niri, so windows land on the focused workspace.

## How the diff works

For the target workspace the plugin lists its windows, reads each window's
`/proc/<pid>/cmdline`, and matches every template app against them by:

- the template `appId` and its last dotted segment (`org.keepassxc.KeePassXC` →
  `keepassxc`),
- the basename of each token in `cmd` (`/opt/zen-browser-bin/zen-bin` → `zen-bin`,
  `ghostty -e herdr` → `ghostty`, `herdr`),

using equality or a prefix/substring match with a 3-character floor, so `zen`
matches `zen-bin`. Apps that find no match are "missing" and get launched; the
rest are left alone. `alwaysLaunch` apps always count as missing.

Not perfect for apps that share a binary (two Ghostty windows both look like
`ghostty`), which is what the bolt toggle is for.

## Closing workspaces

niri has no "delete workspace" verb. A workspace disappears when it is empty and
unnamed, so closing one means:

1. close its windows (optional), then
2. unset its name (`unset-workspace-name`), which also clears its emoji entry.

`dms ipc call workspaceManager closeWorkspace <id> true`

Named workspaces persist while empty, which is why `Gaming` and `Chill` stay in
the bar with no windows; close them from the Live pane when you want them gone.

## Capturing a session

The capture reads the *process* command line, so a terminal running something
inside it is captured as the terminal (e.g. `ghostty`, not
`ghostty -e herdr`). Edit the command in the template afterwards if you want the
inner program re-launched.

## Notes on the examples

- `zeditor` is the Zed binary here (`dev.zed.Zed.desktop` → `Exec=zeditor %U`).
- Zen Browser: `/opt/zen-browser-bin/zen-bin` (also on PATH as `zen-browser`).
- `hermes-agent` needs a TTY, so it is launched as `ghostty -e hermes-agent`;
  a bare `hermes-agent` spawn fails silently. That is why "Dev Work" only
  opened Zed + GitComet before.
- `herdr` runs as `ghostty -e herdr` (its server daemon runs separately).
- MangoHUD is a wrapper (`mangohud %command%`), not a launcher; `focusgame`
  (background-app suspension) is not installed, so both live in the Gaming
  template's `notes`.

## License

MIT — same license as DMS itself. Use it, change it, ship it; keep the copyright
notice and the warranty disclaimer with it.
