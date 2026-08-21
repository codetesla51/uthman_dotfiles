package main

import (
	"archive/zip"
	"bufio"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"math"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

//go:embed static/*
var staticFS embed.FS

var home, _ = os.UserHomeDir()

// ── Config paths (dotfiles is source of truth, stow-managed) ──
const (
	hypridleConf  = "~/dotfiles/.config/hypr/hypridle.conf"
	hyprlockConf  = "~/dotfiles/.config/hypr/hyprlock.conf"
	looknfeelConf = "~/dotfiles/.config/hypr/looknfeel.conf"
	ghosttyConf   = "~/dotfiles/.config/ghostty/config"
	getThemeBin   = "~/dotfiles/.local/bin/getTheme"
	matugenConf   = "~/dotfiles/.config/matugen/config.toml"
	themeJSON     = "~/.config/omarchy/current/theme/matugen-base.json"
	wallpaperLink = "~/.config/omarchy/current/background"
)

var (
	bindingsPath  = home + "/dotfiles/.config/hypr/bindings.conf"
	autostartPath = home + "/dotfiles/.config/hypr/autostart.conf"
)

var wallpaperDirs = []string{
	"~/.config/omarchy/themes/snow_black/backgrounds",
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/api/stats", handleStats)
	mux.HandleFunc("/api/system/info", handleSystemInfo)
	mux.HandleFunc("/api/processes", handleProcesses)
	mux.HandleFunc("/api/process/kill", handleProcessKill)
	mux.HandleFunc("/api/logs/stream", handleLogStream)
	mux.HandleFunc("/api/keybinds", handleKeybinds)
	mux.HandleFunc("/api/autostart", handleAutostart)
	mux.HandleFunc("/api/fonts", handleFonts)
	mux.HandleFunc("/api/fonts/file", handleFontFile)
	mux.HandleFunc("/api/logs/recent", handleLogsRecent)
	mux.HandleFunc("/api/appearance", handleAppearance)
	mux.HandleFunc("/api/disks", handleDisks)
	mux.HandleFunc("/api/services", handleServices)
	mux.HandleFunc("/api/theme", handleTheme)
	mux.HandleFunc("/api/hypridle", handleHypridle)
	mux.HandleFunc("/api/hyprland", handleHyprland)
	mux.HandleFunc("/api/ghostty", handleGhostty)
	mux.HandleFunc("/api/matugen", handleMatugen)
	mux.HandleFunc("/api/wallpapers", handleWallpapers)
	mux.HandleFunc("/api/wallpaper/set", handleWallpaperSet)
	mux.HandleFunc("/api/reload", handleReload)
	mux.HandleFunc("/api/audio", handleAudio)
	mux.HandleFunc("/api/brightness", handleBrightness)
	mux.HandleFunc("/api/network", handleNetwork)
	mux.HandleFunc("/api/monitors", handleMonitors)
	mux.HandleFunc("/api/monitor/set", handleMonitorSet)
	mux.HandleFunc("/api/dnd", handleDND)
	mux.HandleFunc("/api/bluetooth", handleBluetooth)
	mux.HandleFunc("/api/power", handlePower)
	mux.HandleFunc("/api/effects", handleEffects)
	mux.HandleFunc("/api/powerprofile", handlePowerProfile)
	mux.HandleFunc("/api/input", handleInput)
	mux.HandleFunc("/api/mako", handleMako)
	mux.HandleFunc("/api/waybar", handleWaybar)
	mux.HandleFunc("/api/nightlight", handleNightlight)
	mux.HandleFunc("/wallpaper/", handleWallpaperImage)

	staticContent, _ := fs.Sub(staticFS, "static")
	fileServer := http.FileServer(http.FS(staticContent))
	mux.Handle("/", fileServer)

	port := "8765"
	if p := os.Getenv("PORT"); p != "" {
		port = p
	}
	log.Printf("Omarchy Control Panel listening on http://localhost:%s", port)
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}

// ── Helpers ──

func expand(p string) string {
	if strings.HasPrefix(p, "~/") {
		return filepath.Join(home, p[2:])
	}
	return p
}

func readFile(p string) (string, error) {
	b, err := os.ReadFile(expand(p))
	return string(b), err
}

func writeFile(p, content string) error {
	fp := expand(p)
	if err := os.MkdirAll(filepath.Dir(fp), 0o755); err != nil {
		return err
	}
	return os.WriteFile(fp, []byte(content), 0o644)
}

func jsonOK(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func jsonErr(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

func requireMethod(w http.ResponseWriter, r *http.Request, methods ...string) bool {
	for _, m := range methods {
		if r.Method == m {
			return true
		}
	}
	w.Header().Set("Allow", strings.Join(methods, ", "))
	jsonErr(w, "method not allowed", http.StatusMethodNotAllowed)
	return false
}

func decodeBody(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		jsonErr(w, "invalid request body: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func clampFloat(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// ── System stats ──

type Stats struct {
	CPU         float64 `json:"cpu"`
	MemUsed     float64 `json:"memUsed"`  // KiB
	MemTotal    float64 `json:"memTotal"` // KiB
	MemPct      float64 `json:"memPct"`
	SwapPct     float64 `json:"swapPct"`
	Load1       float64 `json:"load1"`
	Load5       float64 `json:"load5"`
	Load15      float64 `json:"load15"`
	Uptime      int64   `json:"uptime"`
	Battery     int     `json:"battery"` // -1 when absent
	Charging    bool    `json:"charging"`
	PowerW      float64 `json:"powerW"`      // current draw/deliver in W
	MinutesLeft int64   `json:"minutesLeft"` // -1 when unknown
	Temp        float64 `json:"temp"`
	NetRx       float64 `json:"netRx"` // KiB/s
	NetTx       float64 `json:"netTx"` // KiB/s
	Time        int64   `json:"time"`
}

var (
	statsMu       sync.Mutex
	prevCPUIdle   uint64
	prevCPUTotal  uint64
	prevNetRx     uint64
	prevNetTx     uint64
	prevStatsTime time.Time
)

func readCPUJiffies() (idle, total uint64, ok bool) {
	b, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, 0, false
	}
	line := strings.SplitN(string(b), "\n", 2)[0]
	fields := strings.Fields(line)[1:]
	var vals [10]uint64
	for i := range vals {
		if i >= len(fields) {
			break
		}
		vals[i], _ = strconv.ParseUint(fields[i], 10, 64)
	}
	user, nice, system := vals[0], vals[1], vals[2]
	idleAll := vals[3] + vals[4]
	iowait, irq, softirq, steal := vals[4], vals[5], vals[6], vals[7]
	total = user + nice + system + idleAll + iowait + irq + softirq + steal
	return vals[3] + iowait, total, true
}

func readNetBytes() (rx, tx uint64) {
	b, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return 0, 0
	}
	for _, line := range strings.Split(string(b), "\n") {
		idx := strings.Index(line, ":")
		if idx < 0 {
			continue
		}
		iface := strings.TrimSpace(line[:idx])
		if iface == "lo" || strings.HasPrefix(iface, "wl") && false {
			continue
		}
		fields := strings.Fields(line[idx+1:])
		if len(fields) < 9 {
			continue
		}
		r, _ := strconv.ParseUint(fields[0], 10, 64)
		t, _ := strconv.ParseUint(fields[8], 10, 64)
		rx += r
		tx += t
	}
	return rx, tx
}

func collectStats() Stats {
	statsMu.Lock()
	defer statsMu.Unlock()

	now := time.Now()
	s := Stats{Time: now.Unix(), Battery: -1}

	idle, total, ok := readCPUJiffies()
	if ok && !prevStatsTime.IsZero() {
		dIdle := float64(idle - prevCPUIdle)
		dTotal := float64(total - prevCPUTotal)
		if dTotal > 0 {
			s.CPU = clampFloat(100*(1-dIdle/dTotal), 0, 100)
		}
	}
	if ok {
		prevCPUIdle, prevCPUTotal = idle, total
	}

	rx, tx := readNetBytes()
	if !prevStatsTime.IsZero() {
		dt := now.Sub(prevStatsTime).Seconds()
		if dt > 0 {
			s.NetRx = clampFloat(float64(rx-prevNetRx)/1024/dt, 0, 1e9)
			s.NetTx = clampFloat(float64(tx-prevNetTx)/1024/dt, 0, 1e9)
		}
	}
	prevNetRx, prevNetTx, prevStatsTime = rx, tx, now

	if b, err := os.ReadFile("/proc/meminfo"); err == nil {
		var memAvail, swapTotal, swapFree float64
		for _, line := range strings.Split(string(b), "\n") {
			switch {
			case strings.HasPrefix(line, "MemTotal:"):
				fmt.Sscanf(line, "MemTotal: %f", &s.MemTotal)
			case strings.HasPrefix(line, "MemAvailable:"):
				fmt.Sscanf(line, "MemAvailable: %f", &memAvail)
			case strings.HasPrefix(line, "SwapTotal:"):
				fmt.Sscanf(line, "SwapTotal: %f", &swapTotal)
			case strings.HasPrefix(line, "SwapFree:"):
				fmt.Sscanf(line, "SwapFree: %f", &swapFree)
			}
		}
		s.MemUsed = s.MemTotal - memAvail
		if s.MemTotal > 0 {
			s.MemPct = s.MemUsed / s.MemTotal * 100
		}
		if swapTotal > 0 {
			s.SwapPct = (swapTotal - swapFree) / swapTotal * 100
		}
	}

	if b, err := os.ReadFile("/proc/loadavg"); err == nil {
		fmt.Sscanf(string(b), "%f %f %f", &s.Load1, &s.Load5, &s.Load15)
	}
	if b, err := os.ReadFile("/proc/uptime"); err == nil {
		var up float64
		fmt.Sscanf(string(b), "%f", &up)
		s.Uptime = int64(up)
	}
	matches, _ := filepath.Glob("/sys/class/power_supply/BAT*/capacity")
	if len(matches) > 0 {
		if b, err := os.ReadFile(matches[0]); err == nil {
			v, _ := strconv.Atoi(strings.TrimSpace(string(b)))
			s.Battery = v
		}
	}
	if len(matches) > 0 {
		batDir := filepath.Dir(matches[0])
		status := strings.ToLower(strings.TrimSpace(readSys(batDir + "/status")))
		s.Charging = status == "charging" || status == "fully-charged"
		// Estimate: charge_* is µAh, voltage_now is µV, current_now is µA.
		chargeNow := readSysFloat(batDir + "/charge_now")   // µAh
		chargeFull := readSysFloat(batDir + "/charge_full") // µAh
		volts := readSysFloat(batDir+"/voltage_now") / 1e6  // V
		amps := readSysFloat(batDir+"/current_now") / 1e6   // A
		if volts > 0 && amps > 0 {
			s.PowerW = volts * amps
		}
		if s.PowerW > 0.5 && chargeNow > 0 && chargeFull > chargeNow {
			energyNow := chargeNow / 1e6 * volts   // Wh
			energyFull := chargeFull / 1e6 * volts // Wh
			var hours float64
			if status == "discharging" {
				hours = energyNow / s.PowerW
			} else if s.Charging {
				hours = (energyFull - energyNow) / s.PowerW
			}
			if hours > 0 && hours < 100 {
				s.MinutesLeft = int64(hours*60 + 0.5)
			} else {
				s.MinutesLeft = -1
			}
		} else {
			s.MinutesLeft = -1
		}
	}
	if matches, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/temp"); len(matches) > 0 {
		if b, err := os.ReadFile(matches[0]); err == nil {
			v, _ := strconv.Atoi(strings.TrimSpace(string(b)))
			s.Temp = float64(v) / 1000
		}
	}
	return s
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	jsonOK(w, collectStats())
}

func handleSystemInfo(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	hostname, _ := os.Hostname()
	kernel, _ := exec.Command("uname", "-r").Output()
	shell := filepath.Base(os.Getenv("SHELL"))
	de := "Hyprland"
	if out, err := exec.Command("hyprctl", "version").Output(); err != nil || len(out) == 0 {
		de = "unknown"
	}
	cur := "unknown"
	if link, err := os.Readlink(expand(wallpaperLink)); err == nil {
		cur = filepath.Base(link)
	}
	jsonOK(w, map[string]string{
		"hostname":  hostname,
		"kernel":    strings.TrimSpace(string(kernel)),
		"user":      os.Getenv("USER"),
		"shell":     shell,
		"de":        de,
		"wallpaper": cur,
	})
}

// ── Processes ──

type Proc struct {
	PID   int     `json:"pid"`
	Name  string  `json:"name"`
	Cmd   string  `json:"cmd"`
	CPU   float64 `json:"cpu"`
	MEM   float64 `json:"mem"`
	RSSMB float64 `json:"rssMb"`
	State string  `json:"state"`
}

func handleProcesses(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	sort := r.URL.Query().Get("sort")
	if sort != "mem" && sort != "rss" {
		sort = "cpu"
	}
	out, err := exec.Command("ps", "-eo", "pid,comm,args,pcpu,pmem,rss,state", "--sort=-"+sort).Output()
	if err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	procs := []Proc{}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	for i, line := range lines {
		if i == 0 {
			continue
		}
		f := strings.Fields(line)
		if len(f) < 7 {
			continue
		}
		pid, _ := strconv.Atoi(f[0])
		cpu, _ := strconv.ParseFloat(f[3], 64)
		mem, _ := strconv.ParseFloat(f[4], 64)
		rssKB, _ := strconv.ParseFloat(f[5], 64)
		// args may contain spaces — rejoin remainder minus state field
		args := strings.Join(f[6:len(f)-1], " ")
		procs = append(procs, Proc{
			PID: pid, Name: f[1], Cmd: args,
			CPU: cpu, MEM: mem,
			RSSMB: rssKB / 1024, State: f[len(f)-1],
		})
		if len(procs) >= 50 {
			break
		}
	}
	jsonOK(w, procs)
}

func handleProcessKill(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		PID    int `json:"pid"`
		Signal int `json:"signal"` // 15=TERM default, 9=KILL
	}
	if !decodeBody(w, r, &req) {
		return
	}
	if req.PID <= 1 {
		jsonErr(w, "refusing to signal pid <= 1", 400)
		return
	}
	if req.Signal == 0 {
		req.Signal = 15
	}
	if req.Signal != 15 && req.Signal != 9 && req.Signal != 1 {
		jsonErr(w, "allowed signals: 15 (TERM), 9 (KILL), 1 (HUP)", 400)
		return
	}
	// Only allow killing processes owned by the current user.
	status, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", req.PID))
	if err != nil {
		jsonErr(w, "process not found", 404)
		return
	}
	uidAllowed := false
	myUID := strconv.Itoa(os.Getuid())
	for _, line := range strings.Split(string(status), "\n") {
		if strings.HasPrefix(line, "Uid:") {
			fields := strings.Fields(line)
			uidAllowed = len(fields) >= 2 && fields[1] == myUID
			break
		}
	}
	if !uidAllowed {
		jsonErr(w, "process belongs to another user", 403)
		return
	}
	if err := syscall.Kill(req.PID, syscall.Signal(req.Signal)); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	jsonOK(w, map[string]string{"status": "signaled"})
}

// ── Keybinds ──

var bindRe = regexp.MustCompile(`^(bind\w*)\s*=\s*(.+)$`)
var validMods = map[string]bool{"SUPER": true, "SHIFT": true, "CTRL": true, "ALT": true}
var validDispatchers = map[string]bool{
	"exec": true, "execr": true, "execsh": true, "killactive": true,
	"togglefloating": true, "fullscreen": true, "workspace": true,
	"movetoworkspace": true, "movetoworkspacesilent": true, "togglespecialworkspace": true,
	"resizeactive": true, "moveactive": true, "pin": true, "toggleplit": false,
	"cyclenext": true, "cycleprev": true, "movefocus": true, "exit": true,
}

func sanitizeField(s string) string {
	s = strings.Map(func(r rune) rune {
		if r == ';' || r == '`' || r == '\n' || r == '\r' {
			return -1
		}
		return r
	}, strings.TrimSpace(s))
	return s
}

func hasUnsafeChars(s string) bool {
	return strings.ContainsAny(s, ";`\n\r")
}

type Keybind struct {
	ID         int    `json:"id"`   // line index in bindings.conf
	Kind       string `json:"kind"` // bindd, bind, bindl…
	Mods       string `json:"mods"`
	Key        string `json:"key"`
	Desc       string `json:"desc"`
	Dispatcher string `json:"dispatcher"`
	Arg        string `json:"arg"`
}

func parseBinds() []Keybind {
	data, err := os.ReadFile(bindingsPath)
	if err != nil {
		return []Keybind{}
	}
	binds := []Keybind{}
	for i, line := range strings.Split(string(data), "\n") {
		m := bindRe.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		parts := strings.Split(m[2], ",")
		for j := range parts {
			parts[j] = strings.TrimSpace(parts[j])
		}
		b := Keybind{ID: i, Kind: m[1]}
		// bindd/bindl have a description field: mods, key, desc, dispatcher, arg…
		if len(parts) >= 4 && (m[1] == "bindd" || m[1] == "bindld" || m[1] == "bindud" || m[1] == "bindnde") {
			b.Mods, b.Key, b.Desc, b.Dispatcher = parts[0], parts[1], parts[2], parts[3]
			b.Arg = strings.Join(parts[4:], ", ")
		} else if len(parts) >= 3 {
			b.Mods, b.Key, b.Dispatcher = parts[0], parts[1], parts[2]
			b.Arg = strings.Join(parts[3:], ", ")
		} else {
			continue
		}
		binds = append(binds, b)
	}
	return binds
}

func handleKeybinds(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		jsonOK(w, parseBinds())
	case http.MethodPost:
		var req struct {
			Action     string   `json:"action"` // add | delete
			ID         int      `json:"id"`
			Mods       []string `json:"mods"`
			Key        string   `json:"key"`
			Desc       string   `json:"desc"`
			Dispatcher string   `json:"dispatcher"`
			Arg        string   `json:"arg"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		switch req.Action {
		case "delete":
			lines := readLines(bindingsPath)
			if req.ID < 0 || req.ID >= len(lines) || !bindRe.MatchString(strings.TrimSpace(lines[req.ID])) {
				jsonErr(w, "invalid bind id", 400)
				return
			}
			out := append(append([]string{}, lines[:req.ID]...), lines[req.ID+1:]...)
			os.WriteFile(bindingsPath, []byte(strings.Join(out, "\n")), 0644)
			go exec.Command("hyprctl", "reload").Run()
			jsonOK(w, map[string]string{"status": "deleted"})
		case "add":
			if hasUnsafeChars(req.Arg) || hasUnsafeChars(req.Key) || hasUnsafeChars(req.Desc) {
				jsonErr(w, "argument contains forbidden characters (; ` newline)", 400)
				return
			}
			req.Key = sanitizeField(req.Key)
			req.Desc = sanitizeField(req.Desc)
			req.Arg = sanitizeField(req.Arg)
			req.Dispatcher = sanitizeField(req.Dispatcher)
			if req.Key == "" || req.Dispatcher == "" || req.Arg == "" {
				jsonErr(w, "key, dispatcher and arg are required", 400)
				return
			}
			if !validDispatchers[req.Dispatcher] {
				jsonErr(w, "unsupported dispatcher: "+req.Dispatcher, 400)
				return
			}
			mods := []string{}
			for _, m := range req.Mods {
				mu := strings.ToUpper(sanitizeField(m))
				if !validMods[mu] {
					jsonErr(w, "invalid modifier: "+m, 400)
					return
				}
				mods = append(mods, mu)
			}
			modStr := strings.Join(mods, " ")
			if modStr == "" {
				modStr = "SUPER"
			}
			desc := req.Desc
			if desc == "" {
				desc = "Custom bind"
			}
			line := fmt.Sprintf("bindd = %s, %s, %s, %s, %s\n", modStr, req.Key, desc, req.Dispatcher, req.Arg)
			f, err := os.OpenFile(bindingsPath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
			if err != nil {
				jsonErr(w, err.Error(), 500)
				return
			}
			defer f.Close()
			if _, err := f.WriteString(line); err != nil {
				jsonErr(w, err.Error(), 500)
				return
			}
			go exec.Command("hyprctl", "reload").Run()
			jsonOK(w, map[string]string{"status": "added"})
		default:
			jsonErr(w, "action must be add or delete", 400)
		}
	default:
		jsonErr(w, "method not allowed", 405)
	}
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	return strings.Split(string(data), "\n")
}

