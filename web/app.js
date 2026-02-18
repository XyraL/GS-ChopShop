/* GS-ChopShop NUI (Revamp V5) - ES5 Safe */
(function () {
  'use strict';

  function $(id) { return document.getElementById(id); }
  var DOM_READY = false;
  function safeText(id, value) {
    var el = $(id);
    if (!el) return;
    el.textContent = value;
  }

  function safeStyle(id, prop, value) {
    var el = $(id);
    if (!el || !el.style) return;
    el.style[prop] = value;
  }

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

  // Luxury Upgrades (UI first; server economy hook can be wired later)
  var upgrades = [
    { id:'tech_hands', name:'Technician Hands', desc:'Quicker work on dismantle actions.', tag:'Personal', category:'personal',
      preview:function(cur,next){ return 'Time: -' + (cur*3) + '% → -' + (next*3) + '%'; } },
    { id:'runner_instinct', name:'Runner Instinct', desc:'Better search intel and faster lock-on.', tag:'Personal', category:'personal',
      preview:function(cur,next){ return 'Radius: -' + (cur*6) + '% → -' + (next*6) + '%'; } },
    { id:'broker_cut', name:'Broker Cut', desc:'Cleaner deals, better money per run.', tag:'Personal', category:'personal',
      preview:function(cur,next){ return 'Payout: +' + (cur*6) + '% → +' + (next*6) + '%'; } },
    { id:'scanner', name:'Scanner Suite', desc:'Tightens the search radius on higher tiers.', tag:'Personal', category:'personal',
      preview:function(cur,next){ return 'Radius: -' + (cur*10) + '% → -' + (next*10) + '%'; } },

    { id:'hydraulic_lift', name:'Hydraulic Lift', desc:'Faster positioning and access to parts.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Time: -' + (cur*4) + '% → -' + (next*4) + '%'; } },
    { id:'chop_speed', name:'Chop Speed', desc:'Reduces action time across steps.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Time: -' + (cur*5) + '% → -' + (next*5) + '%'; } },
    { id:'sound_dampening', name:'Sound Dampening', desc:'Lower attention during the job.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Alert: -' + (cur*6) + '% → -' + (next*6) + '%'; } },
    { id:'heat_dampener', name:'Heat Dampener', desc:'Lower attention during the job.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Alert: -' + (cur*8) + '% → -' + (next*8) + '%'; } },
    { id:'scrap_compactor', name:'Scrap Compactor', desc:'More value from the same metal.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Payout: +' + (cur*5) + '% → +' + (next*5) + '%'; } },
    { id:'shell_shredder', name:'Shell Shredder', desc:'Streamlines final disposal.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Final: -' + (cur*8) + '% → -' + (next*8) + '%'; } },
    { id:'auto_dispatch', name:'Auto Dispatch', desc:'Streamlines final disposal.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Final: -' + (cur*10) + '% → -' + (next*10) + '%'; } },
    { id:'clean_payout', name:'Clean Payout', desc:'Boosts final cash payout.', tag:'Shop', category:'shop',
      preview:function(cur,next){ return 'Payout: +' + (cur*10) + '% → +' + (next*10) + '%'; } },

    { id:'fence_connections', name:'Fence Connections', desc:'Better buyers and better prices.', tag:'Network', category:'network',
      preview:function(cur,next){ return 'Payout: +' + (cur*7) + '% → +' + (next*7) + '%'; } },
    { id:'parts_market', name:'Parts Market', desc:'Demand spikes, payouts climb.', tag:'Network', category:'network',
      preview:function(cur,next){ return 'Payout: +' + (cur*4) + '% → +' + (next*4) + '%'; } },
    { id:'forgery_lab', name:'Forgery Lab', desc:'Improves special contract access.', tag:'Network', category:'network',
      preview:function(cur,next){ return 'Special Weight: +' + (cur*5) + '% → +' + (next*5) + '%'; } }
  ];

  function post(name, data) {
    data = data || {};
    return fetch('https://' + GetParentResourceName() + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data)
    }).catch(function () {
      // swallow fetch errors
    });
  }

  function pad2(n) { n = Math.floor(Math.max(0, n)); return (n < 10 ? '0' : '') + n; }

    function fmt2(n){ n = Number(n||0); return (Math.round(n*100)/100).toFixed(2); }

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

  // --- Cinematic SFX (no external libs) ---
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
    if (!DOM_READY) return;
    var c = state.contract;
    var s = state.session;

    safeText('contractStatus', c ? (c.found ? 'FOUND' : 'ACTIVE') : 'IDLE');

    var st = nowServer();
    var d = new Date(st * 1000);
    safeText('serverClock', pad2(d.getHours()) + ':' + pad2(d.getMinutes()));

    if (!c) {
      safeText('liveTimer','--:--');
      safeText('liveSub','No contract.');
      safeText('tierPill','TIER: -');
      safeText('platePill','PLATE: -');
      safeText('activeTier','-');
      safeText('activeVeh','-');
      safeText('activePlate','-');
      safeText('activeExpires','--:--');
      safeText('nextLabel','—');
      safeText('nextTip','Start a contract to see next steps.');
      if ($('modChips')) $('modChips').innerHTML = '';
      safeText('stepCount','Step 0 / 0');
      safeText('progressPct','0%');
      safeStyle('progressBarFill', 'width', '0%');
      var tl = $('timeline'); if (tl) tl.innerHTML = '';
      var cl = $('checklist') || $('checklistRight'); if (cl) cl.innerHTML = '';
      var cb2 = $('cancelBtn'); if (cb2) cb2.disabled = true;
      // co-op removed
      try {
        var sp = $('startPanel');
        var rp = $('rightChecklistPanel');
        if (sp) sp.classList.remove('hidden');
        if (rp) rp.classList.add('hidden');
        if ($('rightCardTitle')) $('rightCardTitle').textContent = 'Start New Contract';
        if ($('rightCardSub')) $('rightCardSub').textContent = 'Choose your tier. Higher tiers hit harder.';
        if ($('checklistRight')) $('checklistRight').innerHTML = '';
      } catch(e){}
      return;
    }

    var cb = $('cancelBtn'); if (cb) cb.disabled = false;
    // co-op removed

    var rem = (c.expiresAt || 0) - st;
    if (rem < 0) rem = 0;
    safeText('liveTimer', fmtMMSS(rem));
    safeText('liveSub', (c.model ? String(c.model) : '-') + ' • plate locked');
    safeText('tierPill', (c.specialTag ? (String(c.specialTag).toUpperCase()) : ('TIER: ' + String(c.tier || '').toUpperCase())));
    safeText('platePill', 'PLATE: ' + String(c.plate || '').toUpperCase());
    safeText('activeTier', c.tier || '-');
    safeText('activeVeh', c.model || '-');
    safeText('activePlate', c.plate || '-');
    safeText('activeExpires', fmtMMSS(rem));

    var next = getNextStep(s);
    var prog = getProgress(s);
    var meta = next && stepMeta[next] ? stepMeta[next] : null;
    safeText('nextLabel', meta ? meta.label : (next ? next : '—'));
    safeText('nextTip', meta ? meta.tip : (next ? 'Follow the required workflow.' : (c.found ? 'Drive to the salvage yard bay to begin.' : 'Find the contract vehicle.')));

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

    // Bonus objective (with live status)
    try {
      var bb = $("bonusBox");
      var row = $("bonusStatusRow");
      var pill = $("bonusStatusPill");
      var txt = $("bonusStatusText");

      if (bb) bb.innerHTML = "";

      if (!c || !c.bonusObjective || !c.bonusObjective.label) {
        if (row) row.classList.add("hidden");
      } else {
        var b = c.bonusObjective;
        var stt = (c.bonus && c.bonus.state) ? String(c.bonus.state) : "active";
        var pretty = stt === "at_risk" ? "AT RISK" : (stt === "failed" ? "FAILED" : (stt === "completed" ? "COMPLETED" : "ACTIVE"));

        if (bb) {
          bb.innerHTML =
            "<div class=\"bonusRow\">" +
              "<span class=\"bonusTag\">BONUS</span>" +
              "<div class=\"bonusText\">" +
                "<div class=\"bonusLabel\">" + escapeHtml(b.label) + "</div>" +
                "<div class=\"bonusDesc\">" + escapeHtml(b.desc || "") + "</div>" +
              "</div>" +
            "</div>";
        }

        if (row) row.classList.remove("hidden");
        if (pill) {
          pill.textContent = pretty;
          pill.className = "bonusPill " + (stt || "active");
        }
        if (txt) {
          // show reward info
          var parts = [];
          if (b.moneyMult && Number(b.moneyMult) > 1) parts.push("+" + Math.round((Number(b.moneyMult) - 1) * 100) + "% cash");
          if (b.rep && Number(b.rep) > 0) parts.push("+" + Number(b.rep) + " rep");
          txt.textContent = parts.length ? ("Reward: " + parts.join(" • ")) : "";
        }
      }
    } catch (eB) {}

    safeText('stepCount', 'Step ' + String(Math.min(prog.done + 1, Math.max(prog.total, 1))) + ' / ' + String(prog.total || 0));
    safeText('progressPct', String(prog.pct) + '%');
    safeStyle('progressBarFill', 'width', String(prog.pct) + '%');

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
    var tlEl2 = $('timeline'); if (tlEl2) tlEl2.innerHTML = tl || '<div class="muted">No steps yet.</div>';
    var clEl2 = $('checklist') || $('checklistRight'); if (clEl2) clEl2.innerHTML = list || '<div class="muted">No steps yet.</div>';
    // Right column swap: show checklist when contract is active
    try {
      var sp2 = $('startPanel');
      var rp2 = $('rightChecklistPanel');
      if (sp2) sp2.classList.add('hidden');
      if (rp2) rp2.classList.remove('hidden');
      if ($('rightCardTitle')) $('rightCardTitle').textContent = 'Contract Checklist';
      if ($('rightCardSub')) $('rightCardSub').textContent = 'Live steps for this run.';
      var rhtml = '';
      if (s && s.requiredList && s.requiredList.length) {
        var doneMap2 = s.done || {};
        for (var ri=0;ri<s.requiredList.length;ri++){
          var rk = s.requiredList[ri];
          if (rk === 'final') continue;
          var rlabel = (stepMeta[rk] && stepMeta[rk].label) ? stepMeta[rk].label : rk;
          var rtip = (stepMeta[rk] && stepMeta[rk].tip) ? stepMeta[rk].tip : '';
          var rdone = !!doneMap2[rk];
          var rcls = rdone ? 'cItem done' : (rk === next ? 'cItem' : 'cItem');
          rhtml += '<div class="' + rcls + '"><div class="cLabel">' + escapeHtml(rlabel) + '</div><div class="cSub">' + escapeHtml(rtip) + '</div></div>';
        }
      }
      if ($('checklistRight')) $('checklistRight').innerHTML = rhtml || '<div class="muted">No steps yet.</div>';
    } catch (eR) {}

  }

  function renderLeaderboard() {
    var rows = '';
    for (var i = 0; i < (state.leaderboard || []).length; i++) {
      var r = state.leaderboard[i];
      rows += '<div class="row"><div class="rowLeft">#' + (i + 1) + ' ' + escapeHtml(r.display || r.name || r.citizenid || 'Operator') + '</div><div class="rowRight">' + escapeHtml(String(r.chops || 0)) + '</div></div>';
    }
    $('lbList').innerHTML = rows || '<div class="muted">No data yet.</div>';

    // Top Groups (Syndicates)
    try {
      var srows = '';
      for (var j = 0; j < (state.topSyndicates || []).length; j++) {
        var s = state.topSyndicates[j];
        var nm = s.name || ('Group #' + (s.id || '?'));
        var pts = (s.prestige_points != null) ? s.prestige_points : (s.prestigePoints || 0);
        srows += '<div class="row"><div class="rowLeft">#' + (j + 1) + ' ' + escapeHtml(nm) + '</div><div class="rowRight">' + escapeHtml(String(pts || 0)) + '</div></div>';
      }
      var el = $('lbSyndList');
      if (el) el.innerHTML = srows || '<div class="muted">No groups yet.</div>';
    } catch (e) {}
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
    $("sysText").innerHTML =
      '<div class="sysK">Tier 1 completed:</div><div class="sysV">' + escapeHtml(String(p.tier1 || 0)) + '</div>' +
      '<div class="sysK">Tier 2 completed:</div><div class="sysV">' + escapeHtml(String(p.tier2 || 0)) + '</div>' +
      '<div class="sysK">Tier 3 completed:</div><div class="sysV">' + escapeHtml(String(p.tier3 || 0)) + '</div>' +
      '<div class="sysK">Reputation:</div><div class="sysV">' + escapeHtml(String(p.rep || 0)) + '</div>';

    try {
      var prof = state.profile || {};
      var ai = $('aliasInput');
      if (ai) ai.value = prof.alias || '';
    } catch (eP) {}

  }

  function renderUpgrades() {
    var up = state.upgrades || {};
    var lv = up.levels || {};
    var prices = up.prices || {};
    var caps = up.caps || {};
    var mult = up.mult || {};
    var role = up.role || null;
    var partnerRole = up.partnerRole || null;
    var synergy = up.synergy || null;

    // Totals at top
    if ($('totTime')) $('totTime').textContent = 'x' + fmt2(mult.time || 1);
    if ($('totPayout')) $('totPayout').textContent = 'x' + fmt2(mult.payout || 1);
    if ($('totAlert')) $('totAlert').textContent = 'x' + fmt2(mult.alert || 1);
    if ($('totRadius')) $('totRadius').textContent = 'x' + fmt2(mult.radius || 1);
    if ($('totFinal')) $('totFinal').textContent = 'x' + fmt2(mult.final || 1);

    // Switch panels
    var listEl = $('upgList'), treeEl = $('upgTree'), roleEl = $('rolePanel');
    if (listEl) listEl.classList.toggle('hidden', upgView !== 'list');
    if (treeEl) treeEl.classList.toggle('hidden', upgView !== 'tree');
    if (roleEl) roleEl.classList.toggle('hidden', upgView !== 'roles');

    // Filter
    var q = ( ($('upgSearch') && $('upgSearch').value) ? $('upgSearch').value : '' ).toLowerCase().trim();

    // List view (cards)
    if (listEl && upgView === 'list') {
      var html = '';
      for (var i = 0; i < upgrades.length; i++) {
        var udef = upgrades[i];
        var name = String(udef.name || '');
        var desc = String(udef.desc || '');
        var tag = String(udef.tag || udef.category || '');
        if (q && (name.toLowerCase().indexOf(q) === -1) && (desc.toLowerCase().indexOf(q) === -1) && (tag.toLowerCase().indexOf(q) === -1)) continue;

        var id = udef.id;
        var level = parseInt(lv[id] || 0, 10) || 0;
        var cap = parseInt(caps[id] || 0, 10) || 0;
        var maxed = cap > 0 && level >= cap;
        var price = parseInt(prices[id] || udef.price || 0, 10) || 0;

        var btnTxt = maxed ? 'MAXED' : ('BUY $' + price);
        var btnCls = 'btn gold' + (maxed ? ' maxed' : '');
        var dis = maxed ? 'disabled' : '';

        var pct = cap > 0 ? Math.round((level / cap) * 100) : 0;
        html +=
          '<div class="upgItem luxShimmer" data-hov="' + escapeHtml(id) + '">'
            + '<div class="upgLeft">'
              + '<div class="upgName">' + escapeHtml(name) + '</div>'
              + '<div class="upgDesc">' + escapeHtml(desc) + '</div>'
              + '<div class="upgTags"><span class="upgTag">' + escapeHtml(tag) + '</span></div>'
              + '<div class="nBar" style="margin-top:10px"><div class="nFill" style="width:' + pct + '%"></div></div>'
              + '<div class="upgPrice" style="margin-top:8px">Level ' + level + (cap ? (' / ' + cap) : '') + '</div>'
            + '</div>'
            + '<div class="upgRight">'
              + '<button class="' + btnCls + ' nBtn" data-upg="' + escapeHtml(id) + '" ' + dis + '>' + btnTxt + '</button>'
            + '</div>'
          + '</div>';
      }
      listEl.innerHTML = html || '<div class="muted">No upgrades match your search.</div>';

      // hover perks panel
      var hov = listEl.querySelectorAll('[data-hov]');
      for (var h = 0; h < hov.length; h++) {
        (function(card){
          card.onmouseenter = function(){ upgHoverId = card.getAttribute('data-hov'); renderPerksPanel(upgHoverId); };
          card.onmouseleave = function(){ upgHoverId = null; renderPerksPanel(null); };
        })(hov[h]);
      }

      // purchase bind
      var btns = listEl.querySelectorAll('[data-upg]');
      for (var j = 0; j < btns.length; j++) {
        (function (b) {
          b.onclick = function () {
            var id = b.getAttribute('data-upg');
            // animated bar pulse
            try {
              var fill = b.closest('.upgItem').querySelector('.nFill');
              if (fill) { fill.style.width = '0%'; setTimeout(function(){ fill.style.width = '100%'; }, 10); }
            } catch (e) {}
            post('buyUpgrade', { id: id });
            toast('Applied');
            playUpgSfx();
            setTimeout(function(){ post('refresh'); }, 250);
          };
        })(btns[j]);
      }
    }

    // Tree view
    if (treeEl && upgView === 'tree') {
      renderTreeCanvas(q);
    }

    // Roles view
    if (roleEl && upgView === 'roles') {
      renderRolePanel(role, partnerRole, synergy);
    }


    // Default perks panel content
    renderPerksPanel(upgHoverId);
  }

  
  function renderPerksPanel(id) {
    var panel = $('perksPanel');
    if (!panel) return;

    var up = state.upgrades || {};
    var lv = up.levels || {};
    var caps = up.caps || {};
    var prices = up.prices || {};
    var mult = up.mult || {};

    if (!id) {
      panel.innerHTML =
        '<div class="perkRow"><div class="pK">Time Mult</div><div class="pV">x' + fmt2(mult.time || 1) + '</div></div>' +
        '<div class="perkRow"><div class="pK">Payout Mult</div><div class="pV">x' + fmt2(mult.payout || 1) + '</div></div>' +
        '<div class="perkRow"><div class="pK">Alert Mult</div><div class="pV">x' + fmt2(mult.alert || 1) + '</div></div>' +
        '<div class="perkRow"><div class="pK">Radius Mult</div><div class="pV">x' + fmt2(mult.radius || 1) + '</div></div>' +
        '<div class="perkRow"><div class="pK">Final Mult</div><div class="pV">x' + fmt2(mult.final || 1) + '</div></div>';
      return;
    }

    // Find definition
    var def = null;
    for (var i=0;i<upgrades.length;i++){ if (upgrades[i].id===id){ def = upgrades[i]; break; } }
    if (!def) return;

    var level = parseInt(lv[id] || 0, 10) || 0;
    var cap = parseInt(caps[id] || 0, 10) || 0;
    var next = Math.min(level + 1, cap || (level + 1));
    var price = parseInt(prices[id] || 0, 10) || 0;

    // Simple preview text (server does exact; UI shows pattern)
    var preview = def.preview ? def.preview(level, next) : ('Level ' + level + ' → ' + next);

    panel.innerHTML =
      '<div class="perkRow"><div class="pK">Upgrade</div><div class="pV">' + escapeHtml(def.name) + '</div></div>' +
      '<div class="perkRow"><div class="pK">Next Level</div><div class="pV">' + escapeHtml(preview) + '</div></div>' +
      '<div class="perkRow"><div class="pK">Cost</div><div class="pV">$' + escapeHtml(String(price)) + '</div></div>' +
      '<div class="perkRow"><div class="pK">Category</div><div class="pV">' + escapeHtml(def.tag || def.category || '-') + '</div></div>';
  }

  function applyTreeTransform(viewport) {
    if (!viewport || !viewport._pan || !viewport._layer) return;
    var pan = viewport._pan;
    var layer = viewport._layer;
    layer.style.transformOrigin = '0 0';
    layer.style.transform = 'translate(' + pan.x + 'px,' + pan.y + 'px) scale(' + pan.z + ')';
  }

  function renderTreeCanvas(q) {
    var wrap = $('treeCanvas');
    if (!wrap) return;
    wrap.innerHTML = '';

    // viewport + transform layer (so panning actually works)
    var layer = document.createElement('div');
    layer.className = 'treeLayer';
    wrap.appendChild(layer);

    // naive grid layout by category to keep stable
    var cols = { personal: 0, shop: 1, network: 2, other: 3 };
    var buckets = { personal: [], shop: [], network: [], other: [] };

    for (var i=0;i<upgrades.length;i++){
      var u = upgrades[i];
      var name = String(u.name||'');
      var desc = String(u.desc||'');
      var tag = String(u.tag||u.category||'');
      if (q && (name.toLowerCase().indexOf(q) === -1) && (desc.toLowerCase().indexOf(q) === -1) && (tag.toLowerCase().indexOf(q) === -1)) continue;
      var cat = (u.category || '').toLowerCase();
      if (!buckets[cat]) cat = 'other';
      buckets[cat].push(u);
    }

    var up = state.upgrades || {};
    var lv = up.levels || {};
    var prices = up.prices || {};
    var caps = up.caps || {};

    var spacingX = 320, spacingY = 150;
    var baseX = 40, baseY = 40;

    Object.keys(buckets).forEach(function(cat){
      var list = buckets[cat];
      for (var i=0;i<list.length;i++){
        var u = list[i];
        var id = u.id;
        var level = parseInt(lv[id] || 0, 10) || 0;
        var cap = parseInt(caps[id] || 0, 10) || 0;
        var maxed = cap > 0 && level >= cap;
        var price = parseInt(prices[id] || 0, 10) || 0;
        var pct = cap > 0 ? Math.round((level / cap) * 100) : 0;

        var node = document.createElement('div');
        node.className = 'node';
        node.style.left = (baseX + (cols[cat]||0) * spacingX) + 'px';
        node.style.top  = (baseY + i * spacingY) + 'px';
        node.setAttribute('data-hov', id);

        node.innerHTML =
          '<div class="nTop"><div class="nName">' + escapeHtml(u.name) + '</div><div class="nTag">' + escapeHtml(u.tag||'') + '</div></div>' +
          '<div class="nDesc">' + escapeHtml(u.desc||'') + '</div>' +
          '<div class="nBar"><div class="nFill" style="width:' + pct + '%"></div></div>' +
          '<div class="upgPrice" style="margin-top:8px">Level ' + level + (cap ? (' / ' + cap) : '') + '</div>' +
          '<button class="btn gold nBtn ' + (maxed ? 'maxed' : '') + '" ' + (maxed ? 'disabled' : '') + ' data-upg="' + escapeHtml(id) + '">' + (maxed ? 'MAXED' : ('BUY $' + price)) + '</button>';

        layer.appendChild(node);
      }
    });

    // pan/zoom
    // pan/zoom (bind once)
    if (!wrap._pzBound) {
      wrap._pzBound = true;
      wrap._pan = { x: 0, y: 0, z: 1, down: false, sx: 0, sy: 0 };

      wrap.addEventListener('wheel', function (e) {
        if (upgView !== 'tree') return;
        e.preventDefault();
        var pan = wrap._pan;
        var dz = (e.deltaY > 0) ? -0.06 : 0.06;
        pan.z = Math.max(0.7, Math.min(1.5, pan.z + dz));
        applyTreeTransform(wrap);
      }, { passive: false });

      wrap.addEventListener('mousedown', function (e) {
        if (upgView !== 'tree') return;
        var pan = wrap._pan;
        pan.down = true; pan.sx = e.clientX; pan.sy = e.clientY;
      });

      window.addEventListener('mouseup', function () {
        if (!wrap._pan) return;
        wrap._pan.down = false;
      });

      window.addEventListener('mousemove', function (e) {
        if (!wrap._pan || !wrap._pan.down || upgView !== 'tree') return;
        var pan = wrap._pan;
        pan.x += (e.clientX - pan.sx);
        pan.y += (e.clientY - pan.sy);
        pan.sx = e.clientX; pan.sy = e.clientY;
        applyTreeTransform(wrap);
      });
    }

    // store layer reference on wrap and apply current transform
    wrap._layer = layer;
    applyTreeTransform(wrap);

    // hover + purchase binds
    var nodes = layer.querySelectorAll('[data-hov]');
    for (var h=0;h<nodes.length;h++){
      (function(n){
        n.onmouseenter = function(){ upgHoverId = n.getAttribute('data-hov'); renderPerksPanel(upgHoverId); };
        n.onmouseleave = function(){ upgHoverId = null; renderPerksPanel(null); };
      })(nodes[h]);
    }

    var btns = wrap.querySelectorAll('[data-upg]');
    for (var j=0;j<btns.length;j++){
      (function(b){
        b.onclick = function(){
          var id = b.getAttribute('data-upg');
          // premium feedback: animate the parent node
          try {
            var n = b.closest('.node');
            if (n) {
              n.classList.remove('unlocking');
              // force reflow for re-trigger
              n.offsetHeight;
              n.classList.add('unlocking');
            }
          } catch (e) {}
          try { b.disabled = true; } catch (e) {}
          post('buyUpgrade', { id: id });
          toast('Applied');
          playUpgSfx();
          setTimeout(function(){ post('refresh'); }, 250);
        };
      })(btns[j]);
    }
  }

  function renderRolePanel(role, partnerRole, synergy) {
    var el = $('rolePanel');
    if (!el) return;

    var defs = (state.roleDefs || null);
    if (!defs) {
      // hard-coded fallback (server has the truth)
      defs = {
        tech: { label:'Tech', desc:'Faster dismantle actions.', },
        runner: { label:'Runner', desc:'Better search intel.', },
        broker: { label:'Broker', desc:'Better payouts.', },
      };
    }

    var html = '<div class="muted" style="margin-bottom:10px">Your role affects multipliers. Co-op synergies apply when linked.</div>';

    html += '<div class="perkRow"><div class="pK">Your Role</div><div class="pV">' + escapeHtml(role || 'None') + '</div></div>';
    html += '<div class="perkRow"><div class="pK">Partner Role</div><div class="pV">' + escapeHtml(partnerRole || 'None') + '</div></div>';
    html += '<div class="perkRow"><div class="pK">Synergy</div><div class="pV">' + escapeHtml(synergy || '—') + '</div></div>';

    html += '<div style="height:10px"></div>';

    Object.keys(defs).forEach(function(k){
      var d = defs[k];
      var active = (role === k);
      html +=
        '<div class="upgItem luxShimmer">' +
          '<div class="upgLeft">' +
            '<div class="upgName">' + escapeHtml(d.label || k) + '</div>' +
            '<div class="upgDesc">' + escapeHtml(d.desc || '') + '</div>' +
          '</div>' +
          '<div class="upgRight">' +
            '<button class="btn ' + (active ? 'primary' : 'ghost') + '" data-role="' + escapeHtml(k) + '">' + (active ? 'Selected' : 'Select') + '</button>' +
          '</div>' +
        '</div>';
    });

    el.innerHTML = html;

    var btns = el.querySelectorAll('[data-role]');
    for (var i=0;i<btns.length;i++){
      (function(b){
        b.onclick = function(){
          post('setRole', { role: b.getAttribute('data-role') });
          toast('Role applied');
          setTimeout(function(){ post('refresh'); }, 250);
        };
      })(btns[i]);
    }
  }

  
