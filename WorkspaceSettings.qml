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
        settingKey: "stills"
        label: "Window stills"
        description: "Real pictures of each window in the mini-map, captured when the panel opens and cached for 10 minutes. niri can only hand over a window's pixels through a screenshot, which always also lands on the clipboard, so each capture borrows it for ~60 ms and puts it back. Rich-format copies degrade to plain text; nothing is captured while the panel is closed."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "restoreLabels"
        label: "Re-apply workspace labels at startup"
        description: "Workspace names live in the compositor; the emoji the bar shows for them does not. This quietly re-applies the label of any workspace that exists when the shell starts. It never creates anything."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "restoreCreateWorkspaces"
        label: "Recreate declared workspaces at startup"
        description: "Also create the workspaces your templates declare, empty, so they exist before you launch anything. niri can only create a workspace by focusing it, so the view moves through them and then returns to where you were. Off by default: pressing the template's keybinding creates and names its workspace on demand anyway."
        defaultValue: false
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