// ── Autostart ──

func handleAutostart(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		items := []map[string]interface{}{}
		id := 0
		for _, l := range readLines(autostartPath) {
			trimmed := strings.TrimSpace(l)
			if strings.HasPrefix(trimmed, "exec-once") {
				cmd := strings.TrimSpace(strings.TrimPrefix(trimmed, "exec-once"))
				cmd = strings.TrimPrefix(cmd, "=")
				items = append(items, map[string]interface{}{"id": id, "command": strings.TrimSpace(cmd)})
				id++
			}
		}
		jsonOK(w, items)
	case http.MethodPost:
		var req struct {
			Action  string `json:"action"` // add | delete
			ID      int    `json:"id"`
			Command string `json:"command"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		switch req.Action {
		case "add":
			if hasUnsafeChars(req.Command) {
				jsonErr(w, "command contains forbidden characters (; ` newline)", 400)
				return
			}
			req.Command = sanitizeField(req.Command)
			if req.Command == "" {
				jsonErr(w, "command required", 400)
				return
			}
			f, err := os.OpenFile(autostartPath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
			if err != nil {
				jsonErr(w, err.Error(), 500)
				return
			}
			_, _ = f.WriteString(fmt.Sprintf("exec-once = %s\n", req.Command))
			f.Close()
			jsonOK(w, map[string]string{"status": "added"})
		case "delete":
			lines := readLines(autostartPath)
			count := -1
			out := []string{}
			removed := false
			for _, l := range lines {
				if strings.HasPrefix(strings.TrimSpace(l), "exec-once") {
					count++
					if count == req.ID && !removed {
						removed = true
						continue
					}
				}
				out = append(out, l)
			}
			if !removed {
				jsonErr(w, "entry not found", 404)
				return
			}
			os.WriteFile(autostartPath, []byte(strings.Join(out, "\n")), 0644)
			jsonOK(w, map[string]string{"status": "deleted"})
		default:
			jsonErr(w, "action must be add or delete", 400)
		}
	default:
		jsonErr(w, "method not allowed", 405)
	}
}

