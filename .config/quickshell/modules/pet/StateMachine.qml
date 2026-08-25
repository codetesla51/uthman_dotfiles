import QtQuick

// StateMachine — purposeful decision tree with fatigue.
// - fatigue++ while idle/walk, resets on user interaction
// - sleep probability 0 → ~high after 2-3min, excluded early
// - once asleep, only wake on interaction or fixed sleep duration
// - idle<->walk/sit weighted-random, no sleep in that pool until threshold
Item {
    id: root

    property var actions: ({})
    property string currentAction: "Stand"
    property var currentFrames: []
    property int frameInterval: 180
    property string bubbleText: ""
    property string actionKind: "idle"
    property string userActivity: "idle"
    property var groq: null
    property string sysSummary: ""

    property int fatigue: 0
    property bool isSleeping: false
    readonly property int fatigueThreshold: 120 // 2min
    readonly property int fatigueMax: 180 // 3min

    signal actionChanged(string name, var frames, int interval, string bubble, string kind)

    readonly property var idleActions: ["Stand", "Sit", "SitWithLegsUp", "SitAndDangleLegs", "WatchAction", "WatchLoop", "Sprawl"]
    readonly property var walkActions: ["Walk", "Run", "Dash"]
    readonly property var specialActions: ["PoseAction", "EatBerryAction", "ThrowNeedleAction", "Divide1", "Grapple1", "Grapple2", "Grapple3", "Grapple4"]
    readonly property var petActions: ["PetAction", "PetActionDangleLegs", "BePet", "BePetDangleLegs"]
    readonly property var sleepActions: ["Sprawl", "SitWithLegsUp"]
    readonly property var sitAnywhereCandidates: ["Sit", "SitWithLegsUp", "SitAndDangleLegs", "Sprawl", "WatchAction"]
    readonly property var wallActions: ["GrabWall", "ClimbWall"]
    readonly property var ceilingActions: ["GrabCeiling", "ClimbCeiling"]

    readonly property var bubbleMap: ({
        "PoseAction": ["Shaw!", "…!", "Hmph.", "Heh!"],
        "EatBerryAction": ["*nom*", "*munch*", "Yum!", "Tasty!"],
        "ThrowNeedleAction": ["Take this!", "En garde!", "Hiya!"],
        "Divide1": ["Another me!", "Hello!"],
        "Grapple1": ["*whoosh*"],
        "PetAction": ["purr…", "♥", "heh"],
        "PetActionDangleLegs": ["purr…", "♥"],
        "WatchAction": ["…", "Hm?", "·ω·", "what'cha doing?"],
        "WatchLoop": ["…", "· · ·", "I see you!"],
        "Sprawl": ["Zzz…", "…zzz", "zzZ"],
        "GrabWall": ["…cling", "whoa!"],
        "GrabCeiling": ["…hang", "whee!"],
        "ClimbWall": ["huff…", "climb!"],
        "ClimbCeiling": ["scurry…"],
        "Hide": ["…", "brb", "peek…"],
        "Sleep": ["Zzz…", "night…", "zzz", "…zzz"],
        "WalkToMe": ["comin'!", "wait!"],
        "SitAnywhere": ["ahh~", "here?", "comfy"]
    })
    readonly property var activityBubbles: ({
        "coding": ["coding? cool!", "compile!", "git push!", "bracket…", "·ω·"],
        "browsing": ["surf's up!", "click!", "scroll?"],
        "terminal": ["$ _", "sudo?", "whoami"],
        "media": ["♪", "nice track!", "bop!"],
        "idle": ["you there?", "poke!", "…zzz"]
    })

    // fatigue timer: increments while awake and idle/walk
    Timer {
        id: fatigueTimer
        interval: 1000
        repeat: true
        running: !root.isSleeping
        onTriggered: {
            if (root.actionKind === "idle" || root.actionKind === "walk" || root.actionKind === "walkToMe" || root.actionKind === "sitAnywhere") {
                if (root.fatigue < 300) root.fatigue += 1
            } else if (root.actionKind === "special") {
                // specials tire a bit faster
                if (root.fatigue < 300) root.fatigue += 1
            }
            // sleep resets fatigue slowly? not while sleeping
        }
    }

    function resetFatigue() {
        if (root.fatigue !== 0) console.log("[StateMachine] fatigue reset " + root.fatigue + " -> 0 by interaction")
        root.fatigue = 0
        if (root.isSleeping) {
            console.log("[StateMachine] wake by interaction")
            wakeFromSleep()
        }
    }

    function sleepProbability() {
        if (root.fatigue < 40) return 0
        if (root.fatigue < 80) return 0.02
        if (root.fatigue < 110) return 0.08
        if (root.fatigue < 140) return 0.18
        if (root.fatigue < 170) return 0.32
        if (root.fatigue < 200) return 0.52
        return 0.68
    }

    function dwellFor(action, frames, interval, kind) {
        if (kind === "sleep") return 28000 + Math.random() * 14000 // fixed 28-42s sleep, only wake via timer or interaction
        if (kind === "hide") return 3500 + Math.random() * 3500
        if (kind === "walk" || kind === "walkToMe") return 2600 + Math.random() * 3400
        if (kind === "sitAnywhere") return 3000 + Math.random() * 3000
        if (specialActions.indexOf(action) !== -1) return Math.max(1200, frames.length * interval + 700 + Math.random() * 600)
        if (petActions.indexOf(action) !== -1) return frames.length * interval + 500
        if (action === "WatchAction" || action === "WatchLoop") return 1800 + Math.random() * 2200
        if (action === "Sprawl") return 2200 + Math.random() * 2600
        if (wallActions.indexOf(action) !== -1 || ceilingActions.indexOf(action) !== -1) return 1800 + Math.random() * 2200
        return 1500 + Math.random() * 2400
    }

    function intervalFor(action) {
        if (action === "Walk") return 85
        if (action === "Run") return 72
        if (action === "Dash") return 62
        if (action === "WalkWithIe" || action === "RunWithIe") return 85
        if (action === "Stand") return 450
        if (action === "Sit" || action === "SitAndDangleLegs" || action === "SitWithLegsUp") return 550
        if (action === "WatchAction") return 520
        if (action === "Sprawl") return 700
        if (action === "GrabWall" || action === "GrabCeiling") return 600
        if (action === "ClimbWall" || action === "ClimbCeiling") return 90
        if (action === "PetAction" || action === "PetActionDangleLegs") return 110
        if (action === "PoseAction") return 140
        if (action === "EatBerryAction") return 105
        if (action === "ThrowNeedleAction") return 95
        if (action === "Pinched" || action === "Resisting") return 90
        if (action === "Falling" || action === "Jumping" || action === "Bouncing") return 90
        if (action.indexOf("Grapple") === 0) return 120
        if (action === "Divide1") return 125
        return 130
    }

    function kindFor(action) {
        if (walkActions.indexOf(action) !== -1) return "walk"
        if (specialActions.indexOf(action) !== -1 || petActions.indexOf(action) !== -1) return "special"
        if (wallActions.indexOf(action) !== -1) return "idle" // treat wall hang as idle-ish but not sleep
        if (ceilingActions.indexOf(action) !== -1) return "idle"
        if (action === "Falling" || action === "Jumping" || action === "Bouncing" || action === "Tripping" || action === "Pinched" || action === "Resisting") return "special"
        if (action.indexOf("Climb") === 0 || action.indexOf("Grab") === 0) return "walk"
        return "idle"
    }

    function pickActivityBubble() {
        var list = activityBubbles[userActivity]
        if (!list || Math.random() > 0.22) return ""
        return list[Math.floor(Math.random() * list.length)]
    }
    function pickBubble(action, kind) {
        if (kind === "hide" || kind === "sleep" || kind === "walkToMe" || kind === "sitAnywhere") {
            var lk = bubbleMap[kind === "walkToMe" ? "WalkToMe" : kind === "sitAnywhere" ? "SitAnywhere" : kind === "sleep" ? "Sleep" : "Hide"]
            if (lk && Math.random() < 0.75) return lk[Math.floor(Math.random()*lk.length)]
        }
        var lines = bubbleMap[action]
        if (!lines) {
            var ab = pickActivityBubble()
            if (ab !== "") return ab
            if (Math.random() < 0.12) {
                var generics = ["·ω·", "…", "Hm", "♪"]
                return generics[Math.floor(Math.random() * generics.length)]
            }
            return ""
        }
        var chance = (specialActions.indexOf(action) !== -1 || petActions.indexOf(action) !== -1) ? 0.62 : 0.38
        if (Math.random() > chance) {
            var ab2 = pickActivityBubble()
            if (ab2 !== "" && Math.random() < 0.5) return ab2
            return ""
        }
        return lines[Math.floor(Math.random() * lines.length)]
    }

    function availableNames() {
        var out = []
        for (var k in actions) if (actions[k] && actions[k].length > 0) out.push(k)
        return out
    }
    function filtered(names) {
        var res = []
        for (var i = 0; i < names.length; i++) if (actions[names[i]]) res.push(names[i])
        if (res.length === 0) {
            var all = availableNames()
            for (var j = 0; j < idleActions.length; j++) if (actions[idleActions[j]]) res.push(idleActions[j])
            if (res.length === 0) res = all.slice(0, 6)
        }
        return res
    }

    function wakeFromSleep() {
        root.isSleeping = false
        root.fatigue = 0
        console.log("[StateMachine] wake, fatigue reset")
        var idles = filtered(idleActions)
        var next = idles[Math.floor(Math.random()*idles.length)]
        applyAction(next)
    }

    function pickNext() {
        if (root.isSleeping) { wakeFromSleep(); return }
        // Groq smart decision — 42% chance when groq ready and fatigue>15, now aware of system
        if (root.groq && root.groq.ready && root.fatigue > 15 && Math.random() < 0.42) {
            var avail = availableNames()
            root.groq.decideNext(root.currentAction, root.actionKind, root.userActivity, root.fatigue, avail, root.sysSummary, function(chosen){
                if (chosen && root.actions[chosen]) {
                    console.log("[StateMachine] Groq chose " + chosen + " (fatigue " + root.fatigue + ")")
                    applyAction(chosen)
                } else {
                    pickNextLocal()
                }
            })
            return
        }
        pickNextLocal()
    }
    function pickNextLocal() {
        var allNames = availableNames()
        if (allNames.length === 0) return
        var sp = sleepProbability()
        if (sp > 0 && Math.random() < sp) {
            console.log("[StateMachine] fatigue " + root.fatigue + " -> sleep (p=" + sp.toFixed(2) + ")")
            triggerSynthetic("sleep")
            return
        }
        var cur = currentAction
        var curKind = actionKind
        var r = Math.random()
        var next = cur
        var idleBias = (userActivity === "idle")
        var codingBias = (userActivity === "coding" || userActivity === "terminal")
        var browsingBias = (userActivity === "browsing")
        var synthChance = idleBias ? 0.34 : 0.16
        if (r < synthChance) {
            var sr = Math.random()
            if (sr < 0.30) { triggerSynthetic("hide"); return }
            else if (sr < 0.72) { triggerSynthetic("walkToMe"); return }
            else { triggerSynthetic("sitAnywhere"); return }
        }
        if (curKind === "walk" || curKind === "walkToMe") {
            if (r < 0.38) {
                var idles = filtered(idleActions)
                next = idles[Math.floor(Math.random()*idles.length)]
            } else if (r < 0.60) {
                var walks = filtered(walkActions)
                next = walks[Math.floor(Math.random()*walks.length)]
            } else if (r < 0.82) {
                var specials = filtered(specialActions)
                if (specials.length && Math.random() < (browsingBias?0.7:0.5)) next = specials[Math.floor(Math.random()*specials.length)]
                else { var id2 = filtered(idleActions); next = id2[Math.floor(Math.random()*id2.length)] }
            } else next = cur
        } else if (curKind === "special" || curKind === "hide") {
            if (r < 0.52) {
                var id3 = filtered(idleActions)
                next = id3[Math.floor(Math.random()*id3.length)]
            } else {
                if (codingBias && Math.random() < 0.35) { triggerSynthetic("walkToMe"); return }
                var wk = filtered(walkActions)
                next = wk[Math.floor(Math.random()*wk.length)]
            }
        } else if (curKind === "sitAnywhere") {
            if (r < 0.45) { var wks2 = filtered(walkActions); next = wks2[Math.floor(Math.random()*wks2.length)] }
            else if (r < 0.75) { triggerSynthetic("walkToMe"); return }
            else { var ids2 = filtered(sitAnywhereCandidates); next = ids2[Math.floor(Math.random()*ids2.length)] }
        } else {
            if (r < (codingBias?0.32:0.44)) {
                if (codingBias && Math.random() < 0.55) {
                    var watch = filtered(["WatchAction","WatchLoop","Sit","SitAndDangleLegs"])
                    next = watch[Math.floor(Math.random()*watch.length)]
                } else {
                    var wks = filtered(walkActions); next = wks[Math.floor(Math.random()*wks.length)]
                }
            } else if (r < 0.68) {
                var ids = filtered(idleActions)
                if (ids.length>1) { var pick = ids[Math.floor(Math.random()*ids.length)]; next = (pick===cur && ids.length>1) ? ids[(ids.indexOf(pick)+1)%ids.length] : pick }
                else next = ids[0]
            } else if (r < 0.86) {
                var sp2 = filtered(specialActions.concat(petActions))
                next = sp2[Math.floor(Math.random()*sp2.length)]
            } else next = cur
        }
        if (!actions[next]) next = allNames[Math.floor(Math.random()*allNames.length)]
        applyAction(next)
    }

    function triggerSynthetic(kind) {
        var frames, name, interval, bubble
        if (kind === "hide") {
            name = "Stand"
            frames = actions["Stand"] || ["shime1.png"]
            interval = intervalFor("Stand")
            bubble = pickBubble("Hide", "hide")
            currentAction = "Hide"
            currentFrames = frames
            frameInterval = interval
            bubbleText = bubble
            actionKind = "hide"
            dwellTimer.interval = dwellFor("Hide", frames, interval, "hide")
            dwellTimer.restart()
            actionChanged("Hide", frames, interval, bubble, "hide")
            return
        }
        if (kind === "sleep") {
            var sleepPick = sleepActions[Math.floor(Math.random()*sleepActions.length)]
            if (!actions[sleepPick]) sleepPick = "Sprawl"
            name = sleepPick
            frames = actions[sleepPick] || actions["Sprawl"] || ["shime20.png"]
            interval = intervalFor(name)
            bubble = pickBubble("Sleep", "sleep")
            currentAction = name
            currentFrames = frames
            frameInterval = interval
            bubbleText = bubble
            actionKind = "sleep"
            isSleeping = true
            dwellTimer.interval = dwellFor(name, frames, interval, "sleep")
            dwellTimer.restart()
            console.log("[StateMachine] -> sleep fatigue=" + fatigue + " for " + dwellTimer.interval + "ms")
            actionChanged(name, frames, interval, bubble, "sleep")
            return
        }
        if (kind === "walkToMe") {
            var w = walkActions[Math.floor(Math.random()*walkActions.length)]
            if (!actions[w]) w = "Walk"
            frames = actions[w]
            interval = intervalFor(w)
            bubble = pickBubble("WalkToMe", "walkToMe")
            currentAction = w
            currentFrames = frames
            frameInterval = interval
            bubbleText = bubble
            actionKind = "walkToMe"
            dwellTimer.interval = dwellFor(w, frames, interval, "walkToMe")
            dwellTimer.restart()
            actionChanged(w, frames, interval, bubble, "walkToMe")
            return
        }
        if (kind === "sitAnywhere") {
            var s = sitAnywhereCandidates[Math.floor(Math.random()*sitAnywhereCandidates.length)]
            if (!actions[s]) s = "Sit"
            frames = actions[s]
            interval = intervalFor(s)
            bubble = pickBubble("SitAnywhere", "sitAnywhere")
            currentAction = s
            currentFrames = frames
            frameInterval = interval
            bubbleText = bubble
            actionKind = "sitAnywhere"
            dwellTimer.interval = dwellFor(s, frames, interval, "sitAnywhere")
            dwellTimer.restart()
            actionChanged(s, frames, interval, bubble, "sitAnywhere")
            return
        }
    }

    function applyAction(name) {
        if (!actions[name]) return
        var frames = actions[name]
        var iv = intervalFor(name)
        var k = kindFor(name)
        var bub = pickBubble(name, k)
        // leaving sleep -> not sleeping
        if (isSleeping && k !== "sleep") isSleeping = false
        currentAction = name
        currentFrames = frames
        frameInterval = iv
        bubbleText = bub
        actionKind = k
        dwellTimer.interval = dwellFor(name, frames, iv, k)
        dwellTimer.restart()
        actionChanged(name, frames, iv, bub, k)
    }

    function trigger(name) {
        if (name === "hide" || name === "Hide") { triggerSynthetic("hide"); return }
        if (name === "sleep" || name === "Sleep") { triggerSynthetic("sleep"); return }
        if (name === "walkToMe" || name === "WalkToMe") { triggerSynthetic("walkToMe"); return }
        if (name === "sitAnywhere" || name === "SitAnywhere") { triggerSynthetic("sitAnywhere"); return }
        if (!actions[name]) return
        applyAction(name)
    }

    Timer { id: dwellTimer; interval: 2200; repeat: false; onTriggered: root.pickNext() }
    function pause() { dwellTimer.stop() }
    function resume() { dwellTimer.restart() }
    function isPaused() { return !dwellTimer.running }

    onActionsChanged: {
        if (!actions || Object.keys(actions).length === 0) return
        if (!actions[currentAction] || currentFrames.length === 0) {
            var first = actions["Stand"] ? "Stand" : availableNames()[0]
            if (first) applyAction(first)
        } else currentFrames = actions[currentAction]
        dwellTimer.restart()
    }
    Component.onCompleted: {
        if (actions && Object.keys(actions).length>0) {
            var init = actions["Stand"] ? "Stand" : availableNames()[0]
            if (init) applyAction(init)
        }
    }
}
