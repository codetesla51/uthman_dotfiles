/* uthmansArch/control-plane — app.js */
const $ = s => document.querySelector(s);
const $$ = s => document.querySelectorAll(s);

/* ── Toasts ── */
function toast(msg, type = 'ok') {
  const el = document.createElement('div');
  el.className = 'toast ' + type;
  const icon = type === 'err' ? 'ph-warning-circle' : type === 'info' ? 'ph-info' : 'ph-check-circle';
  el.innerHTML = `<i class="ph ${icon}"></i><span></span>`;
  el.querySelector('span').textContent = msg;
  $('#toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 200); }, 3200);
}
function flash(id, msg, ok = true) {
  const el = $(id);
  if (el) {
    el.textContent = msg;
    el.classList.toggle('err', !ok);
    setTimeout(() => { el.textContent = ''; }, 4000);
  }
  toast(msg, ok ? 'ok' : 'err');
}

/* ── Tabs ── */
function setTab(name) {
  $$('.nav li, .top-nav .nav-item').forEach(x => x.classList.toggle('active', x.dataset.tab === name));
  $$('.tab').forEach(t => t.classList.remove('active'));
  const tab = $('#tab-' + name);
  if (tab) tab.classList.add('active');
  if (name === 'idle') loadHypridle();
  if (name === 'power') { loadPowerProfile(); }
  if (name === 'appearance') { loadMatugen(); loadTheme(); loadWallpapers(); }
  if (name === 'terminal') loadGhostty();
  if (name === 'hyprland') { loadHyprland(); loadEffects(); loadInput(); }
  if (name === 'binds') { loadKeybinds(); loadAutostart(); }
  if (name === 'fonts') { loadFonts(); }
  if (name === 'appearance') { loadAppearance(); }
  if (name === 'devices') { loadMonitors(); loadAudio(); loadBrightness(); loadMako(); loadWaybar(); loadNightlight(); loadNetwork(); loadDND(); loadBluetooth(); }
  if (name === 'system') loadSystemInfo();
  window.scrollTo({ top: 0 });
}
$$('.nav li, .top-nav .nav-item').forEach(li => {
  li.addEventListener('click', () => setTab(li.dataset.tab));
  li.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setTab(li.dataset.tab); } });
});
$('.menu-btn')?.addEventListener('click', () => $('.sidebar').classList.toggle('open'));

/* ── Helpers ── */
async function api(path, opts) {
  const r = await fetch(path, opts);
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error || r.statusText);
  return data;
}
const post = body => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
function fmtUptime(s) {
  const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
}
const fmtKiB = v => v >= 1024 ? (v / 1024).toFixed(1) + ' MiB/s' : v.toFixed(0) + ' KiB/s';
const fmtLeft = m => m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
const statusWord = s => s.battery < 20 ? 'Low battery' : 'Discharging';

/* ── Charts (Chart.js, tuned) ── */
Chart.defaults.color = '#6f6f6f';
Chart.defaults.font.family = "'Geist Mono', monospace";
Chart.defaults.font.size = 10;

const MAX = 40;
let cpuData = [], memData = [], netData = [], labels = [];
for (let i = 0; i < MAX; i++) { cpuData.push(0); memData.push(0); netData.push(0); labels.push(''); }

function grad(ctx, hex, top = .35) {
  const g = ctx.createLinearGradient(0, 0, 0, 56);
  g.addColorStop(0, hex + Math.round(top * 255).toString(16).padStart(2, '0'));
  g.addColorStop(1, hex + '00');
  return g;
}
const tooltipStyle = {
  backgroundColor: '#1a1a1a', borderColor: 'rgba(255,255,255,.12)', borderWidth: 1,
  titleColor: '#ededed', bodyColor: '#c9c9c9', padding: 10,
  displayColors: false, cornerRadius: 8, titleFont: { weight: '600' }
};
let chCpu, chMem, chNet, chPerf, chDisk;
function mkSpark(id, color) {
  return new Chart($('#' + id), {
    type: 'line',
    data: { labels, datasets: [{ data: [], borderColor: color, borderWidth: 2, fill: true, tension: .4 }] },
    options: {
      responsive: true, maintainAspectRatio: false, animation: { duration: 300 },
      plugins: { legend: { display: false }, tooltip: { enabled: false } },
      scales: { x: { display: false }, y: { display: false, min: 0, max: 100 } },
      elements: { point: { radius: 0, hitRadius: 0 } }
    }
  });
}
function initCharts() {
  chCpu = mkSpark('c-cpu', '#3b82f6');
  chCpu.options.datasets = undefined;
  // gradient fills need the canvas ctx — set after creation
  const cpuDs = chCpu.data.datasets[0];
  cpuDs.backgroundColor = c => grad(c.chart.ctx, '#3b82f6');
  cpuDs.borderColor = '#3b82f6';
  cpuDs.shadowColor = 'rgba(59,130,246,.85)'; cpuDs.shadowBlur = 16;

  chMem = mkSpark('c-mem', '#45a557');
  const memDs = chMem.data.datasets[0];
  memDs.backgroundColor = c => grad(c.chart.ctx, '#45a557');
  memDs.borderColor = '#45a557';
  memDs.shadowColor = 'rgba(69,165,87,.85)'; memDs.shadowBlur = 16;

  chNet = mkSpark('c-net', '#ff990a');
  const netDs = chNet.data.datasets[0];
  netDs.backgroundColor = c => grad(c.chart.ctx, '#ff990a');
  netDs.borderColor = '#ff990a';
  netDs.shadowColor = 'rgba(255,153,10,.85)'; netDs.shadowBlur = 16;

  chPerf = new Chart($('#c-perf'), {
    type: 'line',
    data: {
      labels,
      datasets: [
        { data: [], label: 'cpu', borderColor: '#3b82f6', borderWidth: 2, tension: .4, fill: true,
          backgroundColor: c => { const g = c.chart.ctx.createLinearGradient(0, 0, 0, 170); g.addColorStop(0, 'rgba(59,130,246,.28)'); g.addColorStop(1, 'rgba(59,130,246,0)'); return g; },
          shadowColor: 'rgba(59,130,246,.7)', shadowBlur: 12 },
        { data: [], label: 'mem', borderColor: '#45a557', borderWidth: 1.6, tension: .4, shadowColor: 'rgba(69,165,87,.6)', shadowBlur: 8 },
        { data: [], label: 'net×10', borderColor: '#ff990a', borderWidth: 1.4, borderDash: [4, 3], tension: .4, shadowColor: 'rgba(255,153,10,.55)', shadowBlur: 8 }
      ]
    },
    options: {
      responsive: true, maintainAspectRatio: false, animation: { duration: 300 },
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: { ...tooltipStyle, callbacks: {
          title: items => 'now · -' + ((labels.length - 1 - items[0].dataIndex) * 2) + 's',
          label: item => `${item.dataset.label}: ${item.parsed.y.toFixed(1)}%`
        } }
      },
      scales: {
        x: { display: false },
        y: {
          min: 0, max: 100,
          grid: { color: 'rgba(255,255,255,.05)' },
          border: { display: false },
          ticks: { stepSize: 25, callback: v => v + '%', color: '#55555b' }
        }
      },
      elements: { point: { radius: 0, hoverRadius: 3, hoverBackgroundColor: '#fff' } }
    }
  });

  chDisk = new Chart($('#c-disk'), {
    type: 'doughnut',
    data: { labels: ['used', 'free'], datasets: [{ data: [0, 100], backgroundColor: ['#3b82f6', '#232326'], hoverOffset: 3, borderWidth: 0, borderRadius: 5 }] },
    options: {
      responsive: true, maintainAspectRatio: false, cutout: '74%',
      plugins: { legend: { display: false }, tooltip: { ...tooltipStyle, callbacks: { label: i => i.label === 'used' ? $('#donut-txt').textContent : '' } } }
    }
  });
}

