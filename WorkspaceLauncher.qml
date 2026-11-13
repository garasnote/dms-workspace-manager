import QtQuick
import Quickshell
import qs.Services

Item {
    id: root

    // Launcher surfaces are only injected with `pluginService`, not `pluginId`,
    // so the id is hardcoded here.
    readonly property string myPluginId: "workspaceManager"

    property var pluginService: null
    property string trigger: "ws"

    signal itemsChanged()

    property var templateList: PluginService.getGlobalVar(myPluginId, "templates", [])
    property var workspaceList: NiriService.allWorkspaces

    Connections {
        target: PluginService
        function onGlobalVarChanged(changedId, varName) {
            if (changedId !== myPluginId || varName !== "templates")
                return;
            root.templateList = PluginService.getGlobalVar(myPluginId, "templates", []);
            root.itemsChanged();
        }
    }

    function ipc(fn, arg) {
        Quickshell.execDetached(["dms", "ipc", "call", "workspaceManager", fn, arg || ""]);
    }

    function getItems(query) {
        const items = [];

        items.push({
            name: "New workspace",
            icon: "material:add",
            comment: "Create and focus a new niri workspace",
            action: JSON.stringify({ t: "create", name: "" }),
            categories: ["Workspaces"]
        });

        for (const ws of workspaceList) {
            if (ws.name) {
                items.push({
                    name: "Focus: " + ws.name,
                    icon: "material:space_dashboard",
                    comment: "Named workspace on " + ws.output,
                    action: JSON.stringify({ t: "focus", name: ws.name }),
                    categories: ["Workspaces"]
                });
            }
        }

        for (const t of templateList) {
            const count = (t.apps || []).length;
            const emoji = t.emoji ? t.emoji + " " : "";
            items.push({
                name: emoji + "Launch: " + t.name,
                icon: "material:rocket_launch",
                comment: count + " apps" + (t.workspace ? " · " + t.workspace : " · current workspace"),
                action: JSON.stringify({ t: "launch", name: t.name }),
                categories: ["Workspaces"]
            });
        }

        if (!query)
            return items;

        const q = query.toLowerCase();
        return items.filter(i =>
            i.name.toLowerCase().includes(q) || i.comment.toLowerCase().includes(q));
    }

    function executeItem(item) {
        let a;
        try {
            a = JSON.parse(item.action);
        } catch (e) {
            return;
        }

        const fn = a.t === "launch" ? "launch" : (a.t === "focus" ? "activate" : "create");
        ipc(fn, a.name || "");
    }

    Component.onCompleted: {
        templateList = pluginService ? pluginService.getGlobalVar(myPluginId, "templates", []) : [];
        itemsChanged();
    }
}