function renderSyndPanel(synd) {
var el = $('syndicatePanel') || $('syndPanel');
if (!el) return;

synd = synd || {};
var id = Number(synd.id || 0);
var level = Number(synd.level || 0);
var inf = Number(synd.influence || 0);
var name = synd.name || '';
// rank can be numeric (1/2/3) or a string (member/capo/boss) depending on DB/framework bridges.
var rankRaw = synd.rank;
var rank = Number(rankRaw || 0);

var perms = state.syndicatePermsCfg || {};
var rk;
if (typeof rankRaw === 'string') {
  var rks = String(rankRaw).toLowerCase();
  rk = (rks === 'boss' || rks === 'leader' || rks === 'owner') ? 'boss' : (rks === 'capo' || rks === 'officer') ? 'capo' : 'member';
} else {
  rk = (rank >= 3) ? 'boss' : (rank === 2 ? 'capo' : 'member');
}
var can = function(key){ return !!((perms[rk]||{})[key]); };

var per = (state.syndicateCfg && Number(state.syndicateCfg.influencePerLevel || 100)) || 100;
var nextAt = Math.max(1, (level + 1) * per);
var pct = Math.min(100, Math.round((inf / Math.max(1, nextAt)) * 100));

if (!id) {
  el.innerHTML =
    '<div class="syndBox">'
      + '<div class="syndTitle">No Group</div>'
      + '<div class="muted">Create a group to unlock shared progression and a bank.</div>'
      + '<div style="display:flex; gap:10px; margin-top:12px">'
        + '<input id="syndNameInput" class="input" placeholder="Group Name" maxlength="32" style="flex:1" />'
        + '<button id="syndCreateBtn" class="btn gold">CREATE</button>'
      + '</div>'
      + '<div class="muted" style="margin-top:10px">Letters, numbers, spaces, _ and -.</div>'
    + '</div>';

  var b = $('syndCreateBtn');
  if (b) b.onclick = function(){
    var inp = $('syndNameInput');
    var val = inp ? inp.value : '';
    post('createSyndicate', { name: val });
    setTimeout(function(){ post('refresh'); }, 250);
  };
  return;
}

var vault = Number(state.syndicateVault || 0);
var settings = state.syndicateSettings || { routingEnabled:false, routingPercent: 0.15, branding:{} };
var stats = state.syndicateStatsAgg || {};
var op = state.syndicateOp || { opId:null, activeUntil:0, cooldownUntil:0 };
var tree = state.syndicateTreeCfg || {};
var opsCfg = state.syndicateOpsCfg || {};
var routingCfg = state.syndicateRoutingCfg || {};

var tag = (settings.branding && settings.branding.tag) ? settings.branding.tag : '';

var tabs = [
  { id:'overview', label:'Overview' },
  { id:'bank', label:'Bank' },
  { id:'tree', label:'Tree' },
  { id:'ops', label:'Operations' },
  { id:'stats', label:'Stats' },
  { id:'branding', label:'Branding' },
  { id:'bm', label:'Black Market' }
];

var head = '<div class="syndTitle">' + escapeHtml(name || ('Group #' + id))
  + (tag ? (' <span class="pill" style="margin-left:8px">' + escapeHtml(tag) + '</span>') : '')
  + '</div>';

var meta =
  '<div class="syndMeta">'
    + '<div class="pill">LEVEL ' + escapeHtml(String(level)) + '</div>'
    + '<div class="pill">PRESTIGE ' + escapeHtml(String((state.syndicatePrestige && state.syndicatePrestige.prestige) || 0)) + '</div>'
    + '<div class="pill">INFLUENCE ' + escapeHtml(String(inf)) + '</div>'
    + '<div class="pill">FUNDS $' + escapeHtml(String(vault)) + '</div>'
    + '<div class="pill">' + (rank >= 3 ? 'BOSS' : (rank === 2 ? 'CAPO' : 'MEMBER')) + '</div>'
  + '</div>';

var bar =
  '<div class="muted" style="margin-top:8px">Next level at ' + escapeHtml(String(nextAt)) + ' influence.</div>'
  + '<div class="nBar" style="margin-top:10px"><div class="nFill" style="width:' + pct + '%"></div></div>';

var tabBtns = '<div style="display:flex; gap:8px; flex-wrap:wrap; margin-top:12px">';
tabs.forEach(function(t){
  tabBtns += '<button class="btn ghost" data-syn-tab="' + t.id + '">' + t.label + '</button>';
});
tabBtns += '</div>';

var actions =
  '<div class="divider" style="margin-top:14px"></div>'
  + '<div style="display:flex; gap:10px; flex-wrap:wrap">'
    + '<button id="syndInviteBtn" class="btn ghost"' + (!can('invite') ? ' disabled' : '') + '>Invite</button>'
    + (rank >= 3 ? '<button id="syndDisbandBtn" class="btn danger">Disband</button>' : '<button id="syndLeaveBtn" class="btn danger">Leave</button>')
  + '</div>'
  + '<div id="syndInviteRow" class="hidden" style="display:flex; gap:10px; margin-top:10px">'
    + '<input id="syndInviteTarget" class="input" placeholder="Target Server ID" style="flex:1" />'
    + '<button id="syndInviteSend" class="btn gold">SEND</button>'
  + '</div>';

var sections =
  '<div class="divider" style="margin-top:14px"></div>'
  + '<div id="synTab_overview" class="synTab"></div>'
  + '<div id="synTab_bank" class="synTab hidden"></div>'
  + '<div id="synTab_tree" class="synTab hidden"></div>'
  + '<div id="synTab_ops" class="synTab hidden"></div>'
  + '<div id="synTab_stats" class="synTab hidden"></div>'
  + '<div id="synTab_branding" class="synTab hidden"></div>'
  + '<div id="synTab_bm" class="synTab hidden"></div>';

el.innerHTML = '<div class="syndBox">' + head + meta + bar + tabBtns + actions + sections + '</div>';

// Invite actions
var inv = $('syndInviteBtn');
if (inv) inv.onclick = function(){
  var row = $('syndInviteRow');
  if (row) row.classList.toggle('hidden');
};
var send = $('syndInviteSend');
if (send) send.onclick = function(){
  var t = $('syndInviteTarget');
  var target = t ? Number(t.value || 0) : 0;
  if (!target) { toast('Enter a server ID'); return; }
  post('syndInvite', { target: target });
  toast('Invite sent');
};
var dis = $('syndDisbandBtn');
if (dis) dis.onclick = function(){ post('syndDisband', {}); setTimeout(function(){ post('refresh'); }, 250); };
var leave = $('syndLeaveBtn');
if (leave) leave.onclick = function(){ post('syndLeave', {}); setTimeout(function(){ post('refresh'); }, 250); };

// Tabs
var setTab = function(id){
  var all = el.querySelectorAll('.synTab');
  for (var i=0;i<all.length;i++) all[i].classList.add('hidden');
  var tgt = $('synTab_' + id);
  if (tgt) tgt.classList.remove('hidden');
};
var tbs = el.querySelectorAll('[data-syn-tab]');
for (var i=0;i<tbs.length;i++){
  (function(b){
    b.onclick = function(){ setTab(b.getAttribute('data-syn-tab')); };
  })(tbs[i]);
}

// Overview tab
var o = $('synTab_overview');
if (o){
  var re = !!settings.routingEnabled;
  var rp = Number(settings.routingPercent || routingCfg.defaultPercent || 0.15);

  o.innerHTML =
    '<div class="miniK">GROUP PRESTIGE</div>'
    + '<div class="muted" style="margin-top:6px">Prestige is slow and expensive. It unlocks elite systems like Black Market War.</div>'
    + (function(){
        var sp = state.syndicatePrestige || {prestige:0, points:0};
        var pc = state.syndicatePrestigeCfg || {};
        var tiers = (pc && pc.tiers) || {};
        var cur = Number(sp.prestige||0);
        var next = tiers[cur+1];
        if (!next) {
          return '<div style="display:flex; gap:10px; flex-wrap:wrap; margin-top:10px">'
            + '<div class="pill">Prestige '+cur+' (MAX)</div>'
            + '<div class="pill">Prestige Points '+escapeHtml(String(sp.points||0))+'</div>'
          + '</div>';
        }
        return '<div style="display:flex; gap:10px; flex-wrap:wrap; margin-top:10px">'
          + '<div class="pill">Prestige '+cur+'</div>'
          + '<div class="pill">Next: P'+(cur+1)+' needs L'+escapeHtml(String(next.levelReq||0))+' • $'+escapeHtml(String(next.fundsCost||0))+' • '+escapeHtml(String(next.influenceCost||0))+' inf</div>'
          + '<button id="synPrestigeUp" class="btn gold"'+(!can('purchasePerks')?' disabled':'')+'>Prestige Up</button>'
        + '</div>';
      })()
    + '<div class="divider" style="margin-top:14px"></div>'
    + '<div class="miniK">Routing</div>'
    + '<div class="muted" style="margin-top:6px">Route a percent of contract payouts into the group bank.</div>'
    + '<div style="display:flex; align-items:center; gap:10px; margin-top:10px">'
      + '<label class="pill" style="cursor:pointer"><input id="synRouteToggle" type="checkbox"' + (re?' checked':'') + ' style="margin-right:8px"/>Enabled</label>'
      + '<div class="pill">' + Math.round(rp*100) + '%</div>'
    + '</div>'
    + '<input id="synRoutePct" class="input" type="range" min="0" max="35" value="' + Math.round(rp*100) + '" style="width:100%; margin-top:10px"' + (!can('routing')?' disabled':'') + '/>'
    + '<div style="display:flex; gap:10px; margin-top:10px">'
      + '<button id="synRouteSave" class="btn gold"' + (!can('routing')?' disabled':'') + '>Save Routing</button>'
    + '</div>'
    + '<div class="divider" style="margin-top:14px"></div>'
    + '<div class="miniK">Quick Bank</div>'
    + '<div class="muted" style="margin-top:6px">Deposit any time. Withdraw requires permission.</div>'
    + '<div style="display:flex; gap:10px; margin-top:10px">'
      + '<input id="vaultAmtQuick" class="input" placeholder="Amount" type="number" min="0" style="flex:1"/>'
      + '<button id="vaultDepQuick" class="btn ghost">Deposit</button>'
      + '<button id="vaultWitQuick" class="btn gold"' + (!can('withdraw')?' disabled':'') + '>Withdraw</button>'
    + '</div>';

  var save = $('synRouteSave');
  if (save) save.onclick = function(){
    var en = $('synRouteToggle');
    var pv = $('synRoutePct');
    var enabledV = !!(en && en.checked);
    var pctV = (pv ? (Number(pv.value||0)/100) : rp);
    // Optimistic update so the slider doesn't "snap back" during slow DB writes.
    state.syndicateSettings = state.syndicateSettings || { routingEnabled:false, routingPercent: 0.15, branding:{} };
    state.syndicateSettings.routingEnabled = enabledV;
    state.syndicateSettings.routingPercent = pctV;
    renderSyndPanel(state.syndicate);
    post('syndSetRouting', { enabled: enabledV, percent: pctV });
    toast('Routing updated');
  };
  var dq = $('vaultDepQuick');
  if (dq) dq.onclick = function(){ var a=$('vaultAmtQuick'); post('syndVaultDeposit',{amount:Number(a&&a.value||0)}); };
  var wq = $('vaultWitQuick');
  if (wq) wq.onclick = function(){ var a=$('vaultAmtQuick'); post('syndVaultWithdraw',{amount:Number(a&&a.value||0)}); };
  var pu = $('synPrestigeUp');
  if (pu) pu.onclick = function(){ post('syndPrestigeUp'); toast('Prestige requested'); setTimeout(function(){ post('refresh'); }, 250); };
}

// Bank tab
var btab = $('synTab_bank');
if (btab){
  btab.innerHTML =
    '<div class="syndVaultBox">'
      + '<div class="syndVaultHead"><div class="miniK">BANK</div><div class="miniV">$' + escapeHtml(String(vault)) + '</div></div>'
      + '<div class="syndVaultRow">'
        + '<input id="vaultAmt" class="input" placeholder="Amount" type="number" min="0" style="flex:1" />'
        + '<button id="vaultDep" class="btn ghost">Deposit</button>'
        + '<button id="vaultWit" class="btn gold"' + (!can('withdraw')?' disabled':'') + '>Withdraw</button>'
      + '</div>'
      + '<div class="muted" style="margin-top:8px">Ledger shows last 10 transactions.</div>'
      + '<div id="vaultTx" class="vaultTx"></div>'
    + '</div>';

  var dep = $('vaultDep');
  if (dep) dep.onclick = function(){ var a=$('vaultAmt'); post('syndVaultDeposit',{amount:Number(a&&a.value||0)}); };
  var wit = $('vaultWit');
  if (wit) wit.onclick = function(){ var a=$('vaultAmt'); post('syndVaultWithdraw',{amount:Number(a&&a.value||0)}); };

  var txEl = $('vaultTx');
  if (txEl){
    var tx = state.syndicateVaultTx || [];
    if (!tx.length) { txEl.innerHTML = '<div class="muted">No activity yet.</div>'; }
    else {
      var h = '';
      tx.forEach(function(t){
        var who = t.citizenid || '?';
        var k = t.kind || '';
        var amt = Number(t.amount||0);
        var rs = t.reason ? (' • ' + escapeHtml(String(t.reason))) : '';
        h += '<div class="txRow"><div class="txL">' + escapeHtml(who) + '</div><div class="txM">' + escapeHtml(k) + rs + '</div><div class="txR">' + (amt>=0?('$'+amt):('-$'+Math.abs(amt))) + '</div></div>';
      });
      txEl.innerHTML = h;
    }
  }
}

// Tree tab
var ttab = $('synTab_tree');
if (ttab){
  var owned = state.syndicatePerks || {};
  var groups = {};
  Object.keys(tree).forEach(function(id){
    var n = tree[id];
    var br = (n && n.branch) ? n.branch : 'Other';
    groups[br] = groups[br] || [];
    groups[br].push({ id:id, n:n });
  });

  var html = '<div class="miniK">Upgrade Tree</div>'
    + '<div class="muted" style="margin-top:6px">Costs use <b>Funds + Influence</b> and can require a minimum <b>Group Level</b>.</div>';

  var calcCost = function(n, cur){
    cur = Number(cur||0);
    var baseF = Number(n.cost && n.cost.funds || 0);
    var baseI = Number(n.cost && n.cost.influence || 0);
    var g = Number(n.cost && n.cost.growth || 0);
    var f = Math.floor(baseF * Math.pow(1+g, cur));
    var i = Math.floor(baseI * Math.pow(1+g, cur));
    return { funds:f, inf:i };
  };

  Object.keys(groups).sort().forEach(function(br){
    html += '<div class="divider" style="margin-top:14px"></div>';
    html += '<div class="miniK">' + escapeHtml(br) + '</div>';

    groups[br].forEach(function(it){
      var n = it.n || {};
      var cur = Number(owned[it.id]||0);
      var cap = Number(n.maxLevel||0);
      var cost = calcCost(n, cur);

      var meetsLevel = level >= Number(n.minLevel||0);
      var prereqOk = true;
      if (n.requires){
        Object.keys(n.requires).forEach(function(rid){
          if (Number(owned[rid]||0) < Number(n.requires[rid]||0)) prereqOk = false;
        });
      }

      var canAfford = (vault >= cost.funds) && (inf >= cost.inf);
      var maxed = cap>0 && cur>=cap;
      var ok = !maxed && meetsLevel && prereqOk && can('purchase') && canAfford;

      var reqTxt = '';
      if (Number(n.minLevel||0) > 0) reqTxt += ' • Lvl ' + Number(n.minLevel||0) + '+';
      if (n.requires){
        var arr=[];
        Object.keys(n.requires).forEach(function(rid){ arr.push(rid + ' L' + n.requires[rid]); });
        if (arr.length) reqTxt += ' • Requires ' + arr.join(', ');
      }

      html +=
        '<div class="perkRow" style="margin-top:10px">'
          + '<div class="perkL">'
            + '<div class="perkName">' + escapeHtml(n.label || it.id) + ' <span class="pill">' + cur + '/' + (cap||'∞') + '</span></div>'
            + '<div class="muted">' + escapeHtml(n.desc||'') + escapeHtml(reqTxt) + '</div>'
            + '<div class="muted" style="margin-top:6px">Cost: <b>$' + cost.funds + '</b> + <b>' + cost.inf + ' inf</b></div>'
          + '</div>'
          + '<div class="perkR">'
            + '<button class="btn ' + (ok?'gold':'ghost') + '" data-buy-node="' + it.id + '"' + (!ok?' disabled':'') + '>' + (maxed?'MAX':'BUY') + '</button>'
          + '</div>'
        + '</div>';
    });
  });

  ttab.innerHTML = html;

  var buys = ttab.querySelectorAll('[data-buy-node]');
  for (var i=0;i<buys.length;i++){
    (function(b){
      b.onclick = function(){
        post('syndBuyPerk', { id: b.getAttribute('data-buy-node') });
      };
    })(buys[i]);
  }
}

// Ops tab
var otab = $('synTab_ops');
if (otab){
  var nowS = Number(state.serverTime || 0);
  var active = op && op.opId && Number(op.activeUntil||0) > nowS;
  var cd = op && Number(op.cooldownUntil||0) > nowS;

  var html = '<div class="miniK">Operations</div>'
    + '<div class="muted" style="margin-top:6px">Syndicate-wide timed buffs. One active at a time.</div>';

  if (active){
    html += '<div class="pill" style="margin-top:10px">ACTIVE: ' + escapeHtml(op.opId) + '</div>';
  } else if (cd){
    html += '<div class="pill" style="margin-top:10px">COOLDOWN</div>';
  }

  Object.keys(opsCfg).forEach(function(k){
    var d = opsCfg[k];
    html += '<div class="perkRow" style="margin-top:12px">'
      + '<div class="perkL">'
        + '<div class="perkName">' + escapeHtml(d.label||k) + '</div>'
        + '<div class="muted">' + escapeHtml(d.desc||'') + '</div>'
        + '<div class="muted" style="margin-top:6px">Cost: <b>$' + Number(d.cost&&d.cost.funds||0) + '</b> + <b>' + Number(d.cost&&d.cost.influence||0) + ' inf</b> • Requires Lvl ' + Number(d.cost&&d.cost.minLevel||0) + '+</div>'
      + '</div>'
      + '<div class="perkR">'
        + '<button class="btn gold" data-op="' + k + '"' + ((active||cd||!can('ops'))?' disabled':'') + '>START</button>'
      + '</div>'
    + '</div>';
  });

  otab.innerHTML = html;

  var obs = otab.querySelectorAll('[data-op]');
  for (var i=0;i<obs.length;i++){
    (function(b){
      b.onclick = function(){ post('syndStartOp', { id: b.getAttribute('data-op') }); };
    })(obs[i]);
  }
}

// Stats tab
var stab = $('synTab_stats');
if (stab){
  stab.innerHTML =
    '<div class="miniK">Stats</div>'
    + '<div class="muted" style="margin-top:10px">Contracts Completed: <b>' + Number(stats.contractsCompleted||0) + '</b></div>'
    + '<div class="muted" style="margin-top:6px">Total Earnings: <b>$' + Number(stats.earningsTotal||0) + '</b></div>'
    + '<div class="muted" style="margin-top:6px">Total Influence Earned: <b>' + Number(stats.influenceTotal||0) + '</b></div>'
    + '<div class="muted" style="margin-top:6px">Best Payout: <b>$' + Number(stats.bestPayout||0) + '</b></div>';
}

// Branding tab
var br = $('synTab_branding');
if (br){
  var bd = settings.branding || {};
  br.innerHTML =
    '<div class="miniK">Branding</div>'
    + '<div class="muted" style="margin-top:6px">Optional flair. Boss can edit.</div>'
    + '<div style="display:flex; gap:10px; margin-top:10px">'
      + '<input id="synBrandTag" class="input" placeholder="Tag (max 12)" value="' + escapeHtml(bd.tag||'') + '" style="flex:1"' + (!can('branding')?' disabled':'') + '/>'
      + '<input id="synBrandColor" class="input" placeholder="Color (#ffd36a)" value="' + escapeHtml(bd.color||'') + '" style="flex:1"' + (!can('branding')?' disabled':'') + '/>'
    + '</div>'
    + '<div style="display:flex; gap:10px; margin-top:10px">'
      + '<input id="synBrandLogo" class="input" placeholder="Logo ID (optional)" value="' + escapeHtml(bd.logo||'') + '" style="flex:1"' + (!can('branding')?' disabled':'') + '/>'
      + '<button id="synBrandSave" class="btn gold"' + (!can('branding')?' disabled':'') + '>SAVE</button>'
    + '</div>';

  var sv = $('synBrandSave');
  if (sv) sv.onclick = function(){
    var tagEl = $('synBrandTag');
    var cEl = $('synBrandColor');
    var lEl = $('synBrandLogo');
    var b = { tag: (tagEl?tagEl.value:''), color: (cEl?cEl.value:''), logo: (lEl?lEl.value:'') };
    // Optimistic update (same reason as routing).
    state.syndicateSettings = state.syndicateSettings || { routingEnabled:false, routingPercent: 0.15, branding:{} };
    state.syndicateSettings.branding = b;
    renderSyndPanel(state.syndicate);
    post('syndSetBranding', { branding: b });
    toast('Branding saved');
  };
}

setTab('overview');
}




