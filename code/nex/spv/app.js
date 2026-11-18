// spv nexus UI: a reader. Everything comes from /api/status.
(function () {
  var API = '/grubbery/spv/api/status';
  function el(id) { return document.getElementById(id); }
  function num(n) { return (n === undefined || n === null) ? '—' : Number(n).toLocaleString(); }

  function paint(d) {
    var st = d.status || {}, cfg = d.config || {};
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
  setInterval(load, 5000);
  load();
})();
