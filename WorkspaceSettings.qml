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
        settingKey: "compactLiveRows"
        label: "Compact rows"
        description: "Show each workspace as a single line (apps as icon chips) and reveal its preview when you click it. Off means the full preview is always open."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "rehomeWindows"
        label: "Fix up windows after a launch"
        description: "After launching a template, windows that mapped on the wrong workspace are moved onto it, and an app that refused to open a new window (a password manager raising the one it already had) has that window adopted instead."
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "Templates live in templates.json in this plugin's folder; hand edits are picked up when the panel opens. Use Save… on a workspace in the Live tab to snapshot it into a template."
        color: Theme.onSurfaceVariant
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.Wrap
    }

}
