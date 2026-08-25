import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.LocalStorage 2.0

// Hornet Shimeji pet — smart, persistent, free-roaming.
// - transparent PanelWindow overlay, click-through except sprite (mask)
// - exact PNG size, frame Timer, 2D walk (x+y), sit anywhere, hide/sleep/walkToMe
// - smart: watches Hyprland.activeToplevel (coding/browsing/terminal/media/idle)
// - persists: petX/petY/facing/visible via LocalStorage, always there after reload
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: false
    color: "transparent"
    WlrLayershell.namespace: "qs-pet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region { item: petWrapper }

    IpcHandler {
        target: "pet"
        function toggle(): void { stateMachine.resetFatigue(); root.visible = !root.visible; saveState(); console.log("[Pet] ipc toggle visible="+root.visible) }
        function show(): void { stateMachine.resetFatigue(); root.visible = true; saveState(); console.log("[Pet] ipc show"); if (Hyprland.activeToplevel) stateMachine.resume() }
        function hide(): void { stateMachine.resetFatigue(); root.visible = false; saveState(); console.log("[Pet] ipc hide") }
        function pet(): void { console.log("[Pet] ipc pet"); stateMachine.resetFatigue(); stateMachine.trigger("PetAction") }
        function walkToMe(): void { console.log("[Pet] ipc walkToMe cursor="+root.cursorX+","+root.cursorY+" win="+JSON.stringify(root.activeWinAt)+"/"+JSON.stringify(root.activeWinSize)); stateMachine.resetFatigue(); stateMachine.trigger("walkToMe") }
        function sleep(): void { console.log("[Pet] ipc sleep"); stateMachine.trigger("sleep") }
        function sit(): void { console.log("[Pet] ipc sit"); stateMachine.resetFatigue(); stateMachine.trigger("sitAnywhere") }
        function hideMe(): void { console.log("[Pet] ipc hideMe"); stateMachine.resetFatigue(); stateMachine.trigger("hide") }
        function status(): string { return JSON.stringify({x:root.petX,y:root.petY,facingRight:root.facingRight,visible:root.visible,action:root.currentAction,kind:stateMachine.actionKind,activity:root.userActivity,fatigue:stateMachine.fatigue,isSleeping:stateMachine.isSleeping,cursor:[root.cursorX,root.cursorY]}) }
    }

    // ── persistence (LocalStorage qs_pet) ───────────────────────────
    function petDb() { return LocalStorage.openDatabaseSync("qs_pet", "1.0", "hornet pet", 100000) }
    function initDb() {
        var db = petDb()
        db.transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)')
        })
    }
    function saveState() {
        try {
            var db = petDb()
            db.transaction(function(tx){
                tx.executeSql('INSERT OR REPLACE INTO state VALUES(?,?)', ['petX', String(root.petX)])
                tx.executeSql('INSERT OR REPLACE INTO state VALUES(?,?)', ['petY', String(root.petY)])
                tx.executeSql('INSERT OR REPLACE INTO state VALUES(?,?)', ['facingRight', root.facingRight ? '1':'0'])
                tx.executeSql('INSERT OR REPLACE INTO state VALUES(?,?)', ['visible', root.visible ? '1':'0'])
                tx.executeSql('INSERT OR REPLACE INTO state VALUES(?,?)', ['currentAction', root.currentAction])
            })
        } catch(e) { console.warn("[Pet] saveState failed " + e) }
    }
    function loadState() {
        try {
            var db = petDb()
            var vals = {}
            db.transaction(function(tx){
                var rs = tx.executeSql('SELECT * FROM state')
                for (var i=0;i<rs.rows.length;i++) vals[rs.rows.item(i).key] = rs.rows.item(i).value
            })
            if (vals.petX !== undefined) {
                var x = parseInt(vals.petX); if (!isNaN(x)) root.petX = clampX(x)
            }
            if (vals.petY !== undefined) {
                var y = parseInt(vals.petY); if (!isNaN(y)) {
                    // if saved y is near top (floating), ignore — force floor on next frame
                    if (y < 100) {
                        console.log("[Pet] ignoring saved top y="+y+" -> will snap to floor")
                        root.hasSavedY = false
                    } else {
                        root.petY = clampY(y)
                        root.hasSavedY = true
                    }
                }
            }
            if (vals.facingRight !== undefined) root.facingRight = vals.facingRight === '1'
            // persist always there — always visible on start, ignore saved hidden
            root.visible = true
            console.log("[Pet] restored petX=" + root.petX + " petY=" + root.petY + " facing=" + root.facingRight + " (forced visible)")
        } catch(e) { console.warn("[Pet] loadState failed " + e) }
    }
    property bool hasSavedY: false

    // ── actions file ───────────────────────────────────────────────
    property var actions: ({})
    property string actionsFile: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/config/pet-actions.json"
    property string assetsBase: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/assets/"
    FileView { id: actionsFileView; path: root.actionsFile; printErrors: true;
        onLoaded: {
            try { var data = JSON.parse(text()); root.actions = data; console.log("[Pet] loaded " + Object.keys(data).length + " actions") }
            catch(e){ console.warn("[Pet] parse fail " + e) }
        }
    }
    Component.onCompleted: { initDb(); loadState(); actionsFileView.path=""; actionsFileView.path=root.actionsFile }

    // ── frames ─────────────────────────────────────────────────────
    property string currentAction: "Stand"
    property var currentFrames: ["shime1.png","shime1a.png"]
    property int currentFrameIndex: 0
    property int frameInterval: 180
    property string currentFile: currentFrames.length>0 ? currentFrames[currentFrameIndex % currentFrames.length] : "shime1.png"
    property string currentFrameUrl: "file://" + assetsBase + currentFile
    property bool facingRight: false
    property string bubbleText: ""
    property bool isDragging: false
    property bool isFalling: false

    // position — now 2D free roam (x+y), floor fallback if no savedY
    property int petX: 120
    property int petY: 0
    property int spriteW: petWrapper.width>0 ? petWrapper.width : 128
    property int spriteH: petWrapper.height>0 ? petWrapper.height : 128
    function clampX(x){ if (root.width<=0) return x; return Math.max(2, Math.min(x, root.width - spriteW - 2)) }
    function clampY(y){ if (root.height<=0) return y; return Math.max(4, Math.min(y, root.height - spriteH - 4)) }
    function clampXY(x,y){ return {x: clampX(x), y: clampY(y)} }

    // ── smart user activity (Hyprland) ─────────────────────────────
    property string userActivity: "unknown"
    property string lastClass: ""
    property string lastTitle: ""
    property int cursorX: 800
    property int cursorY: 450
    property var activeWinAt: [0,0]
    property var activeWinSize: [0,0]
    property int lastActivityChangeMs: 0
    property bool isUserIdle: false

    function classifyActivity(cls, title) {
        var c = (cls||"").toLowerCase()
        var t = (title||"").toLowerCase()
        if (!c && !t) return "idle"
        if (c.indexOf("code") !== -1 || c.indexOf("cursor") !== -1 || c.indexOf("nvim") !== -1 || c.indexOf("neovim") !== -1 || c.indexOf("windsurf") !== -1 || t.indexOf(".ts") !== -1 || t.indexOf(".py") !== -1 || t.indexOf(".go") !== -1 || c === "ghostty" && (t.indexOf("nvim")!==-1 || t.indexOf("code")!==-1)) return "coding"
        if (c.indexOf("ghostty") !== -1 || c.indexOf("alacritty") !== -1 || c.indexOf("kitty") !== -1 || c.indexOf("foot") !== -1 || c.indexOf("konsole") !== -1) return "terminal"
        if (c.indexOf("firefox") !== -1 || c.indexOf("chrome") !== -1 || c.indexOf("chromium") !== -1 || c.indexOf("brave") !== -1) {
            if (t.indexOf("youtube")!==-1 || t.indexOf("twitch")!==-1) return "media"
            return "browsing"
        }
        if (c.indexOf("spotify")!==-1 || c.indexOf("mpv")!==-1 || c.indexOf("vlc")!==-1) return "media"
        if (c.indexOf("slack")!==-1 || c.indexOf("discord")!==-1 || c.indexOf("telegram")!==-1) return "browsing"
        return "unknown"
    }
    function updateActivity() {
        var tl = Hyprland.activeToplevel
        var cls = "", title=""
        var at = [0,0], sz=[0,0]
        if (tl) {
            // HyprlandToplevel has lastIpcObject with class/at/size
            var obj = tl.lastIpcObject
            if (obj) {
                cls = obj.class || obj.initialClass || ""
                title = obj.title || obj.initialTitle || tl.title || ""
                if (obj.at) at = obj.at
                if (obj.size) sz = obj.size
            } else {
                title = tl.title || ""
            }
        }
        var act = classifyActivity(cls, title)
        // idle if no window change for 55s and no cursor movement (tracked separately)
        var now = Date.now()
        if (cls !== lastClass || title !== lastTitle) {
            lastClass = cls; lastTitle = title; lastActivityChangeMs = now; isUserIdle = false
        } else if (now - lastActivityChangeMs > 55000) {
            isUserIdle = true
            act = "idle"
        }
        if (act !== userActivity) {
            userActivity = act
            stateMachine.userActivity = act
            console.log("[Pet] activity → " + act + " (" + cls + " :: " + title + ")")
        }
        activeWinAt = at; activeWinSize = sz
    }

    Timer { id: activityTimer; interval: 3800; running: true; repeat: true; triggeredOnStart: true; onTriggered: updateActivity() }
    Connections { target: Hyprland; function onActiveToplevelChanged(){ updateActivity() } }

    // cursor polling via hyprctl
    Process {
        id: cursorProc
        command: ["sh","-c","hyprctl cursorpos -j"]
        stdout: StdioCollector { id: cursorOut; waitForEnd: true; onStreamFinished: {
                try {
                    var j = JSON.parse(text.trim())
                    if (j && typeof j.x==="number") { root.cursorX = Math.round(j.x); root.cursorY = Math.round(j.y) }
                } catch(e){}
            }
        }
    }
    Timer { interval: 900; running: true; repeat: true; triggeredOnStart: true; onTriggered: cursorProc.running = true }

    // idle cursor check — if cursor hasn't moved 90s consider idle too
    property int lastCursorX: 0
    property int lastCursorY: 0
    property int lastCursorMoveMs: 0
    onCursorXChanged: checkCursorMove()
    onCursorYChanged: checkCursorMove()
    function checkCursorMove(){
        if (cursorX!==lastCursorX || cursorY!==lastCursorY){ lastCursorX=cursorX; lastCursorY=cursorY; lastCursorMoveMs=Date.now(); if(isUserIdle) isUserIdle=false }
        if (Date.now()-lastCursorMoveMs>90000 && !isUserIdle){ isUserIdle=true; userActivity="idle"; stateMachine.userActivity="idle" }
    }

    // ── state machine ──────────────────────────────────────────────
    StateMachine {
        id: stateMachine
        actions: root.actions
        userActivity: root.userActivity
        onActionChanged: function(name, frames, interval, bubble, kind){
            root.currentAction = name
            root.currentFrames = frames
            root.frameInterval = interval
            root.currentFrameIndex = 0
            root.bubbleText = bubble
            if (bubble!=="") bubbleHideTimer.restart()
            frameTimer.interval = interval; frameTimer.restart()
            if (!root.isDragging && !root.isFalling) {
                if (kind==="walk") root.startWalk(name)
                else if (kind==="walkToMe") root.walkToMe(name)
                else if (kind==="sitAnywhere") root.sitAnywhere(name)
                else if (kind==="sleep") root.sleepAnywhere(name)
                else if (kind==="hide") root.doHide(name)
                else root.stopWalk()
            }
            if (bubble==="") bubbleHideTimer.stop()
        }
    }
    Timer { id: bubbleHideTimer; interval: 2400; repeat:false; onTriggered: root.bubbleText="" }
    Timer { id: frameTimer; interval: root.frameInterval; repeat:true; running:true; onTriggered: { if(root.currentFrames.length>0) root.currentFrameIndex=(root.currentFrameIndex+1)%root.currentFrames.length } }

    // ── 2D movement ────────────────────────────────────────────────
    function speedFor(action){
        if (action==="Run"||action==="RunWithIe") return 145
        if (action==="Dash") return 225
        return 68
    }
    function startWalk(action){
        if (root.width<=0 || root.height<=0){ Qt.callLater(function(){ startWalk(action) }); return }
        var floorY = clampY(root.height - spriteH -6)
        // fallback if height not yet valid (e.g. 4) — use 712 default
        if (floorY < 40) floorY = 712
        console.log("[Pet] startWalk "+action+" rootWH="+root.width+"x"+root.height+" floorY="+floorY+" curY="+root.petY)
        if (Math.abs(root.petY - floorY) > 4) {
            yAnim.duration = 220; root.petY = floorY
        }
        var maxX = Math.max(2, root.width - spriteW -2)
        var cur = root.petX
        var target = Math.floor(Math.random()*(maxX-2+1))+2
        var tries=0; while(Math.abs(target-cur)<120 && tries<6){ target=Math.floor(Math.random()*(maxX-2+1))+2; tries++ }
        var dist=Math.abs(target-cur)
        var dur=Math.max(900, Math.min(9000, dist / speedFor(action)*1000))
        root.facingRight = target>cur
        xAnim.duration=dur; yAnim.duration=240
        root.petX = clampX(target); root.petY = floorY
        saveState()
        console.log("[Pet] startWalk "+action+" to "+target+" dur "+dur+" floorY "+floorY)
    }
    function walkToMe(action){
        console.log("[Pet] walkToMe action="+action+" cursor="+cursorX+","+cursorY+" winAt="+JSON.stringify(activeWinAt)+" size="+JSON.stringify(activeWinSize)+" wh="+root.width+"x"+root.height)
        if (root.width<=0 || root.height<=0){ Qt.callLater(function(){ walkToMe(action) }); return }
        var floorY = clampY(root.height - spriteH -6)
        if (floorY < 40) floorY = 712
        if (Math.abs(root.petY - floorY) > 4) { yAnim.duration=180; root.petY=floorY }
        var tx
        if (activeWinSize[0]>120 && activeWinSize[1]>120) {
            tx = activeWinAt[0] + activeWinSize[0]/2 - spriteW/2
        } else {
            tx = cursorX - spriteW/2
        }
        var c = clampXY(tx, floorY)
        // y always floor — no floating
        var dx=c.x - root.petX, dy=c.y - root.petY
        var dist=Math.hypot(dx,dy)
        var dur=Math.max(700, Math.min(8000, dist / speedFor(action)*1000))
        root.facingRight = dx>0
        xAnim.duration=dur; yAnim.duration=dur
        root.petX=c.x; root.petY=c.y
        root.bubbleText="comin'!"
        bubbleHideTimer.restart()
        saveState()
    }
    function sitAnywhere(action){
        console.log("[Pet] sitAnywhere " + action+" wh="+root.width+"x"+root.height+" activity="+userActivity)
        // any part of screen — not just below: pick random surface
        // 55% floor, 20% ceiling (hang), 15% window top, 10% truly random mid-air (with fall)
        var r = Math.random()
        var targetY, targetX, useFrames = action
        var floorY = clampY(root.height - spriteH -6)
        if (floorY < 40) floorY = 712
        var ceilingY = 10
        if (r < 0.55) {
            // floor — classic sit anywhere along bottom
            targetY = floorY
            targetX = Math.floor(Math.random()*Math.max(4, root.width - spriteW -4))+2
        } else if (r < 0.75) {
            // ceiling — hang from top (uses GrabCeiling frames)
            targetY = ceilingY
            targetX = Math.floor(Math.random()*Math.max(4, root.width - spriteW -4))+2
            if (actions["GrabCeiling"]) useFrames = "GrabCeiling"
        } else if (r < 0.90 && activeWinSize[0]>200) {
            // on window — sit on top edge of active window
            var winTop = activeWinAt[1] - 54 // window screen y -> window-local (bar offset)
            targetY = clampY(winTop - spriteH + 12)
            targetX = clampX(activeWinAt[0] + Math.random()*(activeWinSize[0]-spriteW) )
            if (targetY < 8) targetY = floorY // fallback if window top offscreen
        } else {
            // fallback floor — never truly random mid-air (avoids floating sit)
            targetY = floorY
            targetX = Math.floor(Math.random()*Math.max(4, root.width - spriteW -4))+2
        }
        // if target is ceiling/wall, use appropriate frames
        if (targetY < 40 && actions["GrabCeiling"]) useFrames = "GrabCeiling"
        else if (targetY > floorY - 30) useFrames = action // floor sit keeps original
        if (useFrames !== action && actions[useFrames]) {
            root.currentAction = useFrames
            root.currentFrames = actions[useFrames]
            root.frameInterval = 600
            frameTimer.interval = 600
        }
        var rx = targetX
        var ry = targetY
        var dist=Math.hypot(rx-root.petX, ry-root.petY)
        var dur=Math.max(500, Math.min(7000, dist/68*1000))
        root.facingRight = rx > root.petX
        xAnim.duration=dur; yAnim.duration=dur
        root.petX = clampX(rx); root.petY = clampY(ry)
        saveState()
    }
    function sleepAnywhere(action){
        console.log("[Pet] sleepAnywhere " + action+" wh="+root.width+"x"+root.height)
        // sleep can be anywhere but prefers cozy spots: floor corners, ceiling nook, window ledge
        var floorY = clampY(root.height - spriteH -6)
        if (floorY < 40) floorY = 712
        var ceilingY = 12
        var winY = (activeWinSize[0]>200) ? clampY(activeWinAt[1] - 54 - spriteH/2) : floorY
        var spots = [
            {x:8, y: floorY},
            {x: root.width - spriteW -8, y: floorY},
            {x: Math.floor(root.width/2 - spriteW/2), y: floorY},
            {x: 12, y: ceilingY},
            {x: root.width - spriteW -12, y: ceilingY},
            {x: clampX(activeWinAt[0] + 20), y: winY}
        ]
        var pick = spots[Math.floor(Math.random()*spots.length)]
        pick.x += Math.floor((Math.random()-0.5)*40)
        pick.y += Math.floor((Math.random()-0.5)*20)
        var c=clampXY(pick.x, pick.y)
        // choose frames for spot: ceiling -> GrabCeiling/Sprawl, window -> Sprawl
        if (c.y < 40 && actions["GrabCeiling"]) {
            root.currentAction = "GrabCeiling"
            root.currentFrames = actions["GrabCeiling"]
        }
        var dist=Math.hypot(c.x-root.petX, c.y-root.petY)
        var dur=Math.max(600, Math.min(7000, dist/55*1000))
        xAnim.duration=dur; yAnim.duration=dur
        root.petX=c.x; root.petY=c.y
        root.bubbleText = ["Zzz…","night…","…zzz"][Math.floor(Math.random()*3)]
        bubbleHideTimer.interval=4200; bubbleHideTimer.restart()
        saveState()
    }
    function doHide(action){
        console.log("[Pet] doHide " + action)
        var offX = root.width + 40
        var dur = Math.abs(offX - root.petX)/70*1000
        xAnim.duration=Math.min(2200, Math.max(700, dur))
        yAnim.duration=xAnim.duration
        root.petX = offX
        root.bubbleText="brb…"
        bubbleHideTimer.restart()
        hideTimer.restart()
    }
    Timer { id: hideTimer; interval: 1800; repeat:false; onTriggered: {
            root.visible=false; saveState()
            // reappear after hide dwell
            reappearTimer.interval = 4200 + Math.random()*3500
            reappearTimer.restart()
        }
    }
    Timer { id: reappearTimer; interval: 5000; repeat:false; onTriggered: {
            // re-enter from offscreen right to random visible pos
            root.visible=true; saveState()
            root.petX = root.width + 40
            // next frame will animate in via next state; force walk
            stateMachine.trigger("Walk")
            // nudge immediately to visible
            Qt.callLater(function(){
                var nx = clampX(Math.floor(Math.random()*(root.width - spriteW -40))+20)
                var ny = root.height - spriteH -6
                xAnim.duration=1200; yAnim.duration=1200
                root.petX=nx; root.petY=ny
                saveState()
            })
        }
    }
    function stopWalk(){}
    function cancelWalk(){ xAnim.duration=1; yAnim.duration=1 }

    // ── persistence on move ────────────────────────────────────────
    onPetXChanged: { if (!isDragging && !isFalling) saveState() }
    onPetYChanged: { if (!isDragging && !isFalling) saveState() }
    onFacingRightChanged: saveState()

    // ── drag handling (free 2D) ────────────────────────────────────
    property point dragPressGlobal: Qt.point(0,0)
    property int dragStartX: 0
    property int dragStartY: 0

    Item {
        id: petWrapper
        x: root.petX
        y: root.petY
        width: sprite.implicitWidth>0 ? sprite.implicitWidth : 128
        height: sprite.implicitHeight>0 ? sprite.implicitHeight : 128
        Behavior on x { enabled: !root.isDragging; NumberAnimation { id: xAnim; duration: 3200; easing.type: Easing.Linear } }
        Behavior on y { enabled: !root.isDragging; NumberAnimation { id: yAnim; duration: 3200; easing.type: Easing.Linear } }

        // init position to floor if no savedY, otherwise keep saved
        Component.onCompleted: {
            if (!root.hasSavedY) {
                root.petY = clampY(root.height - height -6)
                saveState()
            }
        }

        Item {
            id: bubble
            visible: root.bubbleText!==""
            opacity: visible?1:0
            Behavior on opacity { NumberAnimation{duration:180}}
            x: (parent.width - bubbleBg.width)/2
            y: -bubbleBg.height -10
            z: 2
            Rectangle {
                id: bubbleBg
                width: bubbleTextItem.implicitWidth+20
                height: bubbleTextItem.implicitHeight+14
                radius: 10
                color: Qt.rgba(0.09,0.09,0.09,0.88)
                border.width:1; border.color:Qt.rgba(1,1,1,0.12)
                Rectangle{width:8;height:8;rotation:45;color:bubbleBg.color;anchors.horizontalCenter:parent.horizontalCenter;anchors.top:parent.bottom;anchors.topMargin:-5}
                Text{ id: bubbleTextItem; anchors.centerIn:parent; text: root.bubbleText; color:"white"; font.family:"FiraCode Nerd Font"; font.pixelSize:11; font.weight:Font.DemiBold }
            }
        }

        Image {
            id: sprite
            anchors.centerIn: parent
            source: root.currentFrameUrl
            fillMode: Image.Pad
            asynchronous: true
            cache: true
            smooth: false
            mipmap: false
            transform: Scale { xScale: root.facingRight ? -1 : 1; origin.x: sprite.width/2; origin.y: sprite.height/2 }
            onStatusChanged: if(status===Image.Error) console.warn("[Pet] image error " + source + " → " + currentFile)
        }

        MouseArea {
            id: spriteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onPressed: function(mouse){
                root.isDragging=true
                root.dragPressGlobal=mapToItem(null, mouse.x, mouse.y)
                root.dragStartX=petWrapper.x
                root.dragStartY=petWrapper.y
                bubbleHideTimer.stop(); root.bubbleText=""
                frameTimer.stop()
                if(root.actions["Pinched"]){
                    root.currentAction="Pinched"; root.currentFrames=root.actions["Pinched"]; root.currentFrameIndex=0; root.frameInterval=90; frameTimer.interval=90; frameTimer.restart()
                }
                stateMachine.resetFatigue()
                stateMachine.pause()
            }
            onPositionChanged: function(mouse){
                if(!root.isDragging) return
                var g=mapToItem(null, mouse.x, mouse.y)
                var dx=g.x - root.dragPressGlobal.x
                var dy=g.y - root.dragPressGlobal.y
                var nx=clampX(root.dragStartX + dx)
                var ny=clampY(root.dragStartY + dy)
                petWrapper.x=nx; petWrapper.y=ny
                root.petX=nx; root.petY=ny
                if(dx>2) root.facingRight=true; else if(dx<-2) root.facingRight=false
                saveState()
            }
            onReleased: function(mouse){
                root.isDragging=false
                var floorY = clampY(root.height - sprite.implicitHeight -6)
                // if dragged mid-air, fall to floor — no floating
                var wasMidAir = Math.abs(petWrapper.y - floorY) > 12
                root.petX=clampX(petWrapper.x)
                if (wasMidAir) {
                    yAnim.duration = 420; root.petY = floorY
                    console.log("[Pet] drop from "+petWrapper.y+" to floor "+floorY)
                } else {
                    root.petY=clampY(petWrapper.y)
                }
                saveState()
                root.isFalling=true
                if(root.actions["Falling"]){
                    root.currentAction="Falling"; root.currentFrames=root.actions["Falling"]; root.currentFrameIndex=0; root.frameInterval=90; frameTimer.interval=90; frameTimer.restart()
                }
                fallTimer.restart()
            }
            onClicked: function(mouse){
                stateMachine.resetFatigue()
                if(mouse.button===Qt.RightButton){
                    var specials=["PoseAction","ThrowNeedleAction","EatBerryAction"]
                    var avail=specials.filter(function(n){return root.actions[n]})
                    if(avail.length) stateMachine.trigger(avail[Math.floor(Math.random()*avail.length)])
                    return
                }
                if(!root.isDragging && root.actions["PetAction"]) stateMachine.trigger("PetAction")
            }
            onDoubleClicked: function(mouse){ stateMachine.resetFatigue(); if(root.actions["Dash"]) stateMachine.trigger("Dash") }
        }
    }

    Timer { id: fallTimer; interval:520; repeat:false; onTriggered:{
            root.isFalling=false
            if(root.actions["Bouncing"]){
                root.currentAction="Bouncing"; root.currentFrames=root.actions["Bouncing"]; root.currentFrameIndex=0; root.frameInterval=85; frameTimer.interval=85; frameTimer.restart(); bounceTimer.restart()
            } else stateMachine.trigger("Stand")
        }
    }
    Timer { id: bounceTimer; interval:380; repeat:false; onTriggered:{
            var name=root.actions["Stand"]?"Stand":Object.keys(root.actions)[0]
            if(name) stateMachine.trigger(name)
        }
    }

    onWidthChanged: { root.petX=clampX(root.petX) }
    onHeightChanged: {
        var floor = clampY(root.height - spriteH -6)
        if (floor < 40) return
        if (!isDragging && !isFalling && Math.abs(root.petY - floor) > 60) {
            console.log("[Pet] heightChanged floor fix " + root.petY + " -> " + floor + " h="+root.height)
            yAnim.duration = 420; root.petY = floor; saveState()
        } else {
            root.petY = clampY(root.petY)
        }
    }
    Timer { id: floorFixTimer; interval: 1600; running: true; repeat: false; onTriggered: {
            var floor = clampY(root.height - spriteH -6)
            if (floor < 40) return
            if (Math.abs(root.petY - floor) > 60) {
                console.log("[Pet] startup floor fix " + root.petY + " -> " + floor)
                yAnim.duration = 520; root.petY = floor; saveState()
            }
        }
    }

    Timer { id: dbg; interval:8000; running:false; repeat:true; onTriggered: console.log("[Pet] " + currentAction + " ("+stateMachine.actionKind+") x="+petX+" y="+petY+" act="+userActivity+" frame="+currentFile) }
}
