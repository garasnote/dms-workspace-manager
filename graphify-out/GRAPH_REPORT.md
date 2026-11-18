# Graph Report - workspaceManager  (2026-11-18)

## Corpus Check
- 23 files · ~24,098 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 4 file(s) not represented in the graph (top: (none) 3, .csv 1)

## Summary
- 327 nodes · 501 edges · 25 communities (17 shown, 8 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 21 edges (avg confidence: 0.94)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `52416ece`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Dash UI: workspace cards and actions
- Daemon core: workspace bookkeeping
- Window stills: capture cost and record
- CI workflow
- Release workflow
- Docs and publishing guide
- Plugin manifest
- A/B stills benchmark harness
- niri IPC transport and workspace verbs
- Logic tests (Qt Quick Test)
- Registry entry
- Workspace creation and template launch
- Pure logic: matching and launch planning
- Template persistence and status
- Window collection and previews
- Graph labelling script
- Rehome and workspace state helpers
- Duration sweep script
- Local and CI checks script
- App icon chip
- Launcher entry
- Mini-map layout math
- Settings pane
- Scrolling title label
- Emoji palette

## God Nodes (most connected - your core abstractions)
1. `launchTemplate()` - 17 edges
2. `publishLive()` - 14 edges
3. `niri()` - 13 edges
4. `Niri Workspace Manager` - 13 edges
5. `restoreWorkspaces()` - 12 edges
6. `createWorkspace()` - 12 edges
7. `niriAction()` - 10 edges
8. `activate()` - 10 edges
9. `publishStatus()` - 9 edges
10. `pumpRehome()` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Limitations, stated plainly` --references--> `niri()`  [INFERRED]
  bench/RESULTS.md → WorkspaceDaemon.qml
- `Undo, restore, share` --references--> `undoClose()`  [INFERRED]
  README.md → WorkspaceDaemon.qml
- `0. What the plugin needs before it is submittable` --references--> `name()`  [INFERRED]
  publish/PUBLISHING.md → WorkspaceDaemon.qml
- `2. Fork the registry and add the entry` --references--> `name()`  [INFERRED]
  publish/PUBLISHING.md → WorkspaceDaemon.qml
- `Round 2b — hold sweep and cache behaviour` --references--> `refreshLive()`  [INFERRED]
  bench/RESULTS.md → WorkspaceDaemon.qml

## Import Cycles
- None detected.

## Communities (25 total, 8 thin omitted)

### Community 0 - "WorkspaceDash.qml"
Cohesion: 0.09
Nodes (18): addDraftApp(), appMissing(), appName(), cancelEdit(), captureLive(), clone(), closeWorkspace(), focusWindow() (+10 more)

### Community 2 - "WorkspaceDaemon.qml"
Cohesion: 0.07
Nodes (4): basename(), emojiForWorkspace(), listText(), preflightApps()

### Community 3 - "plugin.json"
Cohesion: 0.09
Nodes (21): author, capabilities, components, daemon, dash, launcher, dash, icon (+13 more)

### Community 4 - "launchTemplate"
Cohesion: 0.22
Nodes (14): closeWorkspace(), focusByIndex(), focusByName(), focusWindowById(), forgetWorkspaceIcon(), moveWindowTo(), niri(), niriAction() (+6 more)

### Community 5 - "stills-ab.sh"
Cohesion: 0.29
Nodes (14): clip_sig(), cpu_ticks(), log(), panel_up_in_ms(), restart_shell(), restore(), rss_kb(), sample_once() (+6 more)

### Community 6 - "registry-entry.json"
Cohesion: 0.15
Nodes (12): author, capabilities, category, compositors, dependencies, description, distro, id (+4 more)

### Community 8 - "saveTemplateJson"
Cohesion: 0.29
Nodes (12): defaultTemplates(), deleteTemplate(), hotkeySnippets(), importTemplates(), loadTemplates(), publishLive(), publishStatus(), publishTemplates() (+4 more)

### Community 9 - "Window stills — A/B performance report"
Cohesion: 0.07
Nodes (26): Arms, Limitations, stated plainly, Results (median of 3), Round 2a — compact rows vs full previews, Round 2b — hold sweep and cache behaviour, What it means, Window stills — A/B performance report, Install (+18 more)

### Community 10 - "steps"
Cohesion: 0.08
Nodes (23): DUX_SHELL_DIR, GH_TOKEN, jobs, release, name, on, push, workflow_dispatch (+15 more)

### Community 11 - "steps"
Cohesion: 0.08
Nodes (24): runs-on, steps, strategy, DUX_SHELL_DIR, QML_IMPORT_DIR, jobs, checks, shell (+16 more)

### Community 12 - "stills-hold.sh"
Cohesion: 0.60
Nodes (3): cpu(), n_stills(), stills-hold.sh script

### Community 13 - "Niri Workspace Manager"
Cohesion: 0.10
Nodes (20): 0. What the plugin needs before it is submittable, 0b. Let CI gate the PR, 1. Create the public plugin repo, 2. Fork the registry and add the entry, 3. Validate, then open the PR, 4. After merge, Other routes, Publishing this plugin in the DMS plugin registry (+12 more)

### Community 15 - "createWorkspace"
Cohesion: 0.24
Nodes (13): applyWorkspaceIcon(), createWorkspace(), focusById(), focusedOutputName(), focusedOutputWorkspaces(), focusOutput(), lastWorkspaceIdx(), lastWorkspaceIdxFor() (+5 more)

### Community 20 - "ci.sh"
Cohesion: 0.70
Nodes (4): bad(), ok(), ci.sh script, step()

### Community 23 - "Logic.js"
Cohesion: 0.33
Nodes (11): appMatchesWindow(), basename(), keysForApp(), keysForWindow(), keysMatch(), lastSegment(), normalizeApp(), planLaunch() (+3 more)

### Community 25 - "pumpRehome"
Cohesion: 0.33
Nodes (6): appMatchesWindow(), keysForApp(), keysForWindow(), pumpRehome(), workspaceFocused(), workspaceNamed()

### Community 26 - "collectWindows"
Cohesion: 0.20
Nodes (11): collectWindows(), computeDiff(), currentWorkspaceName(), findWorkspaceByName(), focusedWorkspaceRecord(), publishDiffs(), step(), publishPreview() (+3 more)

## Knowledge Gaps
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Niri Workspace Manager` connect `Window stills — A/B performance report` to `Niri Workspace Manager`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `niri()` (e.g. with `Limitations, stated plainly` and `Alpha — `0.1.x` (now)`) actually correct?**
  _`niri()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `WorkspaceDash.qml` be split into smaller, more focused modules?**
  _Cohesion score 0.0855614973262032 - nodes in this community are weakly interconnected._
- **Why does `name()` connect `Niri Workspace Manager` to `WorkspaceDaemon.qml`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Should `WorkspaceDaemon.qml` be split into smaller, more focused modules?**
  _Cohesion score 0.07126436781609195 - nodes in this community are weakly interconnected._
- **Why does `activate()` connect `Niri Workspace Manager` to `WorkspaceDaemon.qml`, `collectWindows`, `launchTemplate`, `createWorkspace`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Should `plugin.json` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._