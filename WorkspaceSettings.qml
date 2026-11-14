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
        label: "Live window previews (heavy)"
        description: "Real screencopies of each window, focused workspace only, while the panel is open. Each one is a live capture held in memory, so it costs GPU/VRAM continuously — leave it off unless you want the effect. Where capture is unavailable (niri with DMS 2.1.x) the mini-map keeps app icons either way."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "rehomeWindows"
        label: "Move late-opening windows to the target workspace"
        description: "niri places a window on whatever workspace is focused when the app finally maps it. After a template launch, sweep any of its windows that landed elsewhere back to the template's workspace."
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
