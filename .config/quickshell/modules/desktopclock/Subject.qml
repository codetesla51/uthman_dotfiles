import QtQuick

// Subject — the cutout layer that sits above the clock.
// Same size and crop as the wallpaper so the pixels line up.
//
// A cutout can be read while wallcut.sh is still writing it, which shows up as
// Image.Error. Retry the same URL a few times instead of leaving a blank layer;
// the atomic writer makes this rare, but a switch mid-generation still races.
Item {
    id: root

    property string source: ""
    property bool shown: false
    readonly property int imageStatus: card.status

    property string loadSource: ""
    property int retries: 0

    onSourceChanged: {
        retryTimer.stop()
        clearTimer.stop()
        retries = 0
        loadSource = source
        if (source === "")
            return
        shown = false
        reveal.restart()
    }

    Timer {
        id: retryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.retries >= 5) return
            root.retries++
            root.loadSource = ""
            clearTimer.restart()
        }
    }

    // A separate tick so Image actually sees "" and then the URL again.
    Timer {
        id: clearTimer
        interval: 120
        repeat: false
        onTriggered: root.loadSource = root.source
    }

    SequentialAnimation {
        id: reveal
        PauseAnimation { duration: 40 }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
    }

    Image {
        id: card
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        source: root.loadSource
        visible: root.source !== "" && root.loadSource !== ""
        onStatusChanged: if (status === Image.Error) retryTimer.restart()
    }
}
