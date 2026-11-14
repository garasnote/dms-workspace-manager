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

    ToggleSetting {
        settingKey: "showEmptyWorkspaces"
        label: "Show empty workspaces"
        description: "Empty unnamed workspaces are niri's filler; they are hidden so the list stays readable. Named ones always show."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "liveThumbnails"
        label: "Live window previews"
        description: "Real screencopies inside the workspace mini-map where the compositor allows window capture (Hyprland, or DMS builds with ext-toplevel capture). On niri + DMS 2.1.x the mini-map falls back to app icons."
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
