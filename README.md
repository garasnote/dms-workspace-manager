# Niri Workspace Manager

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

**Live pane**

- Every workspace with its emoji, output, index, window count and app list.
- **Focus**, **Save…** (sends that workspace to the capture card) and
  **Rename** (sets the niri workspace name + emoji glyph in the bar indicator).

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
