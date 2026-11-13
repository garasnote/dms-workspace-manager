import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins
import qs.Modules.DDash

DashTabComponent {
    id: root

    property var workspaceList: NiriService.allWorkspaces
    property var templateList: PluginService.getGlobalVar(pluginId, "templates", [])

    implicitHeight: Math.max(DashMetrics.tabMinHeight, content.implicitHeight + Theme.spacingL * 2)

    Connections {
        target: PluginService
        function onGlobalVarChanged(changedId, varName) {
            if (changedId !== pluginId || varName !== "templates")
                return;
            root.templateList = PluginService.getGlobalVar(pluginId, "templates", []);
        }
    }

    function ipc(fn, arg) {
        Quickshell.execDetached(["dms", "ipc", "call", "workspaceManager", fn, arg || ""]);
    }

    function workspaceLabel(ws) {
        return ws.name ? ws.name : ("Workspace " + ws.idx);
    }

    Column {
        id: content
        width: parent.width
        spacing: Theme.spacingL

        StyledText {
            width: parent.width
            text: "Workspaces"
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
        }

        Repeater {
            model: root.workspaceList
            delegate: StyledRect {
                width: content.width
                height: 44
                radius: Theme.cornerRadius
                color: modelData.is_focused ? Theme.primaryContainer : Theme.surfaceContainerHigh

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.workspaceLabel(modelData) + (modelData.is_focused ? "  ·  focused" : "")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }

                DButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Focus"
                    iconName: "open_in_full"
                    variant: "tonal"
                    enabled: !modelData.is_focused
                    onClicked: root.ipc("focusId", String(modelData.id))
                }
            }
        }

        Row {
            spacing: Theme.spacingS

            DTextField {
                id: newWorkspaceField
                width: content.width - createButton.width - Theme.spacingS
                height: 44
                text: ""
                placeholderText: "New workspace name (optional)"
                backgroundColor: Theme.surfaceContainerHigh
                textColor: Theme.surfaceText
            }

            DButton {
                id: createButton
                height: 44
                text: "Create"
                iconName: "add"
                onClicked: {
                    root.ipc("create", newWorkspaceField.text.trim());
                    newWorkspaceField.text = "";
                }
            }
        }

        StyledText {
            width: parent.width
            text: "Templates"
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
        }

        Repeater {
            model: root.templateList
            delegate: StyledRect {
                width: content.width
                height: 44
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name + (modelData.workspace ? "  →  " + modelData.workspace : "")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }

                StyledText {
                    anchors.right: launchButton.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: (modelData.apps || []).length + " apps"
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeSmall
                }

                DButton {
                    id: launchButton
                    anchors.right: recordButton.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Launch"
                    iconName: "rocket_launch"
                    variant: "tonal"
                    onClicked: root.ipc("launch", modelData.name)
                }

                DButton {
                    id: recordButton
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Record"
                    iconName: "save"
                    variant: "tonal"
                    onClicked: root.ipc("record", modelData.name)
                }
            }
        }

        Row {
            spacing: Theme.spacingS

            DTextField {
                id: recordField
                width: content.width - recordCurrentButton.width - Theme.spacingS
                height: 44
                text: ""
                placeholderText: "Record current session as…"
                backgroundColor: Theme.surfaceContainerHigh
                textColor: Theme.surfaceText
            }

            DButton {
                id: recordCurrentButton
                height: 44
                text: "Record"
                iconName: "save"
                onClicked: {
                    if (recordField.text.trim())
                        root.ipc("record", recordField.text.trim());
                    recordField.text = "";
                }
            }
        }
    }
}
