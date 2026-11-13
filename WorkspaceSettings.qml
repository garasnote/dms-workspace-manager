import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "workspaceManager"

    ToggleSetting {
        settingKey: "launchIntoNamedWorkspace"
        label: "Launch templates into their named workspace"
        description: "When a template declares a workspace, create or focus it before launching its apps."
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "Templates are stored in templates.json inside this plugin's folder. Edit that file, then press Reload. Use 'Record' in the Workspaces dash tab to snapshot the focused workspace into a template."
        color: Theme.onSurfaceVariant
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.Wrap
    }

    DButton {
        text: "Reload templates"
        iconName: "refresh"
        onClicked: Quickshell.execDetached(["dms", "ipc", "call", "workspaceManager", "reload"])
    }
}
