::  esplora nexus: a bitcoin block-explorer client.
::
::  A caller asks this nexus for the chain; it queries one provider and keeps
::  the answer beside the question. It holds /sys/iris and the provider urls,
::  so callers do not reach the internet themselves.
::
::  The question is a grub, not a poke that returns, because it has to
::  outlive a reboot. A take is ephemeral: a fiber waiting on an answer is
::  gone if the kernel restarts mid-query. A grub is state, so the question
::  persists and +run-ask wakes on it and finishes as if nothing happened.
::  The dance below is the cost; a request that cannot be lost is the point.
::
::  A question is a grub under ask/, its answer written back into it:
::
::    ask/<id>.json  {"status": "pending", "request": {...}}
::                -> {"status": "done", "request": {...},
::                    "ok": true, "code": 200, "body": <the provider>}
::
::  The request is kept beside the answer: an answer that erased what it
::  answered leaves the asker, and the status page, with a result they
::  cannot attribute.
::
::  An asker keeps ask/<id>.json FIRST,
::  before it exists, then pokes main.sig {"id": ..., "req": {...}}, reads on
::  news until status is done, then drops and culls the grub. Keeping before
::  the grub exists: a keep taken out after can miss the very news it waits
::  for.
::
::  A request:
::
::    {"op": "address"|"utxo"|"txs"|"price", "network": "main",
::     "address": "bc1..."}
::    {"op": "broadcast", "network": "main", "tx": "<hex>"}
::
::  Nobody but this nexus speaks to the provider; which provider lives in
::  config.json: {"<network>": "<base url>"}.
::
::  Helper libraries - the chain types, the provider, and serving the page.
::
/<  wt          /lib/wallet-types.hoon    ::  the shapes a chain answer comes back in
/<  esp         /lib/wallet/esplora.hoon  ::  which provider answers, and how to ask it
/<  nw          /lib/nexus-web.hoon       ::  serving the page
::
::  the status page - its assets. The page reads this nexus's state through
::  the kernel's peek api; this nexus only hands it the files.
::
/<  ui-html  ./index.html  ::  the status page
/<  ui-js    ./app.js      ::  what it does
/<  ui-css   ./style.css   ::  how it looks
/<  ui-icon  ./icon.svg    ::  its tile icon
::
::  the json this nexus ships - the name it answers to, its tile, the roads
::  it asks for, and the log it starts empty. Each is the file beside it.
::
/&  link-mime      ./link.json      ::  the name it answers to, for /sys/link
/&  tile-mime      ./tile.json      ::  its launcher tile
/&  weir-mime      ./weir.json      ::  the roads it asks for, and why
/&  activity-mime  ./activity.json  ::  the log it starts empty
=,  wt
=<  ^-  nexus:nexus
    |%
    ++  on-load
      |=  =ball:tarball
      ^-  bole:tarball
      ::  the providers and price the page shows are derived from config.json
      ::  into providers.json beside it, so the page peeks state through the
      ::  kernel api rather than asking this nexus to assemble a view. Read
      ::  config from the ball this load carries.
      =/  conf=json
        =/  c=(unit sang:tarball)  (~(get ba:tarball ball) [/ %'config.json'])
        ?~  c  [%o ~]
        (fall (mole |.(;;(json (sang-noun:tarball u.c)))) [%o ~])
      %+  spin:loader  ball
      :~  (manifest:loader 0)
          [%over %& [/ %'providers.json'] [[/ %json] (resolve-providers conf)]]
          [%over %& [/ %'link.json'] [[/ %json] (as-json:loader link-mime)]]
          [%over %& [/ %'tile.json'] [[/ %json] (as-json:loader tile-mime)]]
          [%over %& [/ %'icon.svg'] [[/ %mime] ui-icon]]
          [%over %& [/ %'index.html'] [[/ %mime] ui-html]]
          [%over %& [/ %'app.js'] [[/ %mime] ui-js]]
          [%over %& [/ %'style.css'] [[/ %mime] ui-css]]
          [%over %& [/ %'weir.json'] [[/ %json] (as-json:loader weir-mime)]]
          [%fall %& [/ %'activity.json'] [[/ %json] (as-json:loader activity-mime)]]  ::  the log, seeded empty
          [%fall %& [/ %'config.json'] [[/ %json] init:esp]]         ::  who to ask, per network
          [%over %& [/ %'main.sig'] [[/ %sig] ~]]                    ::  takes the pokes that open a question
          [%fall %| /ask empty-dir:loader]                           ::  every question asked and not yet collected
          [%over %& [/ %'web.sig'] [[/ %sig] ~]]                     ::  the page's http binding
          [%fall %| /requests empty-dir:loader]                      ::  one fiber per request to it
          [%stay %& [/ %'grant.json']]                               ::  what the user has granted
      ==
    ::
    ++  on-file
      |=  [=rail:tarball =blot:tarball]
      ^-  spool:fiber:nexus
      |=  =prod:fiber:nexus
      =/  m  (fiber:fiber:nexus ,~)
      ^-  process:fiber:nexus
      ?+    rail  stay:m
          ::  the pokes that open a question
          ::
          [~ %'main.sig']
        main-loop
          ::  one question, one fiber, the answer written beside it
          ::
          [[%ask ~] @]
        run-ask
          ::  the page: bound here, each request served below
          ::
          [~ %'web.sig']
        ;<  ~  bind:m  (bind-http-self:io [~ /grubbery/esplora])
        http-dispatch:io
          ::  one request to it, served
          ::
          [[%requests ~] @]
        (serve rail name.rail)
      ==
    --