/* ── Stats polling + status strip ── */
async function pollStats() {
  try {
    const s = await api('/api/stats');
    $('#v-cpu').textContent = s.cpu.toFixed(0) + '%';
    $('#v-mem').textContent = s.memPct.toFixed(0) + '%';
    $('#v-temp').textContent = 'temp ' + s.temp.toFixed(0) + '°C · swap ' + s.swapPct.toFixed(0) + '%';
    $('#v-rx').textContent = fmtKiB(s.netRx);
    $('#v-tx').textContent = fmtKiB(s.netTx);
    $('#v-net').textContent = fmtKiB(s.netRx + s.netTx);
    $('#v-load').textContent = s.load1.toFixed(2);
    lastUptime = s.uptime; lastLoad = s.load1.toFixed(2);
    $('#side-uptime').textContent = fmtUptime(s.uptime);
    // status strip
    $('#t-cpu').textContent = s.cpu.toFixed(0) + '%';
    $('#t-mem').textContent = s.memPct.toFixed(0) + '%';
    $('#t-net').textContent = fmtKiB(s.netRx + s.netTx);
    $('#t-load').textContent = s.load1.toFixed(2);
    $('#t-temp').textContent = s.temp.toFixed(0) + '°C';
    $('#t-up').textContent = fmtUptime(s.uptime);
    let batTxt = 'AC';
    const barBat = $('#bar-bat'), pwLine = $('#pw-line');
    if (s.battery >= 0) {
      batTxt = s.battery + '%' + (s.charging ? ' ⚡' : '');
      if (barBat) {
        barBat.style.width = s.battery + '%';
        barBat.style.background = s.battery < 20 && !s.charging ? '#e5484d' : s.charging ? '#45a557' : '#0072f5';
      }
      $('#d-bat').className = 'dot ' + (s.battery < 20 && !s.charging ? 'dot-off' : 'dot-ok');
      const est = s.minutesLeft >= 0
        ? (s.charging ? ` · full in ${fmtLeft(s.minutesLeft)}` : ` · ${fmtLeft(s.minutesLeft)} left`)
        : '';
      if (pwLine) pwLine.textContent = (s.charging ? 'Charging' : statusWord(s)) + ` · ${s.powerW.toFixed(1)}W${est}`;
      const vb = $('#v-bat');
      if (vb) {
        vb.textContent = s.battery + '%';
        vb.style.color = s.battery < 20 && !s.charging ? '#e5484d' : '';
      }
      $('#v-temp').textContent = `${s.charging ? 'Charging' : statusWord(s)} · ${s.powerW.toFixed(1)}W${est} · ${s.temp.toFixed(0)}°C`;
      const pb = $('#pw-bat'), pbr = $('#pw-bar'), ps = $('#pw-status');
      if (pb) pb.textContent = s.battery + '%';
      if (pbr) pbr.style.width = s.battery + '%';
      if (ps) ps.textContent = (s.charging ? 'Charging' : statusWord(s)) +
        ` · ${s.powerW.toFixed(1)}W` +
        (s.minutesLeft >= 0 ? (s.charging ? ` · full in ${fmtLeft(s.minutesLeft)}` : ` · ${fmtLeft(s.minutesLeft)} remaining`) : '');
    } else {
      if (barBat) barBat.style.width = '100%';
      if (pwLine) pwLine.textContent = 'On AC power';
      const vb = $('#v-bat');
      if (vb) vb.textContent = 'AC';
      $('#v-temp').textContent = `temp ${s.temp.toFixed(0)}°C`;
      const pb = $('#pw-bat'), pbr = $('#pw-bar'), ps = $('#pw-status');
      if (pb) pb.textContent = 'AC';
      if (pbr) pbr.style.width = '100%';
      if (ps) ps.textContent = 'On AC power';
    }
    $('#t-bat').textContent = batTxt;
    cpuData.push(s.cpu); memData.push(s.memPct); netData.push(Math.min(100, (s.netRx + s.netTx) / 30));
    labels.push('');
    if (cpuData.length > MAX) { cpuData.shift(); memData.shift(); netData.shift(); labels.shift(); }
    if (chCpu) {
      chCpu.data.datasets[0].data = [...cpuData]; chCpu.update('none');
      chMem.data.datasets[0].data = [...memData]; chMem.update('none');
      chNet.data.datasets[0].data = [...netData]; chNet.update('none');
      chPerf.data.datasets[0].data = [...cpuData];
      chPerf.data.datasets[1].data = [...memData];
      chPerf.data.datasets[2].data = [...netData];
      chPerf.update('none');
    }
    setRing('ring-cpu', 'rv-cpu', s.cpu);
    setRing('ring-mem', 'rv-mem', s.memPct);
    const batPct = s.battery >= 0 ? s.battery : 100;
    setRing('ring-bat', 'rv-bat', batPct, s.battery >= 0 ? '' : 'AC');
    $('#rv-bat').style.color = s.charging ? '#6cda75' : batPct < 20 ? '#ff7b72' : '';
    $('#rv-cpu').style.color = s.cpu > 85 ? '#ff7b72' : '';
  } catch (e) { /* server restarting */ }
}

/* ── Dashboard extras ── */
async function loadDisks() {
  try {
    const disks = await api('/api/disks');
    const root = disks.find(d => d.target === '/') || disks[0] || { pct: 0 };
    if (chDisk) {
      chDisk.data.datasets[0].data = [root.pct, 100 - root.pct];
      chDisk.update('none');
    }
    $('#donut-txt').innerHTML = `<b>${root.pct}%</b><span>${root.used}</span>`;
    $('#disk-list').innerHTML = disks.slice(0, 5).map(d => `
      <div class="disk-row"><b>${d.target}</b>
        <span class="bar"><i style="width:${Math.min(100, d.pct)}%;${d.pct > 90 ? 'background:#e5484d' : d.pct > 75 ? 'background:#e0d1a8' : ''}"></i></span>
        <span class="dim">${d.used}/${d.size} · ${d.pct}%</span></div>`).join('');
  } catch (e) {}
}
let procSort = 'cpu';
$('#proc-sort')?.addEventListener('change', e => { procSort = e.target.value; loadProcesses(); });
async function loadProcesses() {
  try {
    const procs = await api('/api/processes?sort=' + procSort);
    $('#proc-table tbody').innerHTML = procs.map(p => `
      <tr>
        <td class="dim">${p.pid}</td>
        <td title="${p.cmd.replace(/"/g, '&quot;')}">${p.name}</td>
        <td>${p.cpu.toFixed(1)}</td>
        <td>${p.mem.toFixed(1)}</td>
        <td class="dim">${p.rssMb >= 1024 ? (p.rssMb / 1024).toFixed(1) + 'G' : p.rssMb.toFixed(0) + 'M'}</td>
        <td><span class="state-${p.state}">${p.state}</span></td>
        <td><button class="kill-btn" title="Kill ${p.name} (${p.pid})" onclick="killProc(${p.pid}, '${p.name.replace(/'/g, '')}', this)"><i class="ph ph-x"></i></button></td>
      </tr>`).join('');
  } catch (e) {}
}
async function killProc(pid, name, btn) {
  const hard = confirm(`Send SIGTERM to ${name} (${pid})?\n\nCancel = SIGTERM · OK below confirms`);
  if (!hard) return;
  btn.disabled = true;
  try {
    await api('/api/process/kill', post({ pid, signal: 15 }));
    toast(`SIGTERM sent to ${name} (${pid})`);
    setTimeout(loadProcesses, 800);
  } catch (e) {
    if (confirm(`${e.message}\n\nForce SIGKILL ${name} (${pid})?`)) {
      try {
        await api('/api/process/kill', post({ pid, signal: 9 }));
        toast(`SIGKILL sent to ${name} (${pid})`);
        setTimeout(loadProcesses, 800);
      } catch (e2) { toast(e2.message, 'err'); }
    }
  }
  btn.disabled = false;
}

