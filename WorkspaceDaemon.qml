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
//   dms ipc call workspaceManager activate "Gaming"
//   dms ipc call workspaceManager launch "Chill"
//   dms ipc call workspaceManager record "My Snapshot"
//   dms ipc call workspaceManager reload
//   dms ipc call workspaceManager list
//
// Reads are done through NiriService (live, reactive). Writes go through
// `niri msg` so ordering between "focus workspace" and "spawn" is guaranteed
// by niri itself.

PluginComponent {
    id: root

    property var popoutService: null
    property var templates: []
    property string templatesPath: ""

    Component.onCompleted: {
        templatesPath = (pluginService && pluginService.getPluginPath)
            ? pluginService.getPluginPath(pluginId) + "/templates.json" : "";
        loadTemplates();
    }

    // ---------------------------------------------------------------- templates

    function defaultTemplates() {
        return [
            {
                name: "Dev Work",
                workspace: "Dev Work",
                notes: "Zed + GitComet + Hermes agent shell.",
                apps: ["zeditor", "gitcomet", "hermes-agent"]
            },
            {
                name: "Gaming",
                workspace: "Gaming",
                notes: "Launch games through MangoHUD (mangohud %command%). Start focusgame to suspend background apps (install separately).",
                apps: ["lutris", "prismlauncher", "vesktop"]
            },
            {
                name: "Chill",
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

    function findTemplateByName(name) {
        return (templates || []).find(t => t.name === name) || null;
    }

    function normalizeApp(app) {
        if (typeof app === "string")
            return { name: app, cmd: app };
        const cmd = (app && (app.cmd || app.name)) || "";
        return { name: (app && app.name) || cmd, cmd: cmd };
    }

    // ------------------------------------------------------------- niri reads

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
        const focused = (NiriService.allWorkspaces || []).find(ws => ws.is_focused === true);
        return focused ? (focused.name || "") : "";
    }

    // ------------------------------------------------------------- niri writes

    function niri(args, done) {
        Proc.runCommand("wsm.niri", ["niri", "msg"].concat(args), (stdout, exitCode) => {
            if (done)
                done(stdout, exitCode);
        });
    }

    function focusByIndex(idx, done) {
        niri(["action", "focus-workspace", String(idx)], (out, code) => {
            if (done)
                done(code === 0, code === 0 ? "" : (out || "focus-workspace failed"));
        });
    }

    function focusByName(name, done) {
        niri(["action", "focus-workspace", name], (out, code) => {
            if (done)
                done(code === 0, code === 0 ? "" : (out || "focus-workspace failed"));
        });
    }

    // `niri msg action focus-workspace` only accepts index or name, so focusing
    // by workspace id goes through NiriService's request socket instead.
    function focusById(id, done) {
        const ok = NiriService.switchToWorkspace(id);
        if (done)
            done(ok, ok ? "" : "switch-to-workspace failed (is NiriService connected?)");
    }

    function spawnShell(cmd, done) {
        niri(["action", "spawn-sh", "--", cmd], (out, code) => {
            if (code !== 0)
                console.warn("[workspaceManager] spawn failed:", cmd, out);
            if (done)
                done(code === 0);
        });
    }

    // ----------------------------------------------------------------- actions

    // Create a new workspace on the focused output by focusing the always-empty
    // workspace at the end and, optionally, naming it. niri keeps a fresh empty
    // workspace at the bottom, so this behaves like "new workspace".
    function createWorkspace(name, done) {
        const idx = lastWorkspaceIdx();
        focusByIndex(idx, (ok, err) => {
            if (!ok) {
                if (done)
                    done(false, err);
                return;
            }
            const trimmed = (name || "").trim();
            if (!trimmed) {
                if (done)
                    done(true, "");
                return;
            }
            niri(["action", "set-workspace-name", trimmed], (out2, code2) => {
                if (done)
                    done(code2 === 0, code2 === 0 ? "" : (out2 || "set-workspace-name failed"));
            });
        });
    }

    // Focus a named workspace by name, focus an unnamed one by index, or fall
    // back to launching a template with that name.
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

        if (findWorkspaceByName(arg)) {
            focusByName(arg, done);
            return;
        }

        if (findTemplateByName(arg)) {
            launchTemplate(arg, done);
            return;
        }

        if (done)
            done(false, `no workspace or template named "${arg}"`);
    }

    // Launch every app in a template, optionally on its named workspace.
    function launchTemplate(name, done) {
        const t = findTemplateByName(name);
        if (!t) {
            if (done)
                done(false, `template not found: ${name}`);
            return;
        }

        const apps = (t.apps || []).map(normalizeApp).filter(a => a.cmd);
        const useNamed = (pluginData && pluginData.launchIntoNamedWorkspace) !== false;
        const wsName = (t.workspace || "").trim();

        function afterFocus() {
            let i = 0;
            function next() {
                if (i >= apps.length) {
                    if (done)
                        done(true, "");
                    return;
                }
                const cmd = apps[i].cmd;
                i++;
                spawnShell(cmd, next);
            }
            next();
        }

        if (useNamed && wsName) {
            if (findWorkspaceByName(wsName))
                focusByName(wsName, afterFocus);
            else
                createWorkspace(wsName, afterFocus);
        } else {
            afterFocus();
        }
    }

    // Snapshot the focused workspace's windows into a template and persist it.
    function record(name, done) {
        const trimmed = (name || "").trim();
        if (!trimmed) {
            if (done)
                done(false, "name is required");
            return;
        }

        snapshotFocusedWorkspace((apps) => {
            const wsName = currentWorkspaceName() || trimmed;
            const t = { name: trimmed, workspace: wsName, apps: apps };

            const list = templates.slice();
            const existing = list.findIndex(x => x.name === trimmed);
            if (existing >= 0)
                list[existing] = t;
            else
                list.push(t);

            writeTemplates(list, (ok) => {
                if (ok) {
                    templates = list;
                    publishTemplates();
                }
                if (done)
                    done(ok, ok ? "" : "failed to save templates.json");
            });
        });
    }

    function snapshotFocusedWorkspace(done) {
        // NiriService.focusedWorkspaceId can be a number or a string depending
        // on which niri event populated it, so compare as strings.
        const focusedId = String(NiriService.focusedWorkspaceId);
        const wins = (NiriService.windows || []).filter(w => String(w.workspace_id) === focusedId);
        const apps = [];
        let remaining = wins.length;

        if (remaining === 0) {
            done(apps);
            return;
        }

        wins.forEach((w) => {
            readCmdline(w, (cmdline) => {
                const cmd = cmdline || w.app_id || "";
                apps.push({
                    name: w.app_id || w.title || cmd || ("window-" + w.id),
                    cmd: cmd,
                    appId: w.app_id || ""
                });
                remaining--;
                if (remaining === 0)
                    done(apps);
            });
        });
    }

    function readCmdline(w, done) {
        const pid = w.pid;
        if (!pid) {
            done("");
            return;
        }
        Proc.runCommand(
            "wsm.cmdline." + pid,
            ["sh", "-c", "tr '\\0' ' ' < /proc/" + pid + "/cmdline 2>/dev/null"],
            (out, code) => {
                done(code === 0 ? out.trim() : "");
            }
        );
    }

    // ------------------------------------------------------------------- list

    function listText() {
        const lines = [];
        lines.push("Workspaces:");
        for (const ws of (NiriService.allWorkspaces || [])) {
            const marker = ws.is_focused ? "*" : " ";
            const label = ws.name || ("#" + ws.idx);
            lines.push(` ${marker} ${label}  (output=${ws.output}, idx=${ws.idx})`);
        }
        lines.push("");
        lines.push("Templates:");
        for (const t of templates) {
            const count = (t.apps || []).length;
            const ws = t.workspace ? `  [workspace: ${t.workspace}]` : "";
            lines.push(` - ${t.name}${ws}  (${count} apps)`);
        }
        return lines.join("\n");
    }

    // -------------------------------------------------------------------- ipc

    IpcHandler {
        target: "workspaceManager"

        function create(name: string): string {
            root.createWorkspace(name, (ok, err) => {
                if (!ok) {
                    if (ToastService)
                        ToastService.showError("Workspace Manager", err || "Failed to create workspace");
                } else if (ToastService) {
                    ToastService.showInfo("Workspace Manager", name && name.trim() ? `Created workspace "${name.trim()}"` : "Created workspace");
                }
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
            root.launchTemplate(name, (ok, err) => {
                if (!ok && ToastService)
                    ToastService.showError("Workspace Manager", err || "Launch failed");
            });
            return "QUEUED";
        }

        function record(name: string): string {
            root.record(name, (ok, err) => {
                if (!ToastService)
                    return;
                if (ok)
                    ToastService.showInfo("Workspace Manager", `Recorded session as "${name.trim()}"`);
                else
                    ToastService.showError("Workspace Manager", err || "Record failed");
            });
            return "QUEUED";
        }

        function reload(): string {
            root.loadTemplates();
            return "QUEUED";
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
    }
}