// Black Market tab
var bm = $('synTab_bm');
if (bm){
  var ev = state.bmEvent || { active:false };
  var cfg = state.blackMarketCfg || {};
  var sp = state.syndicatePrestige || { prestige:0, points:0, winStreak:0 };
  var minPrest = Number((cfg && cfg.minPrestige) || 3);

  var nowTs = Math.floor(Date.now()/1000);
  var left = ev.active ? Math.max(0, Number(ev.endsAt||0) - nowTs) : 0;
  var rotLeft = ev.active ? Math.max(0, Number(ev.nextRotationAt||0) - nowTs) : 0;
  var fmt = function(sec){
    sec = Math.max(0, Number(sec||0));
    var m = Math.floor(sec/60), s = sec%60;
    var h = Math.floor(m/60); m = m%60;
    if (h>0) return h+'h '+m+'m';
    return m+'m '+s+'s';
  };

  var status = ev.active ? ('<span class="pill">LIVE</span> <span class="muted">Ends in '+fmt(left)+'</span>') : ('<span class="pill">OFFLINE</span> <span class="muted">No active war right now.</span>');

  var gate = (Number(sp.prestige||0) >= minPrest);

  var pool = state.bmPool || [];
  var lb = state.bmLeaderboard || [];

  var poolHtml = '';
  if (!ev.active) {
    poolHtml = '<div class="muted">The Black Market isn\'t open. Admin can start it with <b>gs_bm_start</b> in server console.</div>';
  } else if (!gate) {
    poolHtml = '<div class="muted">Requires <b>Prestige '+minPrest+'</b> to take Black Market contracts.</div>';
  } else if (!pool.length) {
    poolHtml = '<div class="muted">No offers right now. Next rotation in '+fmt(rotLeft)+'.</div>';
  } else {
    pool.forEach(function(o){
      var kind = (o.kind||'standard').toUpperCase();
      var tag = '<span class="pill">'+escapeHtml(kind)+'</span>';
      var tier = '<span class="pill">'+escapeHtml(String(o.tier||''))+'</span>';
      var exp = '<span class="muted">Rotates in '+fmt(rotLeft)+'</span>';
      poolHtml += '<div class="listItem">'
        + '<div class="liL">'
          + '<div class="liTitle">'+tag+' '+tier+' '+escapeHtml(o.label||'Offer')+'</div>'
          + '<div class="liSub">'+escapeHtml(o.desc||'')+'</div>'
        + '</div>'
        + '<div class="liR">'
          + '<button class="btn gold" data-bm-accept="'+escapeHtml(String(o.id))+'">Accept</button>'
          + '<div style="height:6px"></div>'
          + exp
        + '</div>'
      + '</div>';
    });
  }

  var lbHtml = '';
  if (!lb.length) {
    lbHtml = '<div class="muted">No scores yet.</div>';
  } else {
    lb.forEach(function(r, i){
      lbHtml += '<div class="txRow">'
        + '<div class="txL">#'+(i+1)+' '+escapeHtml(r.name||('Group '+r.syndicate_id))+'</div>'
        + '<div class="txM">Elite '+escapeHtml(String(r.elite_completed||0))+' • Perfect '+escapeHtml(String(r.perfect_runs||0))+'</div>'
        + '<div class="txR">'+escapeHtml(String(r.points||0))+' pts</div>'
      + '</div>';
    });
  }

  bm.innerHTML =
    '<div class="miniK">BLACK MARKET WAR</div>'
    + '<div style="display:flex; gap:10px; align-items:center; margin-top:8px; flex-wrap:wrap">'
      + '<div class="pill">'+escapeHtml(String(ev.theme||'BLACK MARKET'))+'</div>'
      + status
      + '<div class="pill">Prestige Points '+escapeHtml(String(sp.points||0))+'</div>'
    + '</div>'
    + '<div class="divider" style="margin-top:14px"></div>'
    + '<div class="miniK">Offers</div>'
    + '<div class="muted" style="margin-top:6px">Rotating contract pool. Bigger payouts, tighter timers, heavier modifiers.</div>'
    + '<div class="list" style="margin-top:10px">'+poolHtml+'</div>'
    + '<div class="divider" style="margin-top:14px"></div>'
    + '<div class="miniK">Leaderboard</div>'
    + '<div id="bmLb" class="vaultTx" style="margin-top:10px">'+lbHtml+'</div>';

  var btns = bm.querySelectorAll('[data-bm-accept]');
  for (var i=0;i<btns.length;i++){
    (function(b){
      b.onclick = function(){
        post('bmAcceptContract', { id: b.getAttribute('data-bm-accept') });
        toast('Offer accepted');
        setTimeout(function(){ post('refresh'); }, 250);
      };
    })(btns[i]);
  }
}

