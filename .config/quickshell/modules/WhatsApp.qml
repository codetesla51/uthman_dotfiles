import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import QtMultimedia

// WhatsApp — single-pane sheet over the ~/whatsapp-bridge Go daemon (whatsmeow).
// The list fills the window; opening a chat swaps the whole window to the conversation.
// Icons are Phosphor glyphs (@@-tokens resolved at build), never text.
// The daemon is a persistent child process speaking NDJSON on stdio:
// QML writes {"cmd":"start"}, daemon emits {"type":"status"|"qr"|"paired"}.
// Toggle: ipc call whatsapp (SUPER ALT W).
FloatingWindow {
    id: root

    // Fallback palette so colors.* reads never throw during startup:
    // the external `colors` assignment can land after our bindings first
    // evaluate, and one throw aborts setup of the whole shell (no bar, no IPC).
    QtObject {
        id: fallback
        property color background: "#17130f"
        property color foreground: "#ebe1da"
        property color primary: "#f3bc87"
        property color secondary: "#dfc1a8"
        property color tertiary: "#9bcee3"
        property color error: "#ffb4ab"
        property color surface: "#17130f"
        property color on_surface: "#efe5df"
        property color surfaceVariant: "#50453b"
        property color outline: "#a39487"
        function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    }
    property var colors: fallback
    property bool open: false
    property string daemon: Quickshell.env("HOME") + "/whatsapp-bridge/whatsapp-bridge"

    // Icon families. Body text stays in colors.fontSans; every pictogram
    // below is a Phosphor glyph so the UI never mixes icon styles.
    property string iconFont: "Phosphor"
    property string iconFontFill: "Phosphor-Fill"

    // --- pairing state (driven by daemon events, never polled) ---
    property string connState: "starting"   // starting|waiting-qr|connecting|connected|disconnected|logged-out|error
    property string statusDetail: "launching daemon"
    property string qrPng: ""
    property int qrTimeout: 0
    property bool daemonMissing: false

    // --- chat list (driven by daemon events, never polled) ---
    property var chats: []           // [{jid, name, preview, kind, ts, unread}]
    property string selectedJid: ""  // highlighted row
    property string hoverJid: ""     // row under the mouse, live
    property string openJid: ""      // conversation on screen, "" = none
    property var messages: []        // bubbles; sent rows carry status, history rows don't
    property var pendingMsgs: []     // {localId, body, kind, path} awaiting daemon echo
    property var attachPaths: []       // picked photos/videos waiting to send
    property string pasteTarget: ""    // dump path for the in-flight clipboard paste
    property var replyTo: null         // {id, text, kind, sender, from_me} quoted in the next send
    property bool emojiOpen: false     // emoji grid above the composer
    property string emojiMode: "type"  // "type" inserts at cursor, "react" sends a reaction
    property string reactTarget: ""    // message id the picker reacts to
    property bool demoMode: false        // screenshot mode: fake chats, daemon muted
    property string hoverMsgId: ""      // bubble under the cursor (R/O/C act on it)
    property int msgCursor: -1       // keyboard cursor in the conversation
    property int historyLimit: 50    // grows 50 per top-reach, daemon caps 200
    property bool loadingMore: false // top-fetch in flight, don't jump to end
    property bool convoLoading: false // initial history in flight for the open chat
    property var notifState: ({})    // jid -> {name, count} inside the window
    property real _listY: 0  // chat-list scroll hold across re-sorts
    property bool gPending: false  // first g of a gg top-jump
    property string playingId: ""    // voice bubble currently playing
    property var typing: ({})        // jid -> [names] currently typing
    property string openingId: ""    // media bubble handing off to the viewer
    property bool chatsLoading: true // skeleton until the first snapshot lands
    property var avatars: ({})       // jid -> file:// thumbnail, icon fallback until it lands
    property string searchQuery: ""  // filters the list by name/preview
    property int focusTries: 0       // first-open focus retries, see focusGrabber
    property string chatFilter: "all" // all|unread|groups — the WA filter pills

    // Empty state: no rows, no snapshot in flight, not pairing, no error.
    readonly property bool emptyState: root.chats.length === 0 && !root.chatsLoading && root.qrPng === "" && root.connState !== "error" && root.connState !== "logged-out"
    // Dead-end search: same treatment, the illustration names the query.
    readonly property bool noResults: root.searchQuery.trim() !== "" && root.visibleChats().length === 0 && !root.chatsLoading && root.chats.length > 0 && root.qrPng === ""
    // Filter hides everything while chats exist and no query is typed:
    // without this the list sits blank with dead keys and no clue why.
    readonly property bool filterEmpty: root.chats.length > 0 && root.visibleChats().length === 0 && root.searchQuery.trim() === "" && !root.chatsLoading && root.qrPng === "" && root.connState !== "error" && root.connState !== "logged-out"
    // Right pane shows the pair/error view instead of a conversation.
    readonly property bool paneOverlay: root.qrPng !== "" || root.connState === "error" || root.connState === "logged-out"

    function handleLine(line) {
        var ev = null
        try { ev = JSON.parse(line) } catch (e) { return }
        if (ev.type === "status") {
            root.connState = ev.state || "starting"
            root.statusDetail = ev.detail || ""
            if (ev.state === "connected" || ev.state === "connecting") root.qrPng = ""
            if (ev.state === "connected") root.requestChats()
        } else if (ev.type === "qr") {
            root.qrPng = ev.png
            root.qrTimeout = ev.timeout
            root.connState = "waiting-qr"
        } else if (ev.type === "paired") {
            root.qrPng = ""
        } else if (ev.type === "chats") {
            if (root.demoMode) return
            root.chats = ev.chats || []
            root.chatsLoading = false
            root.requestAvatars()
        } else if (ev.type === "chat-updated") {
            if (root.demoMode) return
            root.mergeChat(ev.chat)
            root.requestAvatars()
        } else if (ev.type === "chat-read") {
            var rl = root.chats.slice()
            for (var ri = 0; ri < rl.length; ri++) {
                if (rl[ri].jid === ev.jid && (rl[ri].unread || 0) > 0) {
                    rl[ri] = Object.assign({}, rl[ri], {unread: 0})
                    break
                }
            }
            root.chats = rl
        } else if (ev.type === "avatar") {
            var m = Object.assign({}, root.avatars)
            m[ev.jid] = ev.path
            root.avatars = m
        } else if (ev.type === "history") {
            if (ev.jid === root.openJid) {
                root.convoLoading = false
                if (root.loadingMore) {
                    var oldLen = root.messages.length
                    root.messages = ev.messages || []
                    root.loadingMore = false
                    // Pin the first previously-visible row, don't jump.
                    msgList.positionViewAtIndex(Math.max(0, root.messages.length - oldLen), ListView.Beginning)
                } else {
                    root.messages = ev.messages || []
                    root.msgCursor = root.messages.length - 1
                    root.scrollEnd()
                }
            }
        } else if (ev.type === "message") {
            if (root.demoMode) return
            if (ev.msg && ev.msg.chat === root.openJid) {
                root.convoLoading = false
                if (ev.msg.from_me) root.foldOwnEcho(ev.msg)
                else root.appendBubble(ev.msg)
                if (daemonProc.running) daemonProc.write("{\"cmd\":\"open\",\"jid\":" + JSON.stringify(root.openJid) + "}\n")
            } else if (ev.msg && !ev.msg.from_me) {
                root.notifyChat(ev.chat, ev.msg)
            }
        } else if (ev.type === "ack") {
            if (ev.jid === root.openJid) root.setBubbleAck(ev.id, ev.ack)
        } else if (ev.type === "msg-updated") {
            if (ev.msg && ev.msg.chat === root.openJid) root.replaceBubble(ev.msg)
            if (ev.chat) root.mergeChat(ev.chat)
        } else if (ev.type === "typing") {
            var t = Object.assign({}, root.typing)
            if ((ev.names || []).length === 0) delete t[ev.jid]
            else t[ev.jid] = ev.names
            root.typing = t
        } else if (ev.type === "sent") {
            if (ev.jid === root.openJid) {
                var acked = root.matchSent(ev)
                if (acked === "" || acked === undefined) acked = root.oldestSending()
                root.markBubble(acked, "sent", ev.id)
                root.scrollEnd()
            }
        } else if (ev.type === "send-error") {
            if (root.pendingMsgs.length > 0) {
                var f = root.pendingMsgs.shift()
                root.markBubble(f.localId, "failed", "")
            }
            root.statusDetail = ev.detail || "send failed"
        }
    }

    function appendBubble(m) {
        var wasEnd = root.msgCursor < 0 || root.msgCursor === root.messages.length - 1
        var stick = msgList.atYEnd
        var list = root.messages.slice()
        list.push(m)
        root.messages = list
        if (wasEnd) root.msgCursor = list.length - 1
        if (stick) root.scrollEnd()
    }

    // Match a daemon echo to its optimistic bubble: media by path, text by
    // oldest same-kind pending. Returns the localId or "".
    function matchSent(ev) {
        var at = -1
        if ((ev.media || "") !== "") {
            for (var i = 0; i < root.pendingMsgs.length; i++) {
                if (root.pendingMsgs[i].path === ev.media) { at = i; break }
            }
        } else {
            var wantKind = ev.kind || "text"
            for (var j = 0; j < root.pendingMsgs.length; j++) {
                if ((root.pendingMsgs[j].kind || "text") === wantKind) { at = j; break }
            }
            if (at < 0 && root.pendingMsgs.length > 0) at = 0
        }
        if (at < 0) return ""
        var found = root.pendingMsgs[at]
        root.pendingMsgs.splice(at, 1)
        return found.localId
    }

    function markBubble(localId, status, id) {
        if (localId === "" || localId === undefined) return
        var list = root.messages.slice()
        for (var i = 0; i < list.length; i++) {
            if (list[i].localId === localId) {
                var next = Object.assign({}, list[i])
                next.status = status
                if (id) next.id = id
                list[i] = next
                break
            }
        }
        root.messages = list
        root.holdMsgView()
    }

    // Local id of the oldest bubble still showing the send spinner, or "".
    function oldestSending() {
        for (var i = 0; i < root.messages.length; i++) {
            if ((root.messages[i].status || "") === "sending" && (root.messages[i].localId || "") !== "") return root.messages[i].localId
        }
        return ""
    }

    // Own-message live echo (sent from the phone, or a send ack that
    // arrived as a message event): fold into the matching spinner
    // bubble instead of appending a duplicate row.
    function foldOwnEcho(m) {
        for (var i = 0; i < root.messages.length; i++) {
            var b = root.messages[i]
            if ((b.status || "") === "sending" && (b.kind || "text") === (m.kind || "text") && (b.text || "") === (m.text || "") && Math.abs((m.ts || 0) - (b.ts || 0)) < 60000) {
                var list = root.messages.slice()
                var next = Object.assign({}, b, {status: "sent"})
                if (m.id) next.id = m.id
                if (m.media) next.media = m.media
                list[i] = next
                root.messages = list
                root.holdMsgView()
                return
            }
        }
        root.appendBubble(m)
    }

    function setBubbleAck(id, ack) {
        var list = root.messages.slice()
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id && list[i].from_me) {
                list[i] = Object.assign({}, list[i], {ack: ack})
                break
            }
        }
        root.messages = list
        root.holdMsgView()
    }

    function replaceBubble(m) {
        var list = root.messages.slice()
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === m.id) {
                var keep = {localId: list[i].localId, status: list[i].status}
                list[i] = Object.assign({}, m, keep)
                break
            }
        }
        root.messages = list
        root.holdMsgView()
    }

    function notifyChat(chat, msg) {
        // Drop backlog replays: daemon re-emits missed messages on
        // reconnect with their original server timestamp. Only ping
        // for genuinely fresh inbound (<90s old). Chat list still
        // updates via chat-updated, just no toast for old rows.
        if ((chat && chat.muted) === true) return
        var mts = (msg && msg.ts) || 0
        if (mts > 0 && Date.now() - mts > 90000) return
        var jid = (chat && chat.jid) || ""
        var title = (chat && chat.name) || "WhatsApp"
        var preview = (msg && msg.text) || root.kindLabel(msg ? msg.kind : "")
        if (preview === "") return
        // Coalesce per chat: first message pings at once, the rest fold
        // into one summary when the window drains.
        var st = root.notifState[jid]
        if (st === undefined) {
            root.notifState[jid] = {name: title, count: 1}
            Quickshell.execDetached(["notify-send", "-a", "WhatsApp", title, preview])
            if (!notifFlush.running) notifFlush.restart()
        } else {
            st.count++
        }
    }

    function flushNotifs() {
        var st = root.notifState
        root.notifState = {}
        for (var jid in st) {
            if (st[jid].count > 1) Quickshell.execDetached(["notify-send", "-a", "WhatsApp", st[jid].name, st[jid].count + " new messages"])
        }
    }

    function toggleVoice(m) {
        var key = m.localId || m.id
        if (root.playingId === key) {
            voicePlayer.stop()
            root.playingId = ""
            return
        }
        voicePlayer.source = m.media
        voicePlayer.play()
        root.playingId = key
    }

    // Hand a media file to the system viewer with tap feedback: the tile
    // dims with a spinner until the viewer should be up. xdg-open returns
    // at spawn, so the timer covers launch, not the viewer itself.
    function openMedia(m) {
        var key = m.localId || m.id
        root.openingId = key
        openingLife.restart()
        Quickshell.execDetached(["xdg-open", m.media])
    }

    function resendBubble(localId) {
        var bubble = null
        for (var i = 0; i < root.messages.length; i++) {
            if (root.messages[i].localId === localId) bubble = root.messages[i]
        }
        if (bubble === null || !daemonProc.running) return
        root.markBubble(localId, "sending", "")
        if ((bubble.media || "") !== "") {
            var video = (bubble.kind || "") === "video"
            root.pendingMsgs.push({localId: localId, body: bubble.text || "", kind: bubble.kind, path: bubble.media})
            daemonProc.write("{\"cmd\":\"" + (video ? "send-video" : "send-image") + "\",\"jid\":" + JSON.stringify(root.openJid) + ",\"path\":" + JSON.stringify(bubble.media) + ",\"caption\":" + JSON.stringify(bubble.text || "") + "}\n")
        } else {
            root.pendingMsgs.push({localId: localId, body: bubble.text || "", kind: "text", path: ""})
            daemonProc.write("{\"cmd\":\"send-text\",\"jid\":" + JSON.stringify(root.openJid) + ",\"body\":" + JSON.stringify(bubble.text || "") + "}\n")
        }
    }

    function scrollEnd() {
        msgList.positionViewAtEnd()
    }

    // In-place row updates (acks, edits, retries) rebuild the model and
    // would throw the viewport anywhere: restore pixels, or stay pinned
    // when pinned.
    function holdMsgView() {
        var y = msgList.contentY
        var end = msgList.atYEnd
        Qt.callLater(function () {
            if (end) msgList.positionViewAtEnd()
            else msgList.contentY = Math.min(y, Math.max(0, msgList.contentHeight - msgList.height))
        })
    }

    function requestChats() {
        root.chatsLoading = true
        if (daemonProc.running) daemonProc.write("{\"cmd\":\"chats\"}\n")
    }

    // Thumbnails for the visible viewport only. Missing entries trigger
    // one batched daemon fetch; landed files stay cached on both sides.
    // The daemon queues while busy, so scroll bursts collapse server-side.
    function requestAvatars() {
        var rows = root.visibleChats()
        if (rows.length === 0 || chatList.count === 0) return
        var top = chatList.indexAt(10, chatList.contentY + 10)
        var bottom = chatList.indexAt(10, chatList.contentY + chatList.height - 10)
        if (top < 0) top = 0
        if (bottom < 0) bottom = rows.length - 1
        var missing = []
        for (var i = top; i <= Math.min(bottom, rows.length - 1); i++) {
            if (root.avatars[rows[i].jid] === undefined && (rows[i].avatar || "") === "") missing.push(rows[i].jid)
        }
        if (missing.length > 0 && daemonProc.running) {
            daemonProc.write("{\"cmd\":\"avatars\",\"jids\":" + JSON.stringify(missing) + "}\n")
        }
    }

    function mergeChat(c) {
        var list = root.chats.slice()
        var at = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].jid === c.jid) { at = i; break }
        }
        // Name-only sightings never open new rows; the daemon only lists
        // chats with activity.
        if (at < 0 && !(c.ts > 0)) return
        if (at >= 0) list[at] = c
        else list.unshift(c)
        list.sort(function (a, b) {
            var at0 = (a.ts || 0) === 0
            var bt0 = (b.ts || 0) === 0
            if (at0 !== bt0) return at0 ? 1 : -1
            if ((a.ts || 0) !== (b.ts || 0)) return (b.ts || 0) - (a.ts || 0)
            return a.name < b.name ? -1 : 1
        })
        // Don't yank the list on every message: when scrolled down,
        // hold position across the re-sort; snap to top only near it.
        var holdY = chatList.contentY > 150
        if (holdY) root._listY = chatList.contentY
        root.chats = list.slice(0, 100)
        if (holdY) Qt.callLater(function () {
            chatList.contentY = Math.min(root._listY, Math.max(0, chatList.contentHeight - chatList.height))
        })
    }

    function openChat(jid) {
        root.selectedJid = jid
        root.openJid = jid
        root.messages = []
        root.pendingMsgs = []
        root.msgCursor = -1
        root.historyLimit = 50
        root.loadingMore = false
        root.convoLoading = true
        root.replyTo = null
        root.emojiOpen = false
        if (root.demoMode) {
            root.messages = root.demoMessages(jid)
            root.convoLoading = false
            root.msgCursor = root.messages.length - 1
            root.scrollEnd()
        } else if (daemonProc.running) {
            daemonProc.write("{\"cmd\":\"open\",\"jid\":" + JSON.stringify(jid) + "}\n")
            daemonProc.write("{\"cmd\":\"history\",\"jid\":" + JSON.stringify(jid) + ",\"limit\":50}\n")
        }
        Qt.callLater(function () {
            if (!root.convoReadonly()) composer.forceActiveFocus()
            else msgList.forceActiveFocus()
        })
    }

    function backToList() {
        root.openJid = ""
        root.messages = []
        root.pendingMsgs = []
        root.msgCursor = -1
        root.convoLoading = false
        root.attachPaths = []
        root.replyTo = null
        root.emojiOpen = false
        voicePlayer.stop()
        root.playingId = ""
        Qt.callLater(function () { card.forceActiveFocus() })
    }

    function convoName() {
        for (var i = 0; i < root.chats.length; i++) {
            if (root.chats[i].jid === root.openJid) return root.chats[i].name
        }
        return root.openJid
    }

    function convoReadonly() {
        for (var i = 0; i < root.chats.length; i++) {
            if (root.chats[i].jid === root.openJid) return (root.chats[i].readonly || false) === true
        }
        return false
    }

    function addAttach(p) {
        if (!p) return
        if (root.attachPaths.indexOf(p) >= 0) return
        if (root.attachPaths.length >= 10) return
        root.attachPaths = root.attachPaths.concat([p])
    }

    function removeAttach(i) {
        var a = root.attachPaths.slice()
        a.splice(i, 1)
        root.attachPaths = a
    }

    function cursorMessage() {
        if (root.hoverMsgId !== "") {
            for (var i = 0; i < root.messages.length; i++) {
                if (root.messages[i].id === root.hoverMsgId) return root.messages[i]
            }
        }
        if (root.msgCursor >= 0 && root.msgCursor < root.messages.length) return root.messages[root.msgCursor]
        return null
    }

    function replyToMessage(m) {
        if (!m || (m.id || "") === "" || (m.status || "") === "sending" || (m.status || "") === "failed") return
        if (root.convoReadonly()) return
        root.replyTo = {id: m.id, text: m.text || "", kind: m.kind || "", sender: m.from_me ? "You" : (m.sender || ""), from_me: m.from_me}
        composer.forceActiveFocus()
    }

    function escHtml(t) {
        return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function linkify(t) {
        var e = root.escHtml(t)
        return e.replace(/(https?:\/\/[^\s<]+|www\.[^\s<]+)/g, function (u) {
            var h = u.indexOf("http") === 0 ? u : "http://" + u
            return '<a href="' + h + '">' + u + '</a>'
        })
    }

    function firstLink(t) {
        var m = (t || "").match(/https?:\/\/[^\s<]+|www\.[^\s<]+/)
        if (!m) return ""
        return m[0].indexOf("http") === 0 ? m[0] : "http://" + m[0]
    }

    function isBigEmoji(t) {
        if (!t) return false
        var chars = [...t.trim()]
        if (chars.length === 0 || chars.length > 4) return false
        for (var i = 0; i < chars.length; i++) {
            var c = chars[i].codePointAt(0)
            if (c === 0xFE0F || c === 0x200D || c === 0x20E3) continue
            if (!(c === 0x00A9 || c === 0x00AE || (c >= 0x2000 && c <= 0x3300) || (c >= 0x1F000 && c <= 0x1FAFF) || (c >= 0x2600 && c <= 0x27BF) || (c >= 0x2B00 && c <= 0x2BFF))) return false
        }
        return true
    }

    function jumpToQuote(id) {
        if (!id) return
        for (var i = 0; i < root.messages.length; i++) {
            if (root.messages[i].id === id) {
                root.msgCursor = i
                msgList.positionViewAtIndex(i, ListView.Center)
                break
            }
        }
    }

    function demoChats() {
        var now = Date.now()
        return [
            {jid: "2348012345678@s.whatsapp.net", name: "Mama", preview: "Call me when you land", kind: "text", ts: now - 4 * 60000, unread: 2},
            {jid: "demodev@g.us", name: "Dev Team", preview: "Ada: ship it", kind: "text", ts: now - 26 * 60000, unread: 5},
            {jid: "2348098765432@s.whatsapp.net", name: "Adaeze", preview: "Photo", kind: "photo", ts: now - 70 * 60000, unread: 0},
            {jid: "demofamily@g.us", name: "Family", preview: "You: on my way", kind: "text", ts: now - 3 * 3600000, unread: 0},
            {jid: "2348071122334@s.whatsapp.net", name: "Bola", preview: "Voice message", kind: "voice", ts: now - 7 * 3600000, unread: 0},
            {jid: "demoball@g.us", name: "Football Group", preview: "Match by 4pm", kind: "text", ts: now - 26 * 3600000, unread: 11},
            {jid: "2348055566677@s.whatsapp.net", name: "Chinedu", preview: "Thanks!", kind: "text", ts: now - 86400000, unread: 0},
            {jid: "demodesign@g.us", name: "Design Club", preview: "Ngozi: new mockups", kind: "text", ts: now - 2 * 86400000, unread: 0}
        ]
    }

    function demoMessages(jid) {
        var now = Date.now()
        var M = function (id, mins, fromMe, kind, text, extra) {
            var m = {id: id, chat: jid, from_me: fromMe, sender: fromMe ? "" : "Adaeze", text: text || "", kind: kind || "text", media: "", ack: fromMe ? "read" : "", ts: now - mins * 60000}
            if (extra) for (var k in extra) m[k] = extra[k]
            return m
        }
        if (jid === "2348098765432@s.whatsapp.net") {
            return [
                M("d1", 90, false, "text", "Hey! Finally made it to the coast"),
                M("d2", 88, true, "text", "No way, send pics"),
                M("d3", 70, false, "photo", "Golden hour", {media: "/tmp/wa-demo1.png"}),
                M("d4", 68, true, "text", "That sky is unreal", {quoted_id: "d3", quoted_text: "Golden hour", quoted_name: "Adaeze"}),
                M("d5", 65, false, "photo", "One more", {media: "/tmp/wa-demo2.png", reactions: "{\"\u2764\ufe0f\":[\"You\"]}"}),
                M("d6", 40, true, "text", "Saving both of these")
            ]
        }
        return [
            M("d1", 60, false, "text", "Are we still on for lunch tomorrow?"),
            M("d2", 55, true, "text", "Yes! Same place, 12:30"),
            M("d3", 54, false, "text", "Perfect, see you there", {reactions: "{\"\U0001F44D\":[\"You\"]}"}),
            M("d4", 20, true, "text", "Running 5 late, order me the usual?", {quoted_id: "d1", quoted_text: "Are we still on for lunch tomorrow?", quoted_name: "Adaeze"}),
            M("d5", 4, false, "text", "Done, it is waiting for you")
        ]
    }

    function toggleDemo() {
        if (root.demoMode) {
            root.demoMode = false
            root.openJid = ""
            root.messages = []
            root.chats = []
            root.chatsLoading = true
            if (daemonProc.running) daemonProc.write("{\"cmd\":\"chats\"}\n")
        } else {
            root.demoMode = true
            root.open = true
            root.openJid = ""
            root.messages = []
            root.chatsLoading = false
            root.typing = {}
            root.chats = root.demoChats()
        }
    }

    function sendReaction(id, emoji) {
        if (id === "" || !daemonProc.running) return
        daemonProc.write("{\"cmd\":\"send-reaction\",\"jid\":" + JSON.stringify(root.openJid) + ",\"id\":" + JSON.stringify(id) + ",\"emoji\":" + JSON.stringify(emoji) + "}\n")
    }

    function reactionChips(raw) {
        if (!raw || raw === "{}") return []
        try {
            var m = JSON.parse(raw)
            var out = []
            for (var e in m) {
                if (m[e] && m[e].length > 0) out.push({emoji: e, n: m[e].length})
            }
            return out
        } catch (err) {
            return []
        }
    }

    function pickEmoji(e) {
        if (root.emojiMode === "react" && root.reactTarget !== "") {
            root.sendReaction(root.reactTarget, e)
            root.reactTarget = ""
            root.emojiOpen = false
            Qt.callLater(function () { card.forceActiveFocus() })
            return
        }
        composer.insert(composer.cursorPosition, e)
        composer.forceActiveFocus()
    }

    property var emojiList: ["😀", "😃", "😄", "😁", "😂", "🤣", "😊", "😍", "😘", "😎", "🤔", "😅", "😏", "😜", "😝", "😛", "🤓", "🥸", "😏", "😭", "😮", "😢", "😡", "😠", "👿", "😬", "🤨", "🙄", "🤐", "🤗", "🤯", "😺", "🙀", "🙈", "🙉", "🙊", "👍", "👎", "👌", "👋", "👏", "🙏", "🙌", "💪", "🤦", "🤷", "💅", "❤", "💕", "💖", "💗", "💖", "💔", "💞", "✨", "🌟", "🎉", "🎊", "🥳", "🎀", "🎁", "🎂", "🎃", "🔥", "⚡", "❄", "🌙", "☀", "🌈", "⭐", "✅", "❌", "❓", "❗", "💯", "👀", "👁", "💤", "💥", "💫", "☕", "🍵", "🍺", "🍕", "🍔", "🍰", "🍪", "⚽", "🏀", "🎮", "🎲", "🎰", "🎸", "🎧", "📷", "📚", "💡", "🔑", "🛠", "🚀", "✈", "🚗", "🚲", "⛵", "🏝", "⛺", "🌹", "🌻"]

    function sendDraft() {
        if (root.demoMode) {
            var q = root.replyTo
            if (root.attachPaths.length > 0) {
                for (var i = 0; i < root.attachPaths.length; i++) {
                    var path = root.attachPaths[i]
                    var video = /\.(mp4|mov|webm|3gp)$/i.test(path)
                    var lid = "dl" + Date.now() + "_" + i
                    root.appendBubble({id: lid, localId: lid, chat: root.openJid, from_me: true, sender: "", text: (i === 0 ? composer.text.trim() : ""), kind: video ? "video" : "photo", media: path, status: "sent", ack: "delivered", ts: Date.now()})
                }
            } else if (composer.text.trim() !== "") {
                root.appendBubble({id: "dl" + Date.now(), localId: "dl" + Date.now(), chat: root.openJid, from_me: true, sender: "", text: composer.text.trim(), kind: "text", media: "", quoted_id: q ? q.id : "", quoted_text: q ? q.text : "", quoted_name: q ? q.sender : "", status: "sent", ack: "delivered", ts: Date.now()})
            }
            composer.text = ""
            root.attachPaths = []
            root.replyTo = null
            root.emojiOpen = false
            return
        }
        if (root.openJid === "" || root.convoReadonly() || !daemonProc.running) return
        if (root.attachPaths.length > 0) {
            var caption = composer.text.trim()
            var q = root.replyTo
            for (var i = 0; i < root.attachPaths.length; i++) {
                var path = root.attachPaths[i]
                var video = /\.(mp4|mov|webm|3gp)$/i.test(path)
                var kind = video ? "video" : "photo"
                var lid = "l" + Date.now() + "_" + i
                var cap = i === 0 ? caption : ""
                var qid = (i === 0 && q) ? q.id : ""
                root.pendingMsgs.push({localId: lid, body: cap, kind: kind, path: path})
                root.appendBubble({id: lid, localId: lid, chat: root.openJid, from_me: true, sender: "", text: cap, kind: kind, media: path, quoted_id: qid, quoted_text: (i === 0 && q) ? q.text : "", quoted_name: (i === 0 && q) ? q.sender : "", ts: Date.now(), status: "sending"})
                root.scrollEnd()
                daemonProc.write("{\"cmd\":\"" + (video ? "send-video" : "send-image") + "\",\"jid\":" + JSON.stringify(root.openJid) + ",\"path\":" + JSON.stringify(path) + ",\"caption\":" + JSON.stringify(cap) + ",\"reply_to\":" + JSON.stringify(qid) + "}\n")
            }
            composer.text = ""
            root.attachPaths = []
            root.replyTo = null
            root.emojiOpen = false
            return
        }
        var body = composer.text.trim()
        if (body === "") return
        var q = root.replyTo
        var lid = "l" + Date.now()
        root.pendingMsgs.push({localId: lid, body: body, kind: "text", path: ""})
        root.appendBubble({id: lid, localId: lid, chat: root.openJid, from_me: true, sender: "", text: body, kind: "text", media: "", quoted_id: q ? q.id : "", quoted_text: q ? q.text : "", quoted_name: q ? q.sender : "", ts: Date.now(), status: "sending"})
        root.scrollEnd()
        daemonProc.write("{\"cmd\":\"send-text\",\"jid\":" + JSON.stringify(root.openJid) + ",\"body\":" + JSON.stringify(body) + ",\"reply_to\":" + JSON.stringify(q ? q.id : "") + "}\n")
        composer.text = ""
        root.replyTo = null
        root.emojiOpen = false
    }

    function moveMsgCursor(dir) {
        if (root.messages.length === 0) return
        var at = root.msgCursor < 0 ? (dir > 0 ? 0 : root.messages.length - 1) : Math.min(root.messages.length - 1, Math.max(0, root.msgCursor + dir))
        root.msgCursor = at
        msgList.positionViewAtIndex(at, ListView.Contain)
    }

    function copyCursor() {
        if (root.msgCursor < 0 || root.msgCursor >= root.messages.length) return
        var m = root.messages[root.msgCursor]
        var t = m.text || root.kindLabel(m.kind)
        if (t === "") return
        toast.flash("Copied")
        try {
            Quickshell.clipboardText = t
        } catch (e) {}
    }

    // Mute toggle for one chat. Optimistic: the row retags at once, the
    // daemon persists it and echoes chat-updated as confirmation.
    function toggleMute(jid) {
        if (jid === "" || !daemonProc.running) return
        var muted = false
        for (var i = 0; i < root.chats.length; i++) {
            if (root.chats[i].jid === jid) { muted = root.chats[i].muted === true; break }
        }
        daemonProc.write("{\"cmd\":\"" + (muted ? "unmute" : "mute") + "\",\"jid\":" + JSON.stringify(jid) + "}\n")
        var list = root.chats.slice()
        for (var j = 0; j < list.length; j++) {
            if (list[j].jid === jid) { list[j] = Object.assign({}, list[j], {muted: !muted}); break }
        }
        root.chats = list
        toast.flash(muted ? "Unmuted" : "Muted")
    }

    // Retry the oldest failed bubble in the open conversation, if any.
    function resendFailed() {
        for (var i = 0; i < root.messages.length; i++) {
            if ((root.messages[i].status || "") === "failed" && root.messages[i].localId) {
                root.resendBubble(root.messages[i].localId)
                return
            }
        }
    }

    function pasteToComposer() {
        composer.focus = true
        composer.paste()
    }

    // True for plain typing keys: single printable char, no control
    // modifiers, not a command key. Those jump straight into an input.
    function isTypeChar(e) {
        if (e.text === "" || e.text.length !== 1) return false
        if ((e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0) return false
        return e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Tab && e.key !== Qt.Key_Backspace && e.key !== Qt.Key_Delete
    }

    // Filtered rows: search query plus the All/Unread/Groups pills.
    // A plain function (not a filtered model object) so the ListView
    // re-evaluates whenever chats, the query or the pill change.
    function visibleChats() {
        var q = root.searchQuery.trim().toLowerCase()
        var out = []
        for (var i = 0; i < root.chats.length; i++) {
            var c = root.chats[i]
            if (root.chatFilter === "unread" && (c.unread || 0) === 0) continue
            if (root.chatFilter === "groups" && (c.jid || "").indexOf("@g.us") < 0) continue
            if (q !== "" && (c.name || "").toLowerCase().indexOf(q) < 0 && (c.preview || "").toLowerCase().indexOf(q) < 0) continue
            out.push(c)
        }
        return out
    }

    function moveSelection(dir) {
        var list = root.visibleChats()
        if (list.length === 0) return
        var at = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].jid === root.selectedJid) { at = i; break }
        }
        if (at < 0) at = dir > 0 ? 0 : list.length - 1
        else at = Math.min(list.length - 1, Math.max(0, at + dir))
        root.selectedJid = list[at].jid
        chatList.positionViewAtIndex(at, ListView.Contain)
    }

    function moveEdge(last) {
        var list = root.visibleChats()
        if (list.length === 0) return
        var at = last ? list.length - 1 : 0
        root.selectedJid = list[at].jid
        chatList.positionViewAtIndex(at, ListView.Contain)
    }

    function fmtTime(ts) {
        if (!ts) return ""
        var d = new Date(ts)
        var now = new Date()
        var sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()
        if (sameDay) {
            var h = d.getHours()
            var m = d.getMinutes()
            return (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m)
        }
        return (d.getMonth() + 1) + "/" + d.getDate()
    }

    // Message-kind pictogram (Phosphor). Text and reaction rows show
    // their content with no glyph.
    function kindGlyph(kind) {
        if (kind === "photo") return ""
        if (kind === "video") return ""
        if (kind === "voice") return ""
        if (kind === "file") return ""
        if (kind === "sticker") return ""
        if (kind === "contact") return ""
        if (kind === "location") return ""
        return ""
    }

    function kindLabel(kind) {
        if (kind === "photo") return "Photo"
        if (kind === "video") return "Video"
        if (kind === "voice") return "Voice message"
        if (kind === "file") return "File"
        if (kind === "sticker") return "Sticker"
        if (kind === "contact") return "Contact"
        if (kind === "location") return "Location"
        return ""
    }

    // Delivery pictograms: single check sent, double delivered, double
    // in ice when read. Spinners and words are gone; state is iconic.
    function tickGlyph(ack) {
        if (ack === "read" || ack === "delivered") return ""
        return ""
    }

    function tickColor(ack) {
        if (ack === "read") return colors.tertiary
        if (ack === "delivered") return colors.alpha(colors.outline, 0.8)
        return colors.alpha(colors.outline, 0.5)
    }

    // Typing label for a chat: one name, two names, or a headcount.
    function typingLabel(jid) {
        var names = root.typing[jid] || []
        if (names.length === 0) return ""
        if (names.length === 1) return names[0] + " typing…"
        if (names.length === 2) return names[0] + ", " + names[1] + " typing…"
        return names.length + " typing…"
    }

    function playGlyph() { return ""; }
    function pauseGlyph() { return ""; }

    function retry() {
        root.daemonMissing = false
        root.connState = "starting"
        root.statusDetail = "retrying"
        if (daemonProc.running) daemonProc.write("{\"cmd\":\"start\"}\n")
        else daemonProc.running = true
    }

    title: "WhatsApp"
    implicitWidth: 640
    implicitHeight: 720
    minimumSize: Qt.size(640, 720)
    maximumSize: Qt.size(860, 940)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "whatsapp"; function toggle(): void { root.open = !root.open } function open(jid: string): void { root.openChat(jid); root.open = true } function demo(): void { root.toggleDemo() } function st(): string { return "open=" + root.openJid + " st=" + root.connState + " msgs=" + root.messages.length + " ro=" + root.convoReadonly() + " overlay=" + root.paneOverlay + " chats=" + root.chats.length + " sel=" + root.selectedJid } }

    Timer { id: gTimer; interval: 800; onTriggered: {
        // gg window lapsed: the lone g was type-ahead, deliver it.
        if (root.gPending) { root.gPending = false; composer.insert(composer.cursorPosition, "g") }
    } }
    Timer { id: copyLife; interval: 1500; onTriggered: { if (root.statusDetail === "Copied") root.statusDetail = "" } }
    Timer { id: notifFlush; interval: 15000; repeat: false; onTriggered: root.flushNotifs() }
    Timer { id: openingLife; interval: 2500; onTriggered: root.openingId = "" }
    // First-open focus fix: forceActiveFocus can land before the window
    // maps, silently failing and leaving every key dead. Retry briefly.
    Timer {
        id: focusGrabber
        interval: 150
        repeat: true
        running: root.open && root.focusTries > 0
        onTriggered: {
            root.focusTries--
            if (!searchInput.activeFocus && !composer.activeFocus && !card.activeFocus) card.forceActiveFocus()
        }
    }

    MediaPlayer {
        id: voicePlayer
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState) root.playingId = ""
        }
    }

    function fmtDur(s) {
        s = s || 0
        var m = Math.floor(s / 60)
        var r = s - m * 60
        return m + ":" + (r < 10 ? "0" + r : "" + r)
    }

    // Flea picker via the FileChooser portal: one-shot process, prints
    // picked paths (one per line in multi mode). Cancel changes nothing.
    Process {
        id: pickProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var picked = text.trim().split("\n")
                for (var i = 0; i < picked.length; i++) root.addAttach(picked[i].trim())
                Qt.callLater(function () { card.forceActiveFocus() })
            }
        }
    }

    Process {
        id: pasteTypesProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var hasPng = text.indexOf("image/png") >= 0
                var hasJpeg = text.indexOf("image/jpeg") >= 0
                if (!hasPng && !hasJpeg) {
                    composer.paste()
                    return
                }
                root.pasteTarget = "/tmp/wa-paste-" + Date.now() + ".png"
                pasteDumpProc.command = ["sh", "-c", "wl-paste --type " + (hasPng ? "image/png" : "image/jpeg") + " > " + root.pasteTarget]
                pasteDumpProc.running = true
            }
        }
    }

    Process {
        id: pasteDumpProc
        onExited: function (code) {
            if (code === 0) root.addAttach(root.pasteTarget)
            else composer.paste()
        }
    }

    function pickFile() {
        if (pickProc.running) return
        pickProc.command = [Quickshell.env("HOME") + "/whatsapp-bridge/pick-file", "media", "multi"]
        pickProc.running = true
    }

    // Clipboard image paste: list types first, dump the image if there is
    // one, otherwise fall back to the native text paste we intercepted.
    function pasteImage() {
        if (pasteTypesProc.running || pasteDumpProc.running) return
        pasteTypesProc.command = ["wl-paste", "--list-types"]
        pasteTypesProc.running = true
    }

    onOpenChanged: {
        if (open) {
            root.requestChats()
            root.focusTries = 10
            // Fresh selection every open: a stale selectedJid from last
            // time would make Enter open the wrong chat.
            root.selectedJid = ""
            root.hoverJid = ""
            Qt.callLater(function () { card.forceActiveFocus() })
        }
    }

    // Persistent child: stdin stays open, so the daemon lives exactly as
    // long as the shell does. Stdout lines arrive via SplitParser — no timers.
    Process {
        id: daemonProc
        // Lean heap: frequent GC, 32 MiB soft cap, return pages to the OS
        // at once (costs a little CPU, saves ~10 MB idle).
        command: ["env", "GOGC=20", "GOMEMLIMIT=32MiB", "GODEBUG=madvdontneed=1", root.daemon]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) { root.handleLine(data) }
        }
        // Consume stderr so the daemon can never block on a full pipe.
        // Daemon diagnostics land in the shell log; errors surface in status.
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                console.log("[wa-daemon] " + data)
                if (data.indexOf("level=ERROR") >= 0) {
                    root.connState = "error"
                    root.statusDetail = data.slice(-160)
                }
            }
        }
        onExited: function (code) {
            if (code !== 0 && root.connState !== "connected") {
                root.daemonMissing = true
                root.connState = "error"
                root.statusDetail = "daemon exited — build ~/whatsapp-bridge"
            }
        }
    }

    // ================= UI =================
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: colors.alpha(colors.surface, 0.84) }
            GradientStop { position: 1; color: colors.alpha(colors.surface, 0.68) }
        }
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        scale: root.open ? 1 : 0.97
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- app bar ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                color: "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 12
                    spacing: 6
                    Text {
                        text: "WHATSARCH"
                        color: colors.foreground
                        font.family: "Iceberg"
                        font.pixelSize: 15
                        font.letterSpacing: 3
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    // sign out — visible only while paired
                    Rectangle {
                        visible: root.connState === "connected"
                        width: 34
                        height: 34
                        radius: 17
                        color: signHover.containsMouse ? colors.alpha(colors.error, 0.2) : colors.alpha(colors.surfaceVariant, 0.35)
                        Layout.alignment: Qt.AlignVCenter
                        y: signHover.containsMouse ? -2 : 0
                        scale: signHover.pressed ? 0.9 : 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: colors.alpha(colors.error, 0.9)
                            font.family: root.iconFont
                            font.pixelSize: 19
                        }
                        MouseArea { id: signHover; anchors.fill: parent; hoverEnabled: true; onClicked: { if (daemonProc.running) daemonProc.write("{\"cmd\":\"logout\"}\n") } }
                    }
                }
            }

            // ---- single pane: list or conversation, never both ----
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ---- list (fills the window; hidden while a chat is open) ----
                ColumnLayout {
                    visible: root.openJid === ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // search
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.preferredHeight: 42
                        radius: 12
                        color: searchInput.activeFocus ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surfaceVariant, 0.3)
                        border.width: 1
                        border.color: searchInput.activeFocus ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.1)
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                text: ""
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: root.iconFont
                                font.pixelSize: 16
                                Layout.alignment: Qt.AlignVCenter
                            }
                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                verticalAlignment: TextInput.AlignVCenter
                                color: colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                text: root.searchQuery
                                onTextEdited: root.searchQuery = text
                                // Enter in search opens the top match — a
                                // single-line field swallows Return itself,
                                // so without this Enter dies here silently.
                                onAccepted: {
                                    var sr = root.visibleChats()
                                    if (sr.length > 0) root.openChat(sr[0].jid)
                                }
                                Keys.onPressed: function (e) {
                                    if (e.key === Qt.Key_Escape) {
                                        root.searchQuery = ""
                                        searchInput.focus = false
                                        e.accepted = true
                                        Qt.callLater(function () { card.forceActiveFocus() })
                                    }
                                }
                            }
                            Rectangle {
                                visible: root.searchQuery !== ""
                                width: 26
                                height: 26
                                radius: 13
                                color: clearHover.containsMouse ? colors.alpha(colors.primary, 0.16) : "transparent"
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    color: colors.alpha(colors.outline, 0.8)
                                    font.family: root.iconFont
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: clearHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.searchQuery = ""
                                        Qt.callLater(function () { card.forceActiveFocus() })
                                    }
                                }
                            }
                        }
                    }

                    // filter pills — every one of them actually filters
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 10
                        Layout.bottomMargin: 6
                        spacing: 8
                        Repeater {
                            model: [
                                {key: "all", label: "All"},
                                {key: "unread", label: "Unread"},
                                {key: "groups", label: "Groups"}
                            ]
                            Rectangle {
                                Layout.preferredHeight: 30
                                Layout.preferredWidth: pillLabel.implicitWidth + 28
                                radius: 15
                                color: root.chatFilter === modelData.key ? colors.alpha(colors.primary, 0.18) : colors.alpha(colors.surfaceVariant, 0.3)
                                border.width: 1
                                border.color: root.chatFilter === modelData.key ? colors.alpha(colors.primary, 0.45) : "transparent"
                                scale: pillHover.pressed ? 0.94 : 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Text {
                                    id: pillLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: root.chatFilter === modelData.key ? colors.primary : colors.alpha(colors.outline, 0.85)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                    font.capitalization: Font.AllUppercase
                                }
                                MouseArea {
                                    id: pillHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.chatFilter = modelData.key
                                        root.selectedJid = ""
                                    }
                                }
                            }
                        }
                    }

                    // section label — shared 14px rail with search and rows
                    Text {
                        visible: root.visibleChats().length > 0 && root.qrPng === ""
                        text: "CHATS · " + root.visibleChats().length
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        font.letterSpacing: 1.3
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.topMargin: 8
                        Layout.bottomMargin: 2
                    }

                    // skeleton loader — placeholder rows pulse until the snapshot lands
                    ColumnLayout {
                        visible: root.chatsLoading && root.chats.length === 0 && (root.connState === "connected" || root.connState === "connecting" || root.connState === "starting")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 6
                        spacing: 6
                        Repeater {
                            model: 7
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 68
                                radius: 14
                                color: colors.alpha(colors.surfaceVariant, 0.25)
                                opacity: 0.6
                                SequentialAnimation on opacity {
                                    running: root.chatsLoading
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.9; duration: 700; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutQuad }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    Rectangle {
                                        width: 50
                                        height: 50
                                        radius: 25
                                        color: colors.alpha(colors.surfaceVariant, 0.5)
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    ColumnLayout {
                                        spacing: 8
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 9; radius: 4; color: colors.alpha(colors.surfaceVariant, 0.5) }
                                        Rectangle { Layout.preferredWidth: 150; Layout.preferredHeight: 9; radius: 4; color: colors.alpha(colors.surfaceVariant, 0.35) }
                                    }
                                }
                            }
                        }
                    }

                    // empty states - centered line, search and tabs stay put above
                    Text {
                        visible: (root.emptyState || root.noResults || root.filterEmpty) && root.qrPng === ""
                        text: root.noResults ? "No results found" : (root.filterEmpty ? "Nothing in this filter" : "No chats yet - new chats show up here")
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                    }

                    ListView {
                        id: chatList
                        visible: root.visibleChats().length > 0 && root.qrPng === ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 6
                        clip: true
                        spacing: 2
                        model: root.visibleChats()
                        interactive: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        onMovementEnded: root.requestAvatars()
                        delegate: Rectangle {
                            width: chatList.width
                            height: 74
                            scale: rowMouse.pressed ? 0.98 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            color: modelData.jid === root.selectedJid ? colors.alpha(colors.primary, 0.12) : (rowMouse.containsMouse ? colors.alpha(colors.primary, 0.06) : "transparent")
                            border.width: modelData.jid === root.selectedJid ? 1 : 0
                            border.color: colors.alpha(colors.primary, 0.35)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12
                                // avatar — photo over a person/group icon chip
                                Item {
                                    width: 52
                                    height: 52
                                    Layout.alignment: Qt.AlignVCenter
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 26
                                        color: colors.alpha(modelData.jid.indexOf("@newsletter") >= 0 ? colors.tertiary : (modelData.jid.indexOf("@g.us") >= 0 ? colors.secondary : colors.primary), 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.jid.indexOf("@g.us") >= 0 ? "" : ""
                                            color: modelData.jid.indexOf("@newsletter") >= 0 ? colors.alpha(colors.tertiary, 0.9) : (modelData.jid.indexOf("@g.us") >= 0 ? colors.alpha(colors.secondary, 0.8) : colors.alpha(colors.primary, 0.8))
                                            font.family: root.iconFont
                                            font.pixelSize: 24
                                        }
                                    }
                                    Image {
                                        visible: (root.avatars[modelData.jid] || modelData.avatar || "") !== ""
                                        anchors.fill: parent
                                        source: (root.avatars[modelData.jid] || modelData.avatar || "") !== "" ? (root.avatars[modelData.jid] || modelData.avatar || "") : ""
                                        sourceSize: Qt.size(104, 104)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle { width: 52; height: 52; radius: 26 }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    spacing: 4
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: modelData.name
                                            color: colors.foreground
                                            font.family: colors.fontSans
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            Layout.fillWidth: true
                                        }
                                        Rectangle {
                                            visible: modelData.jid.indexOf("@newsletter") >= 0
                                            implicitWidth: chanLabel.implicitWidth + 12
                                            implicitHeight: 18
                                            radius: 9
                                            color: colors.alpha(colors.tertiary, 0.14)
                                            border.width: 1
                                            border.color: colors.alpha(colors.tertiary, 0.35)
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                id: chanLabel
                                                anchors.centerIn: parent
                                                text: "CHANNEL"
                                                color: colors.tertiary
                                                font.family: colors.fontSans
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                font.letterSpacing: 1.2
                                            }
                                        }
                                        Rectangle {
                                            visible: (modelData.muted || false) === true
                                            implicitWidth: muteLabel.implicitWidth + 12
                                            implicitHeight: 18
                                            radius: 9
                                            color: colors.alpha(colors.outline, 0.14)
                                            border.width: 1
                                            border.color: colors.alpha(colors.outline, 0.3)
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                id: muteLabel
                                                anchors.centerIn: parent
                                                text: "MUTED"
                                                color: colors.alpha(colors.outline, 0.85)
                                                font.family: colors.fontSans
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                font.letterSpacing: 1.2
                                            }
                                        }
                                        Text {
                                            text: root.fmtTime(modelData.ts)
                                            color: (modelData.unread || 0) > 0 ? colors.primary : colors.alpha(colors.outline, 0.55)
                                            font.family: colors.fontSans
                                            font.pixelSize: 9
                                            font.weight: (modelData.unread || 0) > 0 ? Font.Bold : Font.Normal
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        Text {
                                            visible: root.kindGlyph(modelData.kind) !== "" && root.typingLabel(modelData.jid) === ""
                                            text: root.kindGlyph(modelData.kind)
                                            color: colors.alpha(colors.tertiary, 0.9)
                                            font.family: root.iconFont
                                            font.pixelSize: 13
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Text {
                                            text: root.typingLabel(modelData.jid) !== "" ? root.typingLabel(modelData.jid) : (modelData.preview || root.kindLabel(modelData.kind))
                                            color: root.typingLabel(modelData.jid) !== "" ? colors.tertiary : colors.alpha(colors.outline, 0.7)
                                            font.family: colors.fontSans
                                            font.pixelSize: 10
                                            wrapMode: Text.NoWrap
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Rectangle {
                                            visible: (modelData.unread || 0) > 0
                                            implicitWidth: Math.max(20, unreadLabel.implicitWidth + 12)
                                            implicitHeight: 20
                                            radius: 10
                                            color: colors.primary
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                id: unreadLabel
                                                anchors.centerIn: parent
                                                text: (modelData.unread || 0) > 99 ? "99+" : "" + (modelData.unread || 0)
                                                color: colors.background
                                                font.family: colors.fontSans
                                                font.pixelSize: 10
                                                font.weight: Font.ExtraBold
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; onEntered: { root.hoverJid = modelData.jid; if (root.openJid === "" || root.paneOverlay) root.selectedJid = modelData.jid } onExited: { root.hoverJid = "" } onClicked: root.openChat(modelData.jid) }
                        }
                    }

                    Text {
                        visible: root.qrPng === ""
                        text: (root.openJid !== "" && !root.paneOverlay) ? "J/K scroll · gg top · G end · R reply · O react · E emoji · F type · U media · L link · ESC back" : "J/K move · ENTER open · Q mute · / search · G top · SHIFT+G bottom"
                        color: colors.alpha(colors.outline, 0.4)
                        font.family: colors.fontSans
                        font.pixelSize: 8
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 6
                        Layout.bottomMargin: 10
                    }
                }

                // ---- conversation (takes the whole window while a chat is open) ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // conversation
                    ColumnLayout {
                        visible: root.openJid !== "" && !root.paneOverlay
                        anchors.fill: parent
                        spacing: 0
                        // convo header
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 16
                                spacing: 10
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 19
                                    color: backHover.containsMouse ? colors.alpha(colors.primary, 0.14) : "transparent"
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: colors.foreground
                                        font.family: root.iconFont
                                        font.pixelSize: 19
                                    }
                                    MouseArea { id: backHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.backToList() }
                                }
                                Item {
                                    width: 42
                                    height: 42
                                    Layout.alignment: Qt.AlignVCenter
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 21
                                        color: colors.alpha(colors.primary, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.openJid.indexOf("@g.us") >= 0 ? "" : ""
                                            color: colors.alpha(colors.primary, 0.8)
                                            font.family: root.iconFont
                                            font.pixelSize: 20
                                        }
                                    }
                                    Image {
                                        visible: (root.avatars[root.openJid] || "") !== ""
                                        anchors.fill: parent
                                        source: (root.avatars[root.openJid] || "") !== "" ? (root.avatars[root.openJid] || "") : ""
                                        sourceSize: Qt.size(84, 84)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle { width: 42; height: 42; radius: 21 }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        text: root.convoName()
                                        color: colors.foreground
                                        font.family: colors.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: root.typingLabel(root.openJid) !== ""
                                        text: root.typingLabel(root.openJid)
                                        color: colors.tertiary
                                        font.family: colors.fontSans
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: colors.alpha(colors.outline, 0.1)
                        }
                        // empty conversation - slim loader, no giant badge
                        ColumnLayout {
                            visible: root.messages.length === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10
                            Item { Layout.fillWidth: true; Layout.fillHeight: true }
                            Text {
                                visible: root.convoLoading
                                text: ""
                                color: colors.alpha(colors.primary, 0.9)
                                font.family: root.iconFont
                                font.pixelSize: 20
                                Layout.alignment: Qt.AlignHCenter
                                RotationAnimation on rotation {
                                    loops: Animation.Infinite
                                    duration: 900
                                    from: 0
                                    to: 360
                                    running: root.convoLoading
                                }
                            }
                            Text {
                                text: root.convoLoading ? "Loading messages" : "No messages yet"
                                color: colors.alpha(colors.outline, 0.6)
                                font.family: colors.fontSans
                                font.pixelSize: 10
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Item { Layout.fillWidth: true; Layout.fillHeight: true }
                        }
                        ListView {
                            id: msgList
                            visible: root.messages.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 8
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            clip: true
                            spacing: 6
                            model: root.messages
                            interactive: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "y"; from: 14; to: 0; duration: 220; easing.type: Easing.OutCubic }
                            }
                            addDisplaced: Transition {
                                NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic }
                            }
                            header: Item {
                                visible: root.loadingMore
                                width: msgList.width
                                height: 30
                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    color: colors.alpha(colors.outline, 0.7)
                                    font.family: root.iconFont
                                    font.pixelSize: 14
                                    RotationAnimation on rotation {
                                        loops: Animation.Infinite
                                        duration: 900
                                        from: 0
                                        to: 360
                                        running: root.loadingMore
                                    }
                                }
                            }
                            onCountChanged: { if (!root.loadingMore && msgList.atYEnd) Qt.callLater(function () { msgList.positionViewAtEnd() }) }
                            onContentYChanged: {
                                if (msgList.atYBeginning && !root.loadingMore && root.messages.length >= root.historyLimit && root.historyLimit < 200 && daemonProc.running) {
                                    root.loadingMore = true
                                    root.historyLimit += 50
                                    daemonProc.write("{\"cmd\":\"history\",\"jid\":" + JSON.stringify(root.openJid) + ",\"limit\":" + root.historyLimit + "}\n")
                                }
                            }
                            delegate: Item {
                                width: msgList.width
                                height: bubbleBox.height + 4
                                Rectangle {
                                    id: bubbleBox
                                    width: modelData.kind === "sticker" && (modelData.media || "") !== "" ? stickerImg.width : ((modelData.kind === "photo" || modelData.kind === "video") ? parent.width * 0.85 : Math.min(bubbleCol.implicitWidth + 20, parent.width * 0.68))
                                    height: modelData.kind === "sticker" && (modelData.media || "") !== "" ? stickerImg.height : bubbleCol.implicitHeight + 14
                                    anchors.right: modelData.from_me ? parent.right : undefined
                                    anchors.left: modelData.from_me ? undefined : parent.left
                                    topLeftRadius: modelData.from_me ? 16 : 5
                                    topRightRadius: modelData.from_me ? 5 : 16
                                    bottomLeftRadius: 16
                                    bottomRightRadius: 16
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: (modelData.kind === "sticker" && (modelData.media || "") !== "") ? "transparent" : (modelData.from_me ? colors.alpha(colors.primary, 0.3) : colors.alpha(colors.surfaceVariant, 0.74)) }
                                        GradientStop { position: 1; color: (modelData.kind === "sticker" && (modelData.media || "") !== "") ? "transparent" : (modelData.from_me ? colors.alpha(colors.primary, 0.16) : colors.alpha(colors.surfaceVariant, 0.58)) }
                                    }
                                    border.width: 0
                                    opacity: modelData.status === "sending" ? 0.6 : 1
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    // sticker art — frameless, like the app
                                    Image {
                                        id: stickerImg
                                        visible: modelData.kind === "sticker" && (modelData.media || "") !== ""
                                        anchors.centerIn: parent
                                        source: modelData.kind === "sticker" ? (modelData.media || "") : ""
                                        width: 128
                                        height: 128
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                    }
                                    ColumnLayout {
                                        id: bubbleCol
                                        visible: !(modelData.kind === "sticker" && (modelData.media || "") !== "")
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 3
                                        Rectangle {
                                            visible: (modelData.quoted_id || "") !== ""
                                            Layout.fillWidth: true
                                            implicitWidth: 180
                                            height: qSnippet.implicitHeight + 34
                                            radius: 10
                                            color: quotHover.containsMouse ? (modelData.from_me ? colors.alpha(colors.background, 0.35) : colors.alpha(colors.primary, 0.16)) : (modelData.from_me ? colors.alpha(colors.background, 0.25) : colors.alpha(colors.primary, 0.1))
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Rectangle {
                                                x: 10
                                                y: 8
                                                width: 2
                                                height: parent.height - 16
                                                radius: 1
                                                color: colors.primary
                                            }
                                            Text {
                                                x: 22
                                                y: 8
                                                width: parent.width - 32
                                                text: modelData.quoted_name || ""
                                                color: colors.tertiary
                                                font.family: colors.fontSans
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }
                                            Text {
                                                id: qSnippet
                                                x: 22
                                                y: 25
                                                width: parent.width - 32
                                                text: (modelData.quoted_text || "") !== "" ? modelData.quoted_text : "Media"
                                                renderType: Text.NativeRendering
                                                color: colors.alpha(colors.foreground, 0.8)
                                                font.family: colors.fontSans
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                maximumLineCount: 3
                                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                            }
                                            MouseArea {
                                                id: quotHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.jumpToQuote(modelData.quoted_id)
                                            }
                                        }
                                        Text {
                                            visible: !modelData.from_me && (modelData.sender || "") !== ""
                                            text: modelData.sender || ""
                                            color: colors.tertiary
                                            font.family: colors.fontSans
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            Layout.fillWidth: true
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5
                                            Text {
                                                visible: root.kindGlyph(modelData.kind) !== "" && (modelData.media || "") === ""
                                                text: root.kindGlyph(modelData.kind)
                                                color: colors.alpha(colors.tertiary, 0.9)
                                                font.family: root.iconFont
                                                font.pixelSize: 13
                                                Layout.alignment: Qt.AlignTop
                                            }
                                            Text {
                                                visible: (modelData.media || "") === ""
                                                text: root.linkify(modelData.text || root.kindLabel(modelData.kind))
                                                textFormat: Text.StyledText
                                                linkColor: colors.tertiary
                                                color: colors.foreground
                                                font.family: colors.fontSans
                                                font.pixelSize: root.isBigEmoji(modelData.text) ? 26 : 11
                                                renderType: Text.NativeRendering
                                                onLinkActivated: function (link) { Qt.openUrlExternally(link) }

                                                lineHeight: 1.25
                                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                Layout.fillWidth: true
                                            }
                                        }
                                        // photo body - natural aspect, capped, mini loader
                                        Rectangle {
                                            visible: modelData.kind === "photo" && (modelData.media || "") !== ""
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: photoImg.implicitWidth > 0 ? Math.min(300, photoImg.implicitHeight * (photoImg.width / Math.max(1, photoImg.implicitWidth))) : 190
                                            radius: 14
                                            clip: true
                                            color: colors.alpha(colors.surfaceVariant, 0.35)
                                            Image {
                                                id: photoImg
                                                anchors.fill: parent
                                                source: modelData.kind === "photo" ? (modelData.media || "") : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                            }
                                            Text {
                                                visible: photoImg.status !== Image.Ready
                                                anchors.centerIn: parent
                                                text: ""
                                                color: colors.alpha(colors.foreground, 0.7)
                                                font.family: root.iconFont
                                                font.pixelSize: 18
                                                RotationAnimation on rotation {
                                                    loops: Animation.Infinite
                                                    duration: 900
                                                    from: 0
                                                    to: 360
                                                    running: photoImg.status !== Image.Ready
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    if ((modelData.status || "") === "failed") root.resendBubble(modelData.localId)
                                                    else root.openMedia(modelData)
                                                }
                                            }
                                            Rectangle {
                                                id: photoOpening
                                                visible: root.openingId === (modelData.localId || modelData.id) && (modelData.status || "") !== "failed"
                                                anchors.fill: parent
                                                color: colors.alpha(colors.background, 0.55)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ""
                                                    color: colors.foreground
                                                    font.family: root.iconFont
                                                    font.pixelSize: 18
                                                    RotationAnimation on rotation {
                                                        loops: Animation.Infinite
                                                        duration: 900
                                                        from: 0
                                                        to: 360
                                                        running: photoOpening.visible
                                                    }
                                                }
                                            }
                                        }
                                        // unfetched media — icon only, tap fetches
                                        Rectangle {
                                            visible: (modelData.kind === "photo" || modelData.kind === "video") && (modelData.media || "") === ""
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: modelData.kind === "video" ? 130 : 145
                                            radius: 12
                                            color: fetchHover.containsMouse ? colors.alpha(colors.primary, 0.2) : colors.alpha(colors.surfaceVariant, 0.4)
                                            scale: fetchHover.pressed ? 0.97 : 1
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 120 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: ""
                                                color: colors.alpha(colors.foreground, 0.8)
                                                font.family: root.iconFont
                                                font.pixelSize: 22
                                            }
                                            MouseArea {
                                                id: fetchHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    root.openingId = modelData.localId || modelData.id
                                                    openingLife.restart()
                                                    if (daemonProc.running) daemonProc.write("{\"cmd\":\"fetch-media\",\"jid\":" + JSON.stringify(modelData.chat) + ",\"id\":" + JSON.stringify(modelData.id) + "}\n")
                                                }
                                            }
                                        }
                                        // video body — tile with play disc, tap opens
                                        Rectangle {
                                            visible: modelData.kind === "video" && (modelData.media || "") !== ""
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 175
                                            radius: 12
                                            color: colors.alpha("#000000", 0.55)
                                            Rectangle {
                                                width: 52
                                                height: 52
                                                radius: 26
                                                anchors.centerIn: parent
                                                color: colors.alpha(colors.primary, 0.9)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ""
                                                    color: colors.background
                                                    font.family: root.iconFont
                                                    font.pixelSize: 22
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    if ((modelData.status || "") === "failed") root.resendBubble(modelData.localId)
                                                    else root.openMedia(modelData)
                                                }
                                            }
                                            Rectangle {
                                                id: videoOpening
                                                visible: root.openingId === (modelData.localId || modelData.id) && (modelData.status || "") !== "failed"
                                                anchors.fill: parent
                                                radius: 12
                                                color: colors.alpha(colors.background, 0.55)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ""
                                                    color: colors.foreground
                                                    font.family: root.iconFont
                                                    font.pixelSize: 24
                                                    RotationAnimation on rotation {
                                                        loops: Animation.Infinite
                                                        duration: 900
                                                        from: 0
                                                        to: 360
                                                        running: videoOpening.visible
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            visible: (modelData.media || "") !== "" && (modelData.text || "") !== "" && modelData.kind !== "sticker"
                                            text: root.linkify(modelData.text || "")
                                            textFormat: Text.StyledText
                                            linkColor: colors.tertiary
                                            color: colors.foreground
                                            font.family: colors.fontSans
                                            font.pixelSize: root.isBigEmoji(modelData.text) ? 26 : 11
                                            renderType: Text.NativeRendering
                                            onLinkActivated: function (link) { Qt.openUrlExternally(link) }

                                            lineHeight: 1.25
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                            Layout.fillWidth: true
                                        }
                                        // voice body — play disc plus duration
                                        RowLayout {
                                            visible: modelData.kind === "voice" && (modelData.media || "") !== ""
                                            Layout.fillWidth: true
                                            spacing: 10
                                            Rectangle {
                                                width: 36
                                                height: 36
                                                radius: 18
                                                color: colors.alpha(colors.primary, voiceHover.containsMouse ? 0.25 : 0.14)
                                                scale: voiceHover.pressed ? 0.9 : 1
                                                Behavior on scale { NumberAnimation { duration: 120 } }
                                                Layout.alignment: Qt.AlignVCenter
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.playingId === (modelData.localId || modelData.id) ? root.pauseGlyph() : root.playGlyph()
                                                    color: colors.primary
                                                    font.family: root.iconFont
                                                    font.pixelSize: 16
                                                }
                                                MouseArea { id: voiceHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleVoice(modelData) }
                                            }
                                            Text {
                                                text: ""
                                                color: colors.alpha(colors.outline, 0.6)
                                                font.family: root.iconFont
                                                font.pixelSize: 13
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Text {
                                                text: root.fmtDur(modelData.dur)
                                                color: colors.alpha(colors.outline, 0.75)
                                                font.family: colors.fontSans
                                                font.pixelSize: 10
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                        }
                                        RowLayout {
                                            Layout.alignment: Qt.AlignRight
                                            spacing: 4
                                            Text {
                                                text: root.fmtTime(modelData.ts)
                                                color: colors.alpha(colors.outline, 0.6)
                                                font.family: colors.fontSans
                                                font.pixelSize: 9
                                            }
                                            Text {
                                                visible: modelData.from_me && (modelData.status || "") === "sending"
                                                text: ""
                                                color: colors.alpha(colors.outline, 0.7)
                                                font.family: root.iconFont
                                                font.pixelSize: 11
                                                RotationAnimation on rotation {
                                                    loops: Animation.Infinite
                                                    duration: 900
                                                    from: 0
                                                    to: 360
                                                    running: (modelData.status || "") === "sending"
                                                }
                                            }
                                            Text {
                                                visible: modelData.from_me && (modelData.status || "") !== "sending"
                                                text: root.tickGlyph(modelData.ack)
                                                color: root.tickColor(modelData.ack)
                                                font.family: root.iconFont
                                                font.pixelSize: 12
                                            }
                                        }
                                        RowLayout {
                                            visible: root.reactionChips(modelData.reactions).length > 0
                                            spacing: 4
                                            Repeater {
                                                model: root.reactionChips(modelData.reactions)
                                                delegate: Rectangle {
                                                    height: 22
                                                    width: chipInner.implicitWidth + 14
                                                    radius: 11
                                                    color: colors.alpha(colors.primary, 0.14)
                                                    border.width: 1
                                                    border.color: colors.alpha(colors.primary, 0.3)
                                                    RowLayout {
                                                        id: chipInner
                                                        anchors.centerIn: parent
                                                        spacing: 3
                                                        Text { text: modelData.emoji; font.pixelSize: 14; renderType: Text.NativeRendering }
                                                        Text { text: modelData.n; color: colors.alpha(colors.foreground, 0.8); font.family: colors.fontSans; font.pixelSize: 9 }
                                                    }
                                                }
                                            }
                                        }
                                        RowLayout {
                                            visible: (modelData.status || "") === "sending" || (modelData.status || "") === "failed"
                                            Layout.alignment: Qt.AlignRight
                                            spacing: 4
                                            Text {
                                                text: (modelData.status || "") === "failed" ? "" : ""
                                                color: (modelData.status || "") === "failed" ? colors.error : colors.alpha(colors.outline, 0.6)
                                                font.family: root.iconFont
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: bubbleHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                        onEntered: { root.hoverMsgId = modelData.id; root.msgCursor = index }
                                        onExited: { if (root.hoverMsgId === modelData.id) root.hoverMsgId = "" }
                                    }
                                    // failed bubbles retry on tap instead of opening media
                                    MouseArea {
                                        visible: (modelData.status || "") === "failed"
                                        anchors.fill: parent
                                        onClicked: root.resendBubble(modelData.localId)
                                    }
                                }
                            }
                        }
                        // attach strip - one thumb per picked file, X removes
                        Rectangle {
                            visible: root.attachPaths.length > 0 && !root.convoReadonly()
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.bottomMargin: 8
                            Layout.preferredHeight: 58
                            radius: 14
                            color: colors.alpha(colors.primary, 0.1)
                            border.width: 1
                            border.color: colors.alpha(colors.primary, 0.28)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 10
                                spacing: 8
                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    orientation: ListView.Horizontal
                                    spacing: 8
                                    clip: true
                                    model: root.attachPaths
                                    delegate: Item {
                                        width: 44
                                        height: 44
                                        Rectangle {
                                            width: 38
                                            height: 38
                                            y: 3
                                            radius: 10
                                            color: colors.alpha(colors.primary, 0.16)
                                            clip: true
                                            Text {
                                                anchors.centerIn: parent
                                                visible: !(/\.(png|jpe?g|gif|webp|bmp)$/i.test(modelData))
                                                text: ""
                                                color: colors.primary
                                                font.family: root.iconFont
                                                font.pixelSize: 14
                                            }
                                            Image {
                                                anchors.fill: parent
                                                visible: /\.(png|jpe?g|gif|webp|bmp)$/i.test(modelData)
                                                source: "file://" + modelData
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: false
                                            }
                                        }
                                        Rectangle {
                                            width: 16
                                            height: 16
                                            radius: 8
                                            x: 28
                                            color: badgeHover.containsMouse ? colors.alpha("#000000", 0.85) : colors.alpha("#000000", 0.6)
                                            Text {
                                                anchors.centerIn: parent
                                                text: ""
                                                color: colors.foreground
                                                font.family: root.iconFont
                                                font.pixelSize: 9
                                            }
                                            MouseArea { id: badgeHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.removeAttach(index) }
                                        }
                                    }
                                }
                                Text {
                                    text: root.attachPaths.length + " selected"
                                    color: colors.alpha(colors.outline, 0.65)
                                    font.family: colors.fontSans
                                    font.pixelSize: 10
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                        // emoji grid - tap inserts, or reacts when opened from a bubble
                        Rectangle {
                            visible: root.emojiOpen && !root.convoReadonly()
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.bottomMargin: 8
                            Layout.preferredHeight: 196
                            radius: 14
                            color: colors.alpha(colors.surfaceVariant, 0.6)
                            border.width: 1
                            border.color: colors.alpha(colors.outline, 0.14)
                            clip: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: root.emojiMode === "react" ? "React" : "Emoji"
                                        color: colors.alpha(colors.outline, 0.7)
                                        font.family: colors.fontSans
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        width: 26
                                        height: 26
                                        radius: 13
                                        color: emojiX.containsMouse ? colors.alpha(colors.primary, 0.2) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: ""
                                            color: colors.alpha(colors.outline, 0.85)
                                            font.family: root.iconFont
                                            font.pixelSize: 12
                                        }
                                        MouseArea { id: emojiX; anchors.fill: parent; hoverEnabled: true; onClicked: root.emojiOpen = false }
                                    }
                                }
                                GridView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    cellWidth: 34
                                    cellHeight: 34
                                    model: root.emojiList
                                    delegate: Text {
                                        width: 34
                                        height: 34
                                        text: modelData
                                        font.pixelSize: 24
                                        renderType: Text.NativeRendering
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.pickEmoji(modelData) }
                                    }
                                }
                            }
                        }
                        // reply strip - quoted message for the next send
                        Rectangle {
                            visible: root.replyTo !== null && !root.convoReadonly()
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.bottomMargin: 8
                            Layout.preferredHeight: 52
                            radius: 12
                            color: colors.alpha(colors.primary, 0.1)
                            border.width: 1
                            border.color: colors.alpha(colors.primary, 0.28)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 8
                                Rectangle {
                                    width: 3
                                    Layout.fillHeight: true
                                    Layout.topMargin: 10
                                    Layout.bottomMargin: 10
                                    radius: 2
                                    color: colors.primary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2
                                    Text {
                                        text: root.replyTo ? ("Reply to " + root.replyTo.sender) : ""
                                        color: colors.tertiary
                                        font.family: colors.fontSans
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.replyTo ? ((root.replyTo.text || "") !== "" ? root.replyTo.text : "Media") : ""
                                        renderType: Text.NativeRendering
                                        color: colors.alpha(colors.foreground, 0.8)
                                        font.family: colors.fontSans
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }
                                }
                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    Layout.alignment: Qt.AlignVCenter
                                    color: replyX.containsMouse ? colors.alpha(colors.primary, 0.2) : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: colors.alpha(colors.outline, 0.85)
                                        font.family: root.iconFont
                                        font.pixelSize: 13
                                    }
                                    MouseArea { id: replyX; anchors.fill: parent; hoverEnabled: true; onClicked: root.replyTo = null }
                                }
                            }
                        }
                        // typing bubble - bouncing dots while the peer types
                        RowLayout {
                            visible: root.typingLabel(root.openJid) !== ""
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.bottomMargin: 6
                            spacing: 8
                            Rectangle {
                                width: dotRow.implicitWidth + 24
                                height: 30
                                radius: 15
                                color: colors.alpha(colors.surfaceVariant, 0.68)
                                RowLayout {
                                    id: dotRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Repeater {
                                        model: 3
                                        delegate: Rectangle {
                                            width: 7
                                            height: 7
                                            radius: 4
                                            color: colors.primary
                                            opacity: 0.3
                                            SequentialAnimation on opacity {
                                                loops: Animation.Infinite
                                                running: root.typingLabel(root.openJid) !== ""
                                                PauseAnimation { duration: index * 180 }
                                                NumberAnimation { from: 0.3; to: 1; duration: 350 }
                                                NumberAnimation { from: 1; to: 0.3; duration: 350 }
                                            }
                                        }
                                    }
                                }
                            }
                            Text {
                                text: root.typingLabel(root.openJid)
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: colors.fontSans
                                font.pixelSize: 10
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        // composer - stadium pill that grows with the text, solid send button
                        Rectangle {
                            visible: !root.convoReadonly()
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.bottomMargin: 12
                            Layout.preferredHeight: Math.min(112, Math.max(48, composer.implicitHeight + 12))
                            radius: Math.min(24, (composer.implicitHeight + 12) / 2)
                            color: composer.activeFocus ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surfaceVariant, 0.6)
                            border.width: (composer.text.trim() !== "" || root.attachPaths.length > 0) ? 0 : 1
                            border.color: composer.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.14)
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                            clip: true
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 7
                                spacing: 4
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: emojiHover.containsMouse || root.emojiOpen ? colors.alpha(colors.primary, 0.18) : "transparent"
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 7
                                    scale: emojiHover.pressed ? 0.88 : (emojiHover.containsMouse ? 1.06 : 1)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: root.emojiOpen ? colors.primary : colors.alpha(colors.outline, 0.9)
                                        font.family: root.iconFont
                                        font.pixelSize: 17
                                    }
                                    MouseArea { id: emojiHover; anchors.fill: parent; hoverEnabled: true; onClicked: { root.emojiMode = "type"; root.emojiOpen = !root.emojiOpen } }
                                }
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: attachHover.containsMouse ? colors.alpha(colors.primary, 0.18) : "transparent"
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 7
                                    scale: attachHover.pressed ? 0.88 : (attachHover.containsMouse ? 1.06 : 1)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: colors.alpha(colors.outline, 0.9)
                                        font.family: root.iconFont
                                        font.pixelSize: 17
                                    }
                                    MouseArea { id: attachHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.pickFile() }
                                }
                                TextEdit {
                                    id: composer
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: colors.foreground
                                    font.family: colors.fontSans
                                    font.pixelSize: 12
                                    renderType: TextEdit.NativeRendering
                                    verticalAlignment: TextEdit.AlignVCenter
                                    wrapMode: TextEdit.Wrap
                                    selectByMouse: true
                                    selectionColor: colors.alpha(colors.primary, 0.35)
                                    selectedTextColor: colors.foreground
                                    Text {
                                        visible: composer.text === ""
                                        text: root.attachPaths.length > 0 ? "Add a caption..." : "Message"
                                        color: colors.alpha(colors.outline, 0.45)
                                        font.family: colors.fontSans
                                        font.pixelSize: 12
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 2
                                        anchors.rightMargin: 2
                                    }
                                    topPadding: 11
                                    bottomPadding: 11
                                    leftPadding: 2
                                    rightPadding: 2
                                    Keys.onReturnPressed: root.sendDraft()
                                    Keys.onEnterPressed: root.sendDraft()
                                    Keys.onPressed: function (e) {
                                        if (e.key === Qt.Key_Escape) {
                                            if (root.emojiOpen) root.emojiOpen = false
                                            else {
                                                composer.focus = false
                                                Qt.callLater(function () { card.forceActiveFocus() })
                                            }
                                            e.accepted = true
                                        } else if ((e.modifiers & Qt.ControlModifier) !== 0 && e.key === Qt.Key_V) {
                                            root.pasteImage()
                                            e.accepted = true
                                        }
                                    }
                                }
                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: (composer.text.trim() !== "" || root.attachPaths.length > 0) ? colors.primary : colors.alpha(colors.primary, 0.14)
                                    border.width: (composer.text.trim() !== "" || root.attachPaths.length > 0) ? 0 : 1
                                    border.color: colors.alpha(colors.primary, 0.3)
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 6
                                    scale: sendHover.pressed ? 0.88 : (sendHover.containsMouse ? 1.06 : 1)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: (composer.text.trim() !== "" || root.attachPaths.length > 0) ? colors.background : colors.primary
                                        font.family: root.iconFont
                                        font.pixelSize: 16
                                    }
                                    MouseArea { id: sendHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.sendDraft() }
                                }
                            }
                        }
                        Rectangle {
                            visible: root.convoReadonly()
                            Layout.fillWidth: true
                            Layout.leftMargin: 14
                            Layout.rightMargin: 14
                            Layout.bottomMargin: 14
                            Layout.preferredHeight: 40
                            radius: 12
                            color: colors.alpha(colors.surfaceVariant, 0.3)
                            Text {
                                anchors.centerIn: parent
                                text: "Only admins can send here"
                                color: colors.alpha(colors.outline, 0.65)
                                font.family: colors.fontSans
                                font.pixelSize: 10
                            }
                        }
                    }

                    // pair view — big QR, minimal words
                    ColumnLayout {
                        visible: root.qrPng !== ""
                        anchors.fill: parent
                        spacing: 14
                        Item { Layout.fillWidth: true; Layout.fillHeight: true }
                        Rectangle {
                            width: 300
                            height: 300
                            radius: 16
                            color: "#ffffff"
                            Layout.alignment: Qt.AlignHCenter
                            Image {
                                anchors.centerIn: parent
                                width: 268
                                height: 268
                                source: root.qrPng !== "" ? "data:image/png;base64," + root.qrPng : ""
                                asynchronous: true
                                cache: false
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                        Text {
                            text: "Link a device" + (root.qrTimeout > 0 ? "  ·  " + root.qrTimeout + "s" : "")
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "WhatsApp > Settings > Linked devices"
                            color: colors.alpha(colors.outline, 0.65)
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Item { Layout.fillWidth: true; Layout.fillHeight: true }
                    }

                    // error view — icon, detail, round retry
                    ColumnLayout {
                        visible: root.connState === "error" || root.connState === "logged-out"
                        anchors.fill: parent
                        spacing: 14
                        Item { Layout.fillWidth: true; Layout.fillHeight: true }
                        Rectangle {
                            width: 84
                            height: 84
                            radius: 42
                            color: colors.alpha(colors.error, 0.1)
                            border.width: 1
                            border.color: colors.alpha(colors.error, 0.25)
                            Layout.alignment: Qt.AlignHCenter
                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: colors.alpha(colors.error, 0.9)
                                font.family: root.iconFont
                                font.pixelSize: 38
                            }
                        }
                        Text {
                            visible: root.statusDetail !== ""
                            text: root.statusDetail
                            color: colors.alpha(colors.outline, 0.7)
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: retryArea.containsMouse ? colors.alpha(colors.primary, 1.0) : colors.alpha(colors.primary, 0.85)
                            scale: retryArea.pressed ? 0.9 : 1
                            Layout.alignment: Qt.AlignHCenter
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: colors.background
                                font.family: root.iconFont
                                font.pixelSize: 22
                            }
                            MouseArea { id: retryArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.retry() }
                        }
                        Item { Layout.fillWidth: true; Layout.fillHeight: true }
                    }
                }
            }
        }


        // Copied flash — shared Toast component (modules/Toast.qml).
        Toast {
            id: toast
            colors: root.colors
        }

        Keys.onEscapePressed: {
            if (root.openJid !== "") root.backToList()
            else root.open = false
        }
        Keys.onPressed: function (e) {
            if (searchInput.activeFocus || composer.activeFocus) return
            // Conversation keys only when the conversation is actually
            // visible: in error/QR overlay the list is still showing, so
            // keys must stay in list mode or they drive a dead cursor.
            if (root.openJid !== "" && !root.paneOverlay) {
                if (e.key === Qt.Key_Escape) {
                    root.backToList()
                    e.accepted = true
                } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                    msgList.contentY = msgList.contentY + 110
                    e.accepted = true
                } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                    msgList.contentY = msgList.contentY - 110
                    e.accepted = true
                } else if (e.key === Qt.Key_Left) {
                    root.backToList()
                    e.accepted = true
                } else if (e.key === Qt.Key_Right) {
                    composer.focus = true
                    e.accepted = true
                } else if (e.key === Qt.Key_R) {
                    root.replyToMessage(root.cursorMessage())
                    e.accepted = true
                } else if (e.key === Qt.Key_O) {
                    var m = root.cursorMessage()
                    if (m && !root.convoReadonly()) {
                        root.reactTarget = m.id
                        root.emojiMode = "react"
                        root.emojiOpen = true
                    }
                    e.accepted = true
                } else if (e.key === Qt.Key_E) {
                    root.emojiMode = "type"
                    root.emojiOpen = !root.emojiOpen
                    e.accepted = true
                } else if (e.key === Qt.Key_C) {
                    root.copyCursor()
                    e.accepted = true
                } else if (e.key === Qt.Key_A) {
                    if (!root.convoReadonly()) root.pickFile()
                    e.accepted = true
                } else if (e.key === Qt.Key_U) {
                    if (!root.convoReadonly()) root.pickFile()
                    e.accepted = true
                } else if (e.key === Qt.Key_P) {
                    root.pasteToComposer()
                    e.accepted = true
                } else if (e.key === Qt.Key_F) {
                    composer.focus = true
                    e.accepted = true
                } else if (e.key === Qt.Key_L) {
                    var lm = root.cursorMessage()
                    var lu = root.firstLink(lm ? lm.text : "")
                    if (lu !== "") Qt.openUrlExternally(lu)
                    e.accepted = true
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    // Enter with the box unfocused focuses it (regular
                    // chat behavior); Enter inside the box sends.
                    composer.focus = true
                    e.accepted = true
                } else if (e.key === Qt.Key_G && (e.modifiers & Qt.ShiftModifier) !== 0) {
                    msgList.positionViewAtEnd()
                    e.accepted = true
                } else if (e.key === Qt.Key_G) {
                    if (root.gPending) {
                        root.gPending = false
                        gTimer.stop()
                        msgList.positionViewAtBeginning()
                    } else {
                        root.gPending = true
                        gTimer.restart()
                    }
                    e.accepted = true
                } else if (root.isTypeChar(e)) {
                    if (root.gPending) { root.gPending = false; gTimer.stop(); composer.insert(composer.cursorPosition, "g") }
                    composer.focus = true
                    composer.insert(composer.cursorPosition, e.text)
                    e.accepted = true
                }
                return
            }
            if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                root.moveSelection(1)
                e.accepted = true
            } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                root.moveSelection(-1)
                e.accepted = true
            } else if (e.key === Qt.Key_G) {
                root.moveEdge((e.modifiers & Qt.ShiftModifier) !== 0)
                e.accepted = true
            } else if (e.key === Qt.Key_Slash) {
                searchInput.focus = true
                e.accepted = true
            } else if (e.key === Qt.Key_Q) {
                // Mute toggle: explicit selection wins, then hover row,
                // then the top visible chat — same pick as Enter.
                var rowsQ = root.visibleChats()
                var target = root.selectedJid
                if (target === "") {
                    for (var qi = 0; qi < rowsQ.length; qi++) {
                        if (rowsQ[qi].jid === root.hoverJid) { target = root.hoverJid; break }
                    }
                    if (target === "" && rowsQ.length > 0) target = rowsQ[0].jid
                }
                root.toggleMute(target)
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_L) {
                // Explicit keyboard selection wins, then the live hover
                // row, then the top visible chat: Enter always opens the
                // row the user is actually looking at.
                var rows0 = root.visibleChats()
                var hj = ""
                for (var hi = 0; hi < rows0.length; hi++) {
                    if (rows0[hi].jid === root.hoverJid) { hj = root.hoverJid; break }
                }
                if (root.selectedJid !== "") {
                    root.openChat(root.selectedJid)
                    e.accepted = true
                } else if (hj !== "") {
                    root.openChat(hj)
                    e.accepted = true
                } else if (rows0.length > 0) {
                    root.openChat(rows0[0].jid)
                    e.accepted = true
                }
            } else if (root.isTypeChar(e)) {
                searchInput.focus = true
                root.searchQuery = root.searchQuery + e.text
                searchInput.cursorPosition = searchInput.text.length
                e.accepted = true
            }
        }
        focus: root.open
    }
}
