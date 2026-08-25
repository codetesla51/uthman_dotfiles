import QtQuick

// StateMachine — decision tree over Shimeji actions.
// Consumes: actions dict (name → [files]) from pet-actions.json
// Exposes: currentAction, currentFrames, frameInterval, bubbleText, isMoving
// Pet.qml listens to actionChanged(newAction, frames, interval, bubble, kind)
Item {
    id: root

    property var actions: ({})
    property string currentAction: "Stand"
    property var currentFrames: []
    property int frameInterval: 180
    property string bubbleText: ""
    property string actionKind: "idle" // "idle" | "walk" | "special"

    signal actionChanged(string name, var frames, int interval, string bubble, string kind)

    // Categorize Hornet actions into kinds
    readonly property var idleActions: ["Stand", "Sit", "SitWithLegsUp", "SitAndDangleLegs", "WatchAction", "WatchLoop", "Sprawl"]
    readonly property var sitActions: ["Sit", "SitWithLegsUp", "SitAndDangleLegs", "Sprawl"]
    readonly property var walkActions: ["Walk", "Run", "Dash"]
    readonly property var specialActions: ["PoseAction", "EatBerryAction", "ThrowNeedleAction", "Divide1", "Grapple1", "Grapple2", "Grapple3", "Grapple4"]
    readonly property var petActions: ["PetAction", "PetActionDangleLegs", "BePet", "BePetDangleLegs"]
    // bubble lines per special
    readonly property var bubbleMap: ({
        "PoseAction": ["Shaw!", "…!", "Hmph."],
        "EatBerryAction": ["*nom*", "*munch*", "Yum!"],
        "ThrowNeedleAction": ["Take this!", "En garde!", "Hiya!"],
        "Divide1": ["Another me!", "Hello!"],
        "Grapple1": ["*whoosh*"],
        "PetAction": ["purr…", "♥", "heh"],
        "PetActionDangleLegs": ["purr…", "♥"],
        "WatchAction": ["…", "Hm?", "·ω·"],
        "WatchLoop": ["…", "· · ·"],
        "Sprawl": ["Zzz…", "…zzz"],
        "GrabWall": ["…cling"],
        "GrabCeiling": ["…hang"]
    })

    // dwell ms per kind
    function dwellFor(action, frames, interval) {
        if (walkActions.indexOf(action) !== -1) return 2600 + Math.random() * 3400
        if (specialActions.indexOf(action) !== -1) return Math.max(1200, frames.length * interval + 700 + Math.random() * 600)
        if (petActions.indexOf(action) !== -1) return frames.length * interval + 500
        // idle
        if (action === "WatchAction" || action === "WatchLoop") return 1800 + Math.random() * 2200
        if (action === "Sprawl") return 2200 + Math.random() * 2600
        return 1500 + Math.random() * 2400
    }

    function intervalFor(action) {
        if (action === "Walk") return 85
        if (action === "Run") return 72
        if (action === "Dash") return 62
        if (action === "WalkWithIe" || action === "RunWithIe") return 85
        if (action === "Stand") return 450
        if (action === "Sit" || action === "SitAndDangleLegs") return 550
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
        if (action === "Falling" || action === "Jumping" || action === "Bouncing" || action === "Tripping" || action === "Pinched" || action === "Resisting") return "special"
        if (action.indexOf("Climb") === 0 || action.indexOf("Grab") === 0) return "walk" // consider as move-ish but no x slide
        return "idle"
    }

    function pickBubble(action) {
        var lines = bubbleMap[action]
        if (!lines) {
            // occasional generic idle bubble 12% chance
            if (Math.random() < 0.12) {
                var generics = ["·ω·", "…", "Hm", "♪"]
                return generics[Math.floor(Math.random() * generics.length)]
            }
            return ""
        }
        // special/pet always maybe bubble 60% chance, Watch/Sprawl 35%
        var chance = (specialActions.indexOf(action) !== -1 || petActions.indexOf(action) !== -1) ? 0.62 : 0.38
        if (Math.random() > chance) return ""
        return lines[Math.floor(Math.random() * lines.length)]
    }

    function availableNames() {
        var out = []
        for (var k in actions) if (actions[k] && actions[k].length > 0) out.push(k)
        return out
    }

    function filtered(names, kind) {
        // keep only names that exist in actions dict
        var res = []
        for (var i = 0; i < names.length; i++) if (actions[names[i]]) res.push(names[i])
        // if none, fallback to any idle
        if (res.length === 0) {
            var all = availableNames()
            // prefer idle fallbacks
            for (var j = 0; j < idleActions.length; j++) if (actions[idleActions[j]]) res.push(idleActions[j])
            if (res.length === 0) res = all.slice(0, 6)
        }
        return res
    }

    function pickNext() {
        var allNames = availableNames()
        if (allNames.length === 0) return

        var cur = currentAction
        var curKind = kindFor(cur)
        var next = cur
        var r = Math.random()

        // Decision tree weighted by current kind
        if (curKind === "walk") {
            if (r < 0.42) {
                // stop to idle
                var idles = filtered(idleActions, "idle")
                next = idles[Math.floor(Math.random() * idles.length)]
            } else if (r < 0.62) {
                // continue walk but maybe different speed/direction
                var walks = filtered(walkActions, "walk")
                next = walks[Math.floor(Math.random() * walks.length)]
            } else if (r < 0.82) {
                // special flourish then stop
                var specials = filtered(specialActions, "special")
                if (specials.length && Math.random() < 0.5) next = specials[Math.floor(Math.random() * specials.length)]
                else {
                    var id2 = filtered(idleActions, "idle")
                    next = id2[Math.floor(Math.random() * id2.length)]
                }
            } else {
                // stay same walk (direction change handled by Pet)
                next = cur
            }
        } else if (curKind === "special") {
            // specials always return to idle or walk
            if (r < 0.55) {
                var id3 = filtered(idleActions, "idle")
                next = id3[Math.floor(Math.random() * id3.length)]
            } else {
                var wk = filtered(walkActions, "walk")
                next = wk[Math.floor(Math.random() * wk.length)]
            }
        } else { // idle
            if (r < 0.44) {
                var wks = filtered(walkActions, "walk")
                next = wks[Math.floor(Math.random() * wks.length)]
            } else if (r < 0.68) {
                // different idle
                var ids = filtered(idleActions, "idle")
                // avoid picking same if possible
                if (ids.length > 1) {
                    var pick = ids[Math.floor(Math.random() * ids.length)]
                    next = (pick === cur && ids.length > 1) ? ids[(ids.indexOf(pick)+1) % ids.length] : pick
                } else next = ids[0]
            } else if (r < 0.86) {
                var sp = filtered(specialActions.concat(petActions), "special")
                next = sp[Math.floor(Math.random() * sp.length)]
            } else {
                next = cur // dwell linger
            }
        }

        if (!actions[next]) next = allNames[Math.floor(Math.random() * allNames.length)]

        applyAction(next)
    }

    function applyAction(name) {
        if (!actions[name]) return
        var frames = actions[name]
        var iv = intervalFor(name)
        var bub = pickBubble(name)
        var k = kindFor(name)
        currentAction = name
        currentFrames = frames
        frameInterval = iv
        bubbleText = bub
        actionKind = k
        dwellTimer.interval = dwellFor(name, frames, iv)
        dwellTimer.restart()
        actionChanged(name, frames, iv, bub, k)
    }

    // external trigger (e.g., pet click)
    function trigger(name) {
        if (!actions[name]) return
        applyAction(name)
    }

    Timer {
        id: dwellTimer
        interval: 2200
        repeat: false
        onTriggered: root.pickNext()
    }

    function pause() { dwellTimer.stop() }
    function resume() { dwellTimer.restart() }
    function isPaused() { return !dwellTimer.running }

    // auto-start when actions loaded
    onActionsChanged: {
        if (!actions || Object.keys(actions).length === 0) return
        // initialise to a reasonable first action if current empty
        if (!actions[currentAction] || currentFrames.length === 0) {
            var first = actions["Stand"] ? "Stand" : availableNames()[0]
            applyAction(first)
        } else {
            // refresh frames for current
            currentFrames = actions[currentAction]
        }
        dwellTimer.restart()
    }

    Component.onCompleted: {
        if (actions && Object.keys(actions).length > 0) {
            var init = actions["Stand"] ? "Stand" : availableNames()[0]
            if (init) applyAction(init)
        }
    }
}