|%
::  +resolve-providers: the provider per network and the price source,
::  config's choice or the default, as the status page reads them. The
::  defaults and the overlay live in the esp lib; this only lays them out
::  as json for providers.json, derived from config.json on load.
::
++  resolve-providers
  |=  conf=json
  ^-  json
  =/  nets=(list @t)  ~['main' 'testnet3' 'testnet4' 'signet' 'regtest']
  =/  named                             ::  does config name this key?
    |=  key=@t
    ^-  ?
    ?.  ?=([%o *] conf)  |
    =/  g=(unit json)  (~(get by p.conf) key)
    &(?=([~ %s *] g) !=('' p.u.g))
  %-  pairs:enjs:format
  :~  :-  'providers'
      :-  %a
      %+  turn  nets
      |=  net=@t
      ^-  json
      =/  =network  (fall ((soft network) net) %main)
      %-  pairs:enjs:format
      :~  ['network' s+net]
          ['url' s+(crip (base:esp conf network))]
          ['configured' b+(named net)]
      ==
      :-  'price'
      %-  pairs:enjs:format
      :~  ['url' s+(crip (price-base:esp conf))]
          ['configured' b+(named 'price')]
      ==
  ==
::  the ask protocol - a question opened by a poke, answered beside itself.
::
::  +main-loop: the fiber on main.sig. It receives every question a caller
::  pokes in and opens it as a pending ask/<id>.json grub for +run-ask to
::  answer. One poke, one grub; it never returns.
::
++  main-loop
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |-
  ;<  ask=(unit question)  bind:m  take-question
  ?~  ask  $
  ;<  ~  bind:m  (open-ask u.ask)
  $
::  $question: what a poke opens — the id the asker chose, and the request
::  to put to the provider.
::
+$  question  [id=@t req=json]
::  +take-question: the next question a poke opens, or ~ for a poke that is
::  not one — the wrong mark, or json with no id or request. A rejected poke
::  is logged and skipped, never answered.
::
++  take-question
  =/  m  (fiber:fiber:nexus ,(unit question))
  ^-  form:m
  ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
  ?.  =([/ %json] p.sage)
    ~&  >>>  [%esplora-unrecognized-poke mark=p.sage from=from]
    (pure:m ~)
  =/  ask=(unit question)  (parse-ask !<(json q.sage))
  ?~  ask
    ~&  >>>  "%esplora: poke missing id or req"
    (pure:m ~)
  (pure:m ask)
