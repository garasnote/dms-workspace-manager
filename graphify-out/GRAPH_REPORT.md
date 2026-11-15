# Graph Report - workspaceManager  (2026-11-15)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 276 nodes · 414 edges · 22 communities (16 shown, 6 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 16 edges (avg confidence: 0.94)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b2718dc7`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- WorkspaceDash.qml
- Publishing this plugin in the DMS plugin registry
- WorkspaceDaemon.qml
- plugin.json
- launchTemplate
- stills-ab.sh
- registry-entry.json
- computeDiff
- saveTemplateJson
- Window stills — A/B performance report
- steps
- steps
- stills-hold.sh
- Niri Workspace Manager
- AppChip.qml
- launchTemplate
- WorkspacePreview.qml
- ci.sh

## God Nodes (most connected - your core abstractions)
1. `launchTemplate()` - 16 edges
2. `niri()` - 12 edges
3. `Niri Workspace Manager` - 12 edges
4. `publishLive()` - 11 edges
5. `activate()` - 10 edges
6. `computeDiff()` - 10 edges
7. `send()` - 9 edges
8. `niriAction()` - 9 edges
9. `pumpRehome()` - 9 edges
10. `sample_once()` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Limitations, stated plainly` --references--> `niri()`  [INFERRED]
  bench/RESULTS.md → WorkspaceDaemon.qml
- `0. What the plugin needs before it is submittable` --references--> `name()`  [INFERRED]
  publish/PUBLISHING.md → WorkspaceDaemon.qml
- `2. Fork the registry and add the entry` --references--> `name()`  [INFERRED]
  publish/PUBLISHING.md → WorkspaceDaemon.qml
- `Beta — `0.2` → `0.9`` --references--> `activate()`  [INFERRED]
  ROADMAP.md → WorkspaceDaemon.qml
- `Round 2b — hold sweep and cache behaviour` --references--> `refreshLive()`  [INFERRED]
  bench/RESULTS.md → WorkspaceDaemon.qml

## Import Cycles
- None detected.

## Communities (22 total, 6 thin omitted)

### Community 0 - "WorkspaceDash.qml"
Cohesion: 0.09
Nodes (18): addDraftApp(), appMissing(), appName(), cancelEdit(), captureLive(), clone(), closeWorkspace(), focusWindow() (+10 more)

### Community 1 - "Publishing this plugin in the DMS plugin registry"
Cohesion: 0.22
Nodes (9): 0. What the plugin needs before it is submittable, 0b. Let CI gate the PR, 1. Create the public plugin repo, 2. Fork the registry and add the entry, 3. Validate, then open the PR, 4. After merge, Other routes, Publishing this plugin in the DMS plugin registry (+1 more)

### Community 2 - "WorkspaceDaemon.qml"
Cohesion: 0.08
Nodes (6): currentWorkspaceName(), emojiForWorkspace(), focusedWorkspaceRecord(), listText(), publishPreview(), windowLabel()

### Community 3 - "plugin.json"
Cohesion: 0.09
Nodes (21): author, capabilities, components, daemon, dash, launcher, dash, icon (+13 more)

### Community 4 - "launchTemplate"
Cohesion: 0.22
Nodes (14): applyWorkspaceIcon(), closeWorkspace(), focusByIndex(), focusWindowById(), forgetWorkspaceIcon(), moveWindowTo(), niri(), niriAction() (+6 more)

### Community 5 - "stills-ab.sh"
Cohesion: 0.29
Nodes (14): clip_sig(), cpu_ticks(), log(), panel_up_in_ms(), restart_shell(), restore(), rss_kb(), sample_once() (+6 more)

### Community 6 - "registry-entry.json"
Cohesion: 0.15
Nodes (12): author, capabilities, category, compositors, dependencies, description, distro, id (+4 more)

### Community 7 - "computeDiff"
Cohesion: 0.20
Nodes (15): appMatchesWindow(), basename(), collectWindows(), computeDiff(), findWorkspaceByName(), keysForApp(), keysForWindow(), keysMatch() (+7 more)

### Community 8 - "saveTemplateJson"
Cohesion: 0.25
Nodes (11): defaultTemplates(), deleteTemplate(), loadTemplates(), publishDiffs(), step(), publishLive(), publishStatus(), publishTemplates() (+3 more)

### Community 9 - "Window stills — A/B performance report"
Cohesion: 0.12
Nodes (15): Arms, Limitations, stated plainly, Results (median of 3), Round 2a — compact rows vs full previews, Round 2b — hold sweep and cache behaviour, What it means, Window stills — A/B performance report, IPC (+7 more)

### Community 10 - "steps"
Cohesion: 0.08
Nodes (23): DUX_SHELL_DIR, GH_TOKEN, jobs, release, name, on, push, workflow_dispatch (+15 more)

### Community 11 - "steps"
Cohesion: 0.10
Nodes (20): runs-on, steps, DUX_SHELL_DIR, QML_IMPORT_DIR, jobs, checks, name, on (+12 more)

### Community 12 - "stills-hold.sh"
Cohesion: 0.60
Nodes (3): cpu(), n_stills(), stills-hold.sh script

### Community 13 - "Niri Workspace Manager"
Cohesion: 0.11
Nodes (17): Install, License, Niri Workspace Manager, Quick start, Roadmap, Settings, Templates, The dash (+9 more)

### Community 15 - "launchTemplate"
Cohesion: 0.22
Nodes (13): Alpha — `0.1.x` (now), Progress against beta (landed early), activate(), createWorkspace(), findTemplateByName(), focusByName(), focusedOutputWorkspaces(), lastWorkspaceIdx() (+5 more)

### Community 20 - "ci.sh"
Cohesion: 0.70
Nodes (4): bad(), ok(), ci.sh script, step()

## Knowledge Gaps
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `name()` connect `Publishing this plugin in the DMS plugin registry` to `WorkspaceDaemon.qml`, `Niri Workspace Manager`?**
  _High betweenness centrality (0.033) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `niri()` (e.g. with `Limitations, stated plainly` and `Alpha — `0.1.x` (now)`) actually correct?**
  _`niri()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `WorkspaceDash.qml` be split into smaller, more focused modules?**
  _Cohesion score 0.09274193548387097 - nodes in this community are weakly interconnected._
- **Why does `Niri Workspace Manager` connect `Niri Workspace Manager` to `Window stills — A/B performance report`?**
  _High betweenness centrality (0.032) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `activate()` (e.g. with `Templates` and `Alpha — `0.1.x` (now)`) actually correct?**
  _`activate()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `WorkspaceDaemon.qml` be split into smaller, more focused modules?**
  _Cohesion score 0.082010582010582 - nodes in this community are weakly interconnected._
- **Why does `activate()` connect `launchTemplate` to `WorkspaceDaemon.qml`, `launchTemplate`, `Niri Workspace Manager`, `computeDiff`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._