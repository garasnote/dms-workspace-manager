import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One-line label that scrolls horizontally when the text does not fit, instead
// of widening its parent or eliding to nothing.
Item {
    id: root

    property string text: ""
    property color color: Theme.onSurfaceVariant
    property int pixelSize: 10
    property bool animate: false
    property int gap: 32

    clip: true
    implicitHeight: measure.implicitHeight

    readonly property bool overflowing: measure.implicitWidth > width

    // hidden twin used for measuring; TextMetrics is not an Item
    StyledText {
        id: measure

        visible: false
        text: root.text
        font.pixelSize: root.pixelSize
    }

    Row {
        id: track

        spacing: root.gap
        y: Math.max(0, Math.round((root.height - height) / 2))

        // Holds the title at rest first, so opening the panel shows it from the
        // beginning instead of mid-scroll.
        SequentialAnimation on x {
            loops: Animation.Infinite
            running: root.animate && root.overflowing

            PauseAnimation {
                duration: 1600
            }

            NumberAnimation {
                from: 0
                to: -(measure.implicitWidth + root.gap)
                duration: Math.max(3000, (measure.implicitWidth + root.gap) * 28)
                easing.type: Easing.Linear
            }
        }

        StyledText {
            text: root.text
            color: root.color
            font.pixelSize: root.pixelSize
        }

        StyledText {
            visible: root.overflowing
            text: root.text
            color: root.color
            font.pixelSize: root.pixelSize
        }
    }

    onOverflowingChanged: {
        if (!overflowing)
            track.x = 0;
    }
}
