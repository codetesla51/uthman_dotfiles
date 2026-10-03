import Quickshell
import Quickshell.Io
import QtQuick

// GitHubPoller — resident light poller (notifications + workflow runs).
// GitHubDash is lazy-loaded (unloaded on close), so this keeps background
// notify-send alive and the on-disk cache warm for instant dash opens.
// First poll is always silent (baselines unset); logic mirrors
// GitHubDash.applyNotifs/applyRuns minus the UI.
Item {
    id: root
    property int notifBase: -1
    property bool runsBase: false
    property var runsMap: ({})

    Timer {
        id: pollTimer
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { notifProc.running = true; runsProc.running = true }
    }

    function notify(title, body, urgent){
        var args = ["notify-send", "-a", "GitHub"]
        if(urgent){ args.push("-u"); args.push("critical") }
        args.push(title); args.push(body)
        Quickshell.execDetached(args)
    }

    Process {
        id: notifProc
        command: ["sh","-c","mkdir -p $HOME/.cache/quickshell/github; gh api notifications --paginate 2>/dev/null | tee $HOME/.cache/quickshell/github/notifs"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    var count = d.length
                    if(root.notifBase < 0){
                        root.notifBase = count
                    } else if(count > root.notifBase){
                        var fresh = count - root.notifBase
                        var head = (d.length > 0 && d[0].subject && d[0].subject.title) || ""
                        root.notify(fresh + " new GitHub notification" + (fresh > 1 ? "s" : ""), head)
                        root.notifBase = count
                    } else {
                        root.notifBase = count
                    }
                } catch(e) {}
            }
        }
    }
    Process {
        id: runsProc
        command: ["sh","-c","$HOME/.config/quickshell/scripts/gh-runs.sh 2>/dev/null | tee $HOME/.cache/quickshell/github/runs"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var lines = text.trim().split("\n")
                    var m = {}
                    for(var i = 0; i < lines.length; i++){
                        var p = lines[i].split("\t")
                        if(p.length < 8 || p[0] === "") continue
                        m[p[7]] = p[2]
                        if(root.runsBase){
                            var prev = root.runsMap[p[7]]
                            if(prev && prev !== "completed" && p[2] === "completed"){
                                var ok = p[3] === "success"
                                root.notify(ok ? "Workflow passed" : "Workflow " + p[3], p[4] + " · " + p[0] + " (" + p[6] + ")", !ok)
                            }
                        }
                    }
                    root.runsMap = m
                    root.runsBase = true
                } catch(e) {}
            }
        }
    }
}
