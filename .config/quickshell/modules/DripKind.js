.pragma library

// Drip notification classifier.
// Maps a notification to a semantic kind, a Phosphor glyph and a fixed
// accent colour. Codepoints are resolved at runtime with fromCharCode so
// this file never carries fragile \\uXXXX escapes, and every icon is
// verified against Phosphor-Regular before shipping.

function ch(cp) { return String.fromCharCode(cp) }

var glyphs = {
    error:    ch(0xe4f8), // x-circle
    warn:     ch(0xe4e0), // warning
    ok:       ch(0xe184), // check-circle
    test:     ch(0xe7a0), // test-tube
    lint:     ch(0xe186), // check-square
    build:    ch(0xe390), // package
    buildOk:  ch(0xe390), // package (green: CI passed)
    run:      ch(0xe094), // arrows-clockwise
    deploy:   ch(0xe3fe), // rocket-launch
    pr:       ch(0xe282), // git-pull-request
    merge:    ch(0xe280), // git-merge
    git:      ch(0xe278), // git-branch
    github:   ch(0xe576), // github-logo
    ask:      ch(0xe3e8), // question
    claude:   ch(0xe6a2), // sparkle
    media:    ch(0xe33c), // music-note
    mail:     ch(0xe214), // envelope
    chat:     ch(0xe16e), // chat-circle-text
    calendar: ch(0xe10a), // calendar-blank
    capture:  ch(0xe10e), // camera
    net:      ch(0xe4ea), // wifi-high
    security: ch(0xe40c), // shield-check
    battery:  ch(0xe0c8), // battery-warning
    info:     ch(0xe0ce), // bell
}

var kindColors = {
    error:    "#e05a5a",
    warn:     "#e0a13b",
    ok:       "#4fb477",
    test:     "#4fb477",
    lint:     "#6fbf8f",
    build:    "#5b8def",
    buildOk:  "#4fb477",
    run:      "#5b8def",
    deploy:   "#47b8c4",
    pr:       "#b48ead",
    merge:    "#9d7bd8",
    git:      "#a0a8c0",
    github:   "#e6e6e6",
    ask:      "#b48ead",
    claude:   "#e0803b",
    media:    "#e0803b",
    mail:     "#98ccf9",
    chat:     "#6fcf97",
    calendar: "#c39bd3",
    capture:  "#98ccf9",
    net:      "#98ccf9",
    security: "#e6c35c",
    battery:  "#e0a13b",
    info:     "#ae8f8d",
}

function color(kind) {
    return kindColors[kind] || kindColors.info
}

function plain(v) {
    return String(v == null ? "" : v).toLowerCase()
}

