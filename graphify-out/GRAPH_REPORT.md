# Graph Report - workspaceManager  (2026-11-14)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 217 nodes · 348 edges · 20 communities (14 shown, 6 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 10 edges (avg confidence: 0.94)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1d6fdb2a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- WorkspaceDash.qml
- Niri Workspace Manager
- WorkspaceDaemon.qml
- plugin.json
- launchTemplate
- stills-ab.sh
- registry-entry.json
- computeDiff
- saveTemplateJson
- Window stills — A/B performance report
- IPC commands (keybinds / scripts)
- publishLive
- stills-hold.sh
- focusedWorkspaceRecord
- AppChip.qml
- pumpStills
- WorkspacePreview.qml

## God Nodes (most connected - your core abstractions)
1. `Niri Workspace Manager` - 16 edges
2. `launchTemplate()` - 15 edges
3. `publishLive()` - 11 edges
4. `niri()` - 11 edges
5. `computeDiff()` - 10 edges
6. `send()` - 9 edges
7. `niriAction()` - 9 edges
8. `pumpRehome()` - 9 edges
9. `sample_once()` - 9 edges
10. `createWorkspace()` - 8 edges

## Surprising Connections (you probably didn't know these)
- `Limitations, stated plainly` --references--> `niri()`  [INFERRED]
  bench/RESULTS.md → WorkspaceDaemon.qml
- `0. What the plugin needs before it is submittable` --references--> `name()`  [INFERRED]
  publish/PUBLISHING.md → WorkspaceDaemon.qml
- `2. Fork the registry and add the entry` --references--> `name()`  [INFERRED]
  publish/PUBLISHING.md → WorkspaceDaemon.qml
- `IPC commands (keybinds / scripts)` --references--> `previewRecord()`  [INFERRED]
  README.md → WorkspaceDaemon.qml
- `IPC commands (keybinds / scripts)` --references--> `refreshLive()`  [INFERRED]
  README.md → WorkspaceDaemon.qml

## Import Cycles
- None detected.

## Communities (20 total, 6 thin omitted)

### Community 0 - "WorkspaceDash.qml"
Cohesion: 0.09
Nodes (18): addDraftApp(), appMissing(), appName(), cancelEdit(), captureLive(), clone(), closeWorkspace(), focusWindow() (+10 more)

### Community 1 - "Niri Workspace Manager"
Cohesion: 0.08
Nodes (23): 0. What the plugin needs before it is submittable, 1. Create the public plugin repo, 2. Fork the registry and add the entry, 3. Validate, then open the PR, 4. After merge, Other routes, Publishing this plugin in the DMS plugin registry, Capturing a session (+15 more)

### Community 3 - "plugin.json"
Cohesion: 0.09
Nodes (21): author, capabilities, components, daemon, dash, launcher, dash, icon (+13 more)

### Community 4 - "launchTemplate"
Cohesion: 0.17
Nodes (22): activate(), applyWorkspaceIcon(), createWorkspace(), findTemplateByName(), findWorkspaceByName(), focusByIndex(), focusByName(), focusWindowById() (+14 more)

### Community 5 - "stills-ab.sh"
Cohesion: 0.29
Nodes (14): clip_sig(), cpu_ticks(), log(), panel_up_in_ms(), restart_shell(), restore(), rss_kb(), sample_once() (+6 more)

### Community 6 - "registry-entry.json"
Cohesion: 0.15
Nodes (12): author, capabilities, category, compositors, dependencies, description, distro, id (+4 more)

### Community 7 - "computeDiff"
Cohesion: 0.26
Nodes (12): appMatchesWindow(), basename(), collectWindows(), computeDiff(), keysForApp(), keysForWindow(), keysMatch(), lastSegment() (+4 more)

### Community 8 - "saveTemplateJson"
Cohesion: 0.27
Nodes (10): closeWorkspace(), defaultTemplates(), deleteTemplate(), forgetWorkspaceIcon(), loadTemplates(), publishStatus(), publishTemplates(), saveTemplateJson() (+2 more)

### Community 9 - "Window stills — A/B performance report"
Cohesion: 0.29
Nodes (6): Arms, Limitations, stated plainly, Repeat-open check (is the retained RSS a leak?), Results (median of 3), What it means, Window stills — A/B performance report

### Community 10 - "IPC commands (keybinds / scripts)"
Cohesion: 0.33
Nodes (6): IPC commands (keybinds / scripts), previewRecord(), refreshLive(), reload(), state(), syncIcons()

### Community 11 - "publishLive"
Cohesion: 0.33
Nodes (6): emojiForWorkspace(), listText(), publishDiffs(), step(), publishLive(), stillUri()

### Community 12 - "stills-hold.sh"
Cohesion: 0.60
Nodes (3): cpu(), n_stills(), stills-hold.sh script

### Community 13 - "focusedWorkspaceRecord"
Cohesion: 0.50
Nodes (4): currentWorkspaceName(), focusedWorkspaceRecord(), publishPreview(), windowLabel()

### Community 15 - "pumpStills"
Cohesion: 0.67
Nodes (3): pullStills(), pumpStills(), stillScript()

## Knowledge Gaps
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Niri Workspace Manager` connect `Niri Workspace Manager` to `IPC commands (keybinds / scripts)`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Should `WorkspaceDash.qml` be split into smaller, more focused modules?**
  _Cohesion score 0.09274193548387097 - nodes in this community are weakly interconnected._
- **Why does `name()` connect `Niri Workspace Manager` to `WorkspaceDaemon.qml`?**
  _High betweenness centrality (0.051) - this node is a cross-community bridge._
- **Should `Niri Workspace Manager` be split into smaller, more focused modules?**
  _Cohesion score 0.08333333333333333 - nodes in this community are weakly interconnected._
- **Why does `IPC commands (keybinds / scripts)` connect `IPC commands (keybinds / scripts)` to `Niri Workspace Manager`?**
  _High betweenness centrality (0.050) - this node is a cross-community bridge._
- **Should `WorkspaceDaemon.qml` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._
- **Should `plugin.json` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._