/* ── Keybinds ── */
async function loadKeybinds() {
  try {
    const binds = await api('/api/keybinds');
    $('#kb-count').textContent = binds.length + ' binds';
    $('#kb-table tbody').innerHTML = binds.map(b => `
      <tr>
        <td class="dim">${b.mods || '—'}</td>
        <td><b>${b.key}</b></td>
        <td>${b.desc || '—'}</td>
        <td class="dim" title="${(b.arg || '').replace(/"/g, '&quot;')}">${b.dispatcher} ${b.arg.length > 42 ? b.arg.slice(0, 42) + '…' : b.arg}</td>
        <td><button class="kill-btn" title="Delete bind" onclick="delKeybind(${b.id}, this)"><i class="ph ph-trash"></i></button></td>
      </tr>`).join('');
  } catch (e) {}
}
async function addKeybind(btn) {
  const mods = [];
  if ($('#kb-super').checked) mods.push('SUPER');
  if ($('#kb-shift').checked) mods.push('SHIFT');
  if ($('#kb-ctrl').checked) mods.push('CTRL');
  if ($('#kb-alt').checked) mods.push('ALT');
  btn.disabled = true;
  try {
    await api('/api/keybinds', post({
      action: 'add', mods,
      key: $('#kb-key').value.trim(),
      desc: $('#kb-desc').value.trim(),
      dispatcher: $('#kb-disp').value,
      arg: $('#kb-arg').value.trim()
    }));
    toast('Keybind added · Hyprland reloaded');
    $('#kb-key').value = ''; $('#kb-desc').value = ''; $('#kb-arg').value = '';
    loadKeybinds();
  } catch (e) { toast(e.message, 'err'); }
  btn.disabled = false;
}
async function delKeybind(id, btn) {
  if (!confirm('Delete this keybind?')) return;
  btn.disabled = true;
  try {
    await api('/api/keybinds', post({ action: 'delete', id }));
    toast('Keybind deleted · Hyprland reloaded');
    loadKeybinds();
  } catch (e) { toast(e.message, 'err'); btn.disabled = false; }
}

/* ── Autostart ── */
async function loadAutostart() {
  try {
    const items = await api('/api/autostart');
    $('#as-list').innerHTML = items.length ? items.map(it => `
      <div class="as-row mono tiny"><span>${it.command}</span>
        <button class="kill-btn" onclick="delAutostart(${it.id}, this)"><i class="ph ph-trash"></i></button></div>`).join('')
      : '<div class="caption">No autostart entries.</div>';
  } catch (e) {}
}
async function addAutostart(btn) {
  const cmd = $('#as-cmd').value.trim();
  if (!cmd) return;
  btn.disabled = true;
  try {
    await api('/api/autostart', post({ action: 'add', command: cmd }));
    toast('Added to autostart');
    $('#as-cmd').value = '';
    loadAutostart();
  } catch (e) { toast(e.message, 'err'); }
  btn.disabled = false;
}
async function delAutostart(id, btn) {
  if (!confirm('Remove this autostart entry?')) return;
  btn.disabled = true;
  try {
    await api('/api/autostart', post({ action: 'delete', id }));
    toast('Removed');
    loadAutostart();
  } catch (e) { toast(e.message, 'err'); btn.disabled = false; }
}

/* ── Font Studio ── */
let fontData = null;
const loadedFaces = new Set();

// load a font family into the document so specimens render for real
async function ensureFace(family) {
  if (loadedFaces.has(family)) return true;
  try {
    const face = new FontFace(family, `url(/api/fonts/file?family=${encodeURIComponent(family)})`, {
      weight: '100 900', display: 'swap'
    });
    await face.load();
    document.fonts.add(face);
    loadedFaces.add(family);
    return true;
  } catch (e) { return false; }
}

async function loadFonts() {
  try {
    fontData = await api('/api/fonts');
    renderFontCatalog();
    renderInstalledFonts();
    fillApplySelects();
    $('#cur-term').textContent = fontData.current.terminal || '—';
    $('#cur-bar').textContent = fontData.current.bar || '—';
    $('#cur-lock').textContent = fontData.current.lockscreen || '—';
    $('#cur-gtk').textContent = fontData.current.gtk || '—';
    // hero select: current terminal font first
    const fams = [...new Set([fontData.current.terminal, ...fontData.installed])].filter(Boolean);
    $('#spec-font').innerHTML = fams.map(f => `<option ${f === fontData.current.terminal ? 'selected' : ''}>${f}</option>`).join('');
    setSpecimenFont($('#spec-font').value);
  } catch (e) {}
}

function fillApplySelects() {
  const opts = f => ['<option value="">— keep —</option>', ...[...new Set([f, ...fontData.installed])].filter(Boolean).map(x => `<option>${x}</option>`)].join('');
  for (const id of ['sel-term', 'sel-bar', 'sel-lockscreen', 'sel-gtk']) {
    const el = $('#' + id);
    const cur = el.dataset.cur;
    el.innerHTML = opts(cur);
    el.value = cur || '';
  }
}

function renderFontCatalog() {
  $('#font-catalog').innerHTML = fontData.catalog.map((f, idx) => `
    <div class="font-entry ${f.installed ? 'has' : ''}">
      <div class="font-preview" data-fam="${f.family}">${f.installed ? '<span class="pv" style="font-family:\'' + f.family + '\'">Aa</span>' : 'Aa'}</div>
      <div class="font-meta"><b>${f.name}</b><span class="dim tiny mono">${f.kind}</span></div>
      ${f.installed
        ? '<button class="btn ghost sm" title="Try in specimen" onclick=\'setSpecimenFont("' + f.family + '")\'><i class="ph ph-cursor-click"></i></button>'
        : `<button class="btn ghost sm" onclick='installCatalogFont(${JSON.stringify(f.url)}, this, ${idx})'><i class="ph ph-download-simple"></i></button>`}
    </div>`).join('');
  // load real previews for installed catalog entries
  fontData.catalog.filter(f => f.installed).forEach(async f => {
    if (await ensureFace(f.family)) {
      const el = $(`#font-catalog .font-preview[data-fam="${CSS.escape(f.family)}"] .pv`);
      if (el) el.style.fontFamily = `'${f.family}'`;
    }
  });
}

const FONT_PAGE_SIZE = 40;
let fontPage = 1, fontTotalPages = 1;
function fontPageMove(d) {
  fontPage = Math.min(Math.max(1, fontPage + d), fontTotalPages);
  renderInstalledFonts();
}
async function renderInstalledFonts() {
  const q = ($('#font-search')?.value || '').toLowerCase();
  let fams = fontData.installed.filter(f => !q || f.toLowerCase().includes(q));
  fontTotalPages = Math.max(1, Math.ceil(fams.length / FONT_PAGE_SIZE));
  if (fontPage > fontTotalPages) fontPage = fontTotalPages;
  $('#font-count').textContent = fams.length + ' families';
  $('#font-page').textContent = fontPage + '/' + fontTotalPages;
  const page = fams.slice((fontPage - 1) * FONT_PAGE_SIZE, fontPage * FONT_PAGE_SIZE);
  $('#installed-fonts').innerHTML = page.map(f => `
    <div class="font-card" data-fam="${f.replace(/"/g, '&quot;')}" title="Click: specimen · hover: quick-set terminal">
      <div class="fc-sample pv" style="font-family:'${f}'">Aa Bb</div>
      <div class="fc-name mono tiny">${f}</div>
      <button class="kill-btn fc-apply" title="Set terminal font" onclick="event.stopPropagation();quickTerminal('${f.replace(/'/g, "\\'")}')" style="display:none"><i class="ph ph-terminal-window"></i></button>
    </div>`).join('') || '<div class="caption">no matches</div>';
  for (const f of page.slice(0, 24)) {
    if (await ensureFace(f)) {
      const card = $(`#installed-fonts .font-card[data-fam="${CSS.escape(f)}"] .fc-sample`);
      if (card) card.style.opacity = 1;
    }
  }
  $$('#installed-fonts .font-card').forEach(card => {
    card.addEventListener('click', () => { setSpecimenFont(card.dataset.fam); window.scrollTo({ top: 0, behavior: 'smooth' }); });
    card.addEventListener('mouseenter', () => card.querySelector('.fc-apply').style.display = '');
    card.addEventListener('mouseleave', () => card.querySelector('.fc-apply').style.display = 'none');
  });
}

async function setSpecimenFont(family) {
  $('#spec-font').value = family;
  const ok = await ensureFace(family);
  $('#spec-canvas').style.fontFamily = `'${family}', monospace`;
  $('#spec-canvas').style.opacity = ok ? 1 : .55;
  $('#spec-font').title = ok ? family : family + ' (preview unavailable)';
}