// Per-app fallback glyph. Only used when the notification has no semantic
// kind of its own (info), so a known app still shows its own mark.
function glyphForApp(name) {
    var n = plain(name)
    if (n.indexOf("whatsapp") !== -1) return ch(0xe5d0)
    if (n.indexOf("telegram") !== -1) return ch(0xe5bc)
    if (n.indexOf("discord") !== -1) return ch(0xe61a)
    if (n.indexOf("spotify") !== -1) return ch(0xe66e)
    if (n.indexOf("firefox") !== -1) return ch(0xe288)
    if (n.indexOf("mozilla") !== -1) return ch(0xe288)
    if (n.indexOf("chrome") !== -1) return ch(0xe976)
    if (n.indexOf("chromium") !== -1) return ch(0xe976)
    if (n.indexOf("brave") !== -1) return ch(0xe288)
    if (n.indexOf("vivaldi") !== -1) return ch(0xe288)
    if (n.indexOf("edge") !== -1) return ch(0xe288)
    if (n.indexOf("opera") !== -1) return ch(0xe288)
    if (n.indexOf("zen") !== -1) return ch(0xe288)
    if (n.indexOf("github") !== -1) return ch(0xe576)
    if (n.indexOf("gitlab") !== -1) return ch(0xe694)
    if (n.indexOf("git") !== -1) return ch(0xe278)
    if (n.indexOf("notion") !== -1) return ch(0xe9a0)
    if (n.indexOf("figma") !== -1) return ch(0xe22e)
    if (n.indexOf("obsidian") !== -1) return ch(0xe348)
    if (n.indexOf("terminal") !== -1) return ch(0xe47e)
    if (n.indexOf("kitty") !== -1) return ch(0xe47e)
    if (n.indexOf("console") !== -1) return ch(0xe47e)
    if (n.indexOf("nvim") !== -1) return ch(0xe1bc)
    if (n.indexOf("neovim") !== -1) return ch(0xe1bc)
    if (n.indexOf("zed") !== -1) return ch(0xe1bc)
    if (n.indexOf("code") !== -1) return ch(0xe1bc)
    if (n.indexOf("mail") !== -1) return ch(0xe214)
    if (n.indexOf("thunderbird") !== -1) return ch(0xe214)
    if (n.indexOf("envelope") !== -1) return ch(0xe214)
    if (n.indexOf("calendar") !== -1) return ch(0xe10a)
    if (n.indexOf("screenshot") !== -1) return ch(0xe10e)
    if (n.indexOf("camera") !== -1) return ch(0xe10e)
    if (n.indexOf("grim") !== -1) return ch(0xe10e)
    if (n.indexOf("slurp") !== -1) return ch(0xe10e)
    if (n.indexOf("flameshot") !== -1) return ch(0xe10e)
    if (n.indexOf("clipboard") !== -1) return ch(0xe196)
    if (n.indexOf("cliphist") !== -1) return ch(0xe196)
    if (n.indexOf("volume") !== -1) return ch(0xe44a)
    if (n.indexOf("audio") !== -1) return ch(0xe44a)
    if (n.indexOf("wpctl") !== -1) return ch(0xe44a)
    if (n.indexOf("pactl") !== -1) return ch(0xe44a)
    if (n.indexOf("speaker") !== -1) return ch(0xe44a)
    if (n.indexOf("mic") !== -1) return ch(0xe326)
    if (n.indexOf("battery") !== -1) return ch(0xe0c0)
    if (n.indexOf("power") !== -1) return ch(0xe0c0)
    if (n.indexOf("tlp") !== -1) return ch(0xe0c0)
    if (n.indexOf("upower") !== -1) return ch(0xe0c0)
    if (n.indexOf("wifi") !== -1) return ch(0xe4ea)
    if (n.indexOf("network") !== -1) return ch(0xe4ea)
    if (n.indexOf("nmcli") !== -1) return ch(0xe4ea)
    if (n.indexOf("bluetooth") !== -1) return ch(0xe0da)
    if (n.indexOf("headset") !== -1) return ch(0xe584)
    if (n.indexOf("headphone") !== -1) return ch(0xe2a6)
    if (n.indexOf("earbuds") !== -1) return ch(0xe584)
    if (n.indexOf("music") !== -1) return ch(0xe33c)
    if (n.indexOf("mpd") !== -1) return ch(0xe33c)
    if (n.indexOf("ncmpcpp") !== -1) return ch(0xe33c)
    if (n.indexOf("mpv") !== -1) return ch(0xe792)
    if (n.indexOf("video") !== -1) return ch(0xe792)
    if (n.indexOf("obs") !== -1) return ch(0xe792)
    if (n.indexOf("image") !== -1) return ch(0xe2ca)
    if (n.indexOf("chat") !== -1) return ch(0xe16e)
    if (n.indexOf("note") !== -1) return ch(0xe348)
    if (n.indexOf("download") !== -1) return ch(0xe20c)
    if (n.indexOf("update") !== -1) return ch(0xe20c)
    if (n.indexOf("pacman") !== -1) return ch(0xe20c)
    if (n.indexOf("yay") !== -1) return ch(0xe20c)
    if (n.indexOf("paru") !== -1) return ch(0xe20c)
    if (n.indexOf("lock") !== -1) return ch(0xe2fa)
    if (n.indexOf("password") !== -1) return ch(0xe2d6)
    if (n.indexOf("keepassxc") !== -1) return ch(0xe2d6)
    if (n.indexOf("folder") !== -1) return ch(0xe24a)
    if (n.indexOf("nautilus") !== -1) return ch(0xe24a)
    if (n.indexOf("thunar") !== -1) return ch(0xe24a)
    if (n.indexOf("dolphin") !== -1) return ch(0xe24a)
    if (n.indexOf("phone") !== -1) return ch(0xe1e0)
    if (n.indexOf("weather") !== -1) return ch(0xe540)
    if (n.indexOf("usb") !== -1) return ch(0xe956)
    if (n.indexOf("udisk") !== -1) return ch(0xe956)
    if (n.indexOf("timer") !== -1) return ch(0xe492)
    if (n.indexOf("pomodoro") !== -1) return ch(0xe492)
    if (n.indexOf("alarm") !== -1) return ch(0xe006)
    return glyphs.info
}

// "No errors" must not be read as an error. Strip the common negations
// before the failure regex runs.
function stripNegated(s) {
    return s
        .replace(/\b(no|zero|0) (errors?|failures?|issues?|warnings?|problems?)\b/g, " ")
        .replace(/\berror[- ]free\b/g, " ")
        .replace(/\ball (checks? )?(passed|green)\b/g, " all checks passed ")
}

