import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins
import qs.Modules.DDash
import "." as Local

// Workspace Manager
//
// Live workspaces are the main view: every workspace gets a live mini-map with
// its own actions underneath. Templates (saved environments) are the secondary
// pane. All writes go through the daemon's `workspaceManager` IPC target;
// structured state comes back as plugin global vars so the UI stays reactive.

DashTabComponent {
    id: root

    // ------------------------------------------------------------------- state

    property var templateList: PluginService.getGlobalVar(pluginId, "templates", [])
    property var liveList: PluginService.getGlobalVar(pluginId, "live", [])
    property var diffMap: PluginService.getGlobalVar(pluginId, "diffs", ({}))
    property var preview: PluginService.getGlobalVar(pluginId, "preview", null)
    property var previewApps: []
    property var statusObj: PluginService.getGlobalVar(pluginId, "status", null)

    property int pane: 0                     // 0 = live (default), 1 = templates
    property string editingName: ""
    property var draft: null
    property string newAppText: ""
    property string recordName: ""
    property string recordEmoji: ""
    property string liveDraftId: ""
    property string liveDraftName: ""
    property string liveDraftEmoji: ""
    property string pendingDelete: ""
    property string closeArmId: ""
    property bool undoArmed: false
    property string expandedId: ""

    readonly property string statusText: statusObj ? (statusObj.message || "") : ""
    readonly property bool canUndoClose: root.undoArmed
    // Undo stays offered for two minutes; the daemon keeps its own ten-minute copy.
    onStatusTextChanged: {
        if (root.statusText.indexOf("Closed ") === 0 || root.statusText.indexOf("Removed the name") === 0) {
            root.undoArmed = true;
            undoWindow.restart();
        }
    }

    Timer {
        id: undoWindow
        interval: 120000
        onTriggered: root.undoArmed = false
    }
    readonly property bool showEmpty: !root.pluginData || root.pluginData.showEmptyWorkspaces === true
    readonly property bool compactRows: !!root.pluginData && root.pluginData.compactLiveRows === true

    // Empty, unnamed workspaces are niri's filler (there is always one at the
    // bottom of every monitor); they would drown out the real ones.
    readonly property var visibleLive: {
        const list = root.liveList || [];
        return list.filter(w => {
            if (w.focused)
                return true;
            if ((w.windowCount || 0) > 0)
                return true;
            if ((w.name || "") !== "")
                return true;
            return root.showEmpty;
        });
    }

    readonly property int hiddenEmptyCount: {
        const list = root.liveList || [];
        return list.filter(w => !w.focused && !(w.windowCount > 0) && (w.name || "") === "").length;
    }

    implicitHeight: DashMetrics.tabDefaultHeight
    focusTarget: flick

    // ------------------------------------------------------------- state sync

    Connections {
        target: PluginService

        function onGlobalVarChanged(changedId, varName) {
            if (changedId !== pluginId)
                return;
            if (varName === "templates")
                root.templateList = PluginService.getGlobalVar(pluginId, "templates", []);
            else if (varName === "live")
                root.liveList = PluginService.getGlobalVar(pluginId, "live", []);
            else if (varName === "diffs")
                root.diffMap = PluginService.getGlobalVar(pluginId, "diffs", ({}));
            else if (varName === "preview")
                root.adoptPreview(PluginService.getGlobalVar(pluginId, "preview", null));
            else if (varName === "status")
                root.statusObj = PluginService.getGlobalVar(pluginId, "status", null);
        }
    }

    Component.onCompleted: {
        adoptPreview(preview);
        refresh();
    }

    onLiveChanged: {
        if (!live)
            return;
        refresh();
        settleTimer.restart();
    }

    // The dash reveals the focused item when it opens, which leaves the list
    // scrolled into the middle of a card (and hides the Workspaces heading).
    // Snap back to the top twice, because the reveal can come after the first
    // pass; the second pass yields if you already started scrolling.
    Timer {
        id: settleTimer
        interval: 400
        onTriggered: {
            root.flickTop();
            lateSettleTimer.restart();
        }
    }

    Timer {
        id: lateSettleTimer
        interval: 600
        onTriggered: {
            if (!flick.moving)
                root.flickTop();
        }
    }

    onPaneChanged: {
        flick.contentY = 0;
        settleTimer.restart();
    }

    function flickTop() {
        if (flick && flick.contentY !== 0)
            flick.contentY = 0;
    }

    // Re-reading templates.json on open means hand edits show up without a
    // reload button; state updates themselves are event-driven.
    // Put ready-to-paste keybindings on the clipboard. This is the one place the
    // plugin writes to the clipboard on purpose, instead of borrowing it.
    function copyHotkeys() {
        const snippets = PluginService.getGlobalVar(pluginId, "hotkeys", "");
        if (!snippets)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "wsm", snippets]);
        root.send("refreshLive");
    }

    // Focus one window from the mini-map and dismiss the panel, the way a dock
    // click would.
    function focusWindow(windowId) {
        if (!windowId)
            return;
        send("focusWindow", windowId);
        if (root.dashHost)
            root.dashHost.dashVisible = false;
    }

    function refresh() {
        send("reload");
        send("refreshLive");
    }

    function adoptPreview(p) {
        preview = p;
        previewApps = p ? JSON.parse(JSON.stringify(p.apps || [])) : [];
        if (p) {
            recordName = p.name || "";
            recordEmoji = p.emoji || "";
        }
    }

    // ----------------------------------------------------------------- helpers

    function send() {
        const argv = ["dms", "ipc", "call", "workspaceManager"];
        for (let i = 0; i < arguments.length; i++)
            argv.push(String(arguments[i]));
        Quickshell.execDetached(argv);
    }

    function clone(obj) {
        return JSON.parse(JSON.stringify(obj));
    }

    function missingFor(name) {
        const d = diffMap ? diffMap[name] : null;
        return d && d.missing ? d.missing : [];
    }

    function appName(app) {
        return typeof app === "string" ? app : (app.name || app.cmd || "");
    }

    function appIdOf(app) {
        return typeof app === "string" ? "" : (app.appId || "");
    }

    function appCmdOf(app) {
        return typeof app === "string" ? app : (app.cmd || app.name || "");
    }

    function appMissing(templateName, app) {
        return missingFor(templateName).indexOf(appName(app)) >= 0;
    }

    // Windows grouped by app, so a workspace with four Ghostty terminals shows
    // one chip with a "4" badge.
    function groupedApps(apps) {
        const out = [];
        const index = {};
        const list = apps || [];
        for (const app of list) {
            const key = app.appId || app.name || "";
            if (index[key] !== undefined) {
                out[index[key]].count++;
                continue;
            }
            index[key] = out.length;
            out.push({
                appId: app.appId || "",
                name: app.name || "",
                count: 1
            });
        }
        return out;
    }

    function focusedWindowId(apps) {
        const list = apps || [];
        const focused = list.find(a => a.focused);
        return focused ? focused.id : -1;
    }

    function rowExpanded(workspace) {
        if (!root.compactRows)
            return true;
        return root.expandedId === String(workspace.id);
    }

    function toggleRow(workspace) {
        const id = String(workspace.id);
        root.expandedId = (root.expandedId === id) ? "" : id;
    }

    function workspaceLabel(workspace) {
        if (!workspace)
            return "";
        return workspace.name || ("Workspace " + workspace.idx);
    }

    // ---- templates editing

    function startEdit(t) {
        editingName = t.name;
        draft = clone(t);
        if (!draft.apps)
            draft.apps = [];
        newAppText = "";
    }

    function cancelEdit() {
        editingName = "";
        draft = null;
        newAppText = "";
    }

    function saveEdit() {
        if (!draft || !String(draft.name || "").trim())
            return;
        send("saveTemplate", JSON.stringify({
            originalName: editingName,
            template: draft
        }));
        cancelEdit();
    }

    function removeDraftApp(index) {
        if (!draft)
            return;
        const d = clone(draft);
        d.apps.splice(index, 1);
        draft = d;
    }

    function addDraftApp() {
        const text = newAppText.trim();
        if (!draft || !text)
            return;
        const d = clone(draft);
        if (!d.apps)
            d.apps = [];
        d.apps.push({
            name: text,
            cmd: text
        });
        draft = d;
        newAppText = "";
    }

    function toggleAlwaysLaunch(index) {
        if (!draft || !draft.apps || !draft.apps[index])
            return;
        const d = clone(draft);
        d.apps[index].alwaysLaunch = !d.apps[index].alwaysLaunch;
        draft = d;
    }

    // Two-step delete: the trash button arms, a second click removes.
    function requestDelete(name) {
        if (pendingDelete === name) {
            pendingDelete = "";
            send("deleteTemplate", name);
            return;
        }
        pendingDelete = name;
        deleteArmTimer.restart();
    }

    Timer {
        id: deleteArmTimer
        interval: 4000
        onTriggered: root.pendingDelete = ""
    }

    // ---- capture

    function removePreviewApp(index) {
        const apps = previewApps.slice();
        apps.splice(index, 1);
        previewApps = apps;
    }

    function savePreview() {
        const name = recordName.trim();
        if (!name || previewApps.length === 0)
            return;
        const t = {
            name: name,
            emoji: recordEmoji,
            workspace: (preview && preview.workspace) || name,
            notes: "",
            apps: previewApps
        };
        send("saveTemplate", JSON.stringify({
            originalName: name,
            template: t
        }));
        send("clearPreview");
        preview = null;
        previewApps = [];
        recordName = "";
        recordEmoji = "";
    }

    // ---- live workspace actions

    function startLiveEdit(w) {
        liveDraftId = String(w.id);
        liveDraftName = w.name || ("Workspace " + w.idx);
        liveDraftEmoji = w.emoji || "";
        closeArmId = "";
    }

    function saveLiveEdit() {
        if (liveDraftId === "" || !liveDraftName.trim())
            return;
        send("rename", liveDraftId, liveDraftName.trim(), liveDraftEmoji);
        liveDraftId = "";
    }

    // Shortcut for "ask me about the workspace I am looking at".
    function captureFocused() {
        const focused = (root.liveList || []).filter(w => w.focused);
        if (focused.length === 0)
            return;
        root.captureLive(focused[0]);
    }

    function captureLive(w) {
        send("previewWorkspace", String(w.id), w.name || ("Workspace " + w.idx), w.emoji || "");
        pane = 1;
    }

    // Closing a live workspace is destructive, so it always goes through a
    // confirm strip: close everything, or only forget the name.
    function armClose(id) {
        closeArmId = (closeArmId === String(id)) ? "" : String(id);
        closeTimer.restart();
    }

    function closeWorkspace(w, withWindows) {
        closeArmId = "";
        send("closeWorkspace", String(w.id), withWindows ? "true" : "false");
    }

    Timer {
        id: closeTimer
        interval: 8000
        onTriggered: root.closeArmId = ""
    }

    // -------------------------------------------------------------------- view

    Column {
        anchors.fill: parent
        spacing: Theme.spacingS

        // ---- pinned header
        Row {
            id: headerRow

            width: parent.width
            spacing: Theme.spacingXS

            DButton {
                text: "Live"
                iconName: "space_dashboard"
                variant: root.pane === 0 ? "filled" : "tonal"
                onClicked: root.pane = 0
            }

            DButton {
                text: "Templates"
                iconName: "dashboard_customize"
                variant: root.pane === 1 ? "filled" : "tonal"
                onClicked: root.pane = 1
            }

            Item {
                width: Math.max(0, parent.width - 340)
                height: 1
            }

            // Closing a workspace throws its windows away; this brings it back
            // (the name, the emoji and a fresh launch of what was there).
            DButton {
                visible: root.canUndoClose
                text: "Undo close"
                iconName: "undo"
                variant: "tonal"
                onClicked: {
                    root.send("undoClose");
                    root.undoArmed = false;
                }
            }
        }

        StyledText {
            width: parent.width
            visible: root.statusText !== ""
            text: root.statusText
            color: Theme.onSurfaceVariant
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Flickable {
            id: flick

            focus: true
            activeFocusOnTab: true
            width: parent.width
            height: Math.max(1, parent.height - y)
            clip: true
            contentWidth: width
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Column {
                id: content

                width: flick.width
                spacing: Theme.spacingM

                // =================================================== live pane
                Column {
                    id: liveRows

                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.pane === 0

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "Workspaces"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - 220)
                            visible: root.hiddenEmptyCount > 0
                            text: root.hiddenEmptyCount + " empty hidden"
                            color: Theme.withAlpha(Theme.onSurfaceVariant, 0.8)
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    Repeater {
                        model: root.visibleLive

                        delegate: StyledRect {
                            id: liveCard

                            required property var modelData

                            readonly property bool editing: root.liveDraftId === String(modelData.id)
                            readonly property bool closing: root.closeArmId === String(modelData.id)
                            readonly property bool named: (modelData.name || "") !== ""

                            width: content.width
                            height: liveColumn.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: modelData.focused ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            Column {
                                id: liveColumn

                                x: Theme.spacingM
                                y: Theme.spacingM
                                width: parent.width - Theme.spacingM * 2
                                spacing: Theme.spacingS

                                // identity (in compact mode, clicking it toggles the preview)
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    TapHandler {
                                        enabled: root.compactRows
                                        onTapped: root.toggleRow(liveCard.modelData)
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: liveCard.modelData.emoji ? liveCard.modelData.emoji : "◦"
                                        font.pixelSize: Theme.fontSizeLarge
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.workspaceLabel(liveCard.modelData)
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(0, parent.width - 270)
                                        text: liveCard.modelData.output + " · #" + liveCard.modelData.idx
                                              + " · " + liveCard.modelData.windowCount + " windows"
                                        color: Theme.onSurfaceVariant
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }

                                    DActionButton {
                                        visible: root.compactRows
                                        anchors.verticalCenter: parent.verticalCenter
                                        buttonSize: Theme.iconButtonSize
                                        iconSize: Theme.iconSizeSmall
                                        iconName: root.rowExpanded(liveCard.modelData) ? "expand_less" : "expand_more"
                                        iconColor: Theme.surfaceText
                                        backgroundColor: "transparent"
                                        Accessible.name: root.rowExpanded(liveCard.modelData) ? "Hide preview" : "Show preview"
                                        onClicked: root.toggleRow(liveCard.modelData)
                                    }
                                }

                                // compact mode: chips stay visible, the preview does not
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS
                                    visible: root.compactRows && !root.rowExpanded(liveCard.modelData)

                                    Repeater {
                                        model: root.groupedApps(liveCard.modelData.apps)

                                        delegate: Local.AppChip {
                                            required property var modelData

                                            chipSize: 20
                                            appId: modelData.appId
                                            label: modelData.name
                                            count: modelData.count
                                        }
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: liveCard.modelData.windowCount === 0
                                        text: "no windows"
                                        color: Theme.withAlpha(Theme.onSurfaceVariant, 0.7)
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.italic: true
                                    }
                                }

                                // the mini-map: every workspace gets one, empty
                                // workspaces show a placeholder frame
                                Local.WorkspacePreview {
                                    visible: root.rowExpanded(liveCard.modelData)
                                    width: parent.width
                                    previewHeight: 88
                                    workspace: liveCard.modelData
                                    live: root.live
                                    activeWindowId: root.focusedWindowId(liveCard.modelData.apps)
                                    onWindowActivated: windowId => root.focusWindow(windowId)
                                }

                                // actions, directly under the preview
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS
                                    visible: root.rowExpanded(liveCard.modelData)

                                    DButton {
                                        text: "Focus"
                                        iconName: "open_in_full"
                                        variant: "tonal"
                                        enabled: !liveCard.modelData.focused
                                        onClicked: root.send("focusId", String(liveCard.modelData.id))
                                    }

                                    DButton {
                                        text: "Save…"
                                        iconName: "bookmark_add"
                                        enabled: liveCard.modelData.windowCount > 0
                                        onClicked: root.captureLive(liveCard.modelData)
                                    }

                                    DButton {
                                        text: liveCard.editing ? "Done" : "Rename"
                                        iconName: "edit"
                                        variant: "tonal"
                                        onClicked: {
                                            if (liveCard.editing)
                                                root.liveDraftId = "";
                                            else
                                                root.startLiveEdit(liveCard.modelData);
                                        }
                                    }

                                    DButton {
                                        text: "Close"
                                        iconName: "delete"
                                        variant: liveCard.closing ? "filled" : "tonal"
                                        enabled: liveCard.named || liveCard.modelData.windowCount > 0
                                        Accessible.name: "Close this workspace"
                                        onClicked: root.armClose(liveCard.modelData.id)
                                    }
                                }

                                // rename editor
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS
                                    visible: liveCard.editing

                                    DTextField {
                                        width: 64
                                        height: 36
                                        text: root.liveDraftEmoji
                                        placeholderText: "emoji"
                                        backgroundColor: Theme.surfaceContainerHighest
                                        textColor: Theme.surfaceText
                                        onTextEdited: root.liveDraftEmoji = text
                                    }

                                    DTextField {
                                        width: Math.max(120, parent.width - 64 - 90 - Theme.spacingS * 2)
                                        height: 36
                                        text: root.liveDraftName
                                        placeholderText: "Workspace name"
                                        backgroundColor: Theme.surfaceContainerHighest
                                        textColor: Theme.surfaceText
                                        onTextEdited: root.liveDraftName = text
                                    }

                                    DButton {
                                        height: 36
                                        text: "Save"
                                        iconName: "save"
                                        onClicked: root.saveLiveEdit()
                                    }
                                }

                                Local.EmojiPalette {
                                    width: parent.width
                                    visible: liveCard.editing
                                    current: root.liveDraftEmoji
                                    onPicked: emoji => root.liveDraftEmoji = emoji
                                }

                                // close confirm strip
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS
                                    visible: liveCard.closing

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(120, parent.width * 0.38)
                                        text: "Close " + root.workspaceLabel(liveCard.modelData) + "?"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.Wrap
                                    }

                                    DButton {
                                        height: 36
                                        text: liveCard.modelData.windowCount > 0
                                              ? "Close + " + liveCard.modelData.windowCount + " windows"
                                              : "Remove workspace"
                                        iconName: "close"
                                        variant: "filled"
                                        onClicked: root.closeWorkspace(liveCard.modelData, liveCard.modelData.windowCount > 0)
                                    }

                                    DButton {
                                        height: 36
                                        text: "Unname only"
                                        iconName: "label_off"
                                        variant: "tonal"
                                        visible: liveCard.named && liveCard.modelData.windowCount > 0
                                        onClicked: root.closeWorkspace(liveCard.modelData, false)
                                    }

                                    DButton {
                                        height: 36
                                        text: "Cancel"
                                        variant: "text"
                                        onClicked: root.closeArmId = ""
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: root.visibleLive.length === 0
                        text: "No workspaces reported yet."
                        color: Theme.onSurfaceVariant
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                // ============================================ templates pane
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.pane === 1

                    // capture / confirm card
                    StyledRect {
                        width: parent.width
                        height: recordColumn.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            id: recordColumn

                            x: Theme.spacingM
                            y: Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS

                            StyledText {
                                text: root.preview ? "Confirm what gets saved" : "Save a workspace as a template"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                            }

                            // One way to save, reachable from two places: Save… on a
                            // workspace card, or this shortcut for the focused one.
                            // There is deliberately no second form with its own name
                            // field — that is what made the old UI feel like two
                            // different features.
                            Row {
                                width: parent.width
                                spacing: Theme.spacingS
                                visible: root.preview === null

                                DButton {
                                    text: "Save the current workspace…"
                                    iconName: "bookmark_add"
                                    variant: "filled"
                                    onClicked: root.captureFocused()
                                }
                            }

                            DTextField {
                                id: recordNameField

                                width: parent.width
                                height: 40
                                visible: root.preview !== null
                                text: root.recordName
                                placeholderText: "Template name (e.g. JobApp)"
                                backgroundColor: Theme.surfaceContainerHighest
                                textColor: Theme.surfaceText
                                onTextEdited: root.recordName = text
                            }

                            Local.EmojiPalette {
                                width: parent.width
                                visible: root.preview !== null
                                current: root.recordEmoji
                                onPicked: emoji => root.recordEmoji = emoji
                            }

                            StyledText {
                                width: parent.width
                                visible: root.preview !== null
                                text: root.preview ? (root.preview.workspace + " · " + root.previewApps.length + " app(s) — prune the list, then save") : ""
                                color: Theme.onSurfaceVariant
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: root.previewApps

                                delegate: Row {
                                    required property var modelData
                                    required property int index

                                    width: recordColumn.width
                                    height: 30
                                    spacing: Theme.spacingS

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 36
                                        text: (modelData.name || "") + "   ·   " + (modelData.cmd || "")
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideMiddle
                                    }

                                    DActionButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        buttonSize: Theme.iconButtonSize
                                        iconName: "close"
                                        iconSize: Theme.iconSizeSmall
                                        iconColor: Theme.surfaceText
                                        backgroundColor: Theme.surfaceContainerHighest
                                        Accessible.name: "Remove app"
                                        onClicked: root.removePreviewApp(index)
                                    }
                                }
                            }

                            StyledText {
                                width: parent.width
                                visible: root.preview !== null && root.previewApps.length === 0
                                text: "No windows on that workspace — open something first, then capture again."
                                color: Theme.onSurfaceVariant
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }

                            Row {
                                visible: root.preview !== null
                                spacing: Theme.spacingS

                                DButton {
                                    text: "Save template"
                                    iconName: "save"
                                    enabled: root.recordName.trim() !== "" && root.previewApps.length > 0
                                    onClicked: root.savePreview()
                                }

                                DButton {
                                    text: "Discard"
                                    iconName: "undo"
                                    variant: "text"
                                    onClicked: {
                                        root.send("clearPreview");
                                        root.adoptPreview(null);
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        text: "Templates"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }

                    StyledText {
                        width: parent.width
                        text: "Deleting a template never closes a workspace — close workspaces from the Live pane."
                        color: Theme.onSurfaceVariant
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                    }

                    // templates are portable: a friend can send you their file
                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        DButton {
                            text: "Export…"
                            iconName: "download"
                            variant: "tonal"
                            onClicked: root.send("exportTemplates", "/tmp/workspace-manager-templates.json")
                        }

                        DButton {
                            text: "Import…"
                            iconName: "upload"
                            variant: "tonal"
                            onClicked: root.send("importTemplates", "/tmp/workspace-manager-templates.json")
                        }

                        DButton {
                            text: "Keys"
                            iconName: "keyboard"
                            variant: "tonal"
                            onClicked: root.copyHotkeys()
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - 260)
                            text: "/tmp/workspace-manager-templates.json · gist-safe, one JSON file"
                            color: Theme.withAlpha(Theme.onSurfaceVariant, 0.8)
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    Repeater {
                        model: root.templateList

                        delegate: StyledRect {
                            id: templateCard

                            required property var modelData

                            readonly property bool editing: root.editingName === modelData.name
                            readonly property var missing: root.missingFor(modelData.name)
                            readonly property int pending: missing.length

                            width: content.width
                            height: templateColumn.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: templateCard.editing ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            Column {
                                id: templateColumn

                                x: Theme.spacingM
                                y: Theme.spacingM
                                width: parent.width - Theme.spacingM * 2
                                spacing: Theme.spacingS

                                // line 1: identity
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (templateCard.modelData.emoji ? templateCard.modelData.emoji + "  " : "") + templateCard.modelData.name
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(0, parent.width - 160)
                                        text: (templateCard.modelData.workspace ? "→ " + templateCard.modelData.workspace + " · " : "")
                                              + (templateCard.modelData.apps || []).length + " apps"
                                        color: Theme.onSurfaceVariant
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }
                                }

                                // line 2: app icons (dimmed = would be launched)
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    Repeater {
                                        model: templateCard.modelData.apps || []

                                        delegate: Local.AppChip {
                                            required property var modelData

                                            chipSize: 24
                                            appId: root.appIdOf(modelData)
                                            cmd: root.appCmdOf(modelData)
                                            label: root.appName(modelData)
                                            dimmed: root.appMissing(templateCard.modelData.name, modelData)
                                            ringed: root.appMissing(templateCard.modelData.name, modelData)
                                            ringColor: Theme.withAlpha(Theme.primary, 0.55)
                                        }
                                    }
                                }

                                // line 3: actions
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    DButton {
                                        text: templateCard.pending === 0 ? "All open" : "Launch (" + templateCard.pending + ")"
                                        iconName: "rocket_launch"
                                        variant: templateCard.pending === 0 ? "tonal" : "filled"
                                        onClicked: root.send("launch", templateCard.modelData.name)
                                    }

                                    DActionButton {
                                        buttonSize: Theme.iconButtonSize
                                        iconName: "restart_alt"
                                        iconSize: Theme.iconSizeSmall
                                        iconColor: Theme.surfaceText
                                        backgroundColor: Theme.surfaceContainerHighest
                                        Accessible.name: "Relaunch every app"
                                        onClicked: root.send("launchAll", templateCard.modelData.name)
                                    }

                                    DButton {
                                        text: templateCard.editing ? "Done" : "Edit"
                                        iconName: "edit"
                                        variant: "tonal"
                                        onClicked: {
                                            if (templateCard.editing)
                                                root.cancelEdit();
                                            else
                                                root.startEdit(templateCard.modelData);
                                        }
                                    }

                                    DActionButton {
                                        readonly property bool armed: root.pendingDelete === templateCard.modelData.name

                                        buttonSize: Theme.iconButtonSize
                                        iconName: armed ? "delete_forever" : "delete"
                                        iconSize: Theme.iconSizeSmall
                                        iconColor: Theme.error
                                        backgroundColor: armed ? Theme.errorContainer : Theme.surfaceContainerHighest
                                        Accessible.name: armed ? "Click again to delete" : "Delete template"
                                        onClicked: root.requestDelete(templateCard.modelData.name)
                                    }
                                }

                                // line 4: edit panel
                                Column {
                                    width: parent.width
                                    spacing: Theme.spacingS
                                    visible: templateCard.editing && root.draft !== null

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        DTextField {
                                            width: 64
                                            height: 40
                                            text: root.draft ? root.draft.emoji : ""
                                            placeholderText: "emoji"
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onTextEdited: if (root.draft) root.draft.emoji = text
                                        }

                                        DTextField {
                                            width: Math.max(120, (parent.width - 64 - Theme.spacingS * 2) * 0.5)
                                            height: 40
                                            text: root.draft ? root.draft.name : ""
                                            placeholderText: "Template name"
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onTextEdited: if (root.draft) root.draft.name = text
                                        }

                                        DTextField {
                                            width: Math.max(120, (parent.width - 64 - Theme.spacingS * 2) * 0.5 - 4)
                                            height: 40
                                            text: root.draft ? root.draft.workspace : ""
                                            placeholderText: "niri workspace"
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onTextEdited: if (root.draft) root.draft.workspace = text
                                        }
                                    }

                                    Local.EmojiPalette {
                                        width: parent.width
                                        current: root.draft ? root.draft.emoji : ""
                                        onPicked: emoji => {
                                            if (root.draft)
                                                root.draft.emoji = emoji;
                                        }
                                    }

                                    Repeater {
                                        model: root.draft ? root.draft.apps : []

                                        delegate: Row {
                                            required property var modelData
                                            required property int index

                                            width: templateColumn.width
                                            height: 34
                                            spacing: Theme.spacingXS

                                            DTextField {
                                                width: Math.max(100, parent.width * 0.32)
                                                height: 32
                                                text: modelData.name || ""
                                                backgroundColor: Theme.surfaceContainerHighest
                                                textColor: Theme.surfaceText
                                                onTextEdited: {
                                                    if (root.draft)
                                                        root.draft.apps[index].name = text;
                                                }
                                            }

                                            DTextField {
                                                width: Math.max(120, parent.width * 0.44)
                                                height: 32
                                                text: modelData.cmd || ""
                                                backgroundColor: Theme.surfaceContainerHighest
                                                textColor: Theme.surfaceText
                                                onTextEdited: {
                                                    if (root.draft)
                                                        root.draft.apps[index].cmd = text;
                                                }
                                            }

                                            DActionButton {
                                                buttonSize: Theme.iconButtonSize
                                                iconName: modelData.alwaysLaunch ? "bolt" : "bolt_off"
                                                iconSize: Theme.iconSizeSmall
                                                iconColor: modelData.alwaysLaunch ? Theme.primary : Theme.onSurfaceVariant
                                                backgroundColor: Theme.surfaceContainerHighest
                                                Accessible.name: "Always rerun this app"
                                                onClicked: root.toggleAlwaysLaunch(index)
                                            }

                                            DActionButton {
                                                buttonSize: Theme.iconButtonSize
                                                iconName: "close"
                                                iconSize: Theme.iconSizeSmall
                                                iconColor: Theme.error
                                                backgroundColor: Theme.surfaceContainerHighest
                                                Accessible.name: "Remove app"
                                                onClicked: root.removeDraftApp(index)
                                            }
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        DTextField {
                                            width: Math.max(120, parent.width - addAppButton.width - Theme.spacingS)
                                            height: 36
                                            text: root.newAppText
                                            placeholderText: "Add app command"
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onTextEdited: root.newAppText = text
                                        }

                                        DButton {
                                            id: addAppButton

                                            height: 36
                                            text: "Add"
                                            iconName: "add"
                                            variant: "tonal"
                                            onClicked: root.addDraftApp()
                                        }
                                    }

                                    Row {
                                        spacing: Theme.spacingS

                                        DButton {
                                            text: "Save template"
                                            iconName: "save"
                                            onClicked: root.saveEdit()
                                        }

                                        DButton {
                                            text: "Cancel"
                                            iconName: "undo"
                                            variant: "text"
                                            onClicked: root.cancelEdit()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: Theme.spacingS
                }
            }
        }
    }
}
