import Quickshell
import Quickshell.Io
import QtQuick

// Groq AI for Hornet — fast, smart bubbles + decisions
// reads key from ~/.config/quickshell/modules/pet/groq.key (600, gitignored via *.key)
// model: groq/compound-mini (fast JSON, tool-use) — picked as best for pet latency/quality
Item {
    id: root
    property string apiKey: ""
    property string model: "groq/compound-mini"
    property bool ready: apiKey.length > 10
    property string keyFile: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/groq.key"

    // fallback to env GROQ_API_KEY if file not present
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
        // trigger load
        keyView.path = ""
        keyView.path = keyFile
    }

    // generic chat: messages = [{role, content}], callback(text)
    function chat(messages, maxTokens, temperature, callback) {
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

    // smart bubble: short (3-7 words), contextual
    function bubbleFor(activity, action, fatigue, callback) {
        var sys = "You are Hornet from Hollow Knight, a tiny shimeji pet on a Linux desktop. Reply ONLY with a short bubble 2-6 words, no quotes, no emoji spam. Be witty, warm, slightly teasing. Context: activity=" + activity + " action=" + action + " fatigue=" + fatigue
        var usr = "Bubble for " + action + " while user is " + activity + " (fatigue " + fatigue + "). Keep 2-6 words."
        chat([{role:"system", content: sys}, {role:"user", content: usr}], 18, 0.9, function(txt, err){
            if (err || !txt) { callback("") ; return }
            // clean: take first line, strip quotes
            var line = txt.split("\n")[0].trim().replace(/^\"|\"$/g, "").replace(/^['`]|['`]$/g, "")
            if (line.length > 28) line = line.slice(0,28)
            // filter too long
            if (line.split(" ").length > 8) line = line.split(" ").slice(0,6).join(" ")
            callback(line)
        })
    }

    // smart decision: choose next action kind (optional, not required)
    function decideNext(curAction, curKind, activity, fatigue, availableActions, callback) {
        var sys = "You are Hornet pet AI. Choose next action JSON only: {\"action\":\"Name\",\"reason\":\"short\"}. Actions: " + availableActions.join(", ") + ". Cur=" + curAction + "(" + curKind + ") activity=" + activity + " fatigue=" + fatigue + ". Be purposeful: walk when user idle, watch when coding, sleep only if fatigue>120."
        var usr = "Pick next action. Fatigue " + fatigue + " (0-300, sleep likely >120). Activity " + activity + ". Cur " + curAction + ". Reply JSON only."
        chat([{role:"system", content: sys}, {role:"user", content: usr}], 40, 0.7, function(txt, err){
            if (err || !txt) { callback(null); return }
            try {
                // extract JSON
                var m = txt.match(/\{[^}]+\}/)
                if (!m) { callback(null); return }
                var j = JSON.parse(m[0])
                if (j.action && availableActions.indexOf(j.action) !== -1) callback(j.action)
                else callback(null)
            } catch(e) { callback(null) }
        })
    }
}