function renderSyndicateMembers() {
  var box = $('syndicateMembers');
  if (!box) return;
  var s = state.syndicate || null;
  var mem = state.syndicateMembers || [];
  var myCid = state.me && state.me.citizenid ? String(state.me.citizenid) : '';
  if (!s || !s.id) {
    box.innerHTML = '<div class="muted">No members to show.</div>';
    return;
  }
  if (!mem.length) {
    box.innerHTML = '<div class="muted">No members yet. Invite someone.</div>';
    return;
  }
  var html = '';
  for (var i=0;i<mem.length;i++){
    var r = mem[i];
    var tag = (r.rank >= 3) ? 'BOSS' : (r.rank === 2 ? 'CAPO' : 'MEMBER');
    var disp = r.displayName || r.citizenid || 'unknown';
    var isMe = myCid && (String(r.citizenid) === myCid);

    // Actions
    var actions = '';
    if (!isMe) {
      if (Number(s.rank || 0) >= 3 && tag !== 'BOSS') {
        if (r.rank === 1) {
          actions += '<button class="miniBtn" data-act="promote" data-cid="' + escapeHtml(r.citizenid) + '">Promote</button>';
        } else if (r.rank === 2) {
          actions += '<button class="miniBtn" data-act="demote" data-cid="' + escapeHtml(r.citizenid) + '">Demote</button>';
        }
        actions += '<button class="miniBtn danger" data-act="kick" data-cid="' + escapeHtml(r.citizenid) + '">Kick</button>';
      } else if (Number(s.rank || 0) >= 2 && r.rank === 1) {
        actions += '<button class="miniBtn danger" data-act="kick" data-cid="' + escapeHtml(r.citizenid) + '">Kick</button>';
      }
    }

    html += ''
      + '<div class="row">'
        + '<div class="rowLeft">'
          + '<div class="mName">' + escapeHtml(disp) + (isMe ? ' <span class="muted">(you)</span>' : '') + '</div>'
          + '<div class="muted" style="font-size:12px">' + escapeHtml(String(r.citizenid || '')) + '</div>'
        + '</div>'
        + '<div class="rowRight">'
          + '<span class="pill">' + escapeHtml(tag) + '</span>'
          + (actions ? ('<div class="mActions">' + actions + '</div>') : '')
        + '</div>'
      + '</div>';
  }
  box.innerHTML = html;

  // Bind actions
  var btns = box.querySelectorAll('[data-act]');
  for (var b=0;b<btns.length;b++){
    (function(btn){
      btn.onclick = function(){
        var act = btn.getAttribute('data-act');
        var cid = btn.getAttribute('data-cid');
        if (!cid) return;
        if (act === 'kick') {
          post('syndKick', { citizenid: cid });
          toast('Member removed');
          return;
        }
        if (act === 'promote') {
          post('syndSetRank', { citizenid: cid, rank: 2 });
          toast('Promoted');
          return;
        }
        if (act === 'demote') {
          post('syndSetRank', { citizenid: cid, rank: 1 });
          toast('Demoted');
          return;
        }
      };
    })(btns[b]);
  }
}