::  +parse-ask: a poke's json as the question it opens. ~ when it names
::  no id or no request, which is the only thing wrong with it we can see
::  from here.
::
++  parse-ask
  |=  jon=json
  ^-  (unit question)
  =/  id=@t  (~(dug jo:json-utils jon) /id so:dejs:format '')
  =/  req=(unit json)  (~(get jo:json-utils jon) /req)
  ?:  |(=('' id) ?=(~ req))  ~
  `[id u.req]
::  +open-ask: write a question as a pending grub under ask/, gained so the
::  answer outlives this fiber and the asker is still reading when +run-ask
::  fills it in.
::
++  open-ask
  |=  =question
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  =road:tarball  (ask-road id.question)
  =/  content=json
    (pairs:enjs:format ~[['status' s+'pending'] ['request' req.question]])
  ;<  ~  bind:m  (make:io road |+[[[/ %json] content] ~])
  (gain:io road %.y)
::  +ask-road: where a question by that id is kept, beside this nexus.
::
++  ask-road
  |=  id=@t
  ^-  road:tarball
  (cord-to-road:tarball (crip "./ask/{(trip id)}.json"))
::  +query-provider: the one place this nexus reaches past the ship. It
::  builds the request the op needs -- a broadcast POSTs the raw
::  transaction, every other op GETs -- puts it to the provider over iris,
::  and hands back the single response. Nobody else here speaks outward; a
::  caller's question becomes this outbound query and nothing more.
::
++  query-provider
  |=  [req=request url=@t]
  =/  m  (fiber:fiber:nexus ,client-response:iris)
  ^-  form:m
  ;<  ~  bind:m  (send-request:io (ask-request req url))
  take-client-response:io
::  +run-ask: answer the pending question this grub holds, beside it.
::
::  Only a pending grub is work. A grub that already holds an answer is this
::  fiber waking after a reboot; the answer is what matters, so it stays.
::
++  run-ask
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  the grub this fiber woke on; only a pending question is work — a done
  ::  one is this fiber back after a reboot, and its answer stays
  ;<  own=json  bind:m  (get-state-as:io ,json)
  ?.  =('pending' (~(dug jo:json-utils own) /status so:dejs:format ''))  stay:m
  ::  the request it holds, and the url its op and configured provider give it
  =/  req=request  (parse-request (~(gut jo:json-utils own) /request [%o ~]))
  ;<  conf=json  bind:m  (read:esp [%| 1 %& / %'config.json'])
  =/  url=(unit @t)  (ask-url conf req)
  ::  no url: an op we do not answer, or one missing its argument
  ?~  url  (answer req %.n 0 'bad ask' ~)
  ::  put the request, take the one answer, write the outcome beside it
  ;<  resp=client-response:iris  bind:m  (query-provider req u.url)
  =/  out  (response-outcome resp)
  (answer req ok.out code.out err.out body.out)
::  $request: a question's request, parsed into the fields the ops read.
::  Keeps the raw json so the answer can store the question verbatim.
::
+$  request
  $:  raw=json
      op=@t
      network=@t
      address=@t
      tx=@t
      hash=@t
      height=@t
      txid=@t
  ==
::  +parse-request: a request json as the fields its op reads, the raw
::  kept alongside. Absent or non-string fields read as '', which the ops
::  treat as "not given".
::
++  parse-request
  |=  jon=json
  ^-  request
  :*  jon
      (~(dug jo:json-utils jon) /op so:dejs:format '')
      (~(dug jo:json-utils jon) /network so:dejs:format '')
      (~(dug jo:json-utils jon) /address so:dejs:format '')
      (~(dug jo:json-utils jon) /tx so:dejs:format '')
      (~(dug jo:json-utils jon) /hash so:dejs:format '')
      (~(dug jo:json-utils jon) /height so:dejs:format '')
      (~(dug jo:json-utils jon) /txid so:dejs:format '')
  ==
::  +ask-url: where to put a request, from the op it names and the
::  provider configured for its network. ~ for an op we do not answer, or
::  one missing the argument it needs.
::
::    The last four — a header by its hash, the hash at a height, the tip,
::    and the merkle branch proving a txid sits in a block — are standard
::    Esplora, answered by any provider.
::
++  ask-url
  |=  [conf=json req=request]
  ^-  (unit @t)
  ::  the chain it names, main for anything we do not know
  =/  =network  (fall ((soft network) network.req) %main)
  ?+  op.req  ~
    %address    ?:(=('' address.req) ~ `(addr-url:esp conf network address.req))
    %utxo       ?:(=('' address.req) ~ `(utxo-url:esp conf network address.req))
    %txs        ?:(=('' address.req) ~ `(txs-url:esp conf network address.req))
    %price      `(price-url:esp conf)
    %broadcast  ?:(=('' tx.req) ~ `(tx-url:esp conf network))
    %header     ?:(=('' hash.req) ~ `(header-url:esp conf network hash.req))
    %block-at   ?:(=('' height.req) ~ `(height-url:esp conf network height.req))
    %tip        `(tip-url:esp conf network)
    %blocks     ?:(=('' height.req) ~ `(blocks-url:esp conf network height.req))
    %merkle     ?:(=('' txid.req) ~ `(merkle-url:esp conf network txid.req))
  ==
::  +ask-request: how to put it. A broadcast posts the raw transaction;
::  everything else is a get.
::
++  ask-request
  |=  [req=request url=@t]
  ^-  request:http
  ?.  =(%broadcast op.req)
    [%'GET' url ~[['Accept' 'application/json']] ~]
  [%'POST' url ~[['content-type' 'text/plain']] `(as-octs:mimes:html tx.req)]
