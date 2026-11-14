import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Niri Workspace Manager - daemon surface.
//
// Owns all logic and registers the `workspaceManager` IPC target so every
// action is reachable from a terminal or a niri keybind:
//
//   dms ipc call workspaceManager create "Dev Work"
//   dms ipc call workspaceManager launch "Gaming"
//   dms ipc call workspaceManager record "My Snapshot"
//   dms ipc call workspaceManager list
//
// Structured results (live workspaces, record preview, per-template diffs) are
// published as plugin global vars so the dash surface can render them
// reactively without parsing IPC stdout.

PluginComponent {
    id: root

    property var popoutService: null
    property var templates: []
    property string templatesPath: ""
    property var _cmdlineCache: ({})

    // ------------------------------------------------------------- window stills
    //
    // niri's screenshot verb is the only way to get one window's pixels, and it
    // always also copies them to the clipboard (no flag turns that off). So each
    // pull: save the clipboard, screenshot one window, read the PNG back off the
    // clipboard, restore. Measured ~60 ms and ~120 KB per window; nothing here
    // runs unless the panel is open and the setting is on.
    property string stillsDir: "/tmp/wsm-stills"
    property var stills: ({})           // windowId -> { path, ts }
    property var _stillQueue: []
    property bool _stillBusy: false
    property int _stillSeq: 0
    property int _stillActive: 0

    // Let the panel paint before forking a shell per window; captures compete with
    // the first frame otherwise, even though the measured open latency is dominated
    // by the tab's QML load on the first open after a shell restart.
    Timer {
        id: stillKickTimer
        interval: 350
        onTriggered: root.pullStills(false)
    }

    // One publish per burst of captures, so the cards are not rebuilt per window.
    Timer {
        id: stillPublishTimer
        interval: 250
        onTriggered: root.publishLive()
    }

    // Refresh cooldown so a burst of niri window events is one publish.
    Timer {
        id: liveRefreshTimer
        interval: 250
        onTriggered: root.publishLive()
    }

    Connections {
        target: NiriService
        function onWindowsChanged() {
            liveRefreshTimer.restart();
        }
        function onWorkspacesChanged() {
            liveRefreshTimer.restart();
        }
    }

    Component.onCompleted: {
        templatesPath = (pluginService && pluginService.getPluginPath)
            ? pluginService.getPluginPath(pluginId) + "/templates.json" : "";
        loadTemplates();
        publishLive();
    }

    // ---------------------------------------------------------------- templates

    function defaultTemplates() {
        return [
            {
                name: "Dev Work",
                emoji: "💻",
                workspace: "Dev Work",
                notes: "Zed + GitComet + Hermes agent shell.",
                apps: [
                    "zeditor",
                    "gitcomet",
                    { name: "Hermes agent", cmd: "ghostty -e hermes-agent", appId: "com.mitchellh.ghostty", alwaysLaunch: true }
                ]
            },
            {
                name: "JobApp",
                emoji: "🧳",
                workspace: "JobApp",
                notes: "Job applications: browser + password manager + agent shell.",
                apps: ["zen-browser", "keepassxc"]
            },
            {
                name: "Gaming",
                emoji: "🎮",
                workspace: "Gaming",
                notes: "Launch games through MangoHUD (mangohud %command%). Start focusgame to suspend background apps (install separately).",
                apps: ["lutris", "prismlauncher", "vesktop"]
            },
            {
                name: "Chill",
                emoji: "🧊",
                workspace: "Chill",
                notes: "Browser + chat + music.",
                apps: ["/opt/zen-browser-bin/zen-bin", "vesktop", "sonora"]
            }
        ];
    }

    function loadTemplates() {
        if (!templatesPath) {
            templates = defaultTemplates();
            publishTemplates();
            return;
        }

        Proc.runCommand("wsm.loadTemplates", ["cat", templatesPath], (stdout, exitCode) => {
            let list = [];
            if (exitCode === 0) {
                try {
                    const data = JSON.parse(stdout);
                    list = (data && Array.isArray(data.templates)) ? data.templates : [];
                } catch (e) {
                    console.warn("[workspaceManager] templates.json parse error:", e);
                    list = defaultTemplates();
                }
            } else {
                // First run: seed the file so the user has something to edit.
                list = defaultTemplates();
                writeTemplates(list, null);
            }
            templates = list;
            publishTemplates();
        });
    }

    function writeTemplates(list, done) {
        const payload = JSON.stringify({ version: 1, templates: list }, null, 2);
        // Guard the heredoc delimiter against content collisions.
        const safe = payload.split("\n").map(l => l === "WSM_EOF" ? "WSM_EOF " : l).join("\n");
        const script = `mkdir -p "$(dirname '${templatesPath}')" && cat > '${templatesPath}' <<'WSM_EOF'\n${safe}\nWSM_EOF`;

        Proc.runCommand("wsm.writeTemplates", ["sh", "-c", script], (stdout, exitCode) => {
            if (exitCode !== 0) {
                console.warn("[workspaceManager] failed to write templates.json:", stdout);
                if (done)
                    done(false);
                return;
            }
            if (done)
                done(true);
        });
    }

    function publishTemplates() {
        if (!pluginService)
            return;
        pluginService.setGlobalVar(pluginId, "templates", templates);
        pluginService.setGlobalVar(pluginId, "templatesVersion", Date.now());
    }

    function publishStatus(message) {
        if (!pluginService)
            return;
        pluginService.setGlobalVar(pluginId, "status", { message: String(message || ""), at: Date.now() });
    }

    function findTemplateByName(name) {
        return (templates || []).find(t => t.name === name) || null;
    }

    function normalizeApp(app) {
        if (typeof app === "string")
            return { name: app, cmd: app, appId: "", alwaysLaunch: false };
        return {
            name: (app && app.name) || (app && app.cmd) || "",
            cmd: (app && (app.cmd || app.name)) || "",
            appId: (app && app.appId) || "",
            alwaysLaunch: !!(app && app.alwaysLaunch)
        };
    }

    function templateApps(t) {
        return (t.apps || []).map(normalizeApp).filter(a => a.cmd);
    }

    // DMS's bar workspace indicator reads SettingsData.getWorkspaceNameIcon(name)
    // and renders { type: "text", value: emoji } as a glyph.
    function applyWorkspaceIcon(name, emoji) {
        if (!name || !emoji)
            return;
        if (typeof SettingsData === "undefined" || !SettingsData.setWorkspaceNameIcon)
            return;
        SettingsData.setWorkspaceNameIcon(name, { type: "text", value: emoji });
    }

    function emojiForWorkspace(name) {
        if (!name || typeof SettingsData === "undefined" || !SettingsData.getWorkspaceNameIcon)
            return "";
        const data = SettingsData.getWorkspaceNameIcon(name);
        return (data && data.type === "text") ? (data.value || "") : "";
    }

    function forgetWorkspaceIcon(name) {
        if (!name || typeof SettingsData === "undefined" || !SettingsData.removeWorkspaceNameIcon)
            return;
        SettingsData.removeWorkspaceNameIcon(name);
    }

    // Toggle the "Names" option on every workspace switcher widget so the bar
    // shows the niri workspace name next to the emoji glyph.
    function setWorkspaceNamesShown(on) {
        if (typeof SettingsData === "undefined" || !SettingsData.updateBarWidget)
            return 0;
        const bars = SettingsData.barConfigs || [];
        let n = 0;
        for (const bar of bars) {
            if (!bar || !bar.id)
                continue;
            for (const sectionId of ["left", "center", "right"]) {
                const list = bar[sectionId + "Widgets"] || [];
                for (let i = 0; i < list.length; i++) {
                    const entry = list[i];
                    const id = typeof entry === "string" ? entry : (entry.id || entry.widgetId || "");
                    if (id !== "workspaceSwitcher")
                        continue;
                    SettingsData.updateBarWidget(bar.id, sectionId, i, { showWorkspaceName: on });
                    n++;
                }
            }
        }
        return n;
    }

    // ------------------------------------------------------------- niri reads

    function focusedWorkspaceRecord() {
        return (NiriService.allWorkspaces || []).find(ws => ws.is_focused === true) || null;
    }

    function focusedOutputWorkspaces() {
        const src = (NiriService.currentOutputWorkspaces && NiriService.currentOutputWorkspaces.length)
            ? NiriService.currentOutputWorkspaces
            : (NiriService.allWorkspaces || []);
        const list = src.slice();
        list.sort((a, b) => (a.idx || 0) - (b.idx || 0));
        return list;
    }

    function lastWorkspaceIdx() {
        const list = focusedOutputWorkspaces();
        if (list.length === 0)
            return 1;
        return list[list.length - 1].idx || 1;
    }

    function findWorkspaceByName(name) {
        return (NiriService.allWorkspaces || []).find(ws => ws.name === name) || null;
    }

    function currentWorkspaceName() {
        const focused = focusedWorkspaceRecord();
        return focused ? (focused.name || "") : "";
    }

    // ------------------------------------------------------------- niri writes

    // A bounded poll over live niri state. Socket sends return as soon as the
    // bytes are written, so "did niri actually do it" has to be observed.
    property var _waiters: []

    Timer {
        id: waitTimer
        interval: 60
        repeat: true
        running: root._waiters.length > 0
        onTriggered: root.pumpWaiters()
    }

    function waitFor(predicate, timeoutMs, done) {
        _waiters = _waiters.concat([{ predicate: predicate, deadline: Date.now() + timeoutMs, done: done }]);
        waitTimer.restart();
    }

    function pumpWaiters() {
        const now = Date.now();
        const keep = [];
        for (const waiter of _waiters) {
            let ok = false;
            try {
                ok = waiter.predicate() === true;
            } catch (e) {
                ok = false;
            }
            if (ok) {
                waiter.done(true);
                continue;
            }
            if (now >= waiter.deadline) {
                waiter.done(false);
                continue;
            }
            keep.push(waiter);
        }
        _waiters = keep;
    }

    function workspaceNamed(name) {
        return (NiriService.allWorkspaces || []).find(ws => ws.name === name) || null;
    }

    function workspaceFocused(name) {
        const ws = workspaceNamed(name);
        return !!ws && ws.is_focused === true;
    }


    property int _niriSeq: 0

    function niri(args, done) {
        _niriSeq++;
        Proc.runCommand("wsm.niri." + _niriSeq, ["niri", "msg"].concat(args), (stdout, exitCode) => {
            if (done)
                done(stdout, exitCode);
        });
    }

    // Actions go over NiriService's single request socket when it is connected,
    // so "focus workspace" and the spawns that follow are processed in order by
    // niri. The `niri msg` fallback opens a fresh connection per call, so there
    // the caller awaits each step instead.
    // Focus one window by id. niri switches to the window's workspace itself,
    // so this works for a tile of any workspace in the panel.
    function focusWindowById(windowId) {
        const id = Number(windowId);
        if (!id)
            return false;
        if (niriAction("FocusWindow", {
            id: id
        }))
            return true;
        niri(["action", "focus-window", "--id", String(id)], () => {});
        return true;
    }

    function niriAction(action, fields) {
        if (typeof NiriService === "undefined" || !NiriService.send)
            return false;
        const req = { Action: {} };
        req.Action[action] = fields || {};
        return NiriService.send(req);
    }

    function focusByName(name, done) {
        if (niriAction("FocusWorkspace", { reference: { Name: name } })) {
            if (done)
                done(true, "");
            return;
        }
        niri(["action", "focus-workspace", name], (out, code) => {
            if (done)
                done(code === 0, code === 0 ? "" : (out || "focus-workspace failed"));
        });
    }

    function focusByIndex(idx, done) {
        if (niriAction("FocusWorkspace", { reference: { Index: idx } })) {
            if (done)
                done(true, "");
            return;
        }
        niri(["action", "focus-workspace", String(idx)], (out, code) => {
            if (done)
                done(code === 0, code === 0 ? "" : (out || "focus-workspace failed"));
        });
    }

    // `niri msg action focus-workspace` only accepts index or name, so focusing
    // by workspace id goes through NiriService directly.
    function focusById(id, done) {
        const ok = NiriService.switchToWorkspace(id);
        if (done)
            done(ok, ok ? "" : "switch-to-workspace failed (is NiriService connected?)");
    }

    // Names a workspace by index instead of "whatever is focused", which is what
    // the CLI form does; the two are not the same thing under a race.
    function setNameByIndex(idx, name, done) {
        if (niriAction("SetWorkspaceName", {
            name: name,
            workspace: {
                Index: idx
            }
        })) {
            if (done)
                done(true);
            return;
        }
        niri(["action", "set-workspace-name", "--workspace", String(idx), name], (out, code) => {
            if (done)
                done(code === 0);
        });
    }

    function spawnShell(cmd, done) {
        niri(["action", "spawn-sh", "--", cmd], (out, code) => {
            if (code !== 0)
                console.warn("[workspaceManager] spawn failed:", cmd, out);
            if (done)
                done(code === 0);
        });
    }

    function spawnApps(apps, done) {
        let i = 0;
        function next() {
            if (i >= apps.length) {
                if (done)
                    done();
                return;
            }
            const cmd = apps[i].cmd;
            i++;
            if (niriAction("SpawnSh", { command: cmd })) {
                next();
                return;
            }
            spawnShell(cmd, next);
        }
        next();
    }

    // ------------------------------------------------------------- app matching

    function basename(path) {
        const s = String(path || "").trim();
        const i = s.lastIndexOf("/");
        return i >= 0 ? s.substring(i + 1) : s;
    }

    function lastSegment(id) {
        const s = String(id || "").trim();
        const i = s.lastIndexOf(".");
        return i >= 0 ? s.substring(i + 1) : s;
    }

    function pushKey(keys, value) {
        const k = String(value || "").toLowerCase().trim();
        if (k && keys.indexOf(k) < 0)
            keys.push(k);
    }

    // Keys a template app can be recognised by: its app id (and its last dotted
    // segment) plus the basename of every token in the command, so wrappers
    // like `mangohud game` still match a running `game` process.
    function keysForApp(app) {
        const a = normalizeApp(app);
        const keys = [];
        if (a.appId) {
            pushKey(keys, a.appId);
            pushKey(keys, lastSegment(a.appId));
        }
        const tokens = String(a.cmd || "").trim().split(/\s+/);
        for (const tok of tokens)
            pushKey(keys, basename(tok.replace(/^["']|["']$/g, "")));
        return keys;
    }

    function keysForWindow(w) {
        const keys = [];
        if (w.app_id) {
            pushKey(keys, w.app_id);
            pushKey(keys, lastSegment(w.app_id));
        }
        if (w._cmdline) {
            const tokens = String(w._cmdline).trim().split(/\s+/);
            for (const tok of tokens.slice(0, 4))
                pushKey(keys, basename(tok));
        }
        return keys;
    }

    // Prefix/substring matching with a length floor, so "zen" matches
    // "/opt/zen-browser-bin/zen-bin" without matching single letters.
    function keysMatch(a, b) {
        if (!a || !b)
            return false;
        if (a === b)
            return true;
        if (a.length < 3 || b.length < 3)
            return false;
        return a.indexOf(b) >= 0 || b.indexOf(a) >= 0;
    }

    function appMatchesWindow(keys, wkeys) {
        for (const k of keys) {
            for (const wk of wkeys) {
                if (keysMatch(k, wk))
                    return true;
            }
        }
        return false;
    }

    // Windows on one workspace, enriched with their process cmdline (cached by
    // pid, since /proc reads are a fork per window).
    function collectWindows(workspaceId, done) {
        const all = !(workspaceId !== undefined && workspaceId !== null && String(workspaceId) !== "");
        const wins = all
            ? (NiriService.windows || []).slice()
            : (NiriService.windows || []).filter(w => String(w.workspace_id) === String(workspaceId));
        if (wins.length === 0) {
            done([]);
            return;
        }

        const out = [];
        let remaining = wins.length;

        wins.forEach(w => {
            const pid = w.pid;
            const cached = pid ? _cmdlineCache[pid] : null;
            if (cached !== undefined && cached !== null) {
                out.push(Object.assign({}, w, { _cmdline: cached }));
                remaining--;
                if (remaining === 0)
                    done(out);
                return;
            }
            readCmdline(pid, (cmdline) => {
                out.push(Object.assign({}, w, { _cmdline: cmdline }));
                remaining--;
                if (remaining === 0)
                    done(out);
            });
        });
    }

    function readCmdline(pid, done) {
        if (!pid) {
            done("");
            return;
        }
        Proc.runCommand(
            "wsm.cmdline." + pid,
            ["sh", "-c", "tr '\\0' ' ' < /proc/" + pid + "/cmdline 2>/dev/null"],
            (out, code) => {
                const value = code === 0 ? out.trim() : "";
                _cmdlineCache[pid] = value;
                done(value);
            }
        );
    }

    function windowLabel(w) {
        return w.app_id || w.title || ("window-" + w.id);
    }

    // --------------------------------------------------------------- diff logic

    // What a template expects vs what is actually open, anywhere.
    //
    //  present   — a matching window already sits on the target workspace
    //  moveable  — a matching window exists on another workspace: single-instance
    //              apps (browser, password manager, chat) cannot be launched a
    //              second time, they just raise the old window, so the window is
    //              moved instead of spawning a duplicate that lands nowhere
    //  missing   — nothing matches, so the app has to be started
    function computeDiff(t, done) {
        const apps = templateApps(t);
        const wsName = (t.workspace || "").trim();
        const ws = wsName ? findWorkspaceByName(wsName) : focusedWorkspaceRecord();

        if (!ws) {
            done({
                workspace: wsName,
                exists: false,
                present: [],
                moveable: [],
                missing: apps,
                forceMissing: apps.filter(a => a.alwaysLaunch)
            });
            return;
        }

        collectWindows(null, (wins) => {
            const used = [];
            const present = [];
            const moveable = [];
            const missing = [];

            for (const app of apps) {
                if (app.alwaysLaunch) {
                    missing.push(app);
                    continue;
                }
                const keys = keysForApp(app);

                const onTarget = wins.find(w => used.indexOf(w.id) < 0
                    && String(w.workspace_id) === String(ws.id)
                    && appMatchesWindow(keys, keysForWindow(w)));
                if (onTarget) {
                    used.push(onTarget.id);
                    present.push(app);
                    continue;
                }

                const elsewhere = wins.find(w => used.indexOf(w.id) < 0
                    && String(w.workspace_id) !== String(ws.id)
                    && appMatchesWindow(keys, keysForWindow(w)));
                if (elsewhere) {
                    used.push(elsewhere.id);
                    moveable.push({
                        app: app,
                        windowId: elsewhere.id,
                        fromWorkspace: elsewhere.workspace_id
                    });
                    continue;
                }

                missing.push(app);
            }

            done({
                workspace: ws.name || wsName,
                workspaceId: ws.id,
                exists: true,
                present: present,
                moveable: moveable,
                missing: missing,
                forceMissing: missing.filter(a => a.alwaysLaunch)
            });
        });
    }

    function diffSummary(diff) {
        if (!diff)
            return "";
        const missing = (diff.missing || []).map(a => a.name).join(", ");
        const present = (diff.present || []).map(a => a.name).join(", ");
        let text = "";
        if (diff.missing && diff.missing.length)
            text += "opening " + diff.missing.length + ": " + missing;
        if (diff.present && diff.present.length)
            text += (text ? " | " : "") + "already open: " + present;
        return text || "nothing to do";
    }

    // Publishes a per-template diff map for the manager UI.
    function publishDiffs() {
        const list = templates.slice();
        const out = {};
        let i = 0;

        function step() {
            if (i >= list.length) {
                if (pluginService)
                    pluginService.setGlobalVar(pluginId, "diffs", out);
                return;
            }
            const t = list[i];
            i++;
            computeDiff(t, (diff) => {
                out[t.name] = {
                    missing: (diff.missing || []).map(a => a.name),
                    move: (diff.moveable || []).map(m => m.app.name),
                    present: (diff.present || []).map(a => a.name),
                    exists: diff.exists,
                    workspace: diff.workspace
                };
                step();
            });
        }
        step();
    }

    // A window is mapped when the app is ready, not when it is spawned, so a slow
    // app (a browser takes seconds) lands wherever the focus is by then. After a
    // launch, any window that appeared during the run and matches one of the
    // spawned apps is moved onto the target workspace.
    property var _pendingRehome: null

    Timer {
        id: rehomeTimer
        interval: 4000
        repeat: false
        onTriggered: {
            const job = root._pendingRehome;
            root._pendingRehome = null;
            if (job)
                root.pumpRehome(job.apps, job.wsName, job.before, job.done);
        }
    }

    function scheduleRehome(apps, wsName, before, done) {
        _pendingRehome = {
            apps: apps,
            wsName: wsName,
            before: before,
            done: done
        };
        rehomeTimer.restart();
    }

    function moveWindowTo(windowId, wsName) {
        if (!wsName)
            return false;
        if (niriAction("MoveWindowToWorkspace", {
            window_id: windowId,
            reference: {
                Name: wsName
            },
            focus: false
        }))
            return true;
        niri(["action", "move-window-to-workspace", "--window-id", String(windowId), "--focus", "false", wsName], () => {});
        return true;
    }

    // Reconcile a launch against reality, without assuming anything about how
    // an app behaves when it is started a second time. Some open a new window
    // on the focused workspace (Zen, Ghostty), some just raise the window they
    // already have and exit (KeePassXC), some do either depending on flags and
    // profile. So: look at what actually appeared, then fix up.
    //
    //  1. a window the launch created but that mapped on another workspace is
    //     moved onto the target;
    //  2. an app that produced no new window at all, while a matching window
    //     exists elsewhere, has that window adopted (moved) instead.
    function pumpRehome(apps, wsName, before, done) {
        const ws = workspaceNamed(wsName);
        if (!ws) {
            if (done)
                done(0);
            return;
        }
        const wsId = String(ws.id);

        collectWindows(null, (wins) => {
            const fresh = wins.filter(w => before.indexOf(w.id) < 0);
            let moved = 0;

            // 1. strays: created by this launch, mapped elsewhere
            for (const w of fresh) {
                if (String(w.workspace_id) === wsId)
                    continue;
                if (!apps.some(a => appMatchesWindow(keysForApp(a), keysForWindow(w))))
                    continue;
                moveWindowTo(w.id, wsName);
                moved++;
            }

            // 2. apps that ignored the launch: adopt the window they already had
            const adopted = [];
            for (const app of apps) {
                const keys = keysForApp(app);
                if (fresh.some(w => appMatchesWindow(keys, keysForWindow(w))))
                    continue;
                if (wins.some(w => String(w.workspace_id) === wsId && appMatchesWindow(keys, keysForWindow(w))))
                    continue;
                const candidate = wins.find(w => String(w.workspace_id) !== wsId
                    && before.indexOf(w.id) >= 0
                    && appMatchesWindow(keys, keysForWindow(w)));
                if (!candidate)
                    continue;
                moveWindowTo(candidate.id, wsName);
                adopted.push(app.name);
                moved++;
            }

            if (moved > 0) {
                publishStatus(adopted.length > 0
                    ? `Moved ${moved} window${moved === 1 ? "" : "s"} onto "${wsName}" (${adopted.join(", ")} would not open a new one)`
                    : `Moved ${moved} window${moved === 1 ? "" : "s"} that opened on the wrong workspace`);
                publishLive();
            }
            if (done)
                done(moved);
        });
    }

    // ----------------------------------------------------------------- actions

    // Create (focus + name) a workspace on the focused output.
    //
    // Three things used to make this land in the wrong place:
    //  - a socket send reports success when the request is written, not applied;
    //  - naming went through a separate `niri msg` process, so its order against
    //    the socket focus was undefined;
    //  - the CLI form names whatever is focused at that moment.
    // So: name by explicit index, then wait until niri really reports the name,
    // and only then let the caller spawn anything.
    function createWorkspace(name, emoji, done) {
        const trimmed = (name || "").trim();

        const attempt = (triesLeft) => {
            const idx = lastWorkspaceIdx();
            focusByIndex(idx, (ok, err) => {
                if (!ok) {
                    if (done)
                        done(false, err || "could not focus the new workspace");
                    return;
                }
                if (!trimmed) {
                    if (done)
                        done(true, "");
                    return;
                }
                setNameByIndex(idx, trimmed, () => {
                    waitFor(() => workspaceNamed(trimmed) !== null, 1500, (named) => {
                        if (!named) {
                            // A stale index is the usual cause; retry once with a
                            // freshly computed one before giving up.
                            if (triesLeft > 1) {
                                attempt(triesLeft - 1);
                                return;
                            }
                            if (done)
                                done(false, `niri did not accept the name "${trimmed}" (is it used by another workspace?)`);
                            return;
                        }
                        applyWorkspaceIcon(trimmed, emoji);
                        if (done)
                            done(true, "");
                    });
                });
            });
        };

        attempt(2);
    }

    function renameFocused(name, emoji, done) {
        const trimmed = (name || "").trim();
        if (!trimmed) {
            if (done)
                done(false, "name is required");
            return;
        }
        niri(["action", "set-workspace-name", trimmed], (out, code) => {
            if (code === 0)
                applyWorkspaceIcon(trimmed, emoji);
            if (done)
                done(code === 0, code === 0 ? "" : (out || "set-workspace-name failed"));
        });
    }

    function renameWorkspaceById(id, name, emoji, done) {
        const trimmed = (name || "").trim();
        const numericId = parseInt(id, 10);
        if (!trimmed || isNaN(numericId)) {
            if (done)
                done(false, "workspace id and name are required");
            return;
        }
        const sent = niriAction("SetWorkspaceName", { name: trimmed, workspace: { Id: numericId } });
        const finish = (ok, err) => {
            if (ok)
                applyWorkspaceIcon(trimmed, emoji);
            publishLive();
            if (done)
                done(ok, err || "");
        };
        if (sent) {
            finish(true, "");
            return;
        }
        niri(["action", "set-workspace-name", "--workspace", String(numericId), trimmed], (out, code) => {
            finish(code === 0, code === 0 ? "" : (out || "set-workspace-name failed"));
        });
    }

    // Close a live workspace. `closeWindows` also closes every window it holds;
    // either way the name is unset so the workspace goes away once it is empty.
    // Unnamed workspaces only need their windows closed.
    function closeWorkspace(id, closeWindows, done) {
        const numericId = parseInt(id, 10);
        if (isNaN(numericId)) {
            if (done)
                done(false, "invalid workspace id");
            return;
        }

        const ws = (NiriService.allWorkspaces || []).find(w => String(w.id) === String(numericId));
        if (!ws) {
            if (done)
                done(false, `workspace ${numericId} not found`);
            return;
        }

        const wsName = ws.name || "";
        const wins = (NiriService.windows || []).filter(w => String(w.workspace_id) === String(numericId));

        if (closeWindows) {
            for (const win of wins) {
                if (!niriAction("CloseWindow", { id: win.id }))
                    niri(["action", "close-window", "--id", String(win.id)], () => {});
            }
        }

        const label = wsName || `workspace #${ws.idx}`;
        const finish = () => {
            if (wsName)
                forgetWorkspaceIcon(wsName);
            const summary = closeWindows
                ? `Closed ${label} and ${wins.length} window${wins.length === 1 ? "" : "s"}`
                : `Removed the name ${label}${wins.length ? " (windows kept)" : ""}`;
            publishStatus(summary);
            publishLive();
            if (done)
                done(true, summary);
        };

        if (!wsName) {
            finish();
            return;
        }

        if (niriAction("UnsetWorkspaceName", { reference: { Id: numericId } })) {
            finish();
            return;
        }
        niri(["action", "unset-workspace-name", "--workspace", String(numericId)], (out, code) => {
            if (code === 0) {
                finish();
                return;
            }
            if (done)
                done(false, out || "unset-workspace-name failed");
        });
    }

    function activate(name, done) {
        const arg = String(name || "").trim();
        if (!arg) {
            if (done)
                done(false, "name is required");
            return;
        }

        if (/^\d+$/.test(arg)) {
            focusByIndex(parseInt(arg, 10), done);
            return;
        }

        // A template wins over a plain workspace of the same name: activating an
        // environment should also reopen whatever it is missing.
        if (findTemplateByName(arg)) {
            launchTemplate(arg, false, done);
            return;
        }

        if (findWorkspaceByName(arg)) {
            focusByName(arg, done);
            return;
        }

        if (done)
            done(false, `no workspace or template named "${arg}"`);
    }

    // Launch only what is missing on the target workspace. `force` re-runs every
    // app in the template (app entries with alwaysLaunch still always run).
    function launchTemplate(name, force, done) {
        const t = findTemplateByName(name);
        if (!t) {
            if (done)
                done(false, `template not found: ${name}`);
            return;
        }

        const all = templateApps(t);
        const wsName = (t.workspace || "").trim();
        const emoji = t.emoji || "";

        computeDiff(t, (diff) => {
            // Always try to start what is not on the workspace yet. An app in the
            // template can opt into `gather: true` when starting it again is
            // pointless (a chat client that just raises its window); otherwise
            // the window it refuses to duplicate is adopted after the launch.
            const moveable = diff.moveable || [];
            const gatherOnly = force ? [] : moveable.filter(m => m.app.gather === true);
            const apps = force
                ? all
                : diff.missing.concat(moveable.filter(m => m.app.gather !== true).map(m => m.app));
            const moves = gatherOnly;
            if (pluginService)
                pluginService.setGlobalVar(pluginId, "lastDiff", {
                    template: name,
                    missing: apps.map(a => a.name),
                    move: moves.map(m => m.app.name),
                    present: (diff.present || []).map(a => a.name)
                });

            const moveWindows = (next) => {
                if (wsName) {
                    for (const item of moves)
                        moveWindowTo(item.windowId, wsName);
                }
                next();
            };

            const spawnNow = () => {
                const before = (NiriService.windows || []).map(w => w.id);
                spawnApps(apps, () => {
                    let summary;
                    if (apps.length === 0 && moves.length === 0)
                        summary = `"${name}" is already complete`;
                    else if (apps.length === 0)
                        summary = `Moved ${moves.length} window${moves.length === 1 ? "" : "s"} onto "${name}"`;
                    else if (moves.length === 0)
                        summary = `Opened ${apps.length} app${apps.length === 1 ? "" : "s"} for "${name}"`;
                    else
                        summary = `Opened ${apps.length} and moved ${moves.length} window${moves.length === 1 ? "" : "s"} for "${name}"`;
                    publishStatus(summary);
                    publishLive();
                    // window rules aside, niri places a window on whatever
                    // workspace is focused when it maps, so sweep strays back.
                    if (wsName && (apps.length > 0 || moves.length > 0)
                        && (pluginData && pluginData.rehomeWindows) !== false)
                        scheduleRehome(apps, wsName, before, null);
                    if (done)
                        done(true, summary);
                });
            };

            if (!wsName) {
                spawnNow();
                return;
            }

            if (emoji)
                applyWorkspaceIcon(wsName, emoji);

            // Spawning is only safe once niri reports the workspace focused,
            // otherwise the windows land on whatever happened to be focused.
            const focusVerified = () => {
                focusByName(wsName, () => {
                    waitFor(() => workspaceFocused(wsName), 1500, (focused) => {
                        if (focused) {
                            moveWindows(spawnNow);
                            return;
                        }
                        publishStatus(`Could not focus "${wsName}" — nothing was launched`);
                        if (done)
                            done(false, `could not focus "${wsName}"; no apps were launched`);
                    });
                });
            };

            if (diff.exists && diff.workspaceId !== undefined) {
                focusVerified();
                return;
            }

            createWorkspace(wsName, emoji, (ok, err) => {
                if (!ok) {
                    publishStatus(err || "Could not create the workspace");
                    if (done)
                        done(false, err || "could not create workspace");
                    return;
                }
                focusVerified();
            });
        });
    }

    // ------------------------------------------------------------- live/preview

    // ---------------------------------------------------------------- stills

    function stillUri(windowId) {
        const s = stills[windowId];
        if (!s)
            return "";
        // No query string: Qt treats "?t=..." on a file:// URL as part of the
        // file name. Each capture gets its own file instead, which also makes
        // the URL unique so nothing serves a cached image.
        return "file://" + s.path;
    }

    // Screenshot every window that needs a still, one at a time, newest first
    // for the focused workspace.
    function pullStills(force) {
        if (pluginData && pluginData.stills === false)
            return;

        const wins = (NiriService.windows || []).slice();
        const now = Date.now();
        const ttl = 10 * 60 * 1000;

        // forget stills for windows that closed
        const known = {};
        for (const w of wins)
            known[w.id] = true;
        const kept = {};
        for (const key in stills) {
            if (known[key])
                kept[key] = stills[key];
        }
        stills = kept;

        const focusedWs = (NiriService.allWorkspaces || []).filter(ws => ws.is_focused).map(ws => String(ws.id));
        const queue = wins
            .filter(w => (force || !stills[w.id] || (now - stills[w.id].ts) > ttl)
                && _stillQueue.indexOf(w.id) < 0
                && w.id !== _stillActive)
            .sort((a, b) => {
                const af = focusedWs.indexOf(String(a.workspace_id)) >= 0 ? 0 : 1;
                const bf = focusedWs.indexOf(String(b.workspace_id)) >= 0 ? 0 : 1;
                return af - bf;
            })
            .map(w => w.id)
            .slice(0, 16);

        // drop files for windows that are long gone
        Proc.runCommand("wsm.stillprune." + (++_stillSeq), ["sh", "-c",
            "mkdir -p '" + stillsDir + "' && find '" + stillsDir + "' -name '*.png' -mmin +15 -delete 2>/dev/null; true"], () => {});

        if (queue.length === 0)
            return;
        _stillQueue = queue;
        pumpStills();
    }

    function stillScript(windowId, ts) {
        const dir = stillsDir;
        const id = String(windowId);
        const target = id + "-" + ts + ".png";
        // The clipboard is the handoff, so it must be emptied before the capture:
        // otherwise the poll below can read a previous screenshot (or an image the
        // user copied) and the tile ends up showing another window's content.
        return [
            "dir='" + dir + "'; mkdir -p \"$dir\"",
            "out=\"$dir/" + target + "\"",
            "save=\"$dir/.clip-" + id + "\"",
            "type=$(wl-paste --list-types 2>/dev/null | head -1)",
            "if [ -n \"$type\" ]; then wl-paste --type \"$type\" > \"$save\" 2>/dev/null || { rm -f \"$save\"; type=''; }; fi",
            "wl-copy --clear 2>/dev/null",
            "niri msg action screenshot-window --id " + id + " --write-to-disk false >/dev/null 2>&1",
            "i=0",
            "while [ $i -lt 40 ]; do wl-paste --list-types 2>/dev/null | grep -qx 'image/png' && break; sleep 0.02; i=$((i+1)); done",
            "wl-paste --type image/png > \"$out\" 2>/dev/null",
            "[ -s \"$out\" ] || rm -f \"$out\"",
            // put the clipboard back, but only if it still holds our capture
            "if wl-paste --list-types 2>/dev/null | grep -qx 'image/png'; then",
            "  if [ -n \"$type\" ] && [ -s \"$save\" ]; then wl-copy --type \"$type\" < \"$save\"; else wl-copy --clear 2>/dev/null; fi",
            "fi",
            "rm -f \"$save\"",
            "[ -s \"$out\" ]"
        ].join("\n");
    }

    function pumpStills() {
        if (_stillBusy)
            return;
        if (_stillQueue.length === 0)
            return;
        const windowId = _stillQueue.shift();
        const ts = Date.now();
        _stillBusy = true;
        _stillActive = windowId;
        Proc.runCommand("wsm.still." + windowId + "." + (++_stillSeq),
            ["sh", "-c", stillScript(windowId, ts)], (out, code) => {
                _stillBusy = false;
                _stillActive = 0;
                if (code === 0) {
                    stills[windowId] = {
                        path: stillsDir + "/" + windowId + "-" + ts + ".png",
                        ts: ts
                    };
                    stillPublishTimer.restart();
                }
                pumpStills();
            });
    }

    function publishLive() {
        if (!pluginService)
            return;
        const out = [];
        for (const ws of (NiriService.allWorkspaces || [])) {
            const wins = (NiriService.windows || []).filter(w => String(w.workspace_id) === String(ws.id));
            out.push({
                id: ws.id,
                idx: ws.idx,
                name: ws.name || "",
                emoji: emojiForWorkspace(ws.name || ""),
                output: ws.output || "",
                focused: !!ws.is_focused,
                windowCount: wins.length,
                apps: wins.map(w => {
                    const layout = w.layout || null;
                    const pos = (layout && layout.pos_in_scrolling_layout) ? layout.pos_in_scrolling_layout : null;
                    const tile = (layout && layout.tile_size) ? layout.tile_size : null;
                    return {
                        id: w.id,
                        name: windowLabel(w),
                        appId: w.app_id || "",
                        title: w.title || "",
                        pid: w.pid || 0,
                        floating: !!w.is_floating,
                        focused: !!w.is_focused,
                        col: pos ? pos[0] : -1,
                        row: pos ? pos[1] : -1,
                        tileW: tile ? tile[0] : 0,
                        tileH: tile ? tile[1] : 0,
                        still: stillUri(w.id),
                        // niri fills this only while the tile sits in the
                        // monitor's current view. It is null when the field is
                        // not reported (older niri), so the mini-map treats null
                        // as "unknown", not "off screen".
                        inView: (layout && layout.tile_pos_in_workspace_view) ? true : null
                    };
                })
            });
        }
        out.sort((a, b) => {
            if (a.output !== b.output)
                return a.output < b.output ? -1 : 1;
            return (a.idx || 0) - (b.idx || 0);
        });
        pluginService.setGlobalVar(pluginId, "live", out);
        publishDiffs();
    }

    // Snapshot of a workspace for the record/confirm flow. Without an id it
    // snapshots the focused workspace.
    function publishPreview(name, emoji, workspaceId) {
        const targetId = (workspaceId !== undefined && workspaceId !== null && String(workspaceId) !== "")
            ? workspaceId
            : (focusedWorkspaceRecord() ? focusedWorkspaceRecord().id : "");
        const ws = (NiriService.allWorkspaces || []).find(w => String(w.id) === String(targetId)) || null;
        const wsLabel = (ws && ws.name) ? ws.name : ((name || "").trim());

        collectWindows(targetId, (wins) => {
            const apps = wins.map(w => ({
                name: windowLabel(w),
                cmd: (w._cmdline && w._cmdline.trim()) ? w._cmdline.trim() : (w.app_id || ""),
                appId: w.app_id || "",
                title: w.title || ""
            })).filter(a => a.cmd);
            if (pluginService)
                pluginService.setGlobalVar(pluginId, "preview", {
                    name: (name || "").trim() || wsLabel,
                    emoji: emoji || "",
                    workspace: wsLabel,
                    workspaceId: ws ? ws.id : -1,
                    capturedAt: Date.now(),
                    apps: apps
                });
        });
    }

    function clearPreview() {
        if (pluginService)
            pluginService.setGlobalVar(pluginId, "preview", null);
    }

    // ---------------------------------------------------------- template writes

    function saveTemplateJson(json, done) {
        let payload = null;
        try {
            payload = JSON.parse(json);
        } catch (e) {
            if (done)
                done(false, "invalid JSON payload");
            return;
        }

        const t = payload && payload.template ? payload.template : payload;
        const originalName = (payload && payload.originalName) || "";
        if (!t || !t.name || !String(t.name).trim()) {
            if (done)
                done(false, "template name is required");
            return;
        }

        const clean = {
            name: String(t.name).trim(),
            emoji: t.emoji || "",
            workspace: (t.workspace || "").trim(),
            notes: t.notes || "",
            apps: templateApps(t).map(a => {
                const out = { name: a.name || a.cmd, cmd: a.cmd };
                if (a.appId)
                    out.appId = a.appId;
                if (a.alwaysLaunch)
                    out.alwaysLaunch = true;
                return out;
            })
        };

        const list = templates.slice();
        let idx = originalName ? list.findIndex(x => x.name === originalName) : -1;
        if (idx < 0)
            idx = list.findIndex(x => x.name === clean.name);
        if (idx >= 0)
            list[idx] = clean;
        else
            list.push(clean);

        writeTemplates(list, (ok) => {
            if (ok) {
                templates = list;
                publishTemplates();
                if (clean.emoji && clean.workspace)
                    applyWorkspaceIcon(clean.workspace, clean.emoji);
                publishStatus(`Saved template "${clean.name}"`);
                publishLive();
            }
            if (done)
                done(ok, ok ? "" : "failed to save templates.json");
        });
    }

    function deleteTemplate(name, done) {
        const list = templates.filter(t => t.name !== name);
        if (list.length === templates.length) {
            if (done)
                done(false, `template not found: ${name}`);
            return;
        }
        writeTemplates(list, (ok) => {
            if (ok) {
                templates = list;
                publishTemplates();
                publishStatus(`Deleted template "${name}"`);
                publishLive();
            }
            if (done)
                done(ok, ok ? "" : "failed to save templates.json");
        });
    }

    // ------------------------------------------------------------------- list

    function listText() {
        const lines = [];
        lines.push("Workspaces:");
        for (const ws of (NiriService.allWorkspaces || [])) {
            const marker = ws.is_focused ? "*" : " ";
            const emoji = emojiForWorkspace(ws.name || "");
            const label = (emoji ? emoji + " " : "") + (ws.name || ("#" + ws.idx));
            const wins = (NiriService.windows || []).filter(w => String(w.workspace_id) === String(ws.id));
            lines.push(` ${marker} ${label}  (output=${ws.output}, idx=${ws.idx}, ${wins.length} windows)`);
        }
        lines.push("");
        lines.push("Templates:");
        for (const t of templates) {
            const count = (t.apps || []).length;
            const ws = t.workspace ? `  [workspace: ${t.workspace}]` : "";
            const emoji = t.emoji ? `${t.emoji} ` : "";
            lines.push(` - ${emoji}${t.name}${ws}  (${count} apps)`);
        }
        return lines.join("\n");
    }

    // -------------------------------------------------------------------- ipc

    IpcHandler {
        target: "workspaceManager"

        function create(name: string): string {
            root.createWorkspace(name, "", (ok, err) => {
                if (!ok) {
                    if (ToastService)
                        ToastService.showError("Workspace Manager", err || "Failed to create workspace");
                } else if (ToastService) {
                    ToastService.showInfo("Workspace Manager", name && name.trim() ? `Created workspace "${name.trim()}"` : "Created workspace");
                }
                root.publishLive();
            });
            return "QUEUED";
        }

        function activate(name: string): string {
            root.activate(name, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Activate failed");
            });
            return "QUEUED";
        }

        function launch(name: string): string {
            root.launchTemplate(name, false, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Launch failed");
            });
            return "QUEUED";
        }

        function launchAll(name: string): string {
            root.launchTemplate(name, true, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Launch failed");
            });
            return "QUEUED";
        }

        function diff(name: string): string {
            const t = root.findTemplateByName(name);
            if (!t)
                return `ERROR: template not found: ${name}`;
            root.computeDiff(t, (d) => {
                root.publishStatus(root.diffSummary(d));
                root.publishLive();
            });
            return "QUEUED";
        }

        function record(name: string): string {
            root.publishPreview(name, "");
            return "QUEUED";
        }

        function previewRecord(name: string, emoji: string): string {
            root.publishPreview(name, emoji, "");
            return "QUEUED";
        }

        function previewWorkspace(id: string, name: string, emoji: string): string {
            root.publishPreview(name, emoji, id);
            return "QUEUED";
        }

        function clearPreview(): string {
            root.clearPreview();
            return "OK";
        }

        function saveTemplate(json: string): string {
            root.saveTemplateJson(json, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Save failed");
            });
            return "QUEUED";
        }

        function deleteTemplate(name: string): string {
            root.deleteTemplate(name, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Delete failed");
            });
            return "QUEUED";
        }

        function name(workspaceName: string, emoji: string): string {
            root.renameFocused(workspaceName, emoji, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Rename failed");
            });
            return "QUEUED";
        }

        function rename(id: string, workspaceName: string, emoji: string): string {
            root.renameWorkspaceById(id, workspaceName, emoji, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Rename failed");
            });
            return "QUEUED";
        }

        // closeWindows: "true" closes every window on the workspace, "false"
        // only removes the workspace name (empty windows stay put).
        function closeWorkspace(id: string, closeWindows: string): string {
            const withWindows = closeWindows === "true" || closeWindows === "1" || closeWindows === "on";
            root.closeWorkspace(id, withWindows, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Close failed");
            });
            return "QUEUED";
        }

        function refreshLive(): string {
            root.publishLive();
            stillKickTimer.restart();
            return "OK";
        }

        function pullStills(): string {
            root.pullStills(true);
            return "OK";
        }

        function forgetIcon(workspaceName: string): string {
            if (!workspaceName)
                return "ERROR: name is required";
            root.forgetWorkspaceIcon(workspaceName);
            root.publishLive();
            return "OK: forgot icon for " + workspaceName;
        }

        function syncIcons(): string {
            let n = 0;
            for (const t of root.templates) {
                const wsName = (t.workspace || t.name || "").trim();
                if (wsName && t.emoji) {
                    root.applyWorkspaceIcon(wsName, t.emoji);
                    n++;
                }
            }
            root.publishLive();
            return "OK: applied " + n + " workspace icons";
        }

        function showNames(on: string): string {
            const enable = on === "true" || on === "1" || on === "on";
            const n = root.setWorkspaceNamesShown(enable);
            if (n <= 0)
                return "ERROR: no workspace switcher widget found";
            return "OK: showWorkspaceName=" + (enable ? "true" : "false") + " on " + n + " widget(s)";
        }

        function reload(): string {
            root.loadTemplates();
            return "QUEUED";
        }

        function focusWindow(windowId: string): string {
            if (!windowId)
                return "ERROR: windowId is required";
            if (!root.focusWindowById(windowId))
                return "ERROR: could not focus window " + windowId;
            return "OK: focused window " + windowId;
        }

        function focusId(id: string): string {
            const num = parseInt(id, 10);
            if (isNaN(num))
                return "ERROR: invalid workspace id";
            root.focusById(num, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Focus failed");
            });
            return "QUEUED";
        }

        function list(): string {
            return root.listText();
        }

        // Snapshot of everything the manager UI sees, for scripting and tests.
        function state(): string {
            return JSON.stringify({
                templates: root.templates,
                live: root.pluginService ? root.pluginService.getGlobalVar(root.pluginId, "live", []) : [],
                diffs: root.pluginService ? root.pluginService.getGlobalVar(root.pluginId, "diffs", ({})) : {},
                preview: root.pluginService ? root.pluginService.getGlobalVar(root.pluginId, "preview", null) : null,
                status: root.pluginService ? root.pluginService.getGlobalVar(root.pluginId, "status", null) : null
            });
        }
    }
}
