# Roadmap

Status: **alpha**. The plugin does what the README says on the machine it was
written on. Nothing below that line is a promise yet.

---

## Alpha — `0.1.x` (now)

**What it is:** every feature in the README exists and has been used daily by one
person, on one monitor, with one set of templates.

**Contract:** none. Templates, IPC verbs and settings may change without notice.
If your workspaces look wrong, that is what this stage is for.

**Known gaps, stated plainly:**

- Multi-monitor is untested. Workspace creation always targets the focused
  output, and the plugin has only ever been exercised on `eDP-1`.
- A launch reports "Opened 3 apps" even when a `cmd` does not exist. The failure
  is logged, not shown.
- `templates.json` is written with a shell redirect. A crash mid-write can leave
  it truncated.
- Two `activate` calls in quick succession run two capture/spawn passes.
- Close is two-step, but there is no undo once the windows are gone.
- Workspace names do not survive an `niri` restart. Neither the plugin nor niri
  restores them; the emoji map in DMS settings then points at nothing.
- Window stills borrow the clipboard for ~50 ms per window. Correct, but it is a
  side effect on shared state and deserves a way to say "not now".
- No logic tests. CI checks syntax and manifests, not behaviour.

### Progress against beta (landed early)

- [x] **Launch pre-flight** — each app's command is resolved before spawning.
      `Opened 1 app for "JobApp" — not found: ghost` instead of a cheerful count.
- [x] **Crash-safe template writes** — write to `templates.json.tmp`, keep one
      `.bak`, then rename.
- [x] **Serialised launches** — a second `activate` during a launch reports
      `already launching` instead of racing over the clipboard and spawn queue.
- [x] **Emoji for workspaces** — a 36-emoji palette in every place an emoji is
      chosen (rename, session capture, template editor), plus the free-text field
      for anything else. Deliberately not a searchable thousand-emoji picker:
      naming a workspace is a two-second decision.
- [x] **One save flow** — the Templates pane used to carry its own name/emoji/Capture
      form beside the per-card Save…, so "save this workspace" existed twice with
      different capabilities. Now both entry points open the same review.

Remaining beta items: multi-monitor, undo for Close, restart story, stills
defaults, logic tests, compatibility matrix, registry listing.

---

## Beta — `0.2` → `0.9`

**The goal of beta:** a stranger can install this and not get burned. Not "more
features" — the trust surface.

Exit criteria, each one either met or explicitly deferred in the release notes:

1. **Multi-monitor correctness.** Create, name, focus, launch and close behave
   correctly for workspaces on a non-focused output. Tested with two outputs.
2. **Nothing fails silently.** Before spawning, check that each `cmd` resolves, and
   report per-app failures in the dash status strip instead of a cheerful count.
   A template with a typo'd binary is a visible error, not a no-op.
3. **Crash-safe template writes.** Write to a temp file and rename; keep one
   backup. Killing the shell mid-save must not cost the user their templates.
4. **One launch at a time.** Concurrent `activate` calls serialise instead of
   racing over the clipboard and the spawn queue.
5. **Undo for Close.** Closing a workspace keeps its window list and template
   snapshot for a short window so it can be reopened.
6. **A restart story.** Either names are re-applied from `templates.json` on shell
   start (opt-in), or the docs say clearly that they are lost. Silence is the one
   option that is not allowed.
7. **Stills are predictable.** Decide the default (likely off in beta), expose the
   cache TTL, and give a "not now" path so the clipboard borrow never surprises
   anyone.
8. **Logic tests in CI.** Template parsing, diff classification and app matching
   are pure functions; test them with Qt Quick Test offscreen, no compositor.
9. **Compatibility matrix.** Pinned minimum DMS and niri versions, CI linting
   against at least two DMS tags.
10. **Registry listing.** Entry merged, `dms plugins install workspaceManager`
    verified from a clean profile, screenshot and description in the registry.

Beta releases are tagged `v0.x.y-beta.N` and published as GitHub prereleases.

---

## 1.0

**The goal of 1.0:** freeze interfaces, not features.

- Template schema and IPC verbs frozen; changes follow a written deprecation
  policy (old form keeps working for one minor version).
- Logic coverage in CI; no untested parser left.
- No known data-loss path. Every destructive action is undoable or confirmed.
- Docs complete: install, upgrade, troubleshooting, template cookbook.
- Keyboard navigation works through the whole dash without a mouse.
- Registry listing maintained: changelog, issue template, screenshots up to date.

---

## How this grows (and how it does not)

Ranked by value per unit of annoyance, not by novelty:

| candidate | value | effort | verdict |
|---|---|---|---|
| Restore workspaces + optional launches on login | high — the thing people actually want after a reboot | medium | yes, in beta |
| Launch pre-flight and honest failure reporting | high — silent no-ops are the worst class of bug | small | yes, in beta |
| Per-output workspace profiles | medium — users with two monitors think in two sets | medium | yes, after beta items |
| Undo for Close | medium | small | yes, in beta |
| Import/export templates, share them | medium — templates are the community feature | small | yes, toward 1.0 |
| Hotkey snippets generated per template | low-medium — one click instead of copy-paste from docs | small | maybe |
| Workspace-scoped window rules (generate niri kdl from a template) | medium, but risks becoming a window-rule configurator | large | only if asked repeatedly |
| More bar widgets (per-template launcher buttons) | low — the launcher already does this | medium | no |
| A searchable thousand-emoji picker | low — a 36-emoji palette covers naming | small | shipped the palette instead |
| i18n | unknown demand | medium | not until asked |

**Explicit non-goals.** This is not a general app launcher (DMS has one), not a
window-rule manager (niri has one), and not a session/layout serializer for
floating windows. If a feature only makes sense for one person's setup, it belongs
in `templates.json`, not in the plugin.

---

## What would make me stop at 1.0

If the beta criteria land, further growth is mostly motion: the interesting
problems (window placement, app semantics, cache-and-clipboard trade-offs) are
solved, and the remaining work is taste. A plugin that does one job predictably is
worth more than one that does four things approximately.
