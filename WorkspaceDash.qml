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
// Two panes: Templates (edit / launch, diff-aware) and Live (rename, emoji,
// save a live workspace as a template). All writes go through the daemon's
// `workspaceManager` IPC target; structured state comes back as plugin global
// vars so the UI stays reactive.

DashTabComponent {
    id: root

    // ------------------------------------------------------------------- state

    property var templateList: PluginService.getGlobalVar(pluginId, "templates", [])
    property var liveList: PluginService.getGlobalVar(pluginId, "live", [])
    property var diffMap: PluginService.getGlobalVar(pluginId, "diffs", ({}))
    property var preview: PluginService.getGlobalVar(pluginId, "preview", null)
    property var previewApps: []
    property var statusObj: PluginService.getGlobalVar(pluginId, "status", null)

    property int pane: 0                     // 0 = templates, 1 = live
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

    readonly property string statusText: statusObj ? (statusObj.message || "") : ""
    readonly property bool thumbnailsEnabled: !root.pluginData || root.pluginData.liveThumbnails !== false
    readonly property var heroWorkspace: {
        const list = root.liveList || [];
        return list.find(w => w.focused) || list[0] || null;
    }
    readonly property int heroFocusedWindowId: {
        const hero = root.heroWorkspace;
        if (!hero || !hero.apps)
            return -1;
        const focused = hero.apps.find(a => a.focused);
        return focused ? focused.id : -1;
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
        flick.contentY = 0;
        settleTimer.restart();
    }

    // The dash reveals the focused item when it opens; that can leave the list
    // scrolled past the hero, so snap back once layout has settled.
    Timer {
        id: settleTimer
        interval: 200
        onTriggered: root.flickTop()
    }

    function flickTop() {
        if (flick && flick.contentY !== 0)
            flick.contentY = 0;
    }

    // Switching panes starts at the top, so the hero is the first thing seen.
    onPaneChanged: flick.contentY = 0

    function refresh() {
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

    function startLiveEdit(w) {
        liveDraftId = String(w.id);
        liveDraftName = w.name || ("Workspace " + w.idx);
        liveDraftEmoji = w.emoji || "";
    }

    function saveLiveEdit() {
        if (liveDraftId === "" || !liveDraftName.trim())
            return;
        send("rename", liveDraftId, liveDraftName.trim(), liveDraftEmoji);
        liveDraftId = "";
    }

    function captureLive(w) {
        send("previewWorkspace", String(w.id), w.name || ("Workspace " + w.idx), w.emoji || "");
        pane = 0;
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

        // ---- header (pinned: stays put while the list scrolls)
        Row {
            id: headerRow
            width: parent.width
            spacing: Theme.spacingXS

                DButton {
                    text: "Templates"
                    iconName: "dashboard_customize"
                    variant: root.pane === 0 ? "filled" : "tonal"
                    onClicked: root.pane = 0
                }

                DButton {
                    text: "Live"
                    iconName: "space_dashboard"
                    variant: root.pane === 1 ? "filled" : "tonal"
                    onClicked: root.pane = 1
                }

            DActionButton {
                buttonSize: Theme.iconButtonSize
                iconName: "refresh"
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceText
                backgroundColor: Theme.surfaceContainerHighest
                Accessible.name: "Refresh workspace state"
                onClicked: root.refresh()
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

            // ---- record / confirm card
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

                    DTextField {
                        id: recordNameField
                        width: parent.width
                        height: 40
                        text: root.recordName
                        placeholderText: "Template name (e.g. JobApp)"
                        backgroundColor: Theme.surfaceContainerHighest
                        textColor: Theme.surfaceText
                        onTextEdited: root.recordName = text
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DTextField {
                            id: recordEmojiField
                            width: 64
                            height: 40
                            text: root.recordEmoji
                            placeholderText: "🧳"
                            backgroundColor: Theme.surfaceContainerHighest
                            textColor: Theme.surfaceText
                            onTextEdited: root.recordEmoji = text
                        }

                        DButton {
                            height: 40
                            text: root.preview ? "Recapture" : "Capture"
                            iconName: "photo_camera"
                            variant: "tonal"
                            onClicked: root.send("previewRecord", root.recordName, root.recordEmoji)
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - 64 - 150 - Theme.spacingS * 2)
                            text: root.preview ? (root.preview.workspace + " · " + root.previewApps.length + " app(s)") : ""
                            color: Theme.onSurfaceVariant
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
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

            // ---- templates
            Column {
                width: parent.width
                spacing: Theme.spacingS
                visible: root.pane === 0

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

                Repeater {
                    model: root.templateList

                    delegate: StyledRect {
                        id: templateCard
                        required property var modelData

                        readonly property bool editing: root.editingName === modelData.name
                        readonly property var missing: root.missingFor(modelData.name)
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
                                    text: templateCard.missing.length === 0 ? "All open" : "Launch (" + templateCard.missing.length + ")"
                                    iconName: "rocket_launch"
                                    variant: templateCard.missing.length === 0 ? "tonal" : "filled"
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
                                    text: templateCard.editing ? "Close" : "Edit"
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

            // ---- live workspaces
            Column {
                width: parent.width
                spacing: Theme.spacingS
                visible: root.pane === 1

                StyledText {
                    text: "Live workspaces"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                }

                // hero: the focused workspace, previewed live
                StyledRect {
                    width: parent.width
                    height: heroColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.heroWorkspace !== null

                    Column {
                        id: heroColumn

                        x: Theme.spacingM
                        y: Theme.spacingM
                        width: parent.width - Theme.spacingM * 2
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.heroWorkspace && root.heroWorkspace.emoji ? root.heroWorkspace.emoji : "◦"
                                font.pixelSize: Theme.fontSizeXXLarge
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 60
                                spacing: 1

                                StyledText {
                                    text: root.heroWorkspace
                                          ? (root.heroWorkspace.name || ("Workspace " + root.heroWorkspace.idx))
                                          : ""
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.heroWorkspace
                                          ? root.heroWorkspace.output + " · #" + root.heroWorkspace.idx
                                            + " · " + root.heroWorkspace.windowCount + " windows"
                                            + (root.thumbnailsEnabled ? " · live" : "")
                                          : ""
                                    color: Theme.onSurfaceVariant
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Local.WorkspacePreview {
                            width: parent.width
                            workspace: root.heroWorkspace
                            live: root.live
                            wantThumbnails: root.thumbnailsEnabled
                            activeWindowId: root.heroFocusedWindowId
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: root.groupedApps(root.heroWorkspace ? root.heroWorkspace.apps : [])

                                delegate: Local.AppChip {
                                    required property var modelData

                                    chipSize: 22
                                    appId: modelData.appId
                                    label: modelData.name
                                    count: modelData.count
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: root.liveList

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
                            spacing: Theme.spacingXS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (liveCard.modelData.emoji ? liveCard.modelData.emoji + "  " : "")
                                          + (liveCard.modelData.name || ("Workspace " + liveCard.modelData.idx))
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - 150)
                                    text: liveCard.modelData.output + " · #" + liveCard.modelData.idx
                                          + " · " + liveCard.modelData.windowCount + " windows"
                                    color: Theme.onSurfaceVariant
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: root.groupedApps(liveCard.modelData.apps)

                                    delegate: Local.AppChip {
                                        required property var modelData

                                        chipSize: 22
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

                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS

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

                            // close confirm strip
                            Row {
                                width: parent.width
                                spacing: Theme.spacingS
                                visible: liveCard.closing

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(120, parent.width * 0.42)
                                    text: "Close " + (liveCard.modelData.name || ("workspace #" + liveCard.modelData.idx)) + "?"
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
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: root.liveList.length === 0
                    text: "No workspaces reported yet."
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeSmall
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
