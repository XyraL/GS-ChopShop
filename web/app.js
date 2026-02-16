/* GS-ChopShop NUI */
(function () {
  'use strict';

  function $(id) { return document.getElementById(id); }

  var state = {
    open: false,
    serverTime: 0,
    unlocks: null,
    contract: null,
    session: null,
    leaderboard: [],
    history: [],
    progress: null,
    upgrades: null
  };

  // Upgrades
  var upgrades = [
    { id: 'chop_speed', name: 'Chop Speed', desc: 'Reduce action time across dismantle steps.', price: 25000, tag: '+10% faster', locked: false },
    { id: 'clean_payout', name: 'Clean Payout', desc: 'Boost final cash payout when the shell is disposed.', price: 40000, tag: '+10% payout', locked: false },
    { id: 'heat_dampener', name: 'Heat Dampener', desc: 'Lower the chance of police attention during a run.', price: 60000, tag: '-10% heat', locked: false },
    { id: 'scanner', name: 'Scanner Suite', desc: 'Tighten search radius on higher tiers for faster finds.', price: 85000, tag: 'Smaller zone', locked: true },
    { id: 'auto_dispatch', name: 'Auto Dispatch', desc: 'Streamline final disposal. Less waiting, more runs.', price: 120000, tag: 'Faster finish', locked: true }
  ];

  function post(name, data) {
    data = data || {};
    return fetch('https://' + GetParentResourceName() + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data)
    }).catch(function () {
    });
  }

  function pad2(n) { n = Math.floor(Math.max(0, n)); return (n < 10 ? '0' : '') + n; }

  function fmtMMSS(secs) {
    secs = Math.max(0, Math.floor(secs || 0));
    var m = Math.floor(secs / 60);
    var s = secs % 60;
    return pad2(m) + ':' + pad2(s);
  }

  function nowServer() {
    var local = Math.floor(Date.now() / 1000);
    if (!state.serverTime || state.serverTime <= 0) return local;
    if (!nowServer._baseLocal) {
      nowServer._baseLocal = local;
      nowServer._baseServer = state.serverTime;
    }
    return nowServer._baseServer + (local - nowServer._baseLocal);
  }

  function resetServerClockBaseline() {
    nowServer._baseLocal = null;
    nowServer._baseServer = null;
  }

  var stepMeta = {
    vin_scratch: { label: 'Scratch VIN', tip: 'Scratch the VIN before dismantling to reduce traceability.' },
    plate_front: { label: 'Remove Front Plate', tip: 'Remove plates early. Less attention, fewer questions.' },
    plate_rear:  { label: 'Remove Rear Plate',  tip: 'Remove plates early. Less attention, fewer questions.' },

    door_lf: { label: 'Remove Driver Door', tip: 'Stand close to the hinge line and work the fasteners.' },
    door_rf: { label: 'Remove Passenger Door', tip: 'Stand close to the hinge line and work the fasteners.' },
    door_lr: { label: 'Remove Rear Left Door', tip: 'Rear doors come off easier after fronts.' },
    door_rr: { label: 'Remove Rear Right Door', tip: 'Rear doors come off easier after fronts.' },

    hood:  { label: 'Remove Hood',  tip: 'Pop it open and disconnect the mounting bolts.' },
    trunk: { label: 'Remove Trunk', tip: 'Pop it open and disconnect the mounting bolts.' },

    wheel_lf: { label: 'Remove Front Left Wheel', tip: 'Kneel at the wheel and loosen the lugs.' },
    wheel_rf: { label: 'Remove Front Right Wheel', tip: 'Kneel at the wheel and loosen the lugs.' },
    wheel_lr: { label: 'Remove Rear Left Wheel', tip: 'Kneel at the wheel and loosen the lugs.' },
    wheel_rr: { label: 'Remove Rear Right Wheel', tip: 'Kneel at the wheel and loosen the lugs.' },

    move_shell: { label: 'Push Shell to Cut Line', tip: 'Push the shell onto the marked cut line.' },
    cut_shell:  { label: 'Cut the Shell', tip: 'Cut the chassis at the seam. Keep it steady.' },
    engine:     { label: 'Pull Engine', tip: 'Delicate work. Expect resistance. Don’t rush.' },
    final:      { label: 'Dispose Shell', tip: 'Finish the job and clear the bay for payout.' }
  };

  function getNextStep(session) {
    if (!session || !session.requiredList || !session.requiredList.length) return null;
    var done = session.done || {};
    for (var i = 0; i < session.requiredList.length; i++) {
      var k = session.requiredList[i];
      if (k === 'final') continue;
      if (!done[k]) return k;
    }
    if (session.requiredList.indexOf('final') !== -1 && !done['final']) return 'final';
    return null;
  }

  function getProgress(session) {
    var out = { done: 0, total: 0, pct: 0 };
    if (!session || !session.requiredList || !session.requiredList.length) return out;
    var doneMap = session.done || {};
    for (var i = 0; i < session.requiredList.length; i++) {
      var k = session.requiredList[i];
      if (k === 'final') continue;
      out.total++;
      if (doneMap[k]) out.done++;
    }
    out.pct = out.total ? Math.floor((out.done / out.total) * 100) : 0;
    return out;
  }

  function escapeHtml(str) {
    str = String(str == null ? '' : str);
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function fmtCash(n){
    n = Math.floor(Number(n) || 0);
    var s = String(Math.abs(n));
    var out = '';
    while (s.length > 3) {
      out = ',' + s.slice(-3) + out;
      s = s.slice(0, -3);
    }
    out = s + out;
    return (n < 0 ? '-' : '') + '$' + out;
  }

  function setTab(tab) {
    // Soft UI whoosh on tab switch
    try { SFX.whoosh(); } catch (e) {}
    var tabs = document.querySelectorAll('[data-tab]');
    for (var i = 0; i < tabs.length; i++) {
      var t = tabs[i].getAttribute('data-tab');
      tabs[i].classList.toggle('active', t === tab);
    }
    var views = document.querySelectorAll('.view');
    for (var j = 0; j < views.length; j++) {
      var v = views[j].getAttribute('data-view');
      views[j].classList.toggle('active', v === tab);
    }
  }

  // --- Cinematic SFX ---
  var SFX = (function(){
    var ctx = null;
    function getCtx(){
      if (ctx) return ctx;
      var AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
      return ctx;
    }

    function noiseBurst(dur, gain, hp){
      var c = getCtx();
      if (!c) return;
      if (c.state === 'suspended') { try { c.resume(); } catch(e){} }

      var bufferSize = Math.floor(c.sampleRate * dur);
      var buffer = c.createBuffer(1, bufferSize, c.sampleRate);
      var data = buffer.getChannelData(0);
      for (var i = 0; i < bufferSize; i++) {
        data[i] = (Math.random() * 2 - 1);
      }
      var src = c.createBufferSource();
      src.buffer = buffer;

      var g = c.createGain();
      g.gain.setValueAtTime(0.0001, c.currentTime);
      g.gain.exponentialRampToValueAtTime(gain, c.currentTime + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + dur);

      var filter = c.createBiquadFilter();
      filter.type = 'highpass';
      filter.frequency.setValueAtTime(hp || 800, c.currentTime);

      src.connect(filter);
      filter.connect(g);
      g.connect(c.destination);
      src.start();
      src.stop(c.currentTime + dur);
    }

    function tick(){
      var c = getCtx();
      if (!c) return;
      if (c.state === 'suspended') { try { c.resume(); } catch(e){} }
      var o = c.createOscillator();
      var g = c.createGain();
      o.type = 'triangle';
      o.frequency.setValueAtTime(980, c.currentTime);
      g.gain.setValueAtTime(0.0001, c.currentTime);
      g.gain.exponentialRampToValueAtTime(0.12, c.currentTime + 0.005);
      g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + 0.12);
      o.connect(g); g.connect(c.destination);
      o.start(); o.stop(c.currentTime + 0.13);
    }

    return {
      whoosh: function(){ noiseBurst(0.18, 0.09, 900); },
      scan: function(){ noiseBurst(0.22, 0.07, 650); },
      tick: tick
    };
  })();

  function renderContractPanel() {
    var c = state.contract;
    var s = state.session;

    $('contractStatus').textContent = c ? (c.found ? 'FOUND' : 'ACTIVE') : 'IDLE';

    var st = nowServer();
    var d = new Date(st * 1000);
    $('serverClock').textContent = pad2(d.getHours()) + ':' + pad2(d.getMinutes());

    if (!c) {
      $('liveTimer').textContent = '--:--';
      $('liveSub').textContent = 'No contract.';
      $('tierPill').textContent = 'TIER: -';
      $('platePill').textContent = 'PLATE: -';
      $('activeTier').textContent = '-';
      $('activeVeh').textContent = '-';
      $('activePlate').textContent = '-';
      $('activeExpires').textContent = '--:--';
      $('nextLabel').textContent = '—';
      $('nextTip').textContent = 'Start a contract to see next steps.';
      if ($('modChips')) $('modChips').innerHTML = '';
      $('stepCount').textContent = 'Step 0 / 0';
      $('progressPct').textContent = '0%';
      $('progressBarFill').style.width = '0%';
      if ($('timeline')) $('timeline').innerHTML = '';
      $('checklist').innerHTML = '';
      $('cancelBtn').disabled = true;
      return;
    }

    $('cancelBtn').disabled = false;

    var rem = (c.expiresAt || 0) - st;
    if (rem < 0) rem = 0;
    $('liveTimer').textContent = fmtMMSS(rem);
    $('liveSub').textContent = escapeHtml(c.model) + ' • plate locked';
    $('tierPill').textContent = 'TIER: ' + String(c.tier || '').toUpperCase();
    $('platePill').textContent = 'PLATE: ' + String(c.plate || '').toUpperCase();
    $('activeTier').textContent = c.tier || '-';
    $('activeVeh').textContent = c.model || '-';
    $('activePlate').textContent = c.plate || '-';
    $('activeExpires').textContent = fmtMMSS(rem);

    var next = getNextStep(s);
    var prog = getProgress(s);
    var meta = next && stepMeta[next] ? stepMeta[next] : null;
    $('nextLabel').textContent = meta ? meta.label : (next ? next : '—');
    $('nextTip').textContent = meta ? meta.tip : (next ? 'Follow the required workflow.' : (c.found ? 'Drive to the salvage yard bay to begin.' : 'Find the contract vehicle.'));

    // Smarter contract modifiers
    try {
      var mc = $('modChips');
      if (mc) {
        mc.innerHTML = '';
        var mods = c.modifiers || [];
        for (var mi = 0; mi < mods.length; mi++) {
          var m = mods[mi] || {};
          var chip = document.createElement('div');
          chip.className = 'modChip';
          chip.title = m.desc || '';
          chip.innerHTML = '<span class="modDot"></span><span>' + escapeHtml(m.label || m.id || 'Modifier') + '</span>';
          mc.appendChild(chip);
        }
      }
    } catch (eM) {}

    $('stepCount').textContent = 'Step ' + String(Math.min(prog.done + 1, Math.max(prog.total, 1))) + ' / ' + String(prog.total || 0);
    $('progressPct').textContent = String(prog.pct) + '%';
    $('progressBarFill').style.width = String(prog.pct) + '%';

    var list = '';
    var tl = '';
    if (s && s.requiredList && s.requiredList.length) {
      var doneMap = s.done || {};
      for (var i = 0; i < s.requiredList.length; i++) {
        var k = s.requiredList[i];
        if (k === 'final') continue;
        var label = (stepMeta[k] && stepMeta[k].label) ? stepMeta[k].label : k;
        var cls = doneMap[k] ? 'done' : (k === next ? 'current' : 'upcoming');
        var icon = doneMap[k] ? '✔' : (k === next ? '➜' : '○');
        list += '<div class="checkItem ' + cls + '"><span class="ciIcon">' + icon + '</span><span class="ciText">' + escapeHtml(label) + '</span></div>';

        var tip = (stepMeta[k] && stepMeta[k].tip) ? stepMeta[k].tip : 'Follow procedure.';
        tl += '<div class="tItem ' + cls + '">' +
          '<div class="tDot">' + (doneMap[k] ? '✓' : (k === next ? '▶' : '•')) + '</div>' +
          '<div class="tMain"><div class="tLabel">' + escapeHtml(label) + '</div><div class="tSub">' + escapeHtml(tip) + '</div></div>' +
        '</div>';
      }
    }
    if ($('timeline')) $('timeline').innerHTML = tl || '<div class="muted">No steps yet.</div>';
    $('checklist').innerHTML = list || '<div class="muted">No steps yet.</div>';
  }

  function renderLeaderboard() {
    var rows = '';
    for (var i = 0; i < (state.leaderboard || []).length; i++) {
      var r = state.leaderboard[i];
      rows += '<div class="row"><div class="rowLeft">#' + (i + 1) + ' ' + escapeHtml(r.name || r.citizenid || 'Player') + '</div><div class="rowRight">' + escapeHtml(String(r.chops || 0)) + '</div></div>';
    }
    $('lbList').innerHTML = rows || '<div class="muted">No data yet.</div>';
  }

  function renderHistory() {
    var rows = '';
    for (var i = 0; i < (state.history || []).length; i++) {
      var r = state.history[i];
      rows += '<div class="row"><div class="rowLeft">' + escapeHtml((r.tier || 'tier').toUpperCase()) + ' • ' + escapeHtml(r.model || '-') + '</div><div class="rowRight">$' + escapeHtml(String(r.earned || 0)) + '</div></div>';
    }
    $('histList').innerHTML = rows || '<div class="muted">No history yet.</div>';
  }

  function renderSystem() {
    var p = state.progress || { tier1: 0, tier2: 0, tier3: 0 };
    $('sysText').innerHTML =
      '<div class="sysK">Tier 1 completed:</div><div class="sysV">' + escapeHtml(String(p.tier1 || 0)) + '</div>' +
      '<div class="sysK">Tier 2 completed:</div><div class="sysV">' + escapeHtml(String(p.tier2 || 0)) + '</div>' +
      '<div class="sysK">Tier 3 completed:</div><div class="sysV">' + escapeHtml(String(p.tier3 || 0)) + '</div>';
  }

  function renderUpgrades() {
    var el = $('upgList');
    if (!el) return;

    var upState = state.upgrades || {};
    var lv = upState.levels || {};
    var prices = upState.prices || {};
    var caps = upState.caps || {};

    var html = '';
    for (var i = 0; i < upgrades.length; i++) {
      var u = upgrades[i];
      var level = parseInt(lv[u.id] || 0, 10) || 0;
      var cap = parseInt(caps[u.id] || 0, 10) || 0;
      var maxed = cap > 0 && level >= cap;
      var price = parseInt(prices[u.id] || u.price || 0, 10) || 0;
      var disabled = (u.locked || maxed) ? 'disabled' : '';
      var btnTxt = u.locked ? 'Locked' : (maxed ? 'Maxed' : 'Purchase');
      html +=
        '<div class="upgItem luxShimmer">'
          + '<div class="upgLeft">'
            + '<div class="upgName">' + escapeHtml(u.name) + '</div>'
            + '<div class="upgDesc">' + escapeHtml(u.desc) + '</div>'
            + '<div class="upgTags"><span class="upgTag">' + escapeHtml(u.tag) + '</span></div>'
          + '</div>'
          + '<div class="upgRight">'
            + '<div class="upgPrice">Lvl ' + escapeHtml(String(level)) + (cap ? (' / ' + escapeHtml(String(cap))) : '') + ' • $' + escapeHtml(String(price)) + '</div>'
            + '<button class="btn gold" data-upg="' + escapeHtml(u.id) + '" ' + disabled + '>' + btnTxt + '</button>'
          + '</div>'
        + '</div>';
    }
    el.innerHTML = html;

    // bind purchase buttons
    var btns = el.querySelectorAll('[data-upg]');
    for (var j = 0; j < btns.length; j++) {
      (function (b) {
        b.onclick = function () {
          var id = b.getAttribute('data-upg');
          post('buyUpgrade', { id: id });
          var msg = $('upgMsg');
          if (msg) msg.textContent = 'Purchase requested.';
          setTimeout(function(){ post('refresh'); }, 250);
        };
      })(btns[j]);
    }
  }

  function renderTiers() {
    var c = state.contract;
    var unlocks = state.unlocks || {};
    var prog = state.progress || { tier1: 0, tier2: 0, tier3: 0 };
    var t1 = $('tier1Btn'), t2 = $('tier2Btn'), t3 = $('tier3Btn');
    if (!t1) return;

    var locked2 = unlocks.tier2RequiresTier1 && (prog.tier1 || 0) < unlocks.tier2RequiresTier1;
    var locked3 = unlocks.tier3RequiresTier2 && (prog.tier2 || 0) < unlocks.tier3RequiresTier2;

    t1.disabled = !!c;
    t2.disabled = !!c || locked2;
    t3.disabled = !!c || locked3;

    $('tier2Lock').textContent = locked2 ? ('Locked: complete ' + unlocks.tier2RequiresTier1 + ' Tier 1') : 'Unlocked';
    $('tier3Lock').textContent = locked3 ? ('Locked: complete ' + unlocks.tier3RequiresTier2 + ' Tier 2') : 'Unlocked';
  }

  function renderAll() {
    renderContractPanel();
    renderTiers();
    renderLeaderboard();
    renderHistory();
    renderSystem();
    renderUpgrades();
  }

  function bind() {
    $('closeBtn').onclick = function () { post('close'); };
    $('refreshBtn').onclick = function () { post('refresh'); };
    $('cancelBtn').onclick = function () {
      post('cancelContract');
      $('cancelBtn').disabled = true;
      setTimeout(function () { post('refresh'); }, 200);
    };

    $('tier1Btn').onclick = function () { post('startContract', { tier: 'tier1' }); setTimeout(function () { post('refresh'); }, 200); };
    $('tier2Btn').onclick = function () { post('startContract', { tier: 'tier2' }); setTimeout(function () { post('refresh'); }, 200); };
    $('tier3Btn').onclick = function () { post('startContract', { tier: 'tier3' }); setTimeout(function () { post('refresh'); }, 200); };

    var tabBtns = document.querySelectorAll('[data-tab]');
    for (var i = 0; i < tabBtns.length; i++) {
      (function (btn) {
        btn.onclick = function () { setTab(btn.getAttribute('data-tab')); };
      })(tabBtns[i]);
    }

    $('checkToggle').onclick = function () {
      var wrap = $('checkWrap');
      var open = wrap.classList.toggle('open');
      $('checkToggle').textContent = open ? 'Hide checklist' : 'Show checklist';
    };

    // Local UI settings
    var app = document.getElementById('app');
    var themeNeon = $('themeNeon');
    var themeCarbon = $('themeCarbon');
    var uiScale = $('uiScale');
    var uiScaleVal = $('uiScaleVal');

    function applyTheme(t) {
      if (!app) return;
      t = (t === 'carbon') ? 'carbon' : 'neon';
      app.setAttribute('data-theme', t);
      if (themeNeon) themeNeon.classList.toggle('active', t === 'neon');
      if (themeCarbon) themeCarbon.classList.toggle('active', t === 'carbon');
      try { localStorage.setItem('gs_chopshop_theme', t); } catch (e) {}
    }

    function applyScale(v) {
      v = Math.max(85, Math.min(115, parseInt(v, 10) || 100));
      var z = (v / 100);
      document.documentElement.style.setProperty('--uiZoom', String(z));
      if (uiScaleVal) uiScaleVal.textContent = String(v) + '%';
      if (uiScale) uiScale.value = String(v);
      try { localStorage.setItem('gs_chopshop_scale', String(v)); } catch (e) {}
    }

    // Load persisted values
    var savedTheme = null;
    var savedScale = null;
    try {
      savedTheme = localStorage.getItem('gs_chopshop_theme');
      savedScale = localStorage.getItem('gs_chopshop_scale');
    } catch (e) {}
    applyTheme(savedTheme);
    applyScale(savedScale);

    if (themeNeon) themeNeon.onclick = function () { applyTheme('neon'); };
    if (themeCarbon) themeCarbon.onclick = function () { applyTheme('carbon'); };
    if (uiScale) {
      uiScale.oninput = function () {
        // live label only (smooth drag)
        var v = Math.max(85, Math.min(115, parseInt(uiScale.value, 10) || 100));
        if (uiScaleVal) uiScaleVal.textContent = String(v) + '%';
      };
      uiScale.onchange = function () { applyScale(uiScale.value); };
      uiScale.onpointerup = function () { applyScale(uiScale.value); };
      uiScale.ontouchend = function () { applyScale(uiScale.value); };
      uiScale.onmouseup = function () { applyScale(uiScale.value); };
    }
  }

  setInterval(function () {
    if (!state.open) return;
    renderContractPanel();
  }, 250);

  window.addEventListener('message', function (event) {
    var msg = event.data || {};

    if (msg.type === 'completeCinematic') {
      try {
        var ov = $('completeOverlay');
        if (ov) {
          $('completeCash').textContent = '+' + fmtCash(msg.cash || 0);
          var meta = [];
          if (msg.tier) meta.push(String(msg.tier).toUpperCase());
          if (msg.plate) meta.push('PLATE ' + String(msg.plate));
          if (msg.model) meta.push(String(msg.model));
          $('completeMeta').textContent = meta.length ? meta.join(' • ') : '—';

          var modsEl = $('completeMods');
          modsEl.innerHTML = '';
          var mods = msg.modifiers || [];
          for (var i = 0; i < mods.length; i++) {
            var m = mods[i] || {};
            var chip = document.createElement('div');
            chip.className = 'cMod';
            chip.textContent = m.label || m.id || 'Modifier';
            modsEl.appendChild(chip);
          }
          ov.classList.remove('show');
          ov.offsetHeight;
          ov.classList.add('show');
          // cinematic stinger
          try { SFX.scan(); } catch(e){}
        }
      } catch (eC) {}
      return;
    }
    if (msg.type === 'toggle') {
      state.open = !!msg.state;
      document.body.classList.toggle('open', state.open);
      try { var ov0 = $('completeOverlay'); if (ov0) ov0.classList.remove('show'); } catch(e0) {}
      if (state.open) {
        setTab('contract');
        post('refresh');
      }
      return;
    }

    if (msg.type === 'data') {
      var prevContract = state.contract;
      var prevSession = state.session;
      var prevDoneCount = 0;
      if (prevSession && prevSession.done) {
        for (var k in prevSession.done) { if (prevSession.done.hasOwnProperty(k) && prevSession.done[k]) prevDoneCount++; }
      }

      var d = msg.data || {};
      state.serverTime = d.serverTime || 0;
      resetServerClockBaseline();
      state.unlocks = d.unlocks || null;
      state.contract = d.contract || null;
      state.session = d.session || null;
      state.leaderboard = d.leaderboard || [];
      state.history = d.history || [];
      state.progress = d.progress || null;
      state.upgrades = d.upgrades || null;

      // Contract start: gold scan sweep + sfx
      try {
        var started = (!prevContract && state.contract) || (prevContract && state.contract && prevContract.startedAt !== state.contract.startedAt);
        if (started) {
          var app = $('app');
          if (app) {
            app.classList.remove('scan');
            // force reflow
            app.offsetHeight;
            app.classList.add('scan');
            setTimeout(function(){ try{ app.classList.remove('scan'); }catch(e){} }, 950);
          }
          SFX.scan();
        }
      } catch (e) {}

      // Step complete: tick + micro pulse
      try {
        var newDoneCount = 0;
        var s = state.session;
        if (s && s.done) {
          for (var kk in s.done) { if (s.done.hasOwnProperty(kk) && s.done[kk]) newDoneCount++; }
        }
        if (newDoneCount > prevDoneCount) {
          SFX.tick();
          var app2 = $('app');
          if (app2) {
            app2.classList.remove('stepPulse');
            app2.offsetHeight;
            app2.classList.add('stepPulse');
            setTimeout(function(){ try{ app2.classList.remove('stepPulse'); }catch(e){} }, 320);
          }
        }
      } catch (e2) {}

      renderAll();
      return;
    }
  });

  document.addEventListener('keydown', function (e) {
    if (!state.open) return;
    if (e.keyCode === 27) post('close');
  });

  document.addEventListener('DOMContentLoaded', function () {
    bind();
    setTab('contract');
  });
})();