::  +response-outcome: an iris response as the answer fields. A response that
::  never finished, or finished with no body, is still an answer — ok and
::  code say what happened. Json when the body parses, the raw text when it
::  does not: a broadcast answers with a bare txid, an error with a sentence.
::
++  response-outcome
  |=  resp=client-response:iris
  ^-  [ok=? code=@ud err=@t body=(unit json)]
  ?.  ?=(%finished -.resp)  [%.n 0 'no answer' ~]
  =/  code=@ud  status-code.response-header.resp
  ?~  full-file.resp  [(lth code 300) code '' ~]
  =/  raw=@t  q.data.u.full-file.resp
  [(lth code 300) code '' `(fall (de:json:html raw) s+raw)]
::  +answer: the outcome, written beside the request that asked for it.
::  +stay:m, not a return: a fiber that finishes takes its grub with it
::  unless the grub was gained, and the asker may still be reading.
::
++  answer
  |=  [req=request ok=? code=@ud err=@t body=(unit json)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m  (append-activity (activity-entry req ok code err now))
  ;<  ~  bind:m  (replace:io (answer-json req ok code err body))
  stay:m
::  +answer-json: the outcome, with the request it answers kept in it.
::
++  answer-json
  |=  [req=request ok=? code=@ud err=@t body=(unit json)]
  ^-  json
  %-  pairs:enjs:format
  :~  ['status' s+'done']
      ['request' raw.req]
      ['ok' b+ok]
      ['code' (numb:enjs:format code)]
      ['error' s+err]
      ['body' (fall body ~)]
  ==
::  +activity-entry: the same outcome, as one line of the log.
::
++  activity-entry
  |=  [req=request ok=? code=@ud err=@t now=@da]
  ^-  json
  %-  pairs:enjs:format
  :~  ['op' s+op.req]
      ['network' s+network.req]
      ['ok' b+ok]
      ['code' (numb:enjs:format code)]
      ['error' s+err]
      ['at' s+(scot %da now)]
  ==
::  +append-activity: one line per answered question, newest first,
::  capped at 200.
::
++  append-activity
  |=  entry=json
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  prepend the entry to the log, newest first, capped at 200
  =/  =road:tarball  [%| 1 %& / %'activity.json']
  ;<  cur=(unit json)  bind:m  (peek-as:io road ,json)
  =/  kept=(list json)  (scag 200 `(list json)`[entry (log-entries cur)])
  =/  new=json  (pairs:enjs:format ~[['entries' [%a kept]]])
  (over:io road [[/ %json] new])
::  +log-entries: the entries a log grub holds, ~ for an empty or absent one.
::
++  log-entries
  |=  cur=(unit json)
  ^-  (list json)
  ?~  cur  ~
  (~(dug jo:json-utils u.cur) /entries (ar:dejs:format same:dejs:format) ~)
::
::  /esplora status page - bound at /grubbery/esplora, served static.
::
::  +serve: hand each request the file it names. The page reads this nexus's
::  state through the kernel's peek api; serving the files is all this does.
::
++  serve
  |=  [=rail:tarball eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  owner only; the page shows this nexus's own setup and queue
  ;<  [src=@p req=inbound-request:eyre]  bind:m
    (get-state-as:io ,[src=@p inbound-request:eyre])
  ;<  our=@p  bind:m  get-our:io
  ?.  =(src our)  (reply:web:nw eyre-id 403 'Forbidden')
  ::  the path below the binding names the file
  =/  [site=path args=quay:eyre]  (parse-url:http-utils url.request.req)
  (serve-static:web:nw eyre-id (slag (lent `path`/grubbery/esplora) site))
--