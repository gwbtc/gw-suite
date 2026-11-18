// esplora nexus UI: a reader. Everything on the page comes from
// /api/status — config.json as the nexus resolves it, and whatever is
// sitting under ask/ right now. Nothing here writes.
(function () {
  var API = '/grubbery/esplora/api/status';
  var statusEl = document.getElementById('status');
  var provBody = document.querySelector('#providers tbody');
  var waitBody = document.querySelector('#waiting tbody');
  var waitCount = document.getElementById('waiting-count');
  var waitNone = document.getElementById('waiting-none');
  var waitTable = document.getElementById('waiting');

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function paintProviders(rows) {
    provBody.textContent = '';
    rows.forEach(function (p) {
      var tr = el('tr');
      tr.appendChild(el('td', null, p.network));
      tr.appendChild(el('td', 'url', p.url));
      var td = el('td');
      td.appendChild(el('span', p.configured ? 'pill set' : 'pill',
        p.configured ? 'config.json' : 'default'));
      tr.appendChild(td);
      provBody.appendChild(tr);
    });
  }

  function paintWaiting(rows) {
    waitBody.textContent = '';
    waitCount.textContent = rows.length ? rows.length + ' open' : '';
    waitNone.hidden = rows.length > 0;
    waitTable.hidden = rows.length === 0;
    rows.forEach(function (q) {
      var tr = el('tr');
      tr.appendChild(el('td', 'id', q.name));
      tr.appendChild(el('td', null, q.op || '—'));
      tr.appendChild(el('td', null, q.network || '—'));
      var td = el('td');
      var cls = q.state === 'answered' ? 'pill done'
              : q.state === 'failed' ? 'pill bad' : 'pill wait';
      td.appendChild(el('span', cls, q.state));
      tr.appendChild(td);
      waitBody.appendChild(tr);
    });
  }

  function load() {
    return fetch(API, { headers: { accept: 'application/json' } })
      .then(function (r) {
        if (!r.ok) throw new Error('status ' + r.status);
        return r.json();
      })
      .then(function (d) {
        paintProviders(d.providers || []);
        paintWaiting(d.waiting || []);
        statusEl.textContent = 'read ' + new Date().toLocaleTimeString();
      })
      .catch(function (e) {
        statusEl.textContent = e.message;
      });
  }

  document.getElementById('refresh').addEventListener('click', load);
  // questions come and go in seconds, so the in-flight table is only
  // honest if it keeps looking
  setInterval(load, 5000);
  load();
})();
