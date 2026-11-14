import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets

// One app icon in a rounded chip: resolves a desktop entry from an app id (or
// from the command's basename) and falls back to the first letter when no icon
// is installed. `dimmed` marks an app a template would still have to launch.
Item {
    id: root

    property string appId: ""
    property string cmd: ""
    property string label: ""
    property int chipSize: 24
    property bool dimmed: false
    property bool ringed: false
    property int count: 0
    property color ringColor: Theme.primary

    width: chipSize
    height: chipSize

    readonly property string resolvedId: {
        if (appId)
            return appId;
        const text = String(cmd || label || "").trim();
        if (!text)
            return "";
        const first = text.split(/\s+/)[0].replace(/^["']|["']$/g, "");
        const slash = first.lastIndexOf("/");
        return slash >= 0 ? first.substring(slash + 1) : first;
    }

    readonly property string lookupId: resolvedId ? Paths.moddedAppId(resolvedId) : ""
    readonly property var entry: lookupId ? DesktopEntries.heuristicLookup(lookupId) : null
    readonly property string iconSource: resolvedId ? Paths.getAppIcon(resolvedId, entry) : ""
    readonly property real radius: Math.min(Theme.cornerRadiusS, height / 2)

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.chipSurface
        border.width: root.ringed ? Math.max(1, Theme.outlineWidth) : 0
        border.color: root.ringColor
        opacity: root.dimmed ? 0.45 : 1
    }

    IconImage {
        id: icon

        anchors.fill: parent
        anchors.margins: Math.max(2, Math.round(root.chipSize * 0.16))
        source: root.iconSource
        visible: status === Image.Ready
        opacity: root.dimmed ? 0.45 : 1
    }

    StyledText {
        anchors.centerIn: parent
        visible: icon.status !== Image.Ready
        text: String(root.label || root.resolvedId || "?").charAt(0).toUpperCase()
        color: Theme.surfaceText
        font.pixelSize: Math.round(root.chipSize * 0.46)
        font.weight: Font.DemiBold
        opacity: root.dimmed ? 0.5 : 0.9
    }

    Rectangle {
        visible: root.count > 1
        width: Math.max(root.chipSize * 0.44, badge.implicitWidth + Theme.spacingXXS * 2)
        height: width
        radius: width / 2
        color: Theme.primary
        border.width: Math.max(1, Theme.outlineWidth)
        border.color: Theme.surfaceContainerHigh
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -Math.round(root.chipSize * 0.16)
        anchors.bottomMargin: -Math.round(root.chipSize * 0.16)

        StyledText {
            id: badge

            anchors.centerIn: parent
            text: root.count
            color: Theme.onPrimary
            font.pixelSize: Math.max(8, Math.round(root.chipSize * 0.36))
            font.weight: Font.Bold
        }
    }
}
