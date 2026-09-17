import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// GitHubDash — compact tabbed GitHub dashboard. Overview (contribution
// heatmap, stats, top repos), Inbox (notifications + reviews), Pulls
// (open PRs + assigned), Actions (running jobs + recent runs).
// Polls in the background every 5 min and notify-sends on new
// notifications or finished workflow runs (silent baseline on first poll).
// Data via `gh` (already authed); rows open in the browser. No keybind by
// design — lives in the Utilities hub (SUPER+Space → "util").
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    property int tab: 0
    property var notifs: []
    property var prs: []
    property var issues: []
    property var reviews: []
    property bool loading: false
    property string statusMsg: ""

    // contributions — last 12 months via gh graphql, built in contribProc
    property string ghUser: ""
    property var contribWeeks: []
    property var flatContrib: []
    property int contribTotal: 0
    property int contribToday: 0
    property int contribStreak: 0
    property int contribBest: 0
    property string contribBestDate: ""
    property bool contribLoading: false

    // actions — workflow runs via scripts/gh-runs.sh (TSV newest-first)
    property var runsRunning: []
    property var runsRecent: []
    property var runsMap: ({})
    property bool runsBase: false
    property bool runsLoading: false

    // profile stats
    property int followers: 0
    property int following: 0
    property int publicRepos: 0
    property int publicGists: 0
    property int totalStars: 0
    property var topRepos: []

    // background-notify baselines (-1 = unset, first poll is silent)
    property int notifBase: -1

    title: "GitHubDash"
    implicitWidth: 740
    implicitHeight: 540
    minimumSize: Qt.size(700, 500)
    maximumSize: Qt.size(760, 560)
    color: "transparent"
    visible: root.open

    IpcHandler {
        target: "github"
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
    }

    onOpenChanged: if(open){ root.refreshAll(); Qt.callLater(function(){ bg.forceActiveFocus() }) }
    onTabChanged: if(open) Qt.callLater(function(){ bg.forceActiveFocus() })

    function ago(ts){
        var t = Date.parse(ts)
        if(isNaN(t)) return ""
        var s = Math.max(0, Math.floor((Date.now() - t) / 1000))
        if(s < 60) return "now"
        if(s < 3600) return Math.floor(s / 60) + "m"
        if(s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }
    function notifUrl(n){
        var u = n.url || ""
        return u.replace("https://api.github.com/repos/", "https://github.com/")
                .replace("/pulls/", "/pull/")
    }
    function openUrl(u){ if(u) Quickshell.execDetached(["xdg-open", u]) }
    function say(t){ root.statusMsg = t; statusLife.restart() }
    function notify(title, body, urgent){
        var args = ["notify-send", "-a", "GitHub"]
        if(urgent){ args.push("-u"); args.push("critical") }
        args.push(title); args.push(body)
        Quickshell.execDetached(args)
    }
    function contribColor(count, future){
        if(future) return colors.alpha(colors.outline, 0.04)
        if(count <= 0) return colors.alpha(colors.outline, 0.08)
        if(count <= 3) return colors.alpha(colors.primary, 0.22)
        if(count <= 7) return colors.alpha(colors.primary, 0.45)
        if(count <= 12) return colors.alpha(colors.primary, 0.70)
        return colors.primary
    }
    function runDot(status, conclusion){
        if(status !== "completed") return colors.primary
        if(conclusion === "success") return colors.tertiary
        if(conclusion === "failure" || conclusion === "timed_out") return colors.error
        return colors.alpha(colors.outline, 0.5)
    }
    function runState(status, conclusion){
        if(status === "in_progress") return "running"
        if(status === "queued" || status === "waiting" || status === "requested" || status === "pending") return "queued"
        if(status === "completed") return conclusion === "" ? "done" : conclusion
        return status
    }
    function fmtNum(n){
        var s = "" + n
        var out = ""
        while(s.length > 3){ out = "," + s.slice(-3) + out; s = s.slice(0, -3) }
        return s + out
    }
    Timer { id: statusLife; interval: 5000; onTriggered: root.statusMsg = "" }
    // background poller — light (notifs + runs only), always on so new
    // arrivals notify-send even while the dash is closed
    Timer {
        id: pollTimer
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollLight()
    }

    function pollLight(){
        notifProc.command = ["gh", "api", "notifications", "--paginate"]
        notifProc.running = true
        root.runsLoading = true
        runsProc.command = [Quickshell.env("HOME") + "/.config/quickshell/scripts/gh-runs.sh"]
        runsProc.running = true
    }
    function refreshAll(){
        root.loading = true
        root.statusMsg = ""
        root.pollLight()
        prProc.command = ["gh", "search", "prs", "--author=@me", "--state=open", "--json", "number,title,url,updatedAt", "--limit", "20"]
        prProc.running = true
        issProc.command = ["gh", "search", "issues", "--assignee=@me", "--state=open", "--json", "number,title,url,updatedAt", "--limit", "20"]
        issProc.running = true
        revProc.command = ["gh", "search", "prs", "--review-requested=@me", "--state=open", "--json", "number,title,url,updatedAt", "--limit", "20"]
        revProc.running = true
        root.contribLoading = true
        contribProc.running = true
        userProc.running = true
        reposProc.running = true
    }
    function markRead(){
        readProc.command = ["gh", "api", "notifications", "--method", "PUT"]
        readProc.running = true
    }

    Process {
        id: notifProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    root.notifs = d.map(function(n){
                        return { repo: (n.repository && n.repository.full_name) || "",
                                 title: (n.subject && n.subject.title) || "",
                                 type: (n.subject && n.subject.type) || "",
                                 url: root.notifUrl(n.subject || {}),
                                 updated: n.updated_at || "" }
                    })
                    var count = d.length
                    if(root.notifBase < 0){
                        root.notifBase = count
                    } else {
                        if(!root.open && count > root.notifBase){
                            var fresh = count - root.notifBase
                            var head = root.notifs.length > 0 ? root.notifs[0].title : ""
                            root.notify(fresh + " new GitHub notification" + (fresh > 1 ? "s" : ""), head)
                        }
                        root.notifBase = count
                    }
                } catch(e) { root.say("Notifications failed — gh auth?") }
                root.loading = false
            }
        }
        onExited: function(code){ if(code !== 0){ root.say("gh error — check auth"); root.loading = false } }
    }
    Process {
        id: prProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try { root.prs = JSON.parse(text) } catch(e) { root.say("PR search failed") }
            }
        }
    }
    Process {
        id: issProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try { root.issues = JSON.parse(text) } catch(e) { root.say("Issue search failed") }
            }
        }
    }
    Process {
        id: revProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try { root.reviews = JSON.parse(text) } catch(e) { root.say("Review search failed") }
            }
        }
    }
    Process {
        id: readProc
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code){
            if(code === 0){ root.notifs = []; root.notifBase = 0; root.say("Inbox zero") }
            else root.say("Mark-read failed — token scope?")
        }
    }
    Process {
        id: contribProc
        command: ["sh", "-c", "gh api graphql -f query='query{ viewer{ login contributionsCollection{ contributionCalendar{ totalContributions weeks{ contributionDays{ date contributionCount } } } } } }' 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.contribLoading = false
                try {
                    var j = JSON.parse(text)
                    var cal = j.data.viewer.contributionsCollection.contributionCalendar
                    root.ghUser = j.data.viewer.login || ""
                    root.contribTotal = cal.totalContributions || 0
                    var weeks = cal.weeks || []
                    root.contribWeeks = weeks
                    var flat = []
                    var days = []
                    for(var w = 0; w < weeks.length; w++){
                        var dd = weeks[w].contributionDays || []
                        for(var k = 0; k < dd.length; k++) days.push(dd[k])
                        for(var i = 0; i < 7; i++){
                            if(i < dd.length) flat.push({ count: dd[i].contributionCount || 0, future: false, date: dd[i].date })
                            else flat.push({ count: 0, future: true, date: "" })
                        }
                    }
                    root.flatContrib = flat
                    var best = 0
                    var bestDate = ""
                    for(var b = 0; b < days.length; b++){
                        var c = days[b].contributionCount || 0
                        if(c > best){ best = c; bestDate = days[b].date }
                    }
                    root.contribBest = best
                    root.contribBestDate = bestDate
                    root.contribToday = days.length > 0 ? (days[days.length - 1].contributionCount || 0) : 0
                    var streak = 0
                    var start = days.length - 1
                    if(start >= 0 && (days[start].contributionCount || 0) === 0) start--
                    for(var s = start; s >= 0; s--){
                        if((days[s].contributionCount || 0) > 0) streak++
                        else break
                    }
                    root.contribStreak = streak
                } catch(e) { root.say("Contributions failed — gh scope?") }
            }
        }
        onExited: function(code){ if(code !== 0){ root.contribLoading = false } }
    }
    Process {
        id: runsProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.runsLoading = false
                try {
                    var lines = text.trim().split("\n")
                    var all = []
                    for(var i = 0; i < lines.length; i++){
                        var p = lines[i].split("\t")
                        if(p.length < 8 || p[0] === "") continue
                        all.push({ repo: p[0], created: p[1], status: p[2], conclusion: p[3],
                                   workflow: p[4], title: p[5], branch: p[6], url: p[7] })
                    }
                    var run = []
                    var done = []
                    for(var j = 0; j < all.length; j++){
                        if(all[j].status !== "completed") run.push(all[j])
                        else done.push(all[j])
                    }
                    root.runsRunning = run.slice(0, 4)
                    root.runsRecent = done.slice(0, 12)
                    if(!root.runsBase){
                        var m0 = {}
                        for(var k = 0; k < all.length; k++) m0[all[k].url] = all[k].status
                        root.runsMap = m0
                        root.runsBase = true
                    } else if(!root.open){
                        for(var n = 0; n < all.length; n++){
                            var prev = root.runsMap[all[n].url]
                            if(prev && prev !== "completed" && all[n].status === "completed"){
                                var ok = all[n].conclusion === "success"
                                root.notify(ok ? "Workflow passed" : "Workflow " + all[n].conclusion,
                                            all[n].workflow + " · " + all[n].repo + " (" + all[n].branch + ")",
                                            !ok)
                            }
                        }
                        var m1 = {}
                        for(var q = 0; q < all.length; q++) m1[all[q].url] = all[q].status
                        root.runsMap = m1
                    } else {
                        var m2 = {}
                        for(var z = 0; z < all.length; z++) m2[all[z].url] = all[z].status
                        root.runsMap = m2
                    }
                } catch(e) { root.say("Actions fetch failed") }
            }
        }
        onExited: function(code){ if(code !== 0){ root.runsLoading = false } }
    }
    Process {
        id: userProc
        command: ["gh", "api", "user", "--jq", "{followers: .followers, following: .following, repos: .public_repos, gists: .public_gists}"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var u = JSON.parse(text)
                    root.followers = u.followers || 0
                    root.following = u.following || 0
                    root.publicRepos = u.repos || 0
                    root.publicGists = u.gists || 0
                } catch(e) {}
            }
        }
    }
    Process {
        id: reposProc
        command: ["gh", "repo", "list", "--limit", "50", "--json", "nameWithOwner,stargazerCount,updatedAt"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var repos = JSON.parse(text)
                    var stars = 0
                    for(var i = 0; i < repos.length; i++) stars += repos[i].stargazerCount || 0
                    root.totalStars = stars
                    repos.sort(function(a, b){
                        if((b.stargazerCount || 0) !== (a.stargazerCount || 0)) return (b.stargazerCount || 0) - (a.stargazerCount || 0)
                        if(a.updatedAt < b.updatedAt) return 1
                        if(a.updatedAt > b.updatedAt) return -1
                        return 0
                    })
                    root.topRepos = repos.slice(0, 4)
                } catch(e) {}
            }
        }
    }

    // window glass
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        focus: true
        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(e){
            if(e.key === Qt.Key_R){ root.refreshAll(); e.accepted = true }
            else if(e.key === Qt.Key_1){ root.tab = 0; e.accepted = true }
            else if(e.key === Qt.Key_2){ root.tab = 1; e.accepted = true }
            else if(e.key === Qt.Key_3){ root.tab = 2; e.accepted = true }
            else if(e.key === Qt.Key_4){ root.tab = 3; e.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // header — chip + label + user + running pill + refresh + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: "󰊤"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text { text: "GITHUB"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Rectangle {
                    visible: root.ghUser !== ""
                    Layout.preferredWidth: userTxt.implicitWidth + 16; Layout.preferredHeight: 20; radius: 10
                    color: colors.alpha(colors.tertiary, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.35)
                    Text { id: userTxt; anchors.centerIn: parent; text: "@" + root.ghUser; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: root.runsRunning.length > 0
                    Layout.preferredWidth: runTxt.implicitWidth + 16; Layout.preferredHeight: 20; radius: 10
                    color: colors.alpha(colors.primary, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                    Text { id: runTxt; anchors.centerIn: parent; text: "● " + root.runsRunning.length + " running"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                }
                Rectangle { width: 28; height: 28; radius: 14; color: refMa.containsMouse ? colors.alpha(colors.primary, 0.22) : colors.alpha(colors.surface, 0.6); border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11
                        RotationAnimation on rotation { running: root.loading || root.contribLoading || root.runsLoading; loops: Animation.Infinite; from: 0; to: 360; duration: 700 } }
                    MouseArea { id: refMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.refreshAll() } }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            // tab bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        { l: "Overview", c: -1 },
                        { l: "Inbox", c: root.notifs.length },
                        { l: "Pulls", c: root.prs.length },
                        { l: "Actions", c: root.runsRunning.length }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        height: 32
                        radius: 10
                        color: root.tab === index ? colors.alpha(colors.primary, 0.20) : tabMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.35) : colors.alpha(colors.surface, 0.55)
                        border.width: 1
                        border.color: root.tab === index ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.14)
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: modelData.l
                                color: root.tab === index ? colors.primary : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 10
                                font.weight: root.tab === index ? Font.ExtraBold : Font.Bold
                            }
                            Rectangle {
                                visible: modelData.c > 0
                                width: cnt.implicitWidth + 10; height: 16; radius: 8
                                color: root.tab === index ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.surfaceVariant, 0.5)
                                Text { id: cnt; anchors.centerIn: parent; text: modelData.c; color: root.tab === index ? colors.primary : colors.alpha(colors.outline, 0.9); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                            }
                        }
                        MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.tab = index }
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.tab

                // TAB 0: OVERVIEW — heatmap + stats + top repos
                ColumnLayout {
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        radius: 12
                        color: colors.alpha(colors.surface, 0.45)
                        border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text { text: "CONTRIBUTIONS · LAST 12 MONTHS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                                Item { Layout.fillWidth: true }
                                Text { text: root.contribLoading ? "loading…" : root.fmtNum(root.contribTotal) + " total"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Grid {
                                    anchors.centerIn: parent
                                    rows: 7
                                    flow: Grid.TopToBottom
                                    columnSpacing: 3
                                    rowSpacing: 3
                                    Repeater {
                                        model: root.flatContrib
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 9; height: 9
                                            radius: 2.5
                                            color: root.contribColor(modelData.count, modelData.future)
                                        }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.flatContrib.length === 0
                                    text: root.contribLoading ? "loading contributions…" : "no contribution data"
                                    color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 9
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text { text: "Less"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                                Row {
                                    spacing: 3
                                    Repeater {
                                        model: [0, 2, 5, 9, 15]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 9; height: 9; radius: 2.5
                                            color: root.contribColor(modelData, false)
                                        }
                                    }
                                }
                                Text { text: "More"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                                Item { Layout.fillWidth: true }
                                Text { text: root.contribToday + " today · " + root.contribStreak + " day streak · best " + root.contribBest; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 46; radius: 10
                            color: colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 1
                                Text { text: root.fmtNum(root.contribTotal); color: colors.primary; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                                Text { text: "CONTRIBS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 46; radius: 10
                            color: colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 1
                                Text { text: root.fmtNum(root.totalStars); color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                                Text { text: "STARS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 46; radius: 10
                            color: colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 1
                                Text { text: "" + root.followers; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                                Text { text: "FOLLOWERS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 46; radius: 10
                            color: colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 1
                                Text { text: "" + root.contribStreak; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                                Text { text: "STREAK"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "TOP REPOS · " + root.publicRepos + " PUBLIC"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Item { Layout.fillWidth: true }
                    }
                    Repeater {
                        model: root.topRepos.slice(0, 5)
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 26; radius: 8
                            color: repoMa.containsMouse ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                Text { text: modelData.nameWithOwner; color: colors.alpha(colors.tertiary, 0.9); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: (modelData.stargazerCount || 0) + " stars"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.ExtraBold }
                                Text { text: root.ago(modelData.updatedAt); color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8 }
                            }
                            MouseArea { id: repoMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl("https://github.com/" + modelData.nameWithOwner) }
                        }
                    }
                    Item { Layout.fillWidth: true; Layout.fillHeight: true }
                }

                // TAB 1: INBOX — notifications + reviews
                ColumnLayout {
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "NOTIFICATIONS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: root.notifs.length > 0
                            text: "mark all read"
                            color: readMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.7)
                            font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold
                            MouseArea { id: readMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.markRead() }
                        }
                    }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 4
                        model: root.notifs.slice(0, 20)
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ListView.view.width; height: 32; radius: 8
                            color: rowMa.containsMouse ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                Rectangle { width: 6; height: 6; radius: 3; color: colors.primary; Layout.alignment: Qt.AlignVCenter }
                                Text { text: modelData.repo; color: colors.alpha(colors.tertiary, 0.85); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; elide: Text.ElideRight; Layout.preferredWidth: 150 }
                                Text { text: modelData.title; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: root.ago(modelData.updated); color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8 }
                            }
                            MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                        }
                        Text {
                            visible: root.notifs.length === 0
                            anchors.centerIn: parent
                            text: root.loading ? "loading…" : "inbox zero"
                            color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 9
                        }
                    }
                    Text { text: "REVIEW REQUESTS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                    Repeater {
                        model: root.reviews.slice(0, 2)
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 26; radius: 8
                            color: revMa.containsMouse ? colors.alpha(colors.tertiary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            Text { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: Text.AlignVCenter; text: "#" + modelData.number + " " + modelData.title; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; elide: Text.ElideRight }
                            MouseArea { id: revMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                        }
                    }
                    Text { visible: root.reviews.length === 0; text: "nothing to review"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                }

                // TAB 2: PULLS — open PRs + assigned
                ColumnLayout {
                    spacing: 8
                    Text { text: "YOUR OPEN PRS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 4
                        model: root.prs
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ListView.view.width; height: 32; radius: 8
                            color: prowMa.containsMouse ? colors.alpha(colors.secondary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                Text { text: "#" + modelData.number; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.ExtraBold }
                                Text { text: modelData.title; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: root.ago(modelData.updatedAt); color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8 }
                            }
                            MouseArea { id: prowMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                        }
                        Text {
                            visible: root.prs.length === 0
                            anchors.centerIn: parent
                            text: root.loading ? "loading…" : "no open PRs"
                            color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 9
                        }
                    }
                    Text { text: "ASSIGNED TO YOU"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                    Repeater {
                        model: root.issues.slice(0, 2)
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 26; radius: 8
                            color: issMa.containsMouse ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            Text { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: Text.AlignVCenter; text: "#" + modelData.number + " " + modelData.title; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; elide: Text.ElideRight }
                            MouseArea { id: issMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                        }
                    }
                    Text { visible: root.issues.length === 0; text: "nothing assigned"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                }

                // TAB 3: ACTIONS — running jobs + recent runs
                ColumnLayout {
                    spacing: 8
                    Text { text: root.runsRunning.length > 0 ? "RUNNING NOW · " + root.runsRunning.length : "RUNNING NOW"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                    Repeater {
                        model: root.runsRunning
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 34; radius: 8
                            color: runMa.containsMouse ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.primary, 0.25)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                Rectangle { width: 8; height: 8; radius: 4; color: colors.primary; Layout.alignment: Qt.AlignVCenter }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 1
                                    Text { text: modelData.workflow + " · " + modelData.repo; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: modelData.title + " (" + modelData.branch + ")"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Text { text: root.runState(modelData.status, modelData.conclusion) + " · " + root.ago(modelData.created); color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                            }
                            MouseArea { id: runMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                        }
                    }
                    Text { visible: root.runsRunning.length === 0; text: root.runsLoading ? "checking…" : "no running workflows"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                    Text { text: "RECENT RUNS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 4
                        model: root.runsRecent
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ListView.view.width; height: 30; radius: 8
                            color: hMa.containsMouse ? colors.alpha(colors.secondary, 0.12) : colors.alpha(colors.surface, 0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.10)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                Rectangle { width: 7; height: 7; radius: 3.5; color: root.runDot(modelData.status, modelData.conclusion); Layout.alignment: Qt.AlignVCenter }
                                Text { text: modelData.workflow; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; elide: Text.ElideRight; Layout.preferredWidth: 110 }
                                Text { text: modelData.title; color: colors.alpha(colors.foreground, 0.8); font.family: colors.fontSans; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: root.runState(modelData.status, modelData.conclusion); color: root.runDot(modelData.status, modelData.conclusion); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                                Text { text: root.ago(modelData.created); color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8 }
                            }
                            MouseArea { id: hMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                        }
                        Text {
                            visible: root.runsRecent.length === 0
                            anchors.centerIn: parent
                            text: root.runsLoading ? "loading…" : "no runs yet"
                            color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 9
                        }
                    }
                }
            }

            Text {
                visible: root.statusMsg !== ""
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: root.statusMsg
                color: colors.error; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: "1-4 tabs · R refresh · Esc close · polls every 5 min, notifies on new"
                color: colors.alpha(colors.outline, 0.45); font.family: colors.fontSans; font.pixelSize: 7; font.letterSpacing: 0.3
            }
        }
    }
}