// ── Log streaming (journalctl over SSE) ──

func handleLogStream(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		jsonErr(w, "streaming unsupported", 500)
		return
	}
	source := r.URL.Query().Get("source")
	prio := r.URL.Query().Get("prio")

	args := []string{"-f", "-n", "200", "--no-pager", "-o", "short"}
	switch {
	case source == "user":
		args = append(args, "--user")
	case source == "kernel":
		args = append(args, "-k")
	case source == "errors":
		args = append(args, "-p", "err")
	case strings.HasPrefix(source, "unit:"):
		unit := strings.TrimPrefix(source, "unit:")
		if !regexp.MustCompile(`^[A-Za-z0-9_.@\\-]+$`).MatchString(unit) {
			jsonErr(w, "invalid unit", 400)
			return
		}
		args = append(args, "-u", unit)
	}
	switch prio {
	case "err", "warning", "info", "debug", "crit", "notice":
		if source != "errors" {
			args = append(args, "-p", prio)
		}
	}

	ctx := r.Context()
	cmd := exec.CommandContext(ctx, "journalctl", args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	if err := cmd.Start(); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	defer func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	}()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return
		default:
		}
		line := scanner.Text()
		// SSE: split long lines into multiple data: fields
		if _, err := fmt.Fprintf(w, "data: %s\n\n", line); err != nil {
			return
		}
		flusher.Flush()
	}
}

// ── Disks ──

type Disk struct {
	Target string `json:"target"`
	Size   string `json:"size"`
	Used   string `json:"used"`
	Pct    int    `json:"pct"`
}

