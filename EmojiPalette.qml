import QtQuick
import qs.Common
import qs.DCommon.Widgets

// A short, curated set instead of a searchable thousand-emoji picker.
//
// Naming a workspace is a two-second decision, so the palette is one flat grid of
// things people actually call a workspace — a browser, a terminal, a game, a
// meeting — and the text field beside it still takes any character you like. A
// searchable picker would mean a dataset, a keyboard navigation model and a
// scrollable app inside a dashboard, to save typing one emoji.
Item {
    id: root

    property string current: ""

    signal picked(string emoji)

    readonly property var emojis: [
        "💻", "🖥️", "⌨️", "🐚", "🧪", "🔧",
        "⚙️", "📝", "🗂️", "📊", "📈", "🔍",
        "🎮", "🕹️", "🎧", "🎵", "🎬", "📺",
        "🧳", "💼", "📮", "✉️", "🗓️", "🕒",
        "🌐", "🧠", "📦", "🚀", "🌙", "☕",
        "🍵", "🎯", "🌿", "🧊", "🔥", "🧩"
    ]

    implicitHeight: grid.implicitHeight

    Flow {
        id: grid

        width: parent.width
        spacing: 2

        Repeater {
            model: root.emojis

            delegate: StyledRect {
                required property string modelData

                readonly property bool selected: root.current === modelData

                width: 30
                height: 30
                radius: Theme.cornerRadiusS
                color: selected ? Theme.primaryContainer
                     : hover.containsMouse ? Theme.surfaceContainerHighest
                     : "transparent"

                StyledText {
                    anchors.centerIn: parent
                    text: parent.modelData
                    font.pixelSize: 16
                }

                MouseArea {
                    id: hover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(parent.modelData)
                }
            }
        }
    }
}
