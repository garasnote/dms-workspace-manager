import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import "." as Local

// Live mini-map of one workspace.
//
// Columns and cells are drawn from niri's own layout data
// (`pos_in_scrolling_layout`, `tile_size`): a scrollable-tiling workspace reads
// like its real shape. Every tile shows the app icon and the window title, the
// focused window is ringed, and the on-screen subset is framed when niri
// reports it.
Item {
    id: root

    property var workspace: null
    property bool live: false
    property real previewHeight: 112
    property real columnGap: 2
    property real cellGap: 1

    implicitWidth: 100
    implicitHeight: previewHeight
    property int activeWindowId: -1

    readonly property var windows: (workspace && workspace.apps) ? workspace.apps : []
    readonly property var tiled: windows.filter(w => w && w.col !== undefined && w.col >= 0)
    readonly property int floatingCount: windows.length - tiled.length
    readonly property bool hasWindows: tiled.length > 0
    // Only trust the on-screen flag when niri actually reported it for this
    // workspace; otherwise everything counts as visible.
    readonly property bool viewportKnown: tiled.some(w => w.inView === true)
    function onScreen(win) {
        if (!viewportKnown)
            return true;
        return win && win.inView === true;
    }

    // ---------------------------------------------------------------- geometry

    function columnWidth(cells) {
        let widest = 1;
        for (const cell of cells)
            widest = Math.max(widest, cell.tileW || 1);
        return widest;
    }

    function columnHeight(cells) {
        let tall = 0;
        for (const cell of cells)
            tall += Math.max(1, cell.tileH || 1);
        return tall;
    }

    function buildColumns() {
        const byCol = {};
        for (const win of tiled) {
            const key = String(win.col);
            if (!byCol[key])
                byCol[key] = [];
            byCol[key].push(win);
        }
        const keys = Object.keys(byCol).map(Number).sort((a, b) => a - b);
        const columns = [];
        for (const key of keys) {
            const cells = byCol[String(key)].slice().sort((a, b) => (a.row || 0) - (b.row || 0));
            columns.push({
                col: key,
                cells: cells,
                width: columnWidth(cells),
                height: columnHeight(cells),
                onScreen: cells.some(c => root.onScreen(c))
            });
        }
        return columns;
    }

    readonly property var columns: buildColumns()

    readonly property real totalWidth: {
        let sum = 0;
        for (const column of columns)
            sum += column.width;
        return Math.max(1, sum);
    }

    readonly property real totalHeight: {
        let tall = 1;
        for (const column of columns)
            tall = Math.max(tall, column.height);
        return tall;
    }

    readonly property real pad: Theme.spacingS
    readonly property real availW: Math.max(1, width - pad * 2)
    readonly property real availH: Math.max(1, previewHeight - pad * 2)

    // Scrollable tiling makes workspaces far wider than they are tall, so the
    // preview scales each axis to fill the box: relative column widths stay
    // true, and the mini-map uses the whole frame instead of a tiny strip.
    // Columns get equal, fixed widths: proportional widths made one narrow
    // column (or a wide one) dominate the strip and read as a bug. Heights keep
    // their relative sizes so stacked windows still look stacked.
    readonly property real columnWidthFixed: {
        if (columns.length === 0)
            return 0;
        const gaps = columnGap * Math.max(0, columns.length - 1);
        return Math.max(1, (availW - gaps) / columns.length);
    }

    readonly property real scaleY: {
        if (!hasWindows)
            return 1;
        let mostCells = 0;
        for (const column of columns)
            mostCells = Math.max(mostCells, column.cells.length);
        const gaps = cellGap * Math.max(0, mostCells - 1);
        return Math.max(0.00001, (availH - gaps) / totalHeight);
    }

    readonly property real contentWidth: availW
    readonly property real contentHeight: availH

    // Flattened cells with absolute coordinates, so one Repeater draws them all.
    readonly property var cells: {
        const out = [];
        let x = 0;
        for (const column of columns) {
            const columnW = columnWidthFixed;
            let y = 0;
            for (const cell of column.cells) {
                const cellH = Math.max(1, cell.tileH || 1) * scaleY;
                out.push({
                    key: String(cell.id),
                    x: x,
                    y: y,
                    w: columnW,
                    h: cellH,
                    win: cell,
                    onScreen: root.onScreen(cell)
                });
                y += cellH + cellGap;
            }
            x += columnW + columnGap;
        }
        return out;
    }

    readonly property rect viewport: {
        let minX = -1;
        let maxX = -1;
        let minY = -1;
        let maxY = -1;
        for (const cell of cells) {
            if (!cell.onScreen)
                continue;
            if (minX < 0 || cell.x < minX)
                minX = cell.x;
            if (minY < 0 || cell.y < minY)
                minY = cell.y;
            if (maxX < 0 || cell.x + cell.w > maxX)
                maxX = cell.x + cell.w;
            if (maxY < 0 || cell.y + cell.h > maxY)
                maxY = cell.y + cell.h;
        }
        if (minX < 0)
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(minX, minY, maxX - minX, maxY - minY);
    }

    // -------------------------------------------------------------------- view

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerLowest, 0.55)
        border.width: Math.max(1, Theme.outlineWidth)
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.5)
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.hasWindows
        text: root.floatingCount > 0 ? root.floatingCount + " floating window(s)" : "Empty workspace"
        color: Theme.onSurfaceVariant
        font.pixelSize: Theme.fontSizeSmall
    }

    Item {
        id: plot

        visible: root.hasWindows
        width: root.contentWidth
        height: root.contentHeight
        x: root.pad
        y: root.pad

        // frame around what the monitor is actually showing
        Rectangle {
            visible: root.viewportKnown && root.viewport.width > 0
            x: root.viewport.x - 2
            y: root.viewport.y - 2
            width: root.viewport.width + 4
            height: root.viewport.height + 4
            radius: Theme.cornerRadiusS
            color: "transparent"
            border.width: Math.max(1, Theme.outlineWidth + 1)
            border.color: Theme.withAlpha(Theme.primary, 0.85)
        }

        Repeater {
            model: root.cells

            delegate: Rectangle {
                id: cell
                required property var modelData

                readonly property bool showTitle: modelData.h >= 40 && modelData.w >= 70
                readonly property string title: modelData.win ? (modelData.win.title || modelData.win.name || "") : ""

                x: modelData.x
                y: modelData.y
                width: Math.max(2, modelData.w)
                height: Math.max(2, modelData.h)
                radius: Math.min(Theme.cornerRadiusXS, Math.min(width, height) / 3)
                color: modelData.onScreen ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.9) : Theme.withAlpha(Theme.surfaceContainer, 0.55)
                border.width: modelData.win && modelData.win.id === root.activeWindowId ? Math.max(1, Theme.outlineWidth + 1) : Math.max(1, Theme.outlineWidth)
                border.color: modelData.win && modelData.win.id === root.activeWindowId ? Theme.primary : Theme.withAlpha(Theme.outlineVariant, 0.6)
                opacity: modelData.onScreen ? 1 : 0.6
                clip: true

                // a still of the window, when one has been captured; the icon
                // below shows through if not. sourceSize keeps the decode cost
                // proportional to the tile, not to the 954x1148 original.
                Image {
                    id: thumb

                    anchors.fill: parent
                    anchors.margins: 1
                    visible: source !== "" && status === Image.Ready
                    source: modelData.win ? (modelData.win.still || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    sourceSize.width: Math.max(32, Math.min(420, Math.round(width * 2)))
                    sourceSize.height: Math.max(32, Math.min(420, Math.round(height * 2)))
                    opacity: modelData.onScreen ? 1 : 0.55
                }

                // app icon (fallback, and the label while a still loads)
                Local.AppChip {
                    visible: thumb.status !== Image.Ready
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: cell.showTitle ? -Math.round(parent.height * 0.08) : 0
                    chipSize: Math.max(14, Math.min(parent.width, parent.height) * 0.56)
                    appId: modelData.win ? modelData.win.appId : ""
                    label: modelData.win ? modelData.win.name : ""
                    dimmed: !modelData.onScreen
                }

                // scrim so the title stays readable over whatever the still shows
                Rectangle {
                    visible: cell.showTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(parent.height * 0.45, 26)
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 1
                            color: Theme.withAlpha(Theme.surfaceContainerLowest || "#000000", 0.75)
                        }
                    }
                }

                // window title strip along the bottom of the tile; long titles
                // scroll instead of forcing the tile wider
                Local.MarqueeText {
                    visible: cell.showTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    anchors.bottomMargin: 2
                    text: cell.title
                    color: Theme.withAlpha(Theme.onSurfaceVariant, 0.95)
                    pixelSize: Math.max(7, Math.min(10, Math.round(parent.height * 0.14)))
                    animate: root.live
                }

            }
        }
    }
}