func handleDisks(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	out, err := exec.Command("df", "-hP", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs").Output()
	if err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	var disks []Disk
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	seenDev := map[string]bool{} // one row per physical/filesystem device
	for i, line := range lines {
		if i == 0 {
			continue
		}
		f := strings.Fields(line)
		if len(f) < 6 {
			continue
		}
		if seenDev[f[0]] { // same device mounted at multiple subpaths
			continue
		}
		seenDev[f[0]] = true
		pct, _ := strconv.Atoi(strings.TrimSuffix(f[4], "%"))
		disks = append(disks, Disk{Target: f[5], Size: f[1], Used: f[2], Pct: pct})
	}
	jsonOK(w, disks)
}

// ── Services ──

func handleServices(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	names := []string{"hypridle", "hyprlock", "waybar", "ghostty", "mako", "swaync", "hyprsunset", "matugen"}
	type svc struct {
		Name    string `json:"name"`
		Running bool   `json:"running"`
	}
	out := make([]svc, 0, len(names))
	for _, n := range names {
		err := exec.Command("pgrep", "-x", n).Run()
		out = append(out, svc{Name: n, Running: err == nil})
	}
	jsonOK(w, out)
}

// ── Theme palette ──

func handleTheme(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	txt, err := readFile(themeJSON)
	if err != nil {
		jsonErr(w, "theme not generated yet: "+err.Error(), 404)
		return
	}
	var palette map[string]string
	if err := json.Unmarshal([]byte(txt), &palette); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	jsonOK(w, palette)
}

// ── Hypridle ──

type Hypridle struct {
	Screensaver int `json:"screensaver"`
	Lock        int `json:"lock"`
	Dpms        int `json:"dpms"`
}

var hypridleRe = regexp.MustCompile(`(?m)^(\s*)timeout\s*=\s*(\d+)`)

func handleHypridle(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(hypridleConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		h := Hypridle{120, 300, 360}
		if m := hypridleRe.FindAllStringSubmatch(txt, -1); len(m) >= 3 {
			h.Screensaver, _ = strconv.Atoi(m[0][2])
			h.Lock, _ = strconv.Atoi(m[1][2])
			h.Dpms, _ = strconv.Atoi(m[2][2])
		}
		jsonOK(w, h)

	case http.MethodPost:
		var h Hypridle
		if !decodeBody(w, r, &h) {
			return
		}
		h.Screensaver = clampInt(h.Screensaver, 30, 3600)
		h.Lock = clampInt(h.Lock, 60, 7200)
		h.Dpms = clampInt(h.Dpms, 120, 7200)
		txt, err := readFile(hypridleConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		n := 0
		txt = hypridleRe.ReplaceAllStringFunc(txt, func(s string) string {
			n++
			indent := s[:strings.Index(s, "timeout")]
			switch n {
			case 1:
				return fmt.Sprintf("%stimeout = %d", indent, h.Screensaver)
			case 2:
				return fmt.Sprintf("%stimeout = %d", indent, h.Lock)
			default:
				return fmt.Sprintf("%stimeout = %d", indent, h.Dpms)
			}
		})
		if n < 3 {
			jsonErr(w, "could not parse hypridle.conf timeouts", 500)
			return
		}
		if err := writeFile(hypridleConf, txt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		// If live config is NOT a symlink, mirror it so changes apply.
		live := expand("~/.config/hypr/hypridle.conf")
		if real, err := os.Readlink(live); err != nil && real == "" {
			_ = writeFile("~/.config/hypr/hypridle.conf", txt)
		}
		go restartHypridle()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

func restartHypridle() {
	cmd := exec.Command("bash", "-c", "omarchy-restart-hypridle >/dev/null 2>&1 || (pkill -x hypridle; sleep 0.5; (uwsm-app -- hypridle >/dev/null 2>&1 &))")
	_ = cmd.Run()
}

// ── Hyprland look & feel ──

type Hyprland struct {
	GapsIn     int `json:"gapsIn"`
	GapsOut    int `json:"gapsOut"`
	BorderSize int `json:"borderSize"`
	Rounding   int `json:"rounding"`
}

func settingValue(txt, key string) (int, bool) {
	re := regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(key) + `\s*=\s*(-?\d+)`)
	if m := re.FindStringSubmatch(txt); len(m) == 2 {
		v, err := strconv.Atoi(m[1])
		return v, err == nil
	}
	return 0, false
}

func replaceSetting(txt, key string, val int) string {
	re := regexp.MustCompile(`(?m)^(\s*` + regexp.QuoteMeta(key) + `\s*=\s*)(-?\d+)`)
	if re.MatchString(txt) {
		return re.ReplaceAllString(txt, "${1}"+strconv.Itoa(val))
	}
	return txt
}

func handleHyprland(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(looknfeelConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		h := Hyprland{GapsIn: 4, GapsOut: 10, BorderSize: 1, Rounding: 12}
		if v, ok := settingValue(txt, "gaps_in"); ok {
			h.GapsIn = v
		}
		if v, ok := settingValue(txt, "gaps_out"); ok {
			h.GapsOut = v
		}
		if v, ok := settingValue(txt, "border_size"); ok {
			h.BorderSize = v
		}
		if v, ok := settingValue(txt, "rounding"); ok {
			h.Rounding = v
		}
		jsonOK(w, h)

	case http.MethodPost:
		var h Hyprland
		if !decodeBody(w, r, &h) {
			return
		}
		h.GapsIn = clampInt(h.GapsIn, 0, 40)
		h.GapsOut = clampInt(h.GapsOut, 0, 60)
		h.BorderSize = clampInt(h.BorderSize, 0, 10)
		h.Rounding = clampInt(h.Rounding, 0, 32)
		txt, err := readFile(looknfeelConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		txt = replaceSetting(txt, "gaps_in", h.GapsIn)
		txt = replaceSetting(txt, "gaps_out", h.GapsOut)
		txt = replaceSetting(txt, "border_size", h.BorderSize)
		txt = replaceSetting(txt, "rounding", h.Rounding)
		if err := writeFile(looknfeelConf, txt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		live := expand("~/.config/hypr/looknfeel.conf")
		if real, err := os.Readlink(live); err != nil && real == "" {
			_ = writeFile("~/.config/hypr/looknfeel.conf", txt)
		}
		go func() { _ = exec.Command("hyprctl", "reload").Run() }()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Ghostty ──

type Ghostty struct {
	FontSize    int     `json:"fontSize"`
	FontFamily  string  `json:"fontFamily"`
	Opacity     float64 `json:"opacity"`
	Padding     int     `json:"padding"`
	CursorStyle string  `json:"cursorStyle"`
	Blur        int     `json:"blur"`
}

func handleGhostty(w http.ResponseWriter, r *http.Request) {
	const confPath = ghosttyConf
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(confPath)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		gs := Ghostty{FontSize: 13, FontFamily: "FiraCode Nerd Font", Opacity: 0.8, Padding: 12, CursorStyle: "block", Blur: 0}
		for _, line := range strings.Split(txt, "\n") {
			kv := strings.SplitN(strings.TrimSpace(line), "=", 2)
			if len(kv) != 2 {
				continue
			}
			key := strings.TrimSpace(kv[0])
			val := strings.Trim(strings.TrimSpace(kv[1]), `"`)
			switch key {
			case "font-size":
				if v, err := strconv.Atoi(val); err == nil {
					gs.FontSize = v
				}
			case "font-family":
				gs.FontFamily = val
			case "background-opacity":
				if v, err := strconv.ParseFloat(val, 64); err == nil {
					gs.Opacity = v
				}
			case "window-padding-x":
				if v, err := strconv.Atoi(val); err == nil {
					gs.Padding = v
				}
			case "cursor-style":
				if val == "block" || val == "bar" || val == "underline" {
					gs.CursorStyle = val
				}
			case "background-blur":
				if v, err := strconv.Atoi(val); err == nil {
					gs.Blur = v
				}
			}
		}
		jsonOK(w, gs)

	case http.MethodPost:
		var gs Ghostty
		if !decodeBody(w, r, &gs) {
			return
		}
		gs.FontSize = clampInt(gs.FontSize, 6, 32)
		gs.Padding = clampInt(gs.Padding, 0, 40)
		gs.Blur = clampInt(gs.Blur, 0, 40)
		gs.Opacity = clampFloat(gs.Opacity, 0.3, 1.0)
		gs.FontFamily = strings.TrimSpace(gs.FontFamily)
		if gs.FontFamily == "" {
			gs.FontFamily = "FiraCode Nerd Font"
		}
		switch gs.CursorStyle {
		case "bar", "underline":
		default:
			gs.CursorStyle = "block"
		}
		txt, err := readFile(confPath)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		set := map[string]func() string{
			"font-size":          func() string { return fmt.Sprintf("font-size = %d", gs.FontSize) },
			"font-family":        func() string { return fmt.Sprintf("font-family = %q", gs.FontFamily) },
			"background-opacity": func() string { return fmt.Sprintf("background-opacity = %.2f", gs.Opacity) },
			"window-padding-x":   func() string { return fmt.Sprintf("window-padding-x = %d", gs.Padding) },
			"cursor-style":       func() string { return fmt.Sprintf("cursor-style = %s", gs.CursorStyle) },
			"background-blur":    func() string { return fmt.Sprintf("background-blur = %d", gs.Blur) },
		}
		found := map[string]bool{}
		lines := strings.Split(txt, "\n")
		for i, line := range lines {
			kv := strings.SplitN(strings.TrimSpace(line), "=", 2)
			if len(kv) != 2 {
				continue
			}
			key := strings.TrimSpace(kv[0])
			if fn, ok := set[key]; ok && !found[key] {
				lines[i] = fn()
				found[key] = true
			}
		}
		newTxt := strings.Join(lines, "\n")
		if err := writeFile(confPath, newTxt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		_ = writeFile("~/.config/ghostty/config", newTxt)
		go func() { _ = exec.Command("bash", "-c", "pkill -SIGUSR2 -x ghostty || true").Run() }()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Matugen ──

type Matugen struct {
	Type     string  `json:"type"`
	Contrast float64 `json:"contrast"`
	Mode     string  `json:"mode"`
}

var validSchemes = map[string]bool{
	"scheme-content": true, "scheme-vibrant": true, "scheme-expressive": true,
	"scheme-tonal-spot": true, "scheme-fidelity": true, "scheme-fruit-salad": true,
	"scheme-rainbow": true, "scheme-monochrome": true, "scheme-neutral": true,
}

func handleMatugen(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(getThemeBin)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		m := Matugen{Type: "scheme-content", Contrast: 0.3, Mode: "dark"}
		if sm := regexp.MustCompile(`THEME_TYPE="([^"]+)"`).FindStringSubmatch(txt); len(sm) == 2 {
			m.Type = sm[1]
		}
		if sm := regexp.MustCompile(`CONTRAST="([^"]+)"`).FindStringSubmatch(txt); len(sm) == 2 {
			m.Contrast, _ = strconv.ParseFloat(sm[1], 64)
		}
		if sm := regexp.MustCompile(`MODE="([^"]+)"`).FindStringSubmatch(txt); len(sm) == 2 {
			m.Mode = sm[1]
		}
		jsonOK(w, m)

	case http.MethodPost:
		var m Matugen
		if !decodeBody(w, r, &m) {
			return
		}
		if !validSchemes[m.Type] {
			jsonErr(w, "unknown scheme type", 400)
			return
		}
		if m.Mode != "dark" && m.Mode != "light" {
			m.Mode = "dark"
		}
		m.Contrast = clampFloat(m.Contrast, -1, 1)
		txt, err := readFile(getThemeBin)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		txt = regexp.MustCompile(`THEME_TYPE="[^"]+"`).ReplaceAllString(txt, fmt.Sprintf(`THEME_TYPE=%q`, m.Type))
		txt = regexp.MustCompile(`CONTRAST="[^"]+"`).ReplaceAllString(txt, fmt.Sprintf(`CONTRAST="%g"`, m.Contrast))
		txt = regexp.MustCompile(`MODE="[^"]+"`).ReplaceAllString(txt, fmt.Sprintf(`MODE=%q`, m.Mode))
		if err := writeFile(getThemeBin, txt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		_ = writeFile("~/.local/bin/getTheme", txt)
		if mc, err := readFile(matugenConf); err == nil {
			mc = regexp.MustCompile(`contrast\s*=\s*-?[0-9.]+`).ReplaceAllString(mc, fmt.Sprintf("contrast = %g", m.Contrast))
			_ = writeFile(matugenConf, mc)
			_ = writeFile("~/.config/matugen/config.toml", mc)
		}
		go func() {
			_ = exec.Command("bash", "-c", expand("~/.local/bin/getTheme")+" >/tmp/getTheme.log 2>&1").Run()
			reapplyTweakNow()
		}()
		jsonOK(w, map[string]string{"status": "regenerating"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Wallpapers ──

func findWallpaper(name string) string {
	for _, d := range wallpaperDirs {
		p := filepath.Join(expand(d), name)
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	return ""
}

func handleWallpapers(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	var files []string
	seen := map[string]bool{}
	for _, d := range wallpaperDirs {
		entries, err := os.ReadDir(expand(d))
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			n := e.Name()
			lower := strings.ToLower(n)
			if strings.HasSuffix(lower, ".jpg") || strings.HasSuffix(lower, ".png") ||
				strings.HasSuffix(lower, ".jpeg") || strings.HasSuffix(lower, ".webp") {
				if !seen[n] {
					files = append(files, n)
					seen[n] = true
				}
			}
		}
	}
	cur := ""
	if link, err := os.Readlink(expand(wallpaperLink)); err == nil {
		cur = filepath.Base(link)
	}
	if files == nil {
		files = []string{}
	}
	jsonOK(w, map[string]interface{}{"wallpapers": files, "current": cur})
}

func handleWallpaperSet(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if !decodeBody(w, r, &req) {
		return
	}
	name := filepath.Base(req.Name) // prevent traversal
	if name == "." || name == "/" {
		jsonErr(w, "invalid wallpaper name", 400)
		return
	}
	found := findWallpaper(name)
	if found == "" {
		jsonErr(w, "wallpaper not found", 404)
		return
	}
	go func() {
		_ = exec.Command("bash", "-c", fmt.Sprintf("%s %q >/tmp/set-wallpaper.log 2>&1", expand("~/.local/bin/set-wallpaper"), found)).Run()
		reapplyTweakNow()
	}()
	jsonOK(w, map[string]string{"status": "changing", "path": found})
}

func handleWallpaperImage(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	name := filepath.Base(strings.TrimPrefix(r.URL.Path, "/wallpaper/"))
	if p := findWallpaper(name); p != "" {
		http.ServeFile(w, r, p)
		return
	}
	http.NotFound(w, r)
}

// ── Audio (PipeWire via wpctl) ──

type Audio struct {
	Volume int  `json:"volume"` // 0..100
	Muted  bool `json:"muted"`
}

func handleAudio(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		out, err := exec.Command("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@").Output()
		if err != nil {
			jsonErr(w, "wpctl unavailable", 500)
			return
		}
		a := Audio{}
		line := strings.TrimSpace(string(out))
		if sm := regexp.MustCompile(`Volume:\s*([0-9.]+)`).FindStringSubmatch(line); len(sm) == 2 {
			v, _ := strconv.ParseFloat(sm[1], 64)
			a.Volume = clampInt(int(v*100+0.5), 0, 150)
		}
		a.Muted = strings.Contains(line, "MUTED")
		jsonOK(w, a)

	case http.MethodPost:
		var a Audio
		if !decodeBody(w, r, &a) {
			return
		}
		a.Volume = clampInt(a.Volume, 0, 150)
		vol := fmt.Sprintf("%.2f", float64(a.Volume)/100)
		if err := exec.Command("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", vol).Run(); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		muteArg := "0"
		if a.Muted {
			muteArg = "1"
		}
		_ = exec.Command("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", muteArg).Run()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Brightness ──

type Brightness struct {
	Percent int `json:"percent"`
}

func handleBrightness(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		out, err := exec.Command("brightnessctl", "-m").Output()
		if err != nil {
			jsonErr(w, "brightnessctl unavailable", 500)
			return
		}
		b := Brightness{}
		if line := strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]; line != "" {
			f := strings.Split(line, ",")
			if len(f) >= 4 {
				b.Percent, _ = strconv.Atoi(strings.TrimSuffix(f[3], "%"))
			}
		}
		jsonOK(w, b)

	case http.MethodPost:
		var b Brightness
		if !decodeBody(w, r, &b) {
			return
		}
		b.Percent = clampInt(b.Percent, 1, 100)
		if err := exec.Command("brightnessctl", "set", strconv.Itoa(b.Percent)+"%").Run(); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Network ──

type Connection struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Device string `json:"device"`
}

type NetInfo struct {
	IP          string       `json:"ip"`
	Connections []Connection `json:"connections"`
	WifiSSID    string       `json:"wifiSsid,omitempty"`
	WifiSignal  int          `json:"wifiSignal,omitempty"`
}

func handleNetwork(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	info := NetInfo{Connections: []Connection{}}
	haveNmcli := true
	if _, err := exec.LookPath("nmcli"); err != nil {
		haveNmcli = false
	}
	if haveNmcli {
		if out, err := exec.Command("nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "con", "show", "--active").Output(); err == nil {
			for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
				f := strings.Split(line, ":")
				if len(f) >= 3 && f[0] != "" {
					info.Connections = append(info.Connections, Connection{Name: f[0], Type: f[1], Device: f[2]})
				}
			}
		}
		if out, err := exec.Command("nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "dev", "wifi", "--rescan", "no").Output(); err == nil {
			for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
				if strings.HasPrefix(line, "yes:") {
					f := strings.Split(strings.TrimPrefix(line, "yes:"), ":")
					if len(f) >= 2 {
						info.WifiSSID = f[0]
						info.WifiSignal, _ = strconv.Atoi(f[1])
					}
					break
				}
			}
		}
	} else if out, err := exec.Command("ip", "-brief", "address", "show").Output(); err == nil {
		// Fallback without NetworkManager: list interfaces that have addresses.
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			f := strings.Fields(line)
			// e.g. "wlan0 UP 192.168.1.42/24 ..." — skip loopback and down interfaces
			if len(f) >= 3 && f[0] != "lo" && (f[1] == "UP" || f[1] == "UNKNOWN") {
				info.Connections = append(info.Connections, Connection{Name: f[0], Type: "interface", Device: f[0]})
				for _, a := range f[2:] {
					if strings.Contains(a, ".") && info.IP == "" { // IPv4
						info.IP = strings.Split(a, "/")[0]
					}
				}
			}
		}
	}
	jsonOK(w, info)
}

// ── Monitors ──

type Monitor struct {
	Name           string   `json:"name"`
	Description    string   `json:"description"`
	Width          int      `json:"width"`
	Height         int      `json:"height"`
	Refresh        float64  `json:"refresh"`
	Scale          float64  `json:"scale"`
	Active         string   `json:"activeWorkspace"`
	Disabled       bool     `json:"disabled"`
	CurrentMode    string   `json:"currentMode"`
	AvailableModes []string `json:"availableModes"`
}

func handleMonitors(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	out, err := exec.Command("hyprctl", "-j", "monitors").Output()
	if err != nil {
		jsonErr(w, "hyprctl unavailable", 500)
		return
	}
	var raw []struct {
		Name        string  `json:"name"`
		Description string  `json:"description"`
		Width       int     `json:"width"`
		Height      int     `json:"height"`
		RefreshRate float64 `json:"refreshRate"`
		Scale       float64 `json:"scale"`
		ActiveWS    struct {
			ID   int    `json:"id"`
			Name string `json:"name"`
		} `json:"activeWorkspace"`
		Disabled       bool     `json:"disabled"`
		CurrentMode    string   `json:"currentMode"`
		AvailableModes []string `json:"availableModes"`
	}
	if err := json.Unmarshal(out, &raw); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	monitors := make([]Monitor, 0, len(raw))
	for _, m := range raw {
		monitors = append(monitors, Monitor{
			Name: m.Name, Description: m.Description,
			Width: m.Width, Height: m.Height,
			Refresh: m.RefreshRate, Scale: m.Scale,
			Active: m.ActiveWS.Name, Disabled: m.Disabled,
			CurrentMode: m.CurrentMode, AvailableModes: m.AvailableModes,
		})
	}
	jsonOK(w, monitors)
}

// handleMonitorSet persists a monitor= line into monitors.conf.
func handleMonitorSet(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Name  string  `json:"name"`
		Mode  string  `json:"mode"` // e.g. "1920x1080@60.00" or "preferred"
		Scale float64 `json:"scale"`
	}
	if !decodeBody(w, r, &req) {
		return
	}
	req.Name = filepath.Base(req.Name)
	req.Scale = clampFloat(req.Scale, 0.5, 3)
	if req.Mode == "" {
		req.Mode = "preferred"
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_.@\-]+$`).MatchString(req.Mode) {
		jsonErr(w, "invalid mode", 400)
		return
	}
	// Verify the connector exists.
	out, err := exec.Command("hyprctl", "-j", "monitors").Output()
	if err != nil || !strings.Contains(string(out), `"`+req.Name+`"`) {
		jsonErr(w, "unknown monitor", 400)
		return
	}
	line := fmt.Sprintf("monitor = %s, %s, auto, %g", req.Name, req.Mode, req.Scale)
	confPath := "~/dotfiles/.config/hypr/monitors.conf"
	txt, err := readFile(confPath)
	if err != nil {
		txt = ""
	}
	re := regexp.MustCompile(`(?m)^monitor\s*=\s*` + regexp.QuoteMeta(req.Name) + `\s*,.*$`)
	if re.MatchString(txt) {
		txt = re.ReplaceAllString(txt, line)
	} else {
		if txt != "" && !strings.HasSuffix(txt, "\n") {
			txt += "\n"
		}
		txt += line + "\n"
	}
	if err := writeFile(confPath, txt); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	live := expand("~/.config/hypr/monitors.conf")
	if real, err := os.Readlink(live); err != nil && real == "" {
		_ = writeFile("~/.config/hypr/monitors.conf", txt)
	}
	go func() { _ = exec.Command("hyprctl", "reload").Run() }()
	jsonOK(w, map[string]string{"status": "ok", "line": line})
}

// ── Do-not-disturb (swaync) ──

func handleDND(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		out, err := exec.Command("swaync-client", "-DD").Output()
		if err != nil {
			jsonErr(w, "swaync unavailable", 500)
			return
		}
		jsonOK(w, map[string]bool{"dnd": strings.Contains(strings.ToLower(string(out)), "true")})
	case http.MethodPost:
		if err := exec.Command("swaync-client", "-D").Run(); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		out, _ := exec.Command("swaync-client", "-DD").Output()
		jsonOK(w, map[string]bool{"dnd": strings.Contains(strings.ToLower(string(out)), "true")})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Bluetooth ──

func handleBluetooth(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	out, err := exec.Command("bluetoothctl", "show").Output()
	if err != nil {
		jsonOK(w, map[string]interface{}{"available": false})
		return
	}
	powered := strings.Contains(string(out), "Powered: yes")
	var devices []map[string]string
	if devs, err := exec.Command("bluetoothctl", "devices", "Connected").Output(); err == nil {
		for _, line := range strings.Split(strings.TrimSpace(string(devs)), "\n") {
			f := strings.Fields(line)
			if len(f) >= 3 {
				devices = append(devices, map[string]string{"mac": f[1], "name": strings.Join(f[2:], " ")})
			}
		}
	}
	if devices == nil {
		devices = []map[string]string{}
	}
	jsonOK(w, map[string]interface{}{"available": true, "powered": powered, "devices": devices})
}

// ── Power actions ──

func handlePower(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Action string `json:"action"`
	}
	if !decodeBody(w, r, &req) {
		return
	}
	var cmd *exec.Cmd
	switch req.Action {
	case "lock":
		cmd = exec.Command("loginctl", "lock-session")
	case "logout":
		cmd = exec.Command("hyprctl", "dispatch", "exit")
	case "suspend":
		cmd = exec.Command("systemctl", "suspend")
	case "reboot":
		cmd = exec.Command("systemctl", "reboot")
	case "shutdown":
		cmd = exec.Command("systemctl", "poweroff")
	default:
		jsonErr(w, "unknown action", 400)
		return
	}
	if err := cmd.Start(); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	jsonOK(w, map[string]string{"status": req.Action})
}

// ── Hyprland effects (looknfeel.conf blocks) ──

type Effects struct {
	BlurEnabled     bool    `json:"blurEnabled"`
	BlurSize        int     `json:"blurSize"`
	BlurPasses      int     `json:"blurPasses"`
	ShadowEnabled   bool    `json:"shadowEnabled"`
	ActiveOpacity   float64 `json:"activeOpacity"`
	InactiveOpacity float64 `json:"inactiveOpacity"`
	DimStrength     float64 `json:"dimStrength"`
	Animations      bool    `json:"animations"`
}

func boolValue(txt, key string) (bool, bool) {
	re := regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(key) + `\s*=\s*(true|false)`)
	if m := re.FindStringSubmatch(txt); len(m) == 2 {
		return m[1] == "true", true
	}
	return false, false
}

func replaceBool(txt, key string, val bool) string {
	re := regexp.MustCompile(`(?m)^(\s*` + regexp.QuoteMeta(key) + `\s*=\s*)(true|false)`)
	if re.MatchString(txt) {
		s := "false"
		if val {
			s = "true"
		}
		return re.ReplaceAllString(txt, "${1}"+s)
	}
	return txt
}

func floatValue(txt, key string) (float64, bool) {
	re := regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(key) + `\s*=\s*(-?[0-9.]+)`)
	if m := re.FindStringSubmatch(txt); len(m) == 2 {
		v, err := strconv.ParseFloat(m[1], 64)
		return v, err == nil
	}
	return 0, false
}

func replaceFloat(txt, key string, val float64) string {
	re := regexp.MustCompile(`(?m)^(\s*` + regexp.QuoteMeta(key) + `\s*=\s*)-?[0-9.]+`)
	if re.MatchString(txt) {
		return re.ReplaceAllString(txt, "${1}"+strconv.FormatFloat(val, 'g', -1, 64))
	}
	return txt
}

// editBlock applies fn to the contents of `name { ... }` (first match),
// handling nested braces (e.g. touchpad inside input).
func editBlock(txt, name string, fn func(string) string) string {
	loc := regexp.MustCompile(`\b` + name + `\s*\{`).FindStringIndex(txt)
	if loc == nil {
		return txt
	}
	i := loc[1] - 1 // index of '{'
	depth := 0
	j := i
	for ; j < len(txt); j++ {
		switch txt[j] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				inner := txt[i+1 : j]
				return txt[:i+1] + fn(inner) + txt[j:]
			}
		}
	}
	return txt
}

func handleEffects(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(looknfeelConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		e := Effects{
			BlurEnabled: true, BlurSize: 7, BlurPasses: 3,
			ShadowEnabled: true, ActiveOpacity: 0.95, InactiveOpacity: 0.86,
			DimStrength: 0.08, Animations: true,
		}
		editBlock(txt, "blur", func(inner string) string {
			if v, ok := boolValue(inner, "enabled"); ok {
				e.BlurEnabled = v
			}
			if v, ok := settingValue(inner, "size"); ok {
				e.BlurSize = v
			}
			if v, ok := settingValue(inner, "passes"); ok {
				e.BlurPasses = v
			}
			return inner
		})
		editBlock(txt, "shadow", func(inner string) string {
			if v, ok := boolValue(inner, "enabled"); ok {
				e.ShadowEnabled = v
			}
			return inner
		})
		if v, ok := floatValue(txt, "active_opacity"); ok {
			e.ActiveOpacity = v
		}
		if v, ok := floatValue(txt, "inactive_opacity"); ok {
			e.InactiveOpacity = v
		}
		if v, ok := floatValue(txt, "dim_strength"); ok {
			e.DimStrength = v
		}
		editBlock(txt, "animations", func(inner string) string {
			if v, ok := boolValue(inner, "enabled"); ok {
				e.Animations = v
			}
			return inner
		})
		jsonOK(w, e)

	case http.MethodPost:
		var e Effects
		if !decodeBody(w, r, &e) {
			return
		}
		e.BlurSize = clampInt(e.BlurSize, 1, 20)
		e.BlurPasses = clampInt(e.BlurPasses, 1, 8)
		e.ActiveOpacity = clampFloat(e.ActiveOpacity, 0.5, 1)
		e.InactiveOpacity = clampFloat(e.InactiveOpacity, 0.4, 1)
		e.DimStrength = clampFloat(e.DimStrength, 0, 0.9)
		txt, err := readFile(looknfeelConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		txt = editBlock(txt, "blur", func(inner string) string {
			inner = replaceBool(inner, "enabled", e.BlurEnabled)
			inner = replaceSetting(inner, "size", e.BlurSize)
			inner = replaceSetting(inner, "passes", e.BlurPasses)
			return inner
		})
		txt = editBlock(txt, "shadow", func(inner string) string {
			return replaceBool(inner, "enabled", e.ShadowEnabled)
		})
		txt = editBlock(txt, "animations", func(inner string) string {
			return replaceBool(inner, "enabled", e.Animations)
		})
		txt = replaceFloat(txt, "active_opacity", e.ActiveOpacity)
		txt = replaceFloat(txt, "inactive_opacity", e.InactiveOpacity)
		txt = replaceFloat(txt, "dim_strength", e.DimStrength)
		if err := writeFile(looknfeelConf, txt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		live := expand("~/.config/hypr/looknfeel.conf")
		if real, err := os.Readlink(live); err != nil && real == "" {
			_ = writeFile("~/.config/hypr/looknfeel.conf", txt)
		}
		go func() { _ = exec.Command("hyprctl", "reload").Run() }()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Power profile (TLP via pkexec) ──

type PowerProfile struct {
	Mode     string `json:"mode"`     // performance | balanced | power-saver
	Governor string `json:"governor"` // scaling_governor
	EPP      string `json:"epp"`      // energy_performance_preference
	Platform string `json:"platform,omitempty"`
}

func firstLine(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func readSys(path string) string { return firstLine(path) }

func readSysFloat(path string) float64 {
	v, _ := strconv.ParseFloat(firstLine(path), 64)
	return v
}

func detectPowerMode(governor, epp string) string {
	if governor == "performance" || epp == "performance" {
		return "performance"
	}
	if epp == "power" || (epp == "balance_power" && governor == "powersave") {
		return "power-saver"
	}
	return "balanced"
}

func powerModeStateFile() string { return home + "/.cache/omarchy-panel-power-mode" }

func readPowerModeState() string {
	s := strings.TrimSpace(firstLine(powerModeStateFile()))
	if s == "performance" || s == "balanced" || s == "power-saver" {
		return s
	}
	return ""
}

func handlePowerProfile(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		p := PowerProfile{
			Governor: firstLine("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
			EPP:      firstLine("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
			Platform: firstLine("/sys/firmware/acpi/platform_profile"),
		}
		// Trust the last mode the panel set (TLP's EPP values don't map 1:1
		// back to modes on this hardware); fall back to heuristics.
		if m := readPowerModeState(); m != "" {
			p.Mode = m
		} else {
			p.Mode = detectPowerMode(p.Governor, p.EPP)
		}
		jsonOK(w, p)

	case http.MethodPost:
		var req struct {
			Mode string `json:"mode"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		var tlpMode string
		switch req.Mode {
		case "performance":
			tlpMode = "performance"
		case "balanced":
			tlpMode = "balanced"
		case "power-saver":
			tlpMode = "power-saver"
		default:
			jsonErr(w, "unknown mode", 400)
			return
		}
		// Try passwordless sudo first, then pkexec (GUI polkit prompt).
		var cmd *exec.Cmd
		if exec.Command("sudo", "-n", "true").Run() == nil {
			cmd = exec.Command("sudo", "-n", "tlp", tlpMode)
		} else if _, err := exec.LookPath("pkexec"); err == nil {
			cmd = exec.Command("pkexec", "tlp", tlpMode)
		} else {
			jsonErr(w, "no privilege escalation available (need sudo -n or pkexec)", 500)
			return
		}
		if out, err := cmd.CombinedOutput(); err != nil {
			jsonErr(w, fmt.Sprintf("tlp %s failed: %s", tlpMode, strings.TrimSpace(string(out))), 500)
			return
		}
		p := PowerProfile{
			Governor: firstLine("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
			EPP:      firstLine("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
			Platform: firstLine("/sys/firmware/acpi/platform_profile"),
		}
		p.Mode = req.Mode
		_ = os.MkdirAll(home+"/.cache", 0755)
		_ = os.WriteFile(powerModeStateFile(), []byte(req.Mode), 0644)
		jsonOK(w, p)
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Input devices (input.conf) ──

type Input struct {
	KBLayout      string  `json:"kbLayout"`
	RepeatRate    int     `json:"repeatRate"`
	RepeatDelay   int     `json:"repeatDelay"`
	Numlock       bool    `json:"numlock"`
	NaturalScroll bool    `json:"naturalScroll"`
	ScrollFactor  float64 `json:"scrollFactor"`
}

const inputConf = "~/dotfiles/.config/hypr/input.conf"

func handleInput(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(inputConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		in := Input{KBLayout: "us", RepeatRate: 40, RepeatDelay: 600, Numlock: true, NaturalScroll: false, ScrollFactor: 1}
		editBlock(txt, "input", func(inner string) string {
			if m := regexp.MustCompile(`(?m)^\s*kb_layout\s*=\s*(\S+)`).FindStringSubmatch(inner); len(m) == 2 {
				in.KBLayout = m[1]
			}
			if v, ok := settingValue(inner, "repeat_rate"); ok {
				in.RepeatRate = v
			}
			if v, ok := settingValue(inner, "repeat_delay"); ok {
				in.RepeatDelay = v
			}
			if v, ok := boolValue(inner, "numlock_by_default"); ok {
				in.Numlock = v
			}
			if v, ok := boolValue(inner, "natural_scroll"); ok {
				in.NaturalScroll = v
			}
			if v, ok := floatValue(inner, "scroll_factor"); ok {
				in.ScrollFactor = v
			}
			return inner
		})
		jsonOK(w, in)

	case http.MethodPost:
		var in Input
		if !decodeBody(w, r, &in) {
			return
		}
		in.KBLayout = strings.TrimSpace(in.KBLayout)
		if !regexp.MustCompile(`^[a-zA-Z0-9,\-\_]*$`).MatchString(in.KBLayout) || len(in.KBLayout) > 20 {
			jsonErr(w, "invalid keyboard layout", 400)
			return
		}
		in.RepeatRate = clampInt(in.RepeatRate, 10, 120)
		in.RepeatDelay = clampInt(in.RepeatDelay, 150, 1500)
		in.ScrollFactor = clampFloat(in.ScrollFactor, 0.1, 5)
		txt, err := readFile(inputConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		apply := func(inner string) string {
			inner = regexp.MustCompile(`(?m)^(\s*kb_layout\s*=\s*).*$`).ReplaceAllString(inner, "${1}"+in.KBLayout)
			inner = replaceSetting(inner, "repeat_rate", in.RepeatRate)
			inner = replaceSetting(inner, "repeat_delay", in.RepeatDelay)
			inner = replaceBool(inner, "numlock_by_default", in.Numlock)
			// natural_scroll lives inside touchpad sub-block
			inner = editBlock(inner, "touchpad", func(tp string) string {
				return replaceBool(tp, "natural_scroll", in.NaturalScroll)
			})
			inner = replaceFloat(inner, "scroll_factor", in.ScrollFactor)
			return inner
		}
		txt = editBlock(txt, "input", apply)
		if err := writeFile(inputConf, txt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		live := expand("~/.config/hypr/input.conf")
		if real, err := os.Readlink(live); err != nil && real == "" {
			_ = writeFile("~/.config/hypr/input.conf", txt)
		}
		go func() { _ = exec.Command("hyprctl", "reload").Run() }()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Notifications (mako config) ──

type Mako struct {
	Timeout    int `json:"timeout"`
	MaxVisible int `json:"maxVisible"`
	Width      int `json:"width"`
	Height     int `json:"height"`
	Radius     int `json:"radius"`
}

const makoConf = "~/dotfiles/.config/mako/config"

func handleMako(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(makoConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		m := Mako{Timeout: 5000, MaxVisible: 3, Width: 400, Height: 140, Radius: 12}
		if mm := regexp.MustCompile(`(?m)^\s*default-timeout\s*=\s*(\d+)`).FindStringSubmatch(txt); len(mm) == 2 {
			m.Timeout, _ = strconv.Atoi(mm[1])
		}
		if mm := regexp.MustCompile(`(?m)^\s*max-visible\s*=\s*(\d+)`).FindStringSubmatch(txt); len(mm) == 2 {
			m.MaxVisible, _ = strconv.Atoi(mm[1])
		}
		if mm := regexp.MustCompile(`(?m)^\s*width\s*=\s*(\d+)`).FindStringSubmatch(txt); len(mm) == 2 {
			m.Width, _ = strconv.Atoi(mm[1])
		}
		if mm := regexp.MustCompile(`(?m)^\s*height\s*=\s*(\d+)`).FindStringSubmatch(txt); len(mm) == 2 {
			m.Height, _ = strconv.Atoi(mm[1])
		}
		if mm := regexp.MustCompile(`(?m)^\s*border-radius\s*=\s*(\d+)`).FindStringSubmatch(txt); len(mm) == 2 {
			m.Radius, _ = strconv.Atoi(mm[1])
		}
		jsonOK(w, m)

	case http.MethodPost:
		var m Mako
		if !decodeBody(w, r, &m) {
			return
		}
		m.Timeout = clampInt(m.Timeout, 0, 30000)
		m.MaxVisible = clampInt(m.MaxVisible, 1, 20)
		m.Width = clampInt(m.Width, 150, 800)
		m.Height = clampInt(m.Height, 50, 400)
		m.Radius = clampInt(m.Radius, 0, 40)
		txt, err := readFile(makoConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		// Only the top-level default-timeout (first match before section headers).
		replaced := false
		lines := strings.Split(txt, "\n")
		for i, line := range lines {
			t := strings.TrimSpace(line)
			if strings.HasPrefix(t, "[") { // section header — stop editing top-level keys
				break
			}
			switch {
			case !replaced && strings.HasPrefix(t, "default-timeout"):
				lines[i] = fmt.Sprintf("default-timeout=%d", m.Timeout)
				replaced = true
			case strings.HasPrefix(t, "max-visible"):
				lines[i] = fmt.Sprintf("max-visible=%d", m.MaxVisible)
			case strings.HasPrefix(t, "width="):
				lines[i] = fmt.Sprintf("width=%d", m.Width)
			case strings.HasPrefix(t, "height="):
				lines[i] = fmt.Sprintf("height=%d", m.Height)
			case strings.HasPrefix(t, "border-radius="):
				lines[i] = fmt.Sprintf("border-radius=%d", m.Radius)
			}
		}
		newTxt := strings.Join(lines, "\n")
		if err := writeFile(makoConf, newTxt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		_ = writeFile("~/.config/mako/config", newTxt)
		go func() { _ = exec.Command("bash", "-c", "pgrep -x mako >/dev/null && makoctl reload").Run() }()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Waybar (config.jsonc position/height) ──

type Waybar struct {
	Position string `json:"position"` // top | bottom | left | right
	Height   int    `json:"height"`
}

const waybarConf = "~/dotfiles/.config/waybar/config.jsonc"

func handleWaybar(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		txt, err := readFile(waybarConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		wb := Waybar{Position: "top", Height: 34}
		if mm := regexp.MustCompile(`"position"\s*:\s*"(top|bottom|left|right)"`).FindStringSubmatch(txt); len(mm) == 2 {
			wb.Position = mm[1]
		}
		if mm := regexp.MustCompile(`"height"\s*:\s*(\d+)`).FindStringSubmatch(txt); len(mm) == 2 {
			wb.Height, _ = strconv.Atoi(mm[1])
		}
		jsonOK(w, wb)

	case http.MethodPost:
		var wb Waybar
		if !decodeBody(w, r, &wb) {
			return
		}
		switch wb.Position {
		case "top", "bottom", "left", "right":
		default:
			wb.Position = "top"
		}
		wb.Height = clampInt(wb.Height, 16, 80)
		txt, err := readFile(waybarConf)
		if err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		txt = regexp.MustCompile(`("position"\s*:\s*)"(?:top|bottom|left|right)"`).ReplaceAllString(txt, `${1}"`+wb.Position+`"`)
		txt = regexp.MustCompile(`("height"\s*:\s*)\d+`).ReplaceAllString(txt, `${1}`+strconv.Itoa(wb.Height))
		if err := writeFile(waybarConf, txt); err != nil {
			jsonErr(w, err.Error(), 500)
			return
		}
		go func() { _ = exec.Command("bash", "-c", "omarchy-restart-waybar >/dev/null 2>&1").Run() }()
		jsonOK(w, map[string]string{"status": "ok"})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Night light (hyprsunset process toggle) ──

func handleNightlight(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		running := exec.Command("pgrep", "-x", "hyprsunset").Run() == nil
		temp := 3500
		if b, err := os.ReadFile("/tmp/hyprsunset-temp"); err == nil {
			if v, err := strconv.Atoi(strings.TrimSpace(string(b))); err == nil && v >= 1000 && v <= 10000 {
				temp = v
			}
		}
		jsonOK(w, map[string]interface{}{"on": running, "temperature": temp})

	case http.MethodPost:
		var req struct {
			On          bool `json:"on"`
			Temperature int  `json:"temperature"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		req.Temperature = clampInt(req.Temperature, 1000, 10000)
		_ = exec.Command("pkill", "-x", "hyprsunset").Run()
		time.Sleep(300 * time.Millisecond)
		if req.On {
			_ = os.WriteFile("/tmp/hyprsunset-temp", []byte(strconv.Itoa(req.Temperature)), 0o644)
			cmd := exec.Command("setsid", "hyprsunset", "-t", strconv.Itoa(req.Temperature))
			if err := cmd.Start(); err != nil {
				jsonErr(w, err.Error(), 500)
				return
			}
			go func() { _ = cmd.Wait() }()
		}
		jsonOK(w, map[string]bool{"on": req.On})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

// ── Reload actions ──

func handleReload(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	target := r.URL.Query().Get("target")
	var cmd *exec.Cmd
	switch target {
	case "hyprland":
		cmd = exec.Command("hyprctl", "reload")
	case "waybar":
		cmd = exec.Command("bash", "-c", "omarchy-restart-waybar >/dev/null 2>&1")
	case "hypridle":
		go restartHypridle()
		jsonOK(w, map[string]string{"status": "restarting", "target": target})
		return
	case "mako":
		cmd = exec.Command("bash", "-c", "makoctl reload >/dev/null 2>&1")
	case "matugen":
		cmd = exec.Command("bash", "-c", expand("~/.local/bin/getTheme")+" >/tmp/getTheme.log 2>&1")
	case "swaync":
		cmd = exec.Command("bash", "-c", "systemctl --user restart swaync 2>/dev/null || (pkill -x swaync; sleep 0.5; (uwsm-app -- swaync >/dev/null 2>&1 &))")
	default:
		jsonErr(w, "unknown target", 400)
		return
	}
	if err := cmd.Run(); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	if target == "matugen" {
		reapplyTweakNow()
	}
	jsonOK(w, map[string]string{"status": "ok", "target": target})
}

// ── Fonts: download + apply system-wide ──

type FontEntry struct {
	Name      string `json:"name"`
	Family    string `json:"family"` // family name after install
	URL       string `json:"url"`
	Kind      string `json:"kind"` // mono | sans
	Installed bool   `json:"installed"`
}

var fontCatalog = []FontEntry{
	{Name: "JetBrains Mono NF", Family: "JetBrainsMono Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip", Kind: "mono"},
	{Name: "Fira Code NF", Family: "FiraCode Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip", Kind: "mono"},
	{Name: "Caskaydia Cove NF", Family: "CaskaydiaCove Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip", Kind: "mono"},
	{Name: "Hack NF", Family: "Hack Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip", Kind: "mono"},
	{Name: "Iosevka NF", Family: "Iosevka Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip", Kind: "mono"},
	{Name: "Victor Mono NF", Family: "VictorMono Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/VictorMono.zip", Kind: "mono"},
	{Name: "Mononoki NF", Family: "Mononoki Nerd Font", URL: "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Mononoki.zip", Kind: "mono"},
	{Name: "Inter", Family: "Inter", URL: "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf", Kind: "sans"},
	{Name: "Space Grotesk", Family: "Space Grotesk", URL: "https://github.com/google/fonts/raw/main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf", Kind: "sans"},
	{Name: "Outfit", Family: "Outfit", URL: "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit%5Bwght%5D.ttf", Kind: "sans"},
	{Name: "Sora", Family: "Sora", URL: "https://github.com/google/fonts/raw/main/ofl/sora/Sora%5Bwght%5D.ttf", Kind: "sans"},
}

func installedFontFamilies() []string {
	out, err := exec.Command("fc-list", ":", "family").Output()
	if err != nil {
		return []string{}
	}
	seen := map[string]bool{}
	families := []string{}
	for _, line := range strings.Split(string(out), "\n") {
		for _, f := range strings.Split(strings.TrimSpace(line), ",") {
			f = strings.TrimSpace(f)
			if f != "" && !seen[f] {
				seen[f] = true
				families = append(families, f)
			}
		}
	}
	sort.Slice(families, func(i, j int) bool { return families[i] < families[j] })
	return families
}

func currentWaybarFont() string {
	data, err := os.ReadFile(home + "/dotfiles/.config/waybar/style.css")
	if err != nil {
		return ""
	}
	m := regexp.MustCompile(`font-family:\s*'([^']+)';`).FindStringSubmatch(string(data))
	if m != nil {
		return m[1]
	}
	return ""
}

// handleFontFile resolves a font family via fontconfig and serves the file
// so the browser can render real type specimens.
func handleFontFile(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	family := sanitizeField(r.URL.Query().Get("family"))
	if family == "" || strings.ContainsAny(family, "/\\") {
		jsonErr(w, "invalid family", 400)
		return
	}
	out, err := exec.Command("fc-match", "-f", "%{file}", family+":charset=41").Output()
	if err != nil || len(out) == 0 {
		jsonErr(w, "font not found", 404)
		return
	}
	path := strings.TrimSpace(string(out))
	// only serve real font files from sane locations
	if !strings.HasSuffix(strings.ToLower(path), ".ttf") && !strings.HasSuffix(strings.ToLower(path), ".otf") {
		jsonErr(w, "not a font file", 400)
		return
	}
	w.Header().Set("Cache-Control", "max-age=86400")
	http.ServeFile(w, r, path)
}

func handleFonts(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		installed := installedFontFamilies()
		set := map[string]bool{}
		for _, f := range installed {
			set[f] = true
		}
		catalog := make([]FontEntry, len(fontCatalog))
		copy(catalog, fontCatalog)
		for i := range catalog {
			catalog[i].Installed = set[catalog[i].Family]
		}
		gtk := strings.TrimSpace(firstLineRun("gsettings", "get", "org.gnome.desktop.interface", "font-name"))
		gtk = strings.Trim(strings.TrimSuffix(gtk, ","), "'")
		jsonOK(w, map[string]interface{}{
			"installed": installed,
			"catalog":   catalog,
			"current": map[string]string{
				"terminal":   regexFirst(readFileStr(ghosttyConf), `(?m)^\s*font-family\s*=\s*"?(.*?)"?\s*$`),
				"bar":        currentWaybarFont(),
				"lockscreen": regexFirst(readFileStr(hyprlockConf), `(?m)^\s*font_family\s*=\s*(.+?)\s*$`),
				"gtk":        gtk,
			},
		})
	case http.MethodPost:
		var req struct {
			Action  string   `json:"action"`  // install | apply
			URL     string   `json:"url"`     // custom font url (install)
			Family  string   `json:"family"`  // apply
			Targets []string `json:"targets"` // terminal bar lockscreen gtk
		}
		if !decodeBody(w, r, &req) {
			return
		}
		switch req.Action {
		case "install":
			url := req.URL
			if url == "" {
				jsonErr(w, "url required", 400)
				return
			}
			if !strings.HasPrefix(url, "https://") {
				jsonErr(w, "only https urls allowed", 400)
				return
			}
			low := strings.ToLower(url)
			if !strings.HasSuffix(low, ".zip") && !strings.HasSuffix(low, ".ttf") && !strings.HasSuffix(low, ".otf") {
				jsonErr(w, "url must point to .zip, .ttf or .otf", 400)
				return
			}
			if err := downloadFont(url); err != nil {
				jsonErr(w, err.Error(), 500)
				return
			}
			exec.Command("fc-cache", "-f").Run()
			jsonOK(w, map[string]string{"status": "installed"})
		case "apply":
			req.Family = sanitizeField(req.Family)
			if req.Family == "" || strings.ContainsAny(req.Family, "\"'") {
				jsonErr(w, "valid family required", 400)
				return
			}
			found := false
			for _, f := range installedFontFamilies() {
				if f == req.Family {
					found = true
					break
				}
			}
			if !found {
				jsonErr(w, "font not installed: "+req.Family, 404)
				return
			}
			results := map[string]string{}
			for _, t := range req.Targets {
				switch t {
				case "terminal":
					if err := replaceLines(ghosttyConf, regexp.MustCompile(`(?m)^\s*font-family\s*=.*$`), "font-family = \""+req.Family+"\""); err != nil {
						results[t] = err.Error()
						continue
					}
					go exec.Command("bash", "-c", "pkill -SIGUSR2 -x ghostty || true").Run()
					results[t] = "ok"
				case "bar":
					path := home + "/dotfiles/.config/waybar/style.css"
					data, err := os.ReadFile(path)
					if err != nil {
						results[t] = err.Error()
						continue
					}
					old := currentWaybarFont()
					re := regexp.MustCompile(`(font-family:\s*')` + regexp.QuoteMeta(old) + `(';)`)
					out := re.ReplaceAllString(string(data), "${1}"+req.Family+"${2}")
					if err := os.WriteFile(path, []byte(out), 0644); err != nil {
						results[t] = err.Error()
						continue
					}
					go exec.Command("bash", "-c", "omarchy-restart-waybar >/dev/null 2>&1").Run()
					results[t] = "ok"
				case "lockscreen":
					if err := replaceLines(hyprlockConf, regexp.MustCompile(`(?m)^\s*font_family\s*=.*$`), "font_family = "+req.Family); err != nil {
						results[t] = err.Error()
						continue
					}
					results[t] = "ok"
				case "gtk":
					if out, err := exec.Command("gsettings", "set", "org.gnome.desktop.interface", "font-name", req.Family+" 11").CombinedOutput(); err != nil {
						results[t] = strings.TrimSpace(string(out))
						continue
					}
					results[t] = "ok"
				default:
					results[t] = "unknown target"
				}
			}
			jsonOK(w, map[string]interface{}{"status": "applied", "results": results})
		default:
			jsonErr(w, "action must be install or apply", 400)
		}
	default:
		jsonErr(w, "method not allowed", 405)
	}
}

func readFileStr(path string) string {
	b, err := os.ReadFile(expand(path))
	if err != nil {
		return ""
	}
	return string(b)
}

func regexFirst(s, pattern string) string {
	m := regexp.MustCompile(pattern).FindStringSubmatch(s)
	if len(m) > 1 {
		return m[1]
	}
	return ""
}

// replaceLines replaces every line matching re with replacement in path (~/-aware).
func replaceLines(path string, re *regexp.Regexp, replacement string) error {
	p := expand(path)
	data, err := os.ReadFile(p)
	if err != nil {
		return err
	}
	out := re.ReplaceAllStringFunc(string(data), func(string) string { return replacement })
	return os.WriteFile(p, []byte(out), 0644)
}

const maxFontDownload = 300 << 20 // 300 MB

func downloadFont(url string) error {
	client := &http.Client{Timeout: 10 * time.Minute}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
	}
	if resp.ContentLength > maxFontDownload {
		return fmt.Errorf("file too large")
	}
	tmp, err := os.CreateTemp("", "panelfont-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	n, err := io.Copy(tmp, io.LimitReader(resp.Body, maxFontDownload+1))
	tmp.Close()
	if err != nil {
		return err
	}
	if n >= maxFontDownload {
		return fmt.Errorf("file too large")
	}

	fontsDir := home + "/.local/share/fonts"
	base := strings.TrimSuffix(filepath.Base(url), filepath.Ext(url))
	safe := sanitizeField(base)
	if safe == "" {
		safe = "custom"
	}
	destDir := filepath.Join(fontsDir, safe)
	os.MkdirAll(destDir, 0755)

	if strings.HasSuffix(low(url), ".zip") {
		zr, err := zip.OpenReader(tmp.Name())
		if err != nil {
			return err
		}
		defer zr.Close()
		count := 0
		for _, f := range zr.File {
			ext := strings.ToLower(filepath.Ext(f.Name))
			if ext != ".ttf" && ext != ".otf" {
				continue
			}
			src, err := f.Open()
			if err != nil {
				continue
			}
			dstPath := filepath.Join(destDir, filepath.Base(f.Name))
			dst, err := os.Create(dstPath)
			if err != nil {
				src.Close()
				continue
			}
			io.Copy(dst, src)
			dst.Close()
			src.Close()
			count++
		}
		if count == 0 {
			return fmt.Errorf("no ttf/otf files found in zip")
		}
	} else {
		src, err := os.Open(tmp.Name())
		if err != nil {
			return err
		}
		defer src.Close()
		dst, err := os.Create(filepath.Join(destDir, filepath.Base(url)))
		if err != nil {
			return err
		}
		defer dst.Close()
		io.Copy(dst, src)
	}
	return nil
}

func low(s string) string { return strings.ToLower(s) }

func firstLineRun(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// ── Recent logs (dashboard live feed) ──

func handleLogsRecent(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	n := 12
	if v, err := strconv.Atoi(r.URL.Query().Get("n")); err == nil && v > 0 && v <= 100 {
		n = v
	}
	out, err := exec.Command("journalctl", "-n", strconv.Itoa(n), "--no-pager", "-o", "short").Output()
	if err != nil {
		jsonOK(w, []string{})
		return
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	jsonOK(w, lines)
}

// ── Appearance: hue / saturation / brightness tweak over generated theme ──

type Tweak struct {
	Hue    float64 `json:"hue"`    // -180..180 degrees
	Sat    float64 `json:"sat"`    // 0..2 multiplier
	Bright float64 `json:"bright"` // 0.5..1.5 multiplier
}

func tweakStatePath() string { return home + "/.config/omarchy/current/theme/tweak.json" }

func readTweak() Tweak {
	var t Tweak
	if b, err := os.ReadFile(tweakStatePath()); err == nil {
		_ = json.Unmarshal(b, &t)
	}
	if t.Sat == 0 {
		t.Sat = 1
	}
	if t.Bright == 0 {
		t.Bright = 1
	}
	return t
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func handleAppearance(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		t := readTweak()
		pal := map[string]interface{}{}
		if b, err := os.ReadFile(expand(themeJSON)); err == nil {
			_ = json.Unmarshal(shiftHexInJSON(b, t), &pal)
		}
		jsonOK(w, map[string]interface{}{"tweak": t, "palette": pal})
	case http.MethodPost:
		var req struct {
			Hue    float64 `json:"hue"`
			Sat    float64 `json:"sat"`
			Bright float64 `json:"bright"`
			Reset  bool    `json:"reset"`
		}
		if !decodeBody(w, r, &req) {
			return
		}
		req.Hue = clamp(req.Hue, -180, 180)
		req.Sat = clamp(req.Sat, 0, 2)
		req.Bright = clamp(req.Bright, 0.5, 1.5)
		t := Tweak{Hue: req.Hue, Sat: req.Sat, Bright: req.Bright}

		// 1. regenerate pristine outputs from current wallpaper
		wall := ""
		if link, err := os.Readlink(expand(wallpaperLink)); err == nil {
			wall = link
		}
		if wall != "" {
			exec.Command(expand(getThemeBin), wall).Run()
		}
		// 2. apply shift to all generated theme files + a few outside it
		if !req.Reset && (t.Hue != 0 || t.Sat != 1 || t.Bright != 1) {
			shiftThemeDir(t)
		}
		// 3. persist state
		if req.Reset || (t.Hue == 0 && t.Sat == 1 && t.Bright == 1) {
			os.Remove(tweakStatePath())
			t = Tweak{Hue: 0, Sat: 1, Bright: 1}
		} else if b, err := json.Marshal(t); err == nil {
			os.WriteFile(tweakStatePath(), b, 0644)
		}
		// 4. reload visual apps
		go exec.Command("bash", "-c", "omarchy-restart-waybar >/dev/null 2>&1; pkill -SIGUSR2 -x ghostty || true; pgrep -x swaync >/dev/null && swaync-client --reload-css >/dev/null 2>&1; true").Run()
		jsonOK(w, map[string]interface{}{"status": "applied", "tweak": t})
	default:
		requireMethod(w, r, http.MethodGet, http.MethodPost)
	}
}

func themeExtraFiles() []string {
	return []string{
		home + "/.config/waybar/colors.css",
		home + "/.config/swaync/colors.css",
		// swaync colors.css is a symlink into dotfiles — resolve and shift the target too
		expand("~/.config/swaync/colors.css"),
		home + "/.config/rofi/colors.rasi",
		home + "/.config/zed/themes/matugen.json",
		home + "/dotfiles/.config/rofi/colors.rasi",
		home + "/dotfiles/.config/waybar/colors.css",
	}
}

func shiftThemeDir(t Tweak) {
	entries, err := os.ReadDir(expand("~/.config/omarchy/current/theme"))
	if err == nil {
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			name := e.Name()
			ext := strings.ToLower(filepath.Ext(name))
			if ext != ".css" && ext != ".conf" && ext != ".json" && ext != ".toml" && ext != ".lua" &&
				ext != ".rasi" && ext != ".ini" && ext != ".theme" && name != "cava_theme" {
				continue
			}
			p := filepath.Join(expand("~/.config/omarchy/current/theme"), name)
			shiftHexInFile(p, t)
		}
	}
	for _, p := range themeExtraFiles() {
		shiftHexInFile(p, t)
	}
}

// reapplyTweakNow re-applies the stored color tweak immediately after a
// getTheme run has finished, so the tweak survives wallpaper/matugen changes.
func reapplyTweakNow() {
	t := readTweak()
	if t.Hue == 0 && t.Sat == 1 && t.Bright == 1 {
		return
	}
	shiftThemeDir(t)
	exec.Command("bash", "-c", "omarchy-restart-waybar >/dev/null 2>&1; pkill -SIGUSR2 -x ghostty || true; true").Run()
}

var hexRe = regexp.MustCompile(`#[0-9a-fA-F]{6}\b`)

func shiftHexInFile(path string, t Tweak) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	out := hexRe.ReplaceAllStringFunc(string(data), func(h string) string { return shiftHex(h, t) })
	os.WriteFile(path, []byte(out), 0644)
}

// shiftHexInJSON shifts colors inside raw JSON bytes and returns shifted bytes.
func shiftHexInJSON(data []byte, t Tweak) []byte {
	return []byte(hexRe.ReplaceAllStringFunc(string(data), func(h string) string { return shiftHex(h, t) }))
}

func shiftHex(hex string, t Tweak) string {
	r, _ := strconv.ParseUint(hex[1:3], 16, 8)
	g, _ := strconv.ParseUint(hex[3:5], 16, 8)
	b, _ := strconv.ParseUint(hex[5:7], 16, 8)
	h, s, l := rgbToHsl(float64(r)/255, float64(g)/255, float64(b)/255)
	h = math.Mod(h+t.Hue+360, 360)
	s = clamp(s*t.Sat, 0, 1)
	l = clamp(l*t.Bright, 0, 1)
	r2, g2, b2 := hslToRgb(h, s, l)
	to := func(v float64) string {
		c := int(math.Round(v * 255))
		return fmt.Sprintf("%02x", c)
	}
	return "#" + to(r2) + to(g2) + to(b2)
}

func rgbToHsl(r, g, b float64) (h, s, l float64) {
	mx, mn := math.Max(r, math.Max(g, b)), math.Min(r, math.Min(g, b))
	l = (mx + mn) / 2
	if mx == mn {
		return 0, 0, l
	}
	d := mx - mn
	if l > 0.5 {
		s = d / (2 - mx - mn)
	} else {
		s = d / (mx + mn)
	}
	switch mx {
	case r:
		h = (g - b) / d
		if g < b {
			h += 6
		}
	case g:
		h = (b-r)/d + 2
	default:
		h = (r-g)/d + 4
	}
	return h * 60, s, l
}

func hslToRgb(h, s, l float64) (r, g, b float64) {
	if s == 0 {
		return l, l, l
	}
	var q float64
	if l < 0.5 {
		q = l * (1 + s)
	} else {
		q = l + s - l*s
	}
	p := 2*l - q
	hue := func(t float64) float64 {
		if t < 0 {
			t++
		}
		if t > 1 {
			t--
		}
		switch {
		case t < 1.0/6:
			return p + (q-p)*6*t
		case t < 0.5:
			return q
		case t < 2.0/3:
			return p + (q-p)*(2.0/3-t)*6
		default:
			return p
		}
	}
	return hue(h/360 + 1.0/3), hue(h / 360), hue(h/360 - 1.0/3)
}
