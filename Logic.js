.pragma library

// Pure logic, kept out of the daemon so it can be tested without a compositor.
//
// Nothing here touches NiriService, the shell, the filesystem or the clipboard:
// every function takes plain objects and returns plain values. The daemon imports
// this as `Logic` and keeps thin wrappers with the same names, so call sites did
// not change. tests/tst_logic.qml exercises it with qmltestrunner (offscreen).

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

function pushUnique(keys, value) {
    const k = String(value || "").replace(/^["']|["']$/g, "").toLowerCase().trim();
    if (k && keys.indexOf(k) < 0)
        keys.push(k);
}

// One template app, however it was written in the JSON: a bare string or an
// object with name/cmd/appId plus the behaviour flags.
function normalizeApp(app) {
    if (typeof app === "string") {
        const s = app.trim();
        return { name: s, cmd: s, appId: "", alwaysLaunch: false, gather: false };
    }
    const a = app || {};
    const name = a.name || a.cmd || "";
    return {
        name: String(name),
        cmd: String(a.cmd || a.name || ""),
        appId: String(a.appId || ""),
        alwaysLaunch: !!a.alwaysLaunch,
        gather: !!a.gather
    };
}

function templateApps(template) {
    const list = (template && template.apps) || [];
    return list.map(normalizeApp).filter(a => a.cmd.trim() !== "");
}

// Keys a template app can be recognised by: its app id and the last dotted
// segment of it, plus the basename of every token in the command so wrappers
// like `mangohud game` still match a running `game`.
function keysForApp(app) {
    const a = normalizeApp(app);
    const keys = [];
    if (a.appId) {
        pushUnique(keys, a.appId);
        pushUnique(keys, lastSegment(a.appId));
    }
    const tokens = String(a.cmd || "").trim().split(/\s+/);
    for (const tok of tokens)
        pushUnique(keys, basename(tok));
    return keys;
}

// Keys for a live window: its app_id and the basenames of the first tokens of its
// cmdline (when the caller could read /proc/<pid>/cmdline).
function keysForWindow(win) {
    const w = win || {};
    const keys = [];
    if (w.app_id)
        pushUnique(keys, w.app_id);
    if (w.app_id)
        pushUnique(keys, lastSegment(w.app_id));
    if (w._cmdline) {
        const tokens = String(w._cmdline).trim().split(/\s+/);
        for (const tok of tokens.slice(0, 4))
            pushUnique(keys, basename(tok));
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

function appMatchesWindow(appKeys, windowKeys) {
    for (const k of appKeys) {
        for (const wk of windowKeys) {
            if (keysMatch(k, wk))
                return true;
        }
    }
    return false;
}

// Classify a template against every open window.
//
//   present   a matching window already sits on the target workspace
//   moveable  a matching window is elsewhere: single-instance apps just raise it,
//             so the caller decides between moving it and spawning a duplicate
//   missing   nothing matches, so the app has to be started
//
// `windows` entries need { id, workspace_id, app_id, _cmdline? }. Pure by design:
// the daemon feeds it NiriService.windows, the tests feed it fixtures.
function planLaunch(apps, windows, workspaceId) {
    const list = (apps || []).map(normalizeApp);
    const wins = windows || [];
    const target = String(workspaceId);
    const used = [];
    const present = [];
    const moveable = [];
    const missing = [];

    for (const app of list) {
        if (app.alwaysLaunch) {
            missing.push(app);
            continue;
        }
        const keys = keysForApp(app);

        const onTarget = wins.find(w => used.indexOf(w.id) < 0
            && String(w.workspace_id) === target
            && appMatchesWindow(keys, keysForWindow(w)));
        if (onTarget) {
            used.push(onTarget.id);
            present.push(app);
            continue;
        }

        const elsewhere = wins.find(w => used.indexOf(w.id) < 0
            && String(w.workspace_id) !== target
            && appMatchesWindow(keys, keysForWindow(w)));
        if (elsewhere) {
            used.push(elsewhere.id);
            moveable.push({ app: app, windowId: elsewhere.id, fromWorkspace: elsewhere.workspace_id });
            continue;
        }

        missing.push(app);
    }

    return { present, moveable, missing };
}

// First token of a command, which is the thing to resolve before spawning.
function programOf(cmd) {
    const first = String(cmd || "").trim().split(/\s+/)[0] || "";
    return basename(first);
}

// niri screen coordinates come from `pos_in_scrolling_layout` as (column, row)
// indices, so the mini-map needs a stable sort before laying tiles out.
function sortCells(apps) {
    return (apps || []).slice().sort((a, b) => {
        if ((a.col || 0) !== (b.col || 0))
            return (a.col || 0) - (b.col || 0);
        return (a.row || 0) - (b.row || 0);
    });
}