$('#spec-font')?.addEventListener('change', e => setSpecimenFont(e.target.value));
$('#spec-size')?.addEventListener('input', e => $('#spec-canvas').style.fontSize = e.target.value + 'px');
$('#spec-weight')?.addEventListener('input', e => $('#spec-canvas').style.fontWeight = e.target.value);
$('#spec-theme')?.addEventListener('click', e => {
  const c = $('#spec-canvas');
  c.classList.toggle('light');
  e.currentTarget.innerHTML = c.classList.contains('light') ? '<i class="ph ph-moon"></i>' : '<i class="ph ph-sun"></i>';
});

async function applyOne(target) {
  const selId = { terminal: 'sel-term', bar: 'sel-bar', lockscreen: 'sel-lockscreen', gtk: 'sel-gtk' }[target];
  const family = $('#' + selId).value;
  if (!family) return toast('Pick a family first', 'err');
  try {
    const res = await api('/api/fonts', post({ action: 'apply', family, targets: [target] }));
    const v = res.results[target];
    if (v !== 'ok') throw new Error(`${target}: ${v}`);
    toast(`${target}: ${family}`);
    if ($('#sync-spec').checked) setSpecimenFont(family);
    // refresh current labels without full reload
    const d = await api('/api/fonts');
    Object.assign(fontData, d);
    $('#cur-' + ({ lockscreen: 'lock' }[target] || target)).textContent =
      d.current[{ terminal: 'terminal', bar: 'bar', lockscreen: 'lockscreen', gtk: 'gtk' }[target]] || '—';
  } catch (e) { toast(e.message, 'err'); }
}
async function quickTerminal(family) {
  try {
    await api('/api/fonts', post({ action: 'apply', family, targets: ['terminal'] }));
    toast(`terminal → ${family}`);
  } catch (e) { toast(e.message, 'err'); }
}
async function installCatalogFont(url, btn, idx) {
  btn.disabled = true; btn.innerHTML = '<i class="ph ph-circle-notch spin"></i>';
  try {
    await api('/api/fonts', post({ action: 'install', url }));
    toast('Font installed'); loadFonts();
  } catch (e) {
    toast(e.message, 'err');
    btn.disabled = false; btn.innerHTML = '<i class="ph ph-download-simple"></i>';
  }
}
async function installFontUrl(btn) {
  const url = $('#font-url').value.trim();
  if (!url) return;
  btn.disabled = true;
  try {
    await api('/api/fonts', post({ action: 'install', url }));
    toast('Font installed'); $('#font-url').value = ''; loadFonts();
  } catch (e) { toast(e.message, 'err'); }
  btn.disabled = false;
}

/* ── Logs ── */
let logES = null, logPaused = false, logCount = 0;
const LOG_MAX = 2000;
function logClassify(line) {
  const l = line.toLowerCase();
  if (/\b(err(or)?|fail(ed|ure)?|critical|panic|segfault|denied|cannot)\b/.test(l)) return 'err';
  if (/\bwarn(ing)?\b/.test(l)) return 'warn';
  if (/\b(started|finished|done|successfully|active)\b/.test(l)) return 'ok';
  if (/ufw block/i.test(line)) return 'dimline';
  return '';
}
function appendLogLine(line) {
  const viewer = $('#log-viewer');
  const grep = $('#log-grep').value.trim().toLowerCase();
  if (grep && !line.toLowerCase().includes(grep)) return;
  const div = document.createElement('div');
  div.className = 'log-line ' + logClassify(line);
  // dim the timestamp portion
  const m = line.match(/^(\w{3} \d{2} \d{2}:\d{2}:\d{2})\s(.*)$/s);
  if (m) {
    div.innerHTML = `<span class="ts">${m[1]}</span> `;
    div.appendChild(document.createTextNode(m[2]));
  } else {
    div.textContent = line;
  }
  viewer.appendChild(div);
  while (viewer.children.length > LOG_MAX) viewer.removeChild(viewer.firstChild);
  logCount++;
  $('#log-count').textContent = viewer.children.length + ' lines';
  if (!logPaused) viewer.scrollTop = viewer.scrollHeight;
}
function connectLogs() {
  if (logES) { logES.close(); logES = null; }
  const source = $('#log-source').value;
  const prio = $('#log-prio').value;
  logES = new EventSource(`/api/logs/stream?source=${encodeURIComponent(source)}&prio=${encodeURIComponent(prio)}`);
  logES.onmessage = ev => { if (!logPaused) appendLogLine(ev.data); };
  logES.onerror = () => { /* EventSource auto-reconnects */ };
}
$('#log-source')?.addEventListener('change', () => { $('#log-viewer').textContent = ''; connectLogs(); });
$('#log-prio')?.addEventListener('change', () => { $('#log-viewer').textContent = ''; connectLogs(); });
$('#log-grep')?.addEventListener('input', () => {
  // re-filter existing lines client-side
  const grep = $('#log-grep').value.trim().toLowerCase();
  $$('#log-viewer .log-line').forEach(el => {
    el.style.display = !grep || el.textContent.toLowerCase().includes(grep) ? '' : 'none';
  });
});
$('#btn-logpause')?.addEventListener('click', e => {
  logPaused = !logPaused;
  e.currentTarget.innerHTML = logPaused ? '<i class="ph ph-play"></i> Resume' : '<i class="ph ph-pause"></i> Pause';
});
$('#btn-logclear')?.addEventListener('click', () => { $('#log-viewer').textContent = ''; logCount = 0; $('#log-count').textContent = '0 lines'; });
async function loadServices() {
  try {
    const svcs = await api('/api/services');
    $('#svc-grid').innerHTML = svcs.map(s => `
      <div class="svc" title="${s.name}: ${s.running ? 'running' : 'stopped'}">
        <span class="dot ${s.running ? 'dot-ok' : 'dot-off'}"></span>${s.name}</div>`).join('');
  } catch (e) {}
}

/* ── Network ── */
async function loadNetwork() {
  try {
    const n = await api('/api/network');
    $('#side-ip').textContent = n.ip || '—';
    $('#t-ip').textContent = n.ip || '—';
    const conns = n.connections || [];
    const rows = conns.map(c =>
      `<div class="kv"><span><i class="ph ${c.type.includes('wireless') || c.type.includes('wifi') ? 'ph-wifi-high' : 'ph-ethernet'}"></i> ${c.name}</span><b>${c.device}</b></div>`).join('');
    const wifi = n.wifiSsid ? `<div class="kv"><span>wifi signal</span><b>${n.wifiSignal}%</b></div>` : '';
    const html = `<div class="kv"><span>ip</span><b>${n.ip || '—'}</b></div>${rows}${wifi}`;
    $('#net-summary').innerHTML = html;
    $('#net-detail').innerHTML = html || '<span class="dim">No active connections</span>';
  } catch (e) {
    $('#net-summary').innerHTML = '<span class="dim">Network info unavailable</span>';
    $('#net-detail').innerHTML = '<span class="dim">Network info unavailable</span>';
  }
}

/* ── System info ── */
async function loadSystemInfo() {
  try {
    const info = await api('/api/system/info');
    $('#side-wall').textContent = info.wallpaper;
    $('#side-kernel').textContent = info.kernel;
    $('#side-shell').textContent = info.shell;
    $('#host-info').innerHTML = Object.entries(info).map(([k, v]) =>
      `<div class="kv"><span>${k}</span><b class="mono tiny">${v}</b></div>`).join('');
  } catch (e) {}
}

/* ── Power profile ── */
async function loadPowerProfile() {
  try {
    const p = await api('/api/powerprofile');
    $$('.profile-card').forEach(c => {
      const active = c.dataset.mode === p.mode;
      c.classList.toggle('active', active);
      c.querySelector('.badge').textContent = active ? 'active' : 'off';
    });
    $('#power-detail').innerHTML = `
      <div class="kv"><span>scaling governor</span><b>${p.governor || '—'}</b></div>
      <div class="kv"><span>energy preference</span><b>${p.epp || '—'}</b></div>
      <div class="kv"><span>platform profile</span><b>${p.platform || 'n/a'}</b></div>
      <div class="kv"><span>detected mode</span><b>${p.mode}</b></div>`;
    $('#t-profile').textContent = p.mode;
  } catch (e) {}
}
async function setPowerProfile(mode) {
  toast(`Switching to ${mode} — approve the auth prompt…`, 'info');
  try {
    await api('/api/powerprofile', post({ mode }));
    toast(`Power profile: ${mode}`);
    loadPowerProfile();
  } catch (e) { toast(e.message, 'err'); }
}

