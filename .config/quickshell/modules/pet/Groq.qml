import Quickshell
import Quickshell.Io
import QtQuick

// Groq AI for Hornet — fast, smart bubbles + decisions
// reads key from ~/.config/quickshell/modules/pet/groq.key (600, gitignored via *.key)
// model: groq/compound-mini (fast JSON, tool-use) — picked as best for pet latency/quality
Item {
    id: root
    property string apiKey: ""
    property string model: "allam-2-7b"
    property bool ready: false // offline mode — Groq disabled, local StateMachine only
    property int lastBubbleMs: 0
    property int lastDecideMs: 0
    readonly property int bubbleCooldownMs: 8000
    readonly property int decideCooldownMs: 15000
    property string keyFile: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/groq.key"
    property string envKey: Quickshell.env("GROQ_API_KEY") || ""

    FileView {
        id: keyView
        path: root.keyFile
        printErrors: false
        onLoaded: {
            var k = text().trim()
            if (k.length > 10) root.apiKey = k
            else if (root.envKey.length > 10) root.apiKey = root.envKey
        }
        onLoadFailed: {
            if (root.envKey.length > 10) root.apiKey = root.envKey
        }
    }
    Component.onCompleted: {
        if (envKey.length > 10 && apiKey.length === 0) apiKey = envKey
        keyView.path = ""
        keyView.path = keyFile
    }

    function chat(messages, maxTokens, temperature, callback) {
        callback("", "offline"); return
        if (!ready) { callback("", "no key"); return }
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "https://api.groq.com/openai/v1/chat/completions", true)
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var j = JSON.parse(xhr.responseText)
                        var txt = j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content || ""
                        callback(txt.trim(), null)
                    } catch(e) { callback("", e) }
                } else {
                    var err = xhr.responseText
                    console.warn("[Groq] HTTP " + xhr.status + " " + err.slice(0,200))
                    callback("", "http " + xhr.status)
                }
            }
        }
        var body = JSON.stringify({
            model: root.model,
            messages: messages,
            max_tokens: maxTokens || 60,
            temperature: temperature !== undefined ? temperature : 0.85,
            top_p: 1,
            stream: false
        })
        xhr.send(body)
    }

    // offline: no Groq bubbles — use local bubbleMap
    function bubbleFor(activity, action, fatigue, sysInfo, callback) {
        callback(""); return
        if (typeof sysInfo === 'function') { callback = sysInfo; sysInfo = "" }
        var now = Date.now()
        if (now - lastBubbleMs < bubbleCooldownMs) { callback(""); return }
        lastBubbleMs = now
        var info = sysInfo || ""
        var sys = "You are Hornet, you own all bubble text (2-6 words, witty, warm, teasing, no quotes). System structured: " + info + ". Activity=" + activity + " action=" + action + " fatigue=" + fatigue + " -- make bubble based on info, not just text. Add more text if needed but keep bubble short."
        var usr = "Bubble for " + action + " while user is " + activity + " (fatigue " + fatigue + "). System info: " + info + ". You own all text, add more if you want but bubble 2-6 words.";
        chat([{role:"system", content: sys}, {role:"user", content: usr}], 18, 0.9, function(txt, err){
            if (err || !txt) { callback("") ; return }
            var line = txt.split("\n")[0].trim().replace(/^\"|\"$/g, "").replace(/^['`]|['`]$/g, "")
            var low = line.toLowerCase()
            if (low.includes("you are") || low.includes("you own") || low.includes("system") || low.includes("activity=") || low.includes("fatigue=") || low.includes("bubble for") || low.includes("reply json") || line.includes("{") || line.includes("}") || low.includes("structured")) { callback(""); return }
            if (line.length > 28) line = line.slice(0,28)
            if (line.split(" ").length > 8) line = line.split(" ").slice(0,6).join(" ")
            callback(line)
        })
    }

    // offline: no Groq decisions — use local wants/surfaces logic
    function decideNext(curAction, curKind, activity, fatigue, availableActions, sysInfo, callback) {
        callback(null); return
        if (typeof sysInfo === 'function') { callback = sysInfo; sysInfo = "" }
        var now2 = Date.now()
        if (now2 - lastDecideMs < decideCooldownMs) { callback(null); return }
        lastDecideMs = now2
        var info = sysInfo || ""
        var sys = "You are Hornet, a real shimeji living in quickshell PanelWindow Overlay (Hyprland, LocalStorage, mask click-through). You decide what YOU want, not dice. System info (structured, not just text): " + info + ". Available actions: " + availableActions.join(", ") + ". You are at " + curAction + "(" + curKind + ") activity=" + activity + " fatigue=" + fatigue + " (0-300, sleep p 0%<40 68%>200). You own all bubble text -- be witty, warm, teasing, 2-6 words, but decision is based on structured info: CPU/MEM/BAT/T/uptime/clock/apps/focused/spots/at. Prefer near surfaces (wall/ceiling/window) occasionally, not just floor. Reply JSON only {\"action\":\"Name\",\"reason\":\"short why\"}.";
        var usr = "Decide next. Fatigue " + fatigue + " Activity " + activity + " Info: " + info + " Cur " + curAction + " (" + curKind + "). You want to do what YOU want. Reply JSON only.";
        chat([{role:"system", content: sys}, {role:"user", content: usr}], 40, 0.7, function(txt, err){
            if (err || !txt) { callback(null); return }
            try {
                var m = txt.match(/\{[^}]+\}/)
                if (!m) { callback(null); return }
                var j = JSON.parse(m[0])
                if (j.action && availableActions.indexOf(j.action) !== -1) callback(j.action)
                else callback(null)
            } catch(e) { callback(null) }
        })
    }
}
