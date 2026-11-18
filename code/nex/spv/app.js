// spv nexus UI: a reader. Everything comes from /api/status.
(function () {
  var API = '/grubbery/spv/api/status';
  function el(id) { return document.getElementById(id); }
  function num(n) { return (n === undefined || n === null) ? '—' : Number(n).toLocaleString(); }

  function paint(d) {
    var st = d.status || {}, cfg = d.config || {};
    paintConfig(cfg);
    el('net').textContent = st.network || cfg.network || '—';
    el('checkpoint').textContent = num(d.checkpoint);
    el('height').textContent = num(st.height);
    el('tip').textContent = num(st.tip);
    el('headers').textContent = num(d.headers);

    var state = st.state || 'starting';
    var cls = state === 'synced' ? 'pill ok' : state === 'stalled' ? 'pill bad' : 'pill go';
    var pill = el('state-pill');
    pill.className = cls;
    pill.textContent = state;

    // progress from checkpoint to tip, which is the span this ship claims
    var from = Number(d.checkpoint || 0), at = Number(st.height || 0), to = Number(st.tip || 0);
    var pct = (to > from) ? Math.max(0, Math.min(100, ((at - from) / (to - from)) * 100)) : 0;
    el('bar').style.width = pct.toFixed(1) + '%';
    el('behind').textContent = st.behind
      ? num(st.behind) + ' blocks behind the tip'
      : (state === 'synced' ? 'caught up' : '');

    var stalled = state === 'stalled';
    el('why-panel').hidden = !stalled;
    if (stalled) el('why').textContent = st.why || '';

    el('status').textContent = st.at ? 'read ' + new Date().toLocaleTimeString() : '';
  }

  function load() {
    return fetch(API, { headers: { accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('status ' + r.status); return r.json(); })
      .then(paint)
      .catch(function (e) { el('status').textContent = e.message; });
  }
  // --- block headers -------------------------------------------------
  // Paged rather than streamed: the list is a record of work already
  // done, so it does not need to be live. Only the status above does.
  var page = 0, shown = [];
  var hdrBody = document.querySelector('#headers tbody');

  function fmtTime(sec) {
    if (!sec) return '—';
    return new Date(sec * 1000).toISOString().replace('T', ' ').slice(0, 16);
  }

  function showDetail(h) {
    el('d-height').textContent = num(h.height);
    var rows = [
      ['hash', h.hash], ['previous', h.prev], ['merkle root', h.merkle],
      ['timestamp', fmtTime(h.timestamp) + '  (' + h.timestamp + ')'],
      ['bits', h.bits], ['nonce', h.nonce], ['cumulative work', num(h.work)],
      ['proof of work', h.pow ? 'verified here' : 'NOT VERIFIED']
    ];
    el('detail').innerHTML = rows.map(function (r) {
      return '<tr><td>' + r[0] + '</td><td class="v">' + r[1] + '</td></tr>';
    }).join('');
    el('detail-panel').hidden = false;
  }

  function paintHeaders(d) {
    shown = d.headers || [];
    hdrBody.textContent = '';
    el('hdr-none').hidden = shown.length > 0;
    shown.forEach(function (h, i) {
      var tr = el2('tr', 'hdr-row');
      tr.appendChild(el2('td', 'num', num(h.height)));
      tr.appendChild(el2('td', 'hash', h.hash));
      tr.appendChild(el2('td', 'num', fmtTime(h.timestamp)));
      var td = el2('td');
      td.appendChild(el2('span', h.pow ? 'pill ok' : 'pill bad', h.pow ? 'verified' : 'no'));
      tr.appendChild(td);
      tr.addEventListener('click', function () { showDetail(shown[i]); });
      hdrBody.appendChild(tr);
    });
    var from = page * d.per;
    el('hdr-range').textContent = shown.length
      ? (num(from + 1) + '–' + num(from + shown.length) + ' of ' + num(d.total))
      : '';
    el('newer').disabled = page === 0;
    el('older').disabled = (from + shown.length) >= d.total;
  }

  function el2(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function loadHeaders() {
    return fetch('/grubbery/spv/api/headers?page=' + page, { headers: { accept: 'application/json' } })
      .then(function (r) { return r.json(); })
      .then(paintHeaders)
      .catch(function () {});
  }

  el('newer').addEventListener('click', function () {
    if (page > 0) { page--; loadHeaders(); }
  });
  el('older').addEventListener('click', function () { page++; loadHeaders(); });
  el('d-close').addEventListener('click', function () { el('detail-panel').hidden = true; });

  // --- settings ------------------------------------------------------
  // Both fields invalidate the chain, so saving says so plainly and the
  // page does not pretend the old headers still count.
  var cfgLoaded = false;

  function paintConfig(cfg) {
    if (cfgLoaded) return;            // don't fight the user mid-edit
    cfgLoaded = true;
    el('cfg-net').value = cfg.network || 'main';
    el('cfg-look').value = cfg.lookback === undefined ? 1008 : cfg.lookback;
    noteLookback();
  }

  function noteLookback() {
    var n = Number(el('cfg-look').value);
    el('cfg-look-note').textContent = isNaN(n) || n <= 0
      ? 'from the genesis block'
      : 'about ' + (n / 144).toFixed(1) + ' days of chain';
  }

  function saveConfig(body, label) {
    var btns = [el('cfg-save'), el('cfg-reset')];
    btns.forEach(function (b) { b.disabled = true; });
    el('cfg-saved').textContent = '…';
    return fetch('/grubbery/spv/api/config', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
      .then(function (r) { if (!r.ok) throw new Error('save failed'); return r.json(); })
      .then(function () {
        el('cfg-saved').textContent = label;
        page = 0;
        // let the form take the server's view again: what was typed is
        // now what is stored, and anything else here would be a lie
        cfgLoaded = false;
        return Promise.all([load(), loadHeaders()]);
      })
      .catch(function (e) { el('cfg-saved').textContent = e.message; })
      .then(function () { btns.forEach(function (b) { b.disabled = false; }); });
  }

  el('cfg-look').addEventListener('input', noteLookback);
  el('cfg-save').addEventListener('click', function () {
    saveConfig({
      network: el('cfg-net').value,
      lookback: Number(el('cfg-look').value) || 0
    }, 'saved — rebuilding');
  });
  el('cfg-reset').addEventListener('click', function () {
    saveConfig({}, 'rebuilding');
  });

  setInterval(load, 5000);
  load();
  loadHeaders();
})();
