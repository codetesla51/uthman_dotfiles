import QtQuick
import "sources"

// DateQuote — the editorial line under the clock. Long date first, then one
// quote picked once per lock. A missing quote file leaves only the date.
Column {
    id: root

    property var theme
    property var config
    property alias quote: quoteSource.text
    property date now: new Date()

    spacing: 10

    Row {
        width: parent.width
        spacing: 8

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            glyph: ""
            size: 13
            tint: root.theme
                ? root.theme.alpha(root.theme.tertiary, 0.7) : "#565656"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(root.now, "dddd, d MMMM")
            color: root.theme ? root.theme.primary : "#ffffff"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.dateSize : 15
            font.letterSpacing: 0.4
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        text: root.quote
        color: root.theme ? root.theme.muted : "#8c8c8c"
        font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
        font.pixelSize: root.theme ? root.theme.quoteSize : 12
        font.letterSpacing: 0.1
        lineHeight: 1.4
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
    }

    QuoteSource {
        id: quoteSource
        config: root.config
    }

    // Cross midnight while the screen is up without waking more than the
    // clock already does.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }
}