var reFail     = /\b(fail(ed|ing|ure)?|error|exception|crash(ed)?|denied|rejected|fatal|timed? ?out|cancelled|canceled|broken)\b/
var reAsk      = /\b(approve|approval|permission|confirm|authori[sz]e|waiting for|action required|question|can you|could you|shall i|should i|need(s)? (your|input|help))\b|\?/
var reWarn     = /\b(warn(ing)?|low battery|battery low|almost full|low disk|disk space|threshold|exceed(ed|ing)?|expir(ed|ing|es)|degraded|high temp(erature)?|overheat(ed|ing)?|memory pressure|deprecated|unstable)\b/
var reSuccess  = /\b(pass(ed|es|ing)?|success(ful|fully)?|succeed(ed)?|complete(d)?|done|deployed|saved|all clear|green|approved|merged|fixed|resolved|shipped)\b/
var reBuild    = /\b(build(ing)?|workflow|pipeline|actions?|checks?|compil(e|ing|ation)|running|starting|in progress|progress|sync(ing|ed)?|download(ing)?|install(ing|ed)?|updat(e|ing|ed)|index(ing)?)\b/
var reDeploy   = /\b(deploy(ed|ing|ment)?|release(d|ing)?|publish(ed|ing)?|shipped|rollout|production)\b/
var rePr       = /\b(pull request|pr #?\d+|review|changes requested)\b/
var reMerge    = /\b(merged?|merge conflict)\b/
var reGit      = /\b(commit|branch|issue|repository|repo|tag|clone|push(ed)?|fetch(ed)?|checkout)\b/
var reMail     = /\b(mail|email|inbox|unread|newsletter)\b/
var reChat     = /\b(chat|message|dm|direct message|reply|replied|mention(ed)?|typing)\b/
var reCalendar = /\b(calendar|event|meeting|appointment|reminder|starts? in|due (today|tomorrow)|schedule(d)?)\b/
var reCapture  = /\b(screenshot|screen ?shot|screen capture|recording|recorded|captured)\b/
var reNet      = /\b(wifi|wi-fi|network|connected|disconnected|ethernet|vpn|bluetooth|hotspot|signal)\b/
var reSecurity = /\b(password|passcode|2fa|two-factor|verification code|one-time code|login|sign[- ]?in|security alert|new device|authentication)\b/
var reBattery  = /\b(battery|charging|discharg|plugged in|unplugged|power supply)\b/
var reMedia    = /\b(now playing|playing|paused|track|album|playlist|artist|episode|podcast)\b/
var reClaude   = /\b(claude|assistant|anthropic|copilot|chatgpt|openai|llm)\b/

function isCodeHost(app) {
    return /github|gitlab|gitea|forgejo|bitbucket|codeberg/.test(app)
}

function isChatApp(app) {
    return /telegram|discord|whatsapp|signal|slack|matrix|element|messenger|teams/.test(app)
}

function isMailApp(app) {
    return /thunderbird|evolution|geary|outlook|gmail|mail/.test(app)
}

function isMediaApp(app) {
    return /spotify|mpv|vlc|rhythmbox|amberol|audacious|music/.test(app)
}

function isCalendarApp(app) {
    return /calendar|khal|gnome-calendar/.test(app)
}

function isAIApp(app) {
    return /claude|chatgpt|copilot|cursor|codex|aider|ollama|lm studio/.test(app)
}

function pick(kind) {
    return { kind: kind, glyph: glyphs[kind] || glyphs.info }
}

// Order matters: safety and failure first, then the app-specific buckets,
// then generic success / progress, then info.
function classify(n, critical) {
    var app = n ? plain(n.appName) : ""
    var text = n ? (app + " " + plain(n.summary) + " " + plain(n.body)).trim() : ""
    var clean = stripNegated(text)

    if (critical) return pick("error")
    if (reSecurity.test(clean)) return pick("security")
    if (reFail.test(clean)) return pick("error")

    // Messaging, mail, media and calendar keep their identity even when the
    // text is a question or a generic status line.
    if (isChatApp(app)) return pick("chat")
    if (isMailApp(app)) return pick("mail")
    if (isMediaApp(app)) return pick("media")
    if (isCalendarApp(app)) return pick("calendar")

    if (reAsk.test(clean)) return pick("ask")
    if (reBattery.test(clean) && /\b(low|critical|warning|dying)\b/.test(clean)) return pick("battery")
    if (reWarn.test(clean)) return pick("warn")

    if (isCodeHost(app)) {
        if (reMerge.test(clean)) return pick("merge")
        if (rePr.test(clean)) return reSuccess.test(clean) ? pick("ok") : pick("pr")
        if (reDeploy.test(clean)) return pick("deploy")
        if (/\b(workflow|actions?|pipeline|\bci\b|checks?|build)\b/.test(clean))
            return reSuccess.test(clean) ? pick("buildOk") : pick("build")
        if (reGit.test(clean)) return pick("git")
        if (reSuccess.test(clean)) return pick("ok")
        return pick("github")
    }

    if (isAIApp(app) || reClaude.test(clean)) return pick("claude")
    if (reMedia.test(clean)) return pick("media")
    if (reMail.test(clean)) return pick("mail")
    if (reChat.test(clean)) return pick("chat")
    if (reCalendar.test(clean)) return pick("calendar")
    if (reCapture.test(clean)) return pick("capture")
    if (reNet.test(clean)) return pick("net")
    if (reDeploy.test(clean)) return pick("deploy")
    if (reSuccess.test(clean)) {
        if (/\btests?\b/.test(clean)) return pick("test")
        if (/\b(lint|format|style|eslint|prettier)\b/.test(clean)) return pick("lint")
        return pick("ok")
    }
    if (reBuild.test(clean)) return pick("build")
    if (reMerge.test(clean)) return pick("merge")
    if (rePr.test(clean)) return pick("pr")
    if (reGit.test(clean)) return pick("git")
    return pick("info")
}