/* ── Reload actions ── */
async function reloadTarget(target, btn) {
  if (btn) btn.disabled = true;
  try {
    await api('/api/reload?target=' + target, { method: 'POST' });
    toast(target + ' reloaded');
  } catch (e) { toast(e.message, 'err'); }
  if (btn) setTimeout(() => btn.disabled = false, 1500);
}

/* ── Power actions ── */
const POWER_LABELS = { lock: 'Lock session', suspend: 'Suspend', logout: 'Logout', reboot: 'Reboot', shutdown: 'Shutdown' };
async function powerAction(action) {
  if (['logout', 'reboot', 'shutdown'].includes(action) && !confirm(`${POWER_LABELS[action]} — are you sure?`)) return;
  try {
    await api('/api/power', post({ action }));
    toast(POWER_LABELS[action] + '…', 'info');
  } catch (e) { toast(e.message, 'err'); }
}

/* ── Audio & brightness ── */
let volTimer, briTimer;
function syncVolUI(v, muted) {
  ['#r-vol', '#r-vol2'].forEach(s => { const el = $(s); if (el) el.value = v; });
  ['#o-vol', '#o-vol2'].forEach(s => { const el = $(s); if (el) el.textContent = v + '%'; });
  ['#btn-mute', '#btn-mute2'].forEach(s => {
    const b = $(s);
    if (!b) return;
    b.classList.toggle('active', muted);
    b.innerHTML = `<i class="ph ${muted ? 'ph-speaker-slash' : v == 0 ? 'ph-speaker-low' : 'ph-speaker-high'}"></i>`;
  });
}
function syncBriUI(p) {
  ['#r-bri', '#r-bri2'].forEach(s => { const el = $(s); if (el) el.value = p; });
  ['#o-bri', '#o-bri2'].forEach(s => { const el = $(s); if (el) el.textContent = p + '%'; });
}
async function loadAudio() {
  try { const a = await api('/api/audio'); syncVolUI(a.volume, a.muted); } catch (e) {}
}
async function loadBrightness() {
  try { const b = await api('/api/brightness'); syncBriUI(b.percent); } catch (e) {}
}
['#r-vol', '#r-vol2'].forEach(sel => $(sel)?.addEventListener('input', e => {
  syncVolUI(+e.target.value, $('#btn-mute')?.classList.contains('active'));
  clearTimeout(volTimer);
  volTimer = setTimeout(() => api('/api/audio', post({ volume: +e.target.value, muted: false })).catch(() => {}), 150);
}));
['#r-bri', '#r-bri2'].forEach(sel => $(sel)?.addEventListener('input', e => {
  syncBriUI(+e.target.value);
  clearTimeout(briTimer);
  briTimer = setTimeout(() => api('/api/brightness', post({ percent: +e.target.value })).catch(() => {}), 120);
}));
['#btn-mute', '#btn-mute2'].forEach(sel => $(sel)?.addEventListener('click', async () => {
  const muted = !$(sel).classList.contains('active');
  try {
    await api('/api/audio', post({ volume: +$('#r-vol').value || 50, muted }));
    syncVolUI(+$('#r-vol').value, muted);
    toast(muted ? 'Muted' : 'Unmuted');
  } catch (e) { toast(e.message, 'err'); }
}));

/* ── Monitors (interactive) ── */
async function loadMonitors() {
  try {
    const mons = await api('/api/monitors');
    $('#monitor-list').innerHTML = mons.length ? mons.map((m, idx) => {
      const modes = (m.availableModes && m.availableModes.length ? m.availableModes : ['preferred']);
      const cur = m.currentMode || `${m.width}x${m.height}@${Math.round(m.refresh)}Hz`;
      const curNorm = cur.replace(/Hz$/, '');
      const matched = modes.find(x => x.replace(/Hz$/, '') === curNorm) || modes[0];
      return `
      <div class="mon" data-name="${m.name}">
        <span class="mon-icon"><i class="ph ph-desktop"></i></span>
        <div style="min-width:0;flex:1">
          <b>${m.name}${m.disabled ? ' <span class="dim">(disabled)</span>' : ''}</b>
          <span class="dim tiny mono">${m.description || ''} · ws ${m.activeWorkspace || '—'}</span>
          <div class="mon-editor">
            <label>mode
              <select data-role="mode" aria-label="${m.name} mode">
                ${modes.map(x => `<option ${x === matched ? 'selected' : ''}>${x}</option>`).join('')}
              </select>
            </label>
            <label>scale
              <input type="number" data-role="scale" min="0.5" max="3" step="0.05" value="${m.scale}" aria-label="${m.name} scale">
            </label>
            <button class="btn primary sm" onclick="applyMonitor('${m.name}', this)">Apply</button>
          </div>
        </div>
      </div>`;
    }).join('') : '<span class="dim">No monitors reported</span>';
  } catch (e) {
    $('#monitor-list').innerHTML = '<span class="dim">hyprctl unavailable</span>';
  }
}
async function applyMonitor(name, btn) {
  const mon = document.querySelector(`.mon[data-name="${name}"]`);
  const mode = mon.querySelector('[data-role=mode]').value;
  const scale = parseFloat(mon.querySelector('[data-role=scale]').value) || 1;
  btn.disabled = true;
  try {
    await api('/api/monitor/set', post({ name, mode, scale }));
    toast(`${name} → ${mode} @${scale}×`);
    setTimeout(loadMonitors, 1200);
  } catch (e) { toast(e.message, 'err'); }
  btn.disabled = false;
}

/* ── Mako notifications ── */
bindRange('#r-ntimeout', '#o-ntimeout', v => v + 'ms');
bindRange('#r-nmax', '#o-nmax', v => v);
bindRange('#r-nwidth', '#o-nwidth', v => v + 'px');
bindRange('#r-nheight', '#o-nheight', v => v + 'px');
bindRange('#r-nradius', '#o-nradius', v => v);
async function loadMako() {
  try {
    const m = await api('/api/mako');
    $('#r-ntimeout').value = m.timeout; $('#o-ntimeout').textContent = m.timeout + 'ms';
    $('#r-nmax').value = m.maxVisible; $('#o-nmax').textContent = m.maxVisible;
    $('#r-nwidth').value = m.width; $('#o-nwidth').textContent = m.width + 'px';
    $('#r-nheight').value = m.height; $('#o-nheight').textContent = m.height + 'px';
    $('#r-nradius').value = m.radius; $('#o-nradius').textContent = m.radius;
  } catch (e) {}
}
async function saveMako(btn) {
  btn.disabled = true;
  try {
    await api('/api/mako', post({
      timeout: +$('#r-ntimeout').value,
      maxVisible: +$('#r-nmax').value,
      width: +$('#r-nwidth').value,
      height: +$('#r-nheight').value,
      radius: +$('#r-nradius').value
    }));
    flash('#st-mako', 'Saved — mako reloaded if running');
  } catch (e) { flash('#st-mako', e.message, false); }
  btn.disabled = false;
}

/* ── Waybar ── */
bindRange('#r-wbheight', '#o-wbheight', v => v);
async function loadWaybar() {
  try {
    const wb = await api('/api/waybar');
    $('#s-wbpos').value = wb.position;
    $('#r-wbheight').value = wb.height; $('#o-wbheight').textContent = wb.height;
  } catch (e) {}
}
async function saveWaybar(btn) {
  btn.disabled = true;
  try {
    await api('/api/waybar', post({ position: $('#s-wbpos').value, height: +$('#r-wbheight').value }));
    flash('#st-waybar', 'Saved — waybar restarted');
  } catch (e) { flash('#st-waybar', e.message, false); }
  btn.disabled = false;
}

