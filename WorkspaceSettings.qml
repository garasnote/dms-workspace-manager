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
        settingKey: "restoreWorkspaces"
        label: "Recreate named workspaces at startup"
        description: "Workspace names live in the compositor and disappear when niri restarts, which leaves the emoji in the bar pointing at nothing. With this on, every workspace named by a template is recreated (empty) when the shell starts, and labels are re-applied. Apps are not started — use a keybinding for that."
        defaultValue: false
    }

    SliderSetting {
        settingKey: "stillsTtlMinutes"
        label: "Window stills cache (minutes)"
        description: "How long a captured window picture stays fresh. Opening the panel after this expires captures one fresh batch."
        defaultValue: 10
        minimum: 1
        maximum: 120
        unit: " min"
    }

    SliderSetting {
        settingKey: "stillsMaxWindows"
        label: "Window stills per batch"
        description: "Upper bound on how many windows get captured when the panel opens, so a 40-window session does not borrow the clipboard 40 times in a row."
        defaultValue: 16
        minimum: 4
        maximum: 64
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
