.pragma library

// ── shell motion style ────────────────────────────────────────────────
// Change this one word to swap the whole shell's motion language:
//   "magnet"  — the Magnet demo: quick, magnetic, small 2° twist.
//   "apple"   — soft Apple-like settle: no visible overshoot on panels.
//   "bloom"   — the big 0.08-scale Bloom entrance with a long spring.
// Reload quickshell after changing it.
var style = "magnet"

// Every preset exposes the same names, so no QML changes are needed when
// swapping. Durations are milliseconds; curves are cubic-bezier controls.
var presets = {
    magnet: {
        out:    [0.32, 0.72, 0, 1],
        spring: [0.33, 1.12, 0.58, 1],
        soft:   [0.34, 1.06, 0.64, 1],
        snap:   [0.22, 0.95, 0.36, 1.03],
        move:   [0.22, 0.9, 0.25, 1],
        fast: 130, normal: 180, slow: 240,
        panel: 260, close: 170, anchor: 250, row: 240,
        rowDelay: 0, rowStagger: 8, stagger: 18,
        panelScale: 0.98, panelRotate: 0,
        anchorScale: 0.98, anchorRotate: 0,
        islandSpring: 2.8, islandDamping: 0.9, islandMass: 1.0, islandEpsilon: 0.001
    },
    apple: {
        out:    [0.25, 0.1, 0.25, 1],
        spring: [0.22, 1.0, 0.36, 1.0],
        soft:   [0.25, 0.8, 0.35, 1.0],
        snap:   [0.2, 0.8, 0.2, 1.0],
        move:   [0.25, 0.1, 0.25, 1],
        fast: 120, normal: 200, slow: 260,
        panel: 300, close: 180, anchor: 300, row: 260,
        rowDelay: 40, rowStagger: 18, stagger: 24,
        panelScale: 0.55, panelRotate: 0,
        anchorScale: 0.55, anchorRotate: 0,
        islandSpring: 2.8, islandDamping: 0.7, islandMass: 1.0, islandEpsilon: 0.001
    },
    bloom: {
        out:    [0.32, 0.72, 0, 1],
        spring: [0.34, 1.35, 0.64, 1],
        soft:   [0.34, 1.15, 0.64, 1],
        snap:   [0.2, 0.9, 0.3, 1.12],
        move:   [0.2, 0.8, 0.2, 1],
        fast: 160, normal: 240, slow: 340,
        panel: 520, close: 240, anchor: 400, row: 460,
        rowDelay: 90, rowStagger: 30, stagger: 48,
        panelScale: 0.08, panelRotate: -8,
        anchorScale: 0.4, anchorRotate: 2,
        islandSpring: 2.0, islandDamping: 0.42, islandMass: 1.0, islandEpsilon: 0.001
    }
}

var p = presets[style] || presets.magnet

var out = p.out
var spring = p.spring
var soft = p.soft
var snap = p.snap
var move = p.move

var fast = p.fast
var normal = p.normal
var slow = p.slow
var panel = p.panel
var close = p.close
var anchor = p.anchor
var row = p.row

var rowDelay = p.rowDelay
var rowStagger = p.rowStagger
var stagger = p.stagger

var panelScale = p.panelScale
var panelRotate = p.panelRotate
var anchorScale = p.anchorScale
var anchorRotate = p.anchorRotate

var islandSpring = p.islandSpring
var islandDamping = p.islandDamping
var islandMass = p.islandMass
var islandEpsilon = p.islandEpsilon