/* ── Night light ── */
bindRange('#r-nltemp', '#o-nltemp', v => v + 'K');
async function loadNightlight() {
  try {
    const nl = await api('/api/nightlight');
    $('#t-nightlight').checked = nl.on;
    $('#r-nltemp').value = nl.temperature; $('#o-nltemp').textContent = nl.temperature + 'K';
  } catch (e) {}
}
let nlTimer;
$('#t-nightlight')?.addEventListener('change', async e => {
  try {
    const r = await api('/api/nightlight', post({ on: e.target.checked, temperature: +$('#r-nltemp').value }));
    e.target.checked = r.on;
    toast(r.on ? `Night light on (${ $('#r-nltemp').value }K)` : 'Night light off');
  } catch (err) { toast(err.message, 'err'); }
});
$('#r-nltemp')?.addEventListener('input', () => {
  if (!$('#t-nightlight').checked) return;
  clearTimeout(nlTimer);
  nlTimer = setTimeout(() =>
    api('/api/nightlight', post({ on: true, temperature: +$('#r-nltemp').value })).catch(() => {}), 400);
});

/* ── DND ── */
async function loadDND() {
  try {
    const d = await api('/api/dnd');
    $('#t-dnd').checked = d.dnd;
  } catch (e) { $('#t-dnd').disabled = true; }
}
$('#t-dnd')?.addEventListener('change', async e => {
  try {
    const d = await api('/api/dnd', { method: 'POST' });
    e.target.checked = d.dnd;
    toast(d.dnd ? 'Do not disturb on' : 'Do not disturb off');
  } catch (err) { toast(err.message, 'err'); }
});

/* ── Bluetooth ── */
async function loadBluetooth() {
  try {
    const bt = await api('/api/bluetooth');
    if (!bt.available) {
      $('#bt-list').innerHTML = '<span class="dim">bluetoothctl not installed</span>';
      return;
    }
    const devs = (bt.devices || []).map(d =>
      `<div class="svc"><span class="dot dot-ok"></span>${d.name}</div>`).join('');
    $('#bt-list').innerHTML =
      `<div class="kv"><span>adapter</span><b>${bt.powered ? 'powered' : 'off'}</b></div>` +
      (devs || '<span class="dim">No connected devices</span>');
  } catch (e) {
    $('#bt-list').innerHTML = '<span class="dim">Bluetooth unavailable</span>';
  }
}

/* ── Hypridle ── */
function bindRange(rid, oid, fmt, cb) {
  const r = $(rid), o = $(oid);
  if (!r) return;
  r.addEventListener('input', () => { o.textContent = fmt(r.value); cb?.(+r.value); });
}
bindRange('#r-screensaver', '#o-screensaver', v => v + 's');
bindRange('#r-lock', '#o-lock', v => v + 's');
bindRange('#r-dpms', '#o-dpms', v => v + 's');

async function loadHypridle() {
  try {
    const h = await api('/api/hypridle');
    $('#r-screensaver').value = h.screensaver; $('#o-screensaver').textContent = h.screensaver + 's';
    $('#r-lock').value = h.lock; $('#o-lock').textContent = h.lock + 's';
    $('#r-dpms').value = h.dpms; $('#o-dpms').textContent = h.dpms + 's';
  } catch (e) { flash('#st-idle', e.message, false); }
}
async function saveHypridle(btn) {
  btn.disabled = true;
  try {
    await api('/api/hypridle', post({
      screensaver: +$('#r-screensaver').value,
      lock: +$('#r-lock').value,
      dpms: +$('#r-dpms').value
    }));
    flash('#st-idle', 'Saved — hypridle restarted');
  } catch (e) { flash('#st-idle', e.message, false); }
  btn.disabled = false;
}

/* ── Matugen ── */
let matMode = 'dark';
$$('#tab-appearance .segmented button').forEach(b => b.addEventListener('click', () => {
  matMode = b.dataset.mode;
  $$('#tab-appearance .segmented button').forEach(x => {
    x.classList.toggle('active', x === b);
    x.setAttribute('aria-checked', x === b);
  });
}));
bindRange('#r-contrast', '#o-contrast', v => (+v).toFixed(2));

async function loadMatugen() {
  try {
    const m = await api('/api/matugen');
    $('#s-type').value = m.type;
    $('#r-contrast').value = m.contrast; $('#o-contrast').textContent = m.contrast.toFixed(2);
    matMode = m.mode;
    $$('#tab-appearance .segmented button').forEach(x => x.classList.toggle('active', x.dataset.mode === m.mode));
  } catch (e) {}
}
async function saveMatugen(btn) {
  btn.disabled = true;
  try {
    await api('/api/matugen', post({ type: $('#s-type').value, contrast: +$('#r-contrast').value, mode: matMode }));
    flash('#st-mat', 'Regenerating theme… palette refreshes in a few seconds');
    setTimeout(loadTheme, 3500);
  } catch (e) { flash('#st-mat', e.message, false); }
  btn.disabled = false;
}

/* Theme palette preview */
const PAL_KEYS = ['background', 'on_background', 'primary', 'secondary', 'tertiary', 'error', 'outline', 'surface_container'];
async function loadTheme() {
  try {
    const pal = await api('/api/theme');
    $('#palette').innerHTML = PAL_KEYS.filter(k => pal[k]).map(k => `
      <div class="swatch">
        <div class="sw-color" style="background:${pal[k]}"></div>
        <div class="sw-name"><b>${k.replace(/_/g, ' ')}</b><span>${pal[k]}</span></div>
      </div>`).join('');
    const r = document.documentElement.style;
    r.setProperty('--pv-primary', pal.primary || '#c2c6d1');
    r.setProperty('--pv-secondary', pal.secondary || '#c6c6ca');
    r.setProperty('--pv-outline', pal.outline || '#737479');
    r.setProperty('--pv-error', pal.error || '#ffb4ab');
    updateTermBg(pal.background || '#131316');
  } catch (e) {
    $('#palette').innerHTML = '<div class="caption">No generated theme found — apply matugen first.</div>';
  }
}

/* ── Wallpapers (snow_black set only) ── */
async function loadWallpapers() {
  try {
    const { wallpapers, current } = await api('/api/wallpapers');
    $('#wp-count').textContent = wallpapers.length + ' in snow_black/backgrounds';
    $('#wp-grid').innerHTML = wallpapers.map(w => `
      <div class="wp-item ${w === current ? 'active' : ''}" data-name="${w}" tabindex="0" role="button" aria-label="Set wallpaper ${w}">
        <div class="wp-thumb"><img src="/wallpaper/${encodeURIComponent(w)}" alt="" loading="lazy"></div>
        <div class="wp-name">${w}</div>
      </div>`).join('');
    $$('.wp-item').forEach(el => {
      const pick = async () => {
        try {
          await api('/api/wallpaper/set', post({ name: el.dataset.name }));
          $$('.wp-item').forEach(x => x.classList.remove('active'));
          el.classList.add('active');
          $('#side-wall').textContent = el.dataset.name;
          toast('Wallpaper set — regenerating theme…');
        } catch (e) { toast(e.message, 'err'); }
      };
      el.addEventListener('click', pick);
      el.addEventListener('keydown', e => { if (e.key === 'Enter') pick(); });
    });
  } catch (e) {}
}

/* ── Ghostty ── */
bindRange('#r-size', '#o-size', v => v);
bindRange('#r-opacity', '#o-opacity', v => (+v).toFixed(2));
bindRange('#r-padding', '#o-padding', v => v + 'px');
$('#s-family')?.addEventListener('input', updateTermFont);
['#r-size', '#r-opacity'].forEach(sel => $(sel)?.addEventListener('input', updateTermFont));

