# Niri Workspace Manager

A DMS (Dux Modular Shell) plugin for managing niri workspaces and launching
"app templates" (sets of apps) on demand.

It provides three surfaces in one plugin:

- **daemon** — all logic + the `workspaceManager` IPC target
- **dash tab** — a "Workspaces" tab in the dash (list, focus, create, launch, record)
- **launcher** — type `ws` in the launcher to search workspaces/templates

## Install / enable

The plugin already lives at `~/.config/dms/plugins/workspaceManager/`.

1. Rescan plugins:
   ```bash
   dms ipc call plugin-scan scan
   ```
2. Enable it:
   ```bash
   dms ipc call plugins enable workspaceManager
   ```
   (Or use Settings → Plugins → scan + toggle.)

## IPC commands (for keybinds / scripts)

Every action is a `dms ipc call workspaceManager <fn> [arg]`:

| Command | Effect |
|---------|--------|
| `create "<name>"` | Create and focus a new workspace on the focused monitor. If a name is given, the workspace is named (persistent). Pass `""` for an unnamed workspace. |
| `activate "<name-or-index>"` | Focus a named workspace by name, an unnamed one by index (`"2"`), or launch the template with that name. |
| `launch "<template>"` | Launch every app in a template, on its named workspace (if any). |
| `record "<name>"` | Snapshot the focused workspace's windows into a template (saved to `templates.json`). |
| `focusId "<id>"` | Focus a workspace by its niri id (used by the dash; unambiguous across outputs). |
| `reload` | Re-read `templates.json`. |
| `list` | Print workspaces and templates. |

## niri keybindings

Add these to your niri config (e.g. `~/.config/niri/config.kdl` or the DMS
keybind editor). The format is niri's `spawn "cmd" "arg"...`:

```kdl
binds {
    // Create a fresh (unnamed) workspace and focus it
    Mod+Ctrl+N { spawn "dms" "ipc" "call" "workspaceManager" "create" ""; }

    // Jump to a named workspace (or create it and launch its template if it doesn't exist)
    Mod+Ctrl+D { spawn "dms" "ipc" "call" "workspaceManager" "activate" "Dev Work"; }
    Mod+Ctrl+G { spawn "dms" "ipc" "call" "workspaceManager" "activate" "Gaming"; }
    Mod+Ctrl+Z { spawn "dms" "ipc" "call" "workspaceManager" "activate" "Chill"; }

    // Open the Workspaces dash tab
    Mod+Ctrl+W { spawn "dms" "ipc" "call" "dash" "open" "plugin_workspaceManager"; }
}
```

These exact bindings have been added to `~/.config/niri/config.kdl`.

## Templates

Templates live in `templates.json` next to this README:

```json
{
  "version": 1,
  "templates": [
    {
      "name": "Dev Work",
      "workspace": "Dev Work",
      "notes": "Zed + GitComet + Hermes agent shell.",
      "apps": ["zeditor", "gitcomet", "hermes-agent"]
    }
  ]
}
```

Fields:

- `name` — unique template name (used by `activate`/`launch`/`record`).
- `workspace` — optional niri workspace name. When set and the
  "Launch templates into their named workspace" setting is on, launching
  creates/focuses that workspace first. Leave empty to launch on the current
  workspace.
- `notes` — optional, shown only for humans.
- `apps` — list of commands to run, in order. Each entry is a shell command
  string (so `mangohud gamemoderun ...`, env vars, etc. work). Apps are
  spawned through niri (`niri msg action spawn-sh`), so windows land on the
  focused workspace.

Edit the file, then run `dms ipc call workspaceManager reload` (or press
Reload in Settings).

## Recording a session

Focus a workspace, then either:

- dash → Workspaces → "Record current session as…", or
- `dms ipc call workspaceManager record "My Snapshot"`

The plugin reads `/proc/<pid>/cmdline` for every window on the focused
workspace and stores the resulting commands as a template, so relaunching
recreates roughly the same session. Flatpak/snap apps may need manual tweaks
(the captured command is the raw process argv).

## Notes on the examples

- `zeditor` is the Zed editor binary installed here (desktop file
  `dev.zed.Zed.desktop` → `Exec=zeditor %U`).
- Zen Browser runs from `/opt/zen-browser-bin/zen-bin` on this machine;
  `zen-browser` is also on PATH if you prefer.
- `hermes-agent` is the Hermes agent shell binary in `~/.local/bin`.
- MangoHUD is not a launcher; it wraps a game command
  (`mangohud %command%`). The Gaming template notes cover this.
- `focusgame` (background-process suspension) is not installed here, so it is
  left out of the auto-launch list and mentioned in `notes` instead.