function renderTiers() {
    var c = state.contract;
    var unlocks = state.unlocks || {};
    var prog = state.progress || { tier1: 0, tier2: 0, tier3: 0 };
    var t1 = $('tier1Btn'), t2 = $('tier2Btn'), t3 = $('tier3Btn');
    if (!t1) return;

    var rep = (prog && prog.rep) ? Number(prog.rep) : 0;
    var ru = state.repUnlocks || {};

    var locked2 = unlocks.tier2RequiresTier1 && (prog.tier1 || 0) < unlocks.tier2RequiresTier1;
    var locked3 = unlocks.tier3RequiresTier2 && (prog.tier2 || 0) < unlocks.tier3RequiresTier2;

    var repLock2 = ru.tier2Rep && Number(ru.tier2Rep) > 0 && rep < Number(ru.tier2Rep);
    var repLock3 = ru.tier3Rep && Number(ru.tier3Rep) > 0 && rep < Number(ru.tier3Rep);
    locked2 = locked2 || repLock2;
    locked3 = locked3 || repLock3;

    t1.disabled = !!c;
    t2.disabled = !!c || locked2;
    t3.disabled = !!c || locked3;

    $('tier2Lock').textContent = locked2 ? (repLock2 ? ('Locked: need ' + ru.tier2Rep + ' rep') : ('Locked: complete ' + unlocks.tier2RequiresTier1 + ' Tier 1')) : 'Unlocked';
    $('tier3Lock').textContent = locked3 ? (repLock3 ? ('Locked: need ' + ru.tier3Rep + ' rep') : ('Locked: complete ' + unlocks.tier3RequiresTier2 + ' Tier 2')) : 'Unlocked';

    // Special contracts (rep-gated)
    var sc = state.special || { enabled:false, repRequired:0 };
    var sb = $('specialBtn');
    var sh = $('specialHint');
    if (sh) sh.textContent = sc.enabled ? ('Requires REP: ' + Number(sc.repRequired || 0)) : 'Special disabled';
    if (sb) sb.disabled = !!c || !sc.enabled || (rep < Number(sc.repRequired || 0));
  }

  
  function showBonusWarn(text) {
    var bw = $('bonusWarn');
    if (!bw) return;
    bw.classList.remove('hidden');
    bw.textContent = String(text || 'BONUS AT RISK');
    // restart animation
    bw.classList.remove('show');
    void bw.offsetWidth;
    bw.classList.add('show');
    setTimeout(function(){
      bw.classList.remove('show');
    }, 2300);
  }