function termScale() {
  const box = $('#term-preview');
  if (!box) return 1;
  return Math.min(1, box.clientWidth / 480);
}
function updateTermFont() {
  const fam = ($('#s-family')?.value || 'FiraCode Nerd Font').replace(/"/g, '');
  const size = (+$('#r-size')?.value || 13) * termScale();
  const body = $('#term-body');
  body.style.fontFamily = `'${fam}', 'Geist Mono', monospace`;
  body.style.fontSize = size + 'px';
}
function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`;
}
function updateTermBg(bgHex) {
  const op = +($('#r-opacity')?.value ?? 0.8);
  const tp = $('#term-preview');
  if (!tp) return;
  tp.style.background = hexA(bgHex, op);
  tp.style.boxShadow = `inset 0 0 0 1px rgba(255,255,255,.1), 0 12px 32px -12px rgba(0,0,0,.8)`;
}
$('#r-opacity')?.addEventListener('input', () => {
  api('/api/theme').then(updateTermBg).catch(() => {});
});

async function loadGhostty() {
  try {
    const g = await api('/api/ghostty');
    $('#s-family').value = g.fontFamily;
    $('#r-size').value = g.fontSize; $('#o-size').textContent = g.fontSize;
    $('#r-opacity').value = g.opacity; $('#o-opacity').textContent = g.opacity.toFixed(2);
    $('#r-padding').value = g.padding; $('#o-padding').textContent = g.padding + 'px';
    $('#s-cursor').value = g.cursorStyle;
    $('#r-blur').value = g.blur; $('#o-blur').textContent = g.blur;
    updateTermFont();
    api('/api/theme').then(updateTermBg).catch(() => {});
  } catch (e) { flash('#st-ghostty', e.message, false); }
}
async function saveGhostty(btn) {
  btn.disabled = true;
  try {
    await api('/api/ghostty', post({
      fontFamily: $('#s-family').value.trim(),
      fontSize: +$('#r-size').value,
      opacity: +$('#r-opacity').value,
      padding: +$('#r-padding').value,
      cursorStyle: $('#s-cursor').value,
      blur: +$('#r-blur').value
    }));
    flash('#st-ghostty', 'Saved — ghostty reloaded');
  } catch (e) { flash('#st-ghostty', e.message, false); }
  btn.disabled = false;
}

/* ── Hyprland look & feel ── */
function updateHlPreview() {
  const p = $('#hl-preview');
  if (!p) return;
  p.style.setProperty('--hl-gapsout', $('#r-gapsout').value + 'px');
  p.style.setProperty('--hl-gapsin', $('#r-gapsin').value + 'px');
  p.style.setProperty('--hl-border', $('#r-border').value + 'px');
  p.style.setProperty('--hl-rounding', $('#r-rounding').value + 'px');
}
['#r-gapsin', '#r-gapsout', '#r-border', '#r-rounding'].forEach((sel, i) =>
  bindRange(sel, ['#o-gapsin', '#o-gapsout', '#o-border', '#o-rounding'][i], v => v, updateHlPreview));

async function loadHyprland() {
  try {
    const h = await api('/api/hyprland');
    $('#r-gapsin').value = h.gapsIn; $('#o-gapsin').textContent = h.gapsIn;
    $('#r-gapsout').value = h.gapsOut; $('#o-gapsout').textContent = h.gapsOut;
    $('#r-border').value = h.borderSize; $('#o-border').textContent = h.borderSize;
    $('#r-rounding').value = h.rounding; $('#o-rounding').textContent = h.rounding;
    updateHlPreview();
  } catch (e) { flash('#st-hyprland', e.message, false); }
}
async function saveHyprland(btn) {
  btn.disabled = true;
  try {
    await api('/api/hyprland', post({
      gapsIn: +$('#r-gapsin').value,
      gapsOut: +$('#r-gapsout').value,
      borderSize: +$('#r-border').value,
      rounding: +$('#r-rounding').value
    }));
    flash('#st-hyprland', 'Saved — hyprctl reload done');
  } catch (e) { flash('#st-hyprland', e.message, false); }
  btn.disabled = false;
}

/* ── Hyprland effects ── */
bindRange('#r-blursize', '#o-blursize', v => v);
bindRange('#r-blurpasses', '#o-blurpasses', v => v);
bindRange('#r-activeop', '#o-activeop', v => (+v).toFixed(2));
bindRange('#r-inactiveop', '#o-inactiveop', v => (+v).toFixed(2));
bindRange('#r-dim', '#o-dim', v => (+v).toFixed(2));

async function loadEffects() {
  try {
    const e = await api('/api/effects');
    $('#t-blur').checked = e.blurEnabled;
    $('#t-shadow').checked = e.shadowEnabled;
    $('#t-anims').checked = e.animations;
    $('#r-blursize').value = e.blurSize; $('#o-blursize').textContent = e.blurSize;
    $('#r-blurpasses').value = e.blurPasses; $('#o-blurpasses').textContent = e.blurPasses;
    $('#r-activeop').value = e.activeOpacity; $('#o-activeop').textContent = e.activeOpacity.toFixed(2);
    $('#r-inactiveop').value = e.inactiveOpacity; $('#o-inactiveop').textContent = e.inactiveOpacity.toFixed(2);
    $('#r-dim').value = e.dimStrength; $('#o-dim').textContent = e.dimStrength.toFixed(2);
  } catch (e) { flash('#st-effects', e.message, false); }
}
async function saveEffects(btn) {
  btn.disabled = true;
  try {
    await api('/api/effects', post({
      blurEnabled: $('#t-blur').checked,
      shadowEnabled: $('#t-shadow').checked,
      animations: $('#t-anims').checked,
      blurSize: +$('#r-blursize').value,
      blurPasses: +$('#r-blurpasses').value,
      activeOpacity: +$('#r-activeop').value,
      inactiveOpacity: +$('#r-inactiveop').value,
      dimStrength: +$('#r-dim').value
    }));
    flash('#st-effects', 'Saved — hyprctl reload done');
  } catch (e) { flash('#st-effects', e.message, false); }
  btn.disabled = false;
}

/* ── Input devices ── */
bindRange('#r-rrate', '#o-rrate', v => v);
bindRange('#r-rdelay', '#o-rdelay', v => v + 'ms');
bindRange('#r-sfactor', '#o-sfactor', v => (+v).toFixed(2));

async function loadInput() {
  try {
    const inp = await api('/api/input');
    $('#s-kblayout').value = inp.kbLayout;
    $('#r-rrate').value = inp.repeatRate; $('#o-rrate').textContent = inp.repeatRate;
    $('#r-rdelay').value = inp.repeatDelay; $('#o-rdelay').textContent = inp.repeatDelay + 'ms';
    $('#t-numlock').checked = inp.numlock;
    $('#t-natscroll').checked = inp.naturalScroll;
    $('#r-sfactor').value = inp.scrollFactor; $('#o-sfactor').textContent = inp.scrollFactor.toFixed(2);
  } catch (e) { flash('#st-input', e.message, false); }
}
async function saveInput(btn) {
  btn.disabled = true;
  try {
    await api('/api/input', post({
      kbLayout: $('#s-kblayout').value.trim(),
      repeatRate: +$('#r-rrate').value,
      repeatDelay: +$('#r-rdelay').value,
      numlock: $('#t-numlock').checked,
      naturalScroll: $('#t-natscroll').checked,
      scrollFactor: +$('#r-sfactor').value
    }));
    flash('#st-input', 'Saved — hyprctl reload done');
  } catch (e) { flash('#st-input', e.message, false); }
  btn.disabled = false;
}

/* ── Clocks ── */
function tickClock() {
  const now = new Date();
  $('#pv-clock').textContent = now.toTimeString().slice(0, 5);
  $('#pv-date').textContent = now.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
  $('#clock').textContent = now.toTimeString().slice(0, 8);
}

/* ── Dashboard: rings, feed, facts ── */
function setRing(id, valId, pct, overrideText) {
  const ring = $('#' + id);
  if (!ring) return;
  const accent = getComputedStyle(ring).getPropertyValue('--accent-ring').trim() || '#3b82f6';
  ring.style.background = `conic-gradient(${accent} ${Math.min(100, pct)}%, rgba(255,255,255,.07) 0)`;
  ring.style.boxShadow = `0 0 ${6 + Math.min(100, pct) * 0.14}px -4px ${accent}`;
  $('#' + valId).innerHTML = (overrideText ?? Math.round(pct)) + '<small>%</small>';
}
async function loadRecentLogs() {
  try {
    const lines = await api('/api/logs/recent?n=10');
    const el = $('#log-feed');
    if (!el) return;
    el.innerHTML = lines.map(l => {
      let cls = '';
      const low = l.toLowerCase();
      if (/\b(err(or)?|fail(ed|ure)?|critical|segfault|denied)\b/.test(low)) cls = 'err';
      else if (/\bwarn(ing)?\b/.test(low)) cls = 'warn';
      return `<div class="log-line ${cls}">${l.replace(/</g, '&lt;')}</div>`;
    }).join('');
    el.scrollTop = el.scrollHeight;
  } catch (e) {}
}
let sysInfoCache = null;
async function loadSystemFacts() {
  try {
    sysInfoCache = await api('/api/system/info');
    renderFacts();
  } catch (e) {}
}
function renderFacts() {
  if (!sysInfoCache) return;
  const rows = [
    ['host', sysInfoCache.hostname], ['user', sysInfoCache.user],
    ['kernel', sysInfoCache.kernel], ['de', sysInfoCache.de],
    ['shell', sysInfoCache.shell], ['wallpaper', sysInfoCache.wallpaper],
  ];
  const html = rows.map(([k, v]) => `<div class="fact-row"><span class="dim">${k}</span><b title="${v}">${String(v).length > 26 ? String(v).slice(0, 26) + '…' : v}</b></div>`).join('');
  const f1 = $('#sys-facts'), f2 = $('#dash-session');
  if (f1) f1.innerHTML = html;
  if (f2) f2.innerHTML = html + `<div class="fact-row"><span class="dim">uptime</span><b>${fmtUptime(lastUptime)}</b></div><div class="fact-row"><span class="dim">load</span><b>${lastLoad}</b></div>`;
}
let lastUptime = 0, lastLoad = 0;

/* ── Appearance color tweak ── */
async function loadAppearance() {
  try {
    const d = await api('/api/appearance');
    const t = d.tweak || {};
    window._palRaw = d.palette || {};
    window._savedTweak = { hue: t.hue || 0, sat: t.sat ?? 1, bright: t.bright ?? 1 };
    document.body.style.filter = ''; $('#tw-live')?.remove();
    $('#r-hue').value = t.hue || 0; $('#o-hue').textContent = (t.hue || 0) + '°';
    $('#r-sat').value = Math.round((t.sat ?? 1) * 100); $('#o-sat').textContent = Math.round((t.sat ?? 1) * 100) + '%';
    $('#r-bright').value = Math.round((t.bright ?? 1) * 100); $('#o-bri2').textContent = Math.round((t.bright ?? 1) * 100) + '%';
    updateTwState(t);
    // preview swatches from palette primary/tertiary
    const pal = d.palette || {};
    const before = pickPal(pal), after = shiftClient(before, +($('#r-hue').value), (+$('#r-sat').value) / 100, (+$('#r-bright').value) / 100);
    $('#tw-before').innerHTML = before.map(c => `<i style="background:${c}"></i>`).join('');
    $('#tw-after').innerHTML = after.map(c => `<i style="background:${c}"></i>`).join('');
  } catch (e) {}
}
function pickPal(pal) {
  const out = [];
  for (const k of ['primary', 'secondary', 'tertiary', 'error']) {
    const c = pal[k]?.default?.hex || pal[k]?.hex;
    if (c) out.push('#' + String(c).replace('#', ''));
  }
  return out.length ? out : ['#3b82f6', '#8b5cf6', '#ec4899', '#ef4444'];
}
function updateTwState(t) {
  const neutral = !t.hue && (t.sat ?? 1) === 1 && (t.bright ?? 1) === 1;
  $('#tw-state').textContent = neutral ? 'neutral' : `hue ${t.hue}° · sat ${Math.round(t.sat * 100)}% · bri ${Math.round(t.bright * 100)}%`;
  ['#o-hue'].forEach(s => {});
}
function savedTweak() { return window._savedTweak || { hue: 0, sat: 1, bright: 1 }; }
function tweakIsDirty() {
  const s = savedTweak();
  return +$('#r-hue').value !== s.hue || +$('#r-sat').value / 100 !== s.sat || +$('#r-bright').value / 100 !== s.bright;
}
// live whole-site preview: CSS filter approximates the shift instantly
function updateTweakPreview() {
  const hue = +$('#r-hue').value, sat = +$('#r-sat').value / 100, bri = +$('#r-bright').value / 100;
  $('#o-hue').textContent = hue + '°';
  $('#o-sat').textContent = Math.round(sat * 100) + '%';
  $('#o-bri2').textContent = Math.round(bri * 100) + '%';
  // after-swatch preview
  const before = pickPal(window._palRaw || {});
  const after = shiftClient(before, hue, sat, bri);
  $('#tw-after').innerHTML = after.map(c => `<i style="background:${c}"></i>`).join('');
  // whole-page approximation preview
  if (tweakIsDirty()) {
    document.body.style.filter = `hue-rotate(${hue}deg) saturate(${sat}) brightness(${bri})`;
    $('#tw-live')?.remove();
    const chip = document.createElement('div');
    chip.id = 'tw-live';
    chip.className = 'mono tiny';
    chip.textContent = '● LIVE PREVIEW — hit Apply to make it real';
    $('.actions .status')?.after?.(chip);
  } else {
    document.body.style.filter = '';
    $('#tw-live')?.remove();
  }
}
['r-hue', 'r-sat', 'r-bright'].forEach(id => $('#' + id)?.addEventListener('input', updateTweakPreview));
async function applyTweak(btn) {
  btn.disabled = true;
  try {
    const res = await api('/api/appearance', post({
      hue: +$('#r-hue').value,
      sat: +$('#r-sat').value / 100,
      bright: +$('#r-bright').value / 100
    }));
    document.body.style.filter = ''; $('#tw-live')?.remove();
    updateTwState(res.tweak);
    toast('Theme shifted · apps reloaded'); 
    loadTheme(); loadAppearance();
  } catch (e) { toast(e.message, 'err'); }
  btn.disabled = false;
}
async function resetTweak(btn) {
  btn.disabled = true;
  try {
    const res = await api('/api/appearance', post({ reset: true }));
    updateTwState(res.tweak);
    toast('Back to wallpaper colors');
    $('#r-hue').value = 0; $('#o-hue').textContent = '0°';
    $('#r-sat').value = 100; $('#o-sat').textContent = '100%';
    $('#r-bright').value = 100; $('#o-bri2').textContent = '100%';
    loadTheme();
  } catch (e) { toast(e.message, 'err'); }
  btn.disabled = false;
}

// tiny client-side hsl shift for the before/after preview only
function shiftClient(hexes, dh, sm, bm) {
  const out = [];
  for (let hex of hexes) {
    let r = parseInt(hex.slice(1, 3), 16) / 255, g = parseInt(hex.slice(3, 5), 16) / 255, b = parseInt(hex.slice(5, 7), 16) / 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    let h = 0, s = 0, l = (mx + mn) / 2;
    if (mx !== mn) {
      const d = mx - mn;
      s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn);
      if (mx === r) { h = (g - b) / d; if (g < b) h += 6; }
      else if (mx === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h *= 60;
    }
    h = ((h + dh) % 360 + 360) % 360; s = Math.min(1, s * sm); l = Math.max(0, Math.min(1, l * bm));
    const q = l < .5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    const hue2 = t => { if (t < 0) t++; if (t > 1) t--; return t < 1/6 ? p+(q-p)*6*t : t < .5 ? q : t < 2/3 ? p+(q-p)*(2/3-t)*6 : p; };
    const c = v => Math.round(hue2(v) * 255).toString(16).padStart(2, '0');
    out.push('#' + c(1/3) + c(0) + c(-1/3));
  }
  return out;
}

/* ── Boot ── */
initCharts();
tickClock(); setInterval(tickClock, 1000);
pollStats(); setInterval(pollStats, 2000);
setInterval(() => { loadDisks(); loadProcesses(); loadServices(); }, 4000);
setInterval(loadPowerProfile, 10000);
loadDisks(); loadProcesses(); loadServices(); loadSystemInfo();
loadAudio(); loadBrightness(); loadNetwork(); loadPowerProfile();
connectLogs();
loadRecentLogs(); setInterval(loadRecentLogs, 5000);
loadSystemFacts();
loadAppearance();
window.addEventListener('resize', updateTermFont);
