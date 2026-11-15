import QtQuick

// Subject — the cutout layer that sits above the clock.
// Same size and crop as the wallpaper so the pixels line up.
//
// A cutout can be read while wallcut.sh is still writing it, which shows up as
// Image.Error. Retry the same URL a few times instead of leaving a blank layer;
// the atomic writer makes this rare, but a switch mid-generation still races.
//
// Reveal is gated on the backdrop: the old cutout fades out as soon as the
// wallpaper changes, and the new one only fades in once the new wallpaper is
// fully in place. Otherwise the previous subject hangs over the incoming image.
Item {
    id: root

    property string source: ""
    // true only when the wallpaper layer has finished its dissolve
    property bool gate: true
    readonly property int imageStatus: card.status
    readonly property real cardOpacity: card.opacity
    readonly property string cardUrl: pathOf(card.source)
    readonly property string wantUrl: pathOf(source)
    readonly property bool cardReady: card.status === Image.Ready

    property string loadSource: ""
    property int retries: 0
    property bool wantReveal: false

    // Image.source may hold a bare path or a file:// URL depending on how it
    // was assigned; compare plain filesystem paths so both forms agree.
    function pathOf(u) {
        var s = u ? u.toString() : ""
        if (s.indexOf("file://") === 0)
            s = s.substring(7)
        try { s = decodeURIComponent(s) } catch (e) {}
        return s
    }

    function maybeReveal() {
        if (!root.gate || root.wantReveal)
            return
        if (root.source === "" || root.loadSource === "")
            return
        if (card.status !== Image.Ready || root.pathOf(card.source) !== root.pathOf(root.source))
            return
        root.wantReveal = true
        hideAnim.stop()
        reveal.restart()
    }

    onSourceChanged: {
        retryTimer.stop()
        clearTimer.stop()
        reveal.stop()
        retries = 0
        wantReveal = false
        loadSource = source
        if (source === "") {
            hideAnim.stop()
            card.opacity = 0
            return
        }
        // Drop the outgoing cutout quickly; it belongs to the old backdrop.
        if (card.opacity > 0.001)
            hideAnim.restart()
        else
            card.opacity = 0
        maybeReveal()
    }

    onGateChanged: maybeReveal()

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

    NumberAnimation {
        id: hideAnim
        target: card
        property: "opacity"
        to: 0
        duration: 130
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: reveal
        PauseAnimation { duration: 60 }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
    }

    Image {
        id: card
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        source: root.loadSource
        visible: root.source !== "" && root.loadSource !== ""
        onStatusChanged: {
            if (status === Image.Error)
                retryTimer.restart()
            else if (status === Image.Ready)
                root.maybeReveal()
        }
    }
}