function renderAll() {
    renderContractPanel();
    renderTiers();
    renderLeaderboard();
    renderHistory();
    renderSystem();
    renderUpgrades();
    renderSyndPanel(state.syndicate || null);
    renderSyndicateMembers();
  }

  function bind() {
    var closeBtn = $('closeBtn');
    if (closeBtn) closeBtn.onclick = function () { post('close'); };

    var refreshBtn = $('refreshBtn');
    if (refreshBtn) refreshBtn.onclick = function () { post('refresh'); };

    var cancelBtn = $('cancelBtn');
    if (cancelBtn) {
      cancelBtn.onclick = function () {
        post('cancelContract');
        cancelBtn.disabled = true;
        setTimeout(function () { post('refresh'); }, 200);
      };
    }

    var tier1Btn = $('tier1Btn');
    if (tier1Btn) tier1Btn.onclick = function () { post('startContract', { tier: 'tier1' }); setTimeout(function () { post('refresh'); }, 200); };
    var tier2Btn = $('tier2Btn');
    if (tier2Btn) tier2Btn.onclick = function () { post('startContract', { tier: 'tier2' }); setTimeout(function () { post('refresh'); }, 200); };
    var tier3Btn = $('tier3Btn');
    if (tier3Btn) tier3Btn.onclick = function () { post('startContract', { tier: 'tier3' }); setTimeout(function () { post('refresh'); }, 200); };

    var specialBtn = $('specialBtn');
    if (specialBtn) {
      specialBtn.onclick = function () { post('startSpecialContract'); setTimeout(function () { post('refresh'); }, 250); };
    }

    // co-op removed

    var tabBtns = document.querySelectorAll('[data-tab]');
    for (var i = 0; i < tabBtns.length; i++) {
      (function (btn) {
        btn.onclick = function () { setTab(btn.getAttribute('data-tab')); };
      })(tabBtns[i]);
    }

    
    // Upgrades: sub-tabs + search
    var upgBtns = document.querySelectorAll('[data-upgview]');
    for (var u = 0; u < upgBtns.length; u++) {
      (function(btn){
        btn.onclick = function(){
          upgView = btn.getAttribute('data-upgview') || 'tree';
          // active class
          for (var k=0;k<upgBtns.length;k++){ upgBtns[k].classList.remove('active'); }
          btn.classList.add('active');
          renderUpgrades();
    renderSyndPanel(state.syndicate || null);
    renderSyndicateMembers();
        };
      })(upgBtns[u]);
    }

    var us = $('upgSearch');
    if (us) {
      us.oninput = function(){ renderUpgrades(); };
    }

    // Tree focus mode (minimal OS style)
    var tf = $('treeFocusBtn');
    if (tf) {
      tf.onclick = function () {
        var appEl = $('app');
        if (!appEl) return;
        var on = appEl.classList.toggle('treeFocus');
        tf.classList.toggle('active', on);
        // re-apply transform after layout changes
        setTimeout(function () {
          try { applyTreeTransform($('treeCanvas')); } catch (e) {}
        }, 50);
      };
    }

    var ct = $("checkToggle");
    if (ct) ct.onclick = function () {
      var wrap = $("checkWrap");
      if (!wrap) return;
      var open = wrap.classList.toggle("open");
      ct.textContent = open ? "Hide checklist" : "Show checklist";
    };

    // Local UI settings
    var app = document.getElementById('app');
    var themeNeon = $('themeNeon');
    var themeCarbon = $('themeCarbon');
    var uiScale = $('uiScale');
    var uiScaleVal = $('uiScaleVal');

    function applyTheme(t) {
      if (!app) return;
      var allowed = { neon:1, carbon:1, terminal:1, obsidian:1 };
      t = allowed[t] ? t : 'neon';
      app.setAttribute('data-theme', t);
      if (themeNeon) themeNeon.classList.toggle('active', t === 'neon');
      if (themeCarbon) themeCarbon.classList.toggle('active', t === 'carbon');
      var themeTerminal = $('themeTerminal');
      var themeObsidian = $('themeObsidian');
      if (themeTerminal) themeTerminal.classList.toggle('active', t === 'terminal');
      if (themeObsidian) themeObsidian.classList.toggle('active', t === 'obsidian');
      try { localStorage.setItem('gs_chopshop_theme', t); } catch (e) {}
    }

    function applyScale(v) {
      // Apply scale only when the user commits (change/pointerup) to avoid jitter.
      v = Math.max(85, Math.min(115, parseInt(v, 10) || 100));
      var z = (v / 100);
      document.documentElement.style.setProperty('--uiZoom', String(z));
      if (uiScaleVal) uiScaleVal.textContent = String(v) + '%';
      if (uiScale) uiScale.value = String(v);
      try { localStorage.setItem('gs_chopshop_scale', String(v)); } catch (e) {}
    }

    // theme chips
    if (themeNeon) themeNeon.onclick = function(){ applyTheme('neon'); };
    if (themeCarbon) themeCarbon.onclick = function(){ applyTheme('carbon'); };
    var themeTerminal = $('themeTerminal');
    var themeObsidian = $('themeObsidian');
    if (themeTerminal) themeTerminal.onclick = function(){ applyTheme('terminal'); };
    if (themeObsidian) themeObsidian.onclick = function(){ applyTheme('obsidian'); };

    // profile
    var aliasSave = $('aliasSave');
    if (aliasSave) {
      aliasSave.onclick = function(){
        var alias = ($('aliasInput') && $('aliasInput').value) || '';
        post('saveProfile', { alias: alias, privacy: 1 });
        setTimeout(function(){ post('refresh'); }, 250);
      };
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

    // Prevent early NUI messages from crashing before DOM is ready.
    if (!DOM_READY) return;


if (msg.type === 'syndInvite') {
  var d = msg.data || {};
  var name = d.name || 'Syndicate';
  var id = d.syndicateId;
  try {
    if (confirm('Join ' + name + '?')) {
      post('syndAcceptInvite', { syndicateId: id });
      setTimeout(function(){ post('refresh'); }, 250);
    }
  } catch(e) {}
  return;
}

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

          var bonusEl = $("completeBonus");
          if (bonusEl) {
            bonusEl.innerHTML = "";
            if (msg.bonusObjective && msg.bonusObjective.label) {
              var b = msg.bonusObjective;
              var line = document.createElement("div");
              line.className = "cBonus";
              var rep = Number(msg.bonusRep || 0) || 0;
              if (msg.bonusAchieved) {
                line.innerHTML = "<span class=\"bTag\">BONUS COMPLETE</span> " + escapeHtml(b.label) + (rep > 0 ? (" <span class=\"bRep\">+" + rep + " rep</span>") : "");
              } else {
                line.innerHTML = "<span class=\"bTag fail\">BONUS</span> " + escapeHtml(b.label);
              }
              bonusEl.appendChild(line);
            }
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

    if (msg.type === 'bonusStatus') {
      try {
        if (state.contract) {
          state.contract.bonus = state.contract.bonus || {};
          state.contract.bonus.state = msg.state || state.contract.bonus.state || 'active';
        }
        // Live status UI
        renderContractPanel();

        // Mid-run warning banner
        var st = String(msg.state || '');
        if (st === 'at_risk') {
          showBonusWarn(msg.reason || 'BONUS AT RISK');
        } else if (st === 'failed') {
          showBonusWarn(msg.reason || 'BONUS FAILED');
        } else if (st === 'completed') {
          showBonusWarn('BONUS COMPLETE');
        }
      } catch(eB){}
      return;
    }
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
      state.topSyndicates = d.topSyndicates || [];
      state.history = d.history || [];
      state.progress = d.progress || null;
      state.repUnlocks = d.repUnlocks || null;
      state.repPerk = d.repPerk || null;
      state.upgrades = d.upgrades || null;
      state.profile = d.profile || null;
      state.special = d.special || null;
      state.roleDefs = d.roleDefs || null;
      state.syndicateCfg = d.syndicateCfg || null;
      state.syndicate = d.syndicate || null;
      state.syndicateMembers = d.syndicateMembers || [];

      // Syndicate extended payloads (bank/tree/ops/war)
      state.syndicateVault = d.syndicateVault || 0;
      state.syndicateVaultTx = d.syndicateVaultTx || [];
      state.syndicatePerks = d.syndicatePerks || {};
      state.syndicateSettings = d.syndicateSettings || null;
      state.syndicateStatsAgg = d.syndicateStatsAgg || {};
      state.syndicateOp = d.syndicateOp || null;
      state.syndicateTreeCfg = d.syndicateTreeCfg || {};
      state.syndicateOpsCfg = d.syndicateOpsCfg || {};
      state.syndicatePrestigeCfg = d.syndicatePrestigeCfg || {};
      state.syndicatePermsCfg = d.syndicatePermsCfg || {};
      state.syndicateRoutingCfg = d.syndicateRoutingCfg || {};
      state.blackMarketCfg = d.blackMarketCfg || {};
      state.syndicatePrestige = d.syndicatePrestige || null;
      state.bmEvent = d.bmEvent || null;
      state.bmPool = d.bmPool || [];
      state.bmLeaderboard = d.bmLeaderboard || [];
      state.toolMastery = d.toolMastery || null;

      // Step completion pulse (subtle, minimal)
      try {
        var nowDoneCount = 0;
        if (state.session && state.session.done) {
          for (var kk in state.session.done) {
            if (state.session.done.hasOwnProperty(kk) && state.session.done[kk]) nowDoneCount++;
          }
        }
        if (nowDoneCount > prevDoneCount) {
          var tl = $('timeline');
          if (tl) {
            tl.classList.remove('stepPulse');
            tl.offsetHeight;
            tl.classList.add('stepPulse');
            setTimeout(function(){ try{ tl.classList.remove('stepPulse'); }catch(e){} }, 480);
          }
          SFX.tick();
        }
      } catch (e) {}

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
          // Contract intro sequence (cinematic card)
          try {
            var io = $("introOverlay");
            if (io) {
              var meta2 = [];
              meta2.push(String(state.contract.tier || "").toUpperCase());
              if (state.contract.model) meta2.push(String(state.contract.model));
              if (state.contract.plate) meta2.push("PLATE " + String(state.contract.plate));
              $("introMeta").textContent = meta2.join(" • ");

              // Mods
              var im = $("introMods");
              if (im) {
                im.innerHTML = "";
                var mods2 = state.contract.modifiers || [];
                for (var ii = 0; ii < mods2.length; ii++) {
                  var m2 = mods2[ii] || {};
                  var chip2 = document.createElement("div");
                  chip2.className = "modChip";
                  chip2.innerHTML = "<span class=\"modDot\"></span><span>" + escapeHtml(m2.label || m2.id || "Modifier") + "</span>";
                  im.appendChild(chip2);
                }
              }

              // Bonus
              var ib = $("introBonus");
              if (ib) {
                ib.innerHTML = "";
                if (state.contract.bonusObjective && state.contract.bonusObjective.label) {
                  var b2 = state.contract.bonusObjective;
                  ib.innerHTML = "<div class=\"bonusRow\"><span class=\"bonusTag\">BONUS</span><div class=\"bonusText\"><div class=\"bonusLabel\">" + escapeHtml(b2.label) + "</div><div class=\"bonusDesc\">" + escapeHtml(b2.desc || "") + "</div></div></div>";
                }
              }

              io.classList.add("show");
              SFX.whoosh();
              setTimeout(function(){ try{ io.classList.remove("show"); }catch(e){} }, 2600);
            }
          } catch(eIntro) {}

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
    DOM_READY = true;
    bind();
    setTab('contract');
    // Ask server for fresh data after UI is fully ready.
    setTimeout(function(){ try{ post('refresh'); }catch(e){} }, 150);
  });
  // (moved) remaining upgrade UI helpers continue below
  var upgView = 'tree';
  var upgHoverId = null;

  function toast(msg) {
    var t = $('toast');
    if (!t) return;
    t.textContent = String(msg || '');
    t.classList.remove('hidden');
    t.classList.add('show');
    clearTimeout(toast._tm);
    toast._tm = setTimeout(function(){ t.classList.add('hidden'); t.classList.remove('show'); }, 1800);
  }

  function playUpgSfx() {
    try {
      var a = $('sfxUpg');
      if (a) { a.currentTime = 0; a.volume = 0.6; a.play(); }
    } catch (e) {}
  }

})();
