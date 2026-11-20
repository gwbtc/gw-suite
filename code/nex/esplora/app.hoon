::  esplora nexus: the chain, asked of exactly one stranger.
::
::  The wallet used to make its own requests: it held /sys/iris, which is
::  "may fetch any url on the internet", and three files in it knew the
::  provider's urls. That is a lot of reach for the app holding the keys,
::  and it put rate limiting, caching and provider choice in the middle of
::  a scan loop.
::
::  This nexus owns the connection. It is the lifecycle-grub pattern the
::  github, anthropic and openrouter proxies share:
::
::    ask/<id>.json  {"status": "pending", "request": {...}}
::                -> {"status": "done", "request": {...},
::                    "ok": true, "code": 200, "body": <the provider>}
::
::  The request is KEPT beside the answer. An answer that erased what it
::  was answering leaves the asker — and anyone reading the status page —
::  holding a result they cannot attribute.
::
::  The flow, for an asker (see +ask in lib/wallet/esplora):
::
::    1. pick an id and KEEP ask/<id>.json FIRST, before it exists
::    2. poke main.sig {"id": ..., "req": {...}}
::    3. read on news until status is done
::    4. drop, and cull the grub
::
::  Keeping first is the whole of step 1: a keep taken out after the
::  grub exists can miss the very news it is waiting for.
::
::  A request:
::
::    {"op": "address"|"utxo"|"txs"|"price", "network": "main",
::     "address": "bc1..."}
::    {"op": "broadcast", "network": "main", "tx": "<hex>"}
::
::  Nobody but this nexus speaks to the provider, and which provider that
::  is lives in config.json: {"<network>": "<base url>"}.
::
::  Helper libraries - the chain types, the provider, serving a page.
::
/<  wt   /lib/wallet-types.hoon    ::  the shapes a chain answer comes back in
/<  esp  /lib/wallet/esplora.hoon  ::  which provider answers, and how to ask it
/<  nw   /lib/nexus-web.hoon       ::  serving a page
::
::  /esplora status page - the page and its assets.
::
/<  ui-html  ./index.html  ::  the status page
/<  ui-js    ./app.js      ::  what it does
/<  ui-css   ./style.css   ::  how it looks
/<  ui-icon  ./icon.svg    ::  its tile icon
=,  wt
=<  ^-  nexus:nexus
    |%
    ++  on-load
      |=  =ball:tarball
      ^-  bole:tarball
      %+  spin:loader  ball
      :~  (manifest:loader 0)
          [%over %& [/ %'link.json'] [[/ %json] link-json]]
          [%over %& [/ %'icon.svg'] [[/ %mime] ui-icon]]
          [%over %& [/ %'index.html'] [[/ %mime] ui-html]]
          [%over %& [/ %'app.js'] [[/ %mime] ui-js]]
          [%over %& [/ %'style.css'] [[/ %mime] ui-css]]
          [%over %& [/ %'tile.json'] [[/ %json] tile-json]]
          [%over %& [/ %'weir.json'] [[/ %json] weir-json]]
          [%fall %& [/ %'activity.json'] [[/ %json] activity-json]]  ::  what was asked, and what came back
          [%fall %& [/ %'config.json'] [[/ %json] init:esp]]         ::  who to ask, per network
          [%over %& [/ %'main.sig'] [[/ %sig] ~]]                    ::  takes the pokes that open a question
          [%fall %| /ask empty-dir:loader]                           ::  every question asked and not yet collected
          [%over %& [/ %'web.sig'] [[/ %sig] ~]]                     ::  the status page
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
          ::  the status page: static files and one json endpoint
          ::
          [~ %'web.sig']
        ;<  ~  bind:m  (bind-http-self:io [~ /grubbery/esplora])
        http-dispatch:io
          ::  one request to it
          ::
          [[%requests ~] @]
        (serve rail name.rail)
      ==
    --
|%
::  the rows seeded at load - the log, the weir, the link and the tile.
::
::  +activity-json: the log starts empty. One line per answered question,
::  newest first, capped — a proxy that forgets is a proxy you cannot
::  debug. When a provider begins rate-limiting mid-scan the wallet keeps
::  its old data quietly, and without this nothing anywhere says why.
::  Summaries only: the asker already got the body, and a txs response for
::  a busy address is not worth keeping.
::
++  activity-json
  ^-  json
  (pairs:enjs:format ~[['entries' [%a ~]]])
::  +weir-json: the roads this nexus asks for, each with why it needs it.
::  Nothing is peeked: the questions arrive as pokes.
::
++  weir-json
  ^-  json
  %-  pairs:enjs:format
  :~  :-  'poke'
      :-  %a
      :~  (weir-road '/sys/bowl.sig' 'the entropy every outbound request is tagged with')
          (weir-road '/sys/iris/' 'read the chain from an esplora api, and broadcast there')
          (weir-road '/sys/eyre/' 'bind /grubbery/esplora and serve the status page')
      ==
      ['peek' a+~]
  ==
::  +weir-road: one road of a weir and the reason it is asked for, as the
::  shell reads them.
::
++  weir-road
  |=  [road=@t why=@t]
  ^-  json
  (pairs:enjs:format ~[['road' s+road] ['why' s+why]])
::  +link-json: the name this nexus answers to, for /sys/link.
::
++  link-json
  ^-  json
  %-  pairs:enjs:format
  :~  ['name' s+'esplora']
      ['description' s+'the bitcoin chain, read from an esplora api']
  ==
::  +tile-json: a utility in the launcher, opening the status page.
::
++  tile-json
  ^-  json
  %-  pairs:enjs:format
  :~  title+s+'Esplora'
      info+s+'the chain, asked of one stranger'
      color+s+'#16212e'
      ::  no image: the shell points the tile at icon.svg beside this
      ::  file, by the path this nexus actually got installed at, which
      ::  is not knowable from in here
      href+s+'/grubbery/esplora'
      kind+s+'utility'
  ==
::
::  /esplora status page - its one endpoint, and what that reports.
::
++  reply          reply:web:nw          ::  a bare status and a line of text
++  send-json      send-json:web:nw      ::  a json body
++  serve-static   serve-static:web:nw   ::  the page and its assets
::  +serve: the status page. Nothing here is driven by a person — the
::  questions come from other apps — so the page only reports:
::    GET  /api/status   {providers, waiting}
::
++  serve
  |=  [=rail:tarball eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  [src=@p req=inbound-request:eyre]  bind:m
    (get-state-as:io ,[src=@p inbound-request:eyre])
  ;<  our=@p  bind:m  get-our:io
  ?.  =(src our)
    (reply eyre-id 403 'Forbidden')
  =/  prefix=path  /grubbery/esplora
  =/  [site=path args=quay:eyre]  (parse-url:http-utils url.request.req)
  =/  suffix=path  (slag (lent prefix) site)
  ?+    suffix  (serve-static eyre-id suffix)
      [%api %status ~]
    ;<  conf=json  bind:m  (read:esp [%| 1 %& / %'config.json'])
    ;<  open=(list json)  bind:m  read-open
    %+  send-json  eyre-id
    %-  pairs:enjs:format
    :~  ['providers' a+(provider-rows conf)]
        ['price' (price-row conf)]
        ['waiting' a+open]
    ==
  ==
::  +provider-rows: who answers for each network, and whether that was
::  decided by config.json or by the default
::
++  provider-rows
  |=  conf=json
  ^-  (list json)
  %+  turn  `(list network)`~[%main %testnet3 %testnet4 %signet %regtest]
  |=  =network
  ^-  json
  =/  said=(unit json)
    ?.  ?=([%o *] conf)  ~
    (~(get by p.conf) (scot %tas network))
  %-  pairs:enjs:format
  :~  ['network' s+(scot %tas network)]
      ['url' s+(crip (base:esp conf network))]
      ['configured' b+?=([~ %s ^] said)]
  ==
::  +price-row: who answers for the price, and whether that was decided
::  by config.json or by the default. Its own row because it is its own
::  provider: /v1/prices is not Esplora, and a self-hosted chain node
::  will not serve it.
::
++  price-row
  |=  conf=json
  ^-  json
  =/  said=(unit json)
    ?.  ?=([%o *] conf)  ~
    (~(get by p.conf) 'price')
  %-  pairs:enjs:format
  :~  ['url' s+(crip (price-base:esp conf))]
      ['configured' b+?=([~ %s ^] said)]
  ==
::  +read-open: every question under ask/ as the page shows it.
::
++  read-open
  =/  m  (fiber:fiber:nexus ,(list json))
  ^-  form:m
  ;<  v=view:nexus  bind:m  (peek:io [%| 1 %| /ask] ~)
  ?.  ?=([%ball *] v)  (pure:m ~)
  =/  names=(list @ta)
    (turn ~(tap ba:tarball ball.v) |=([r=rail:tarball *] name.r))
  =|  out=(list json)
  |-
  ?~  names  (pure:m (flop out))
  ;<  one=(unit json)  bind:m  (peek-as:io [%| 1 %& /ask i.names] ,json)
  $(names t.names, out [(open-row i.names (fall one [%o ~])) out])
::  +open-row: one question, as a row of the waiting list.
::
++  open-row
  |=  [name=@ta jon=json]
  ^-  json
  =/  req=json  (fall (jget jon 'request') [%o ~])
  %-  pairs:enjs:format
  :~  ['name' s+name]
      ['op' s+(jstr req 'op')]
      ['network' s+(jstr req 'network')]
      ['state' s+(ask-state jon)]
  ==
::  +ask-state: waiting, while the grub holds only the question. Answered
::  or failed, once the answer is in it and nobody has collected it.
::
++  ask-state
  |=  jon=json
  ^-  @t
  ?.  =('done' (jstr jon 'status'))  'waiting'
  ?:(=(`[%b %.y] (jget jon 'ok')) 'answered' 'failed')
::
::  the ask protocol - a question opened by a poke, answered beside itself.
::
::  $question: what a poke opens — the id the asker chose, and the request
::  to put to the provider.
::
+$  question  [id=@t req=json]
::  +parse-ask: a poke's json as the question it opens. ~ when it names
::  no id or no request, which is the only thing wrong with it we can see
::  from here.
::
++  parse-ask
  |=  jon=json
  ^-  (unit question)
  =/  id=@t  (jstr jon 'id')
  =/  req=(unit json)  (jget jon 'req')
  ?:  |(=('' id) ?=(~ req))  ~
  `[id u.req]
::  +ask-road: where a question by that id is kept, beside this nexus.
::
++  ask-road
  |=  id=@t
  ^-  road:tarball
  (cord-to-road:tarball (crip "./ask/{(trip id)}.json"))
::  +main-loop: open a question. The asker names the id, so it can keep
::  the road before there is anything there to keep.
::
++  main-loop
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |-
  ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
  ?.  =([/ %json] p.sage)
    ~&  >>>  [%esplora-unrecognized-poke mark=p.sage from=from]
    $
  =/  ask=(unit question)  (parse-ask (fall (mole |.(!<(json q.sage))) *json))
  ?~  ask
    ~&  >>>  "%esplora: poke missing id or req"
    $
  =/  =road:tarball  (ask-road id.u.ask)
  =/  content=json
    (pairs:enjs:format ~[['status' s+'pending'] ['request' req.u.ask]])
  ;<  ~  bind:m  (make:io road |+[[[/ %json] content] ~])
  ::  retention on: the answer is the point, and it has to outlive the
  ::  fiber that wrote it so the asker can still be reading
  ;<  ~  bind:m  (gain:io road %.y)
  $
::  +run-ask: answer the question this grub holds, beside it.
::
::  Only a pending grub is work. Anything else is this fiber coming back
::  after a reboot to a question that was already answered, and the
::  answer is what matters, so it stays.
::
++  run-ask
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  own=json  bind:m  (get-state-as:io ,json)
  ?.  =('pending' (jstr own 'status'))  stay:m
  =/  req=json  (fall (jget own 'request') [%o ~])
  ;<  conf=json  bind:m  (read:esp [%| 1 %& / %'config.json'])
  =/  url=(unit @t)  (ask-url conf req)
  ?~  url  (answer req %.n 0 'bad ask' ~)
  ;<  ~  bind:m  (send-request:io (ask-request req u.url))
  ;<  resp=client-response:iris  bind:m  take-http
  ?.  ?=(%finished -.resp)  (answer req %.n 0 'no answer' ~)
  =/  code=@ud  status-code.response-header.resp
  ?~  full-file.resp  (answer req (lth code 300) code '' ~)
  =/  raw=@t  q.data.u.full-file.resp
  ::  json when it parses, the raw text when it does not: a broadcast
  ::  answers with a bare txid, and an error with a sentence
  =/  body=json  (fall (de:json:html raw) s+raw)
  (answer req (lth code 300) code '' `body)
::  +ask-network: the chain a request names. Anything we do not know is
::  mainnet, which is the one a caller meant if it said nothing.
::
++  ask-network
  |=  net=@t
  ^-  network
  ?+  net  %main
    %main      %main
    %testnet3  %testnet3
    %testnet4  %testnet4
    %signet    %signet
    %regtest   %regtest
  ==
::  +ask-url: where to put a request, from the op it names and the
::  provider configured for its network. ~ for an op we do not answer, or
::  one missing the argument it needs.
::
::    The last four are what SPV needs: a header by its hash, the hash at
::    a height, the tip, and the merkle branch proving a txid sits in a
::    block. All standard Esplora, so they work against any of them.
::
++  ask-url
  |=  [conf=json req=json]
  ^-  (unit @t)
  =/  =network    (ask-network (jstr req 'network'))
  =/  address=@t  (jstr req 'address')
  =/  tx=@t       (jstr req 'tx')
  =/  hash=@t     (jstr req 'hash')
  =/  height=@t   (jstr req 'height')
  =/  txid=@t     (jstr req 'txid')
  ?+  (jstr req 'op')  ~
    %address    ?:(=('' address) ~ `(addr-url:esp conf network address))
    %utxo       ?:(=('' address) ~ `(utxo-url:esp conf network address))
    %txs        ?:(=('' address) ~ `(txs-url:esp conf network address))
    %price      `(price-url:esp conf)
    %broadcast  ?:(=('' tx) ~ `(tx-url:esp conf network))
    %header     ?:(=('' hash) ~ `(header-url:esp conf network hash))
    %block-at   ?:(=('' height) ~ `(height-url:esp conf network height))
    %tip        `(tip-url:esp conf network)
    %blocks     ?:(=('' height) ~ `(blocks-url:esp conf network height))
    %merkle     ?:(=('' txid) ~ `(merkle-url:esp conf network txid))
  ==
::  +ask-request: how to put it. A broadcast posts the raw transaction;
::  everything else is a get.
::
++  ask-request
  |=  [req=json url=@t]
  ^-  request:http
  ?.  =(%broadcast (jstr req 'op'))
    [%'GET' url ~[['Accept' 'application/json']] ~]
  [%'POST' url ~[['content-type' 'text/plain']] `(as-octs:mimes:html (jstr req 'tx'))]
::  +answer: the outcome, written beside the request that asked for it.
::  +stay:m, not a return: a fiber that finishes takes its grub with it
::  unless the grub was gained, and the asker may still be reading.
::
++  answer
  |=  [req=json ok=? code=@ud err=@t body=(unit json)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m  (append-activity (activity-entry req ok code err now))
  ;<  ~  bind:m  (replace:io (answer-json req ok code err body))
  stay:m
::  +answer-json: the outcome, with the request it answers kept in it.
::
++  answer-json
  |=  [req=json ok=? code=@ud err=@t body=(unit json)]
  ^-  json
  %-  pairs:enjs:format
  :~  ['status' s+'done']
      ['request' req]
      ['ok' b+ok]
      ['code' (numb:enjs:format code)]
      ['error' s+err]
      ['body' (fall body ~)]
  ==
::  +activity-entry: the same outcome, as one line of the log.
::
++  activity-entry
  |=  [req=json ok=? code=@ud err=@t now=@da]
  ^-  json
  %-  pairs:enjs:format
  :~  ['op' s+(jstr req 'op')]
      ['network' s+(jstr req 'network')]
      ['ok' b+ok]
      ['code' (numb:enjs:format code)]
      ['error' s+err]
      ['at' s+(scot %da now)]
  ==
::  +append-activity: one line per answered question, newest first,
::  capped at 200 the way the github nexus caps its own.
::
++  append-activity
  |=  entry=json
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  =road:tarball  [%| 1 %& / %'activity.json']
  ;<  cur=(unit json)  bind:m  (peek-as:io road ,json)
  =/  old=(list json)
    ?~  cur  ~
    ?.  ?=(%o -.u.cur)  ~
    =/  e  (~(get by p.u.cur) 'entries')
    ?.(?=([~ %a *] e) ~ p.u.e)
  =/  new=json
    (pairs:enjs:format ~[['entries' [%a (scag 200 `(list json)`[entry old])]]])
  (over:io road [[/ %json] new])
::  +take-http: the one http response this fiber asked for
::
++  take-http
  =/  m  (fiber:fiber:nexus ,client-response:iris)
  ^-  form:m
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
    ~  [%wait ~]
      [~ %poke * *]
    ?.  =([/ %http-response] p.sage.u.in)  [%skip ~]
    [%done !<(client-response:iris q.sage.u.in)]
  ==
::
::  json - reaching into a parsed object.
::
::  +jget: the value at a key, if the json is an object and holds one.
::
++  jget
  |=  [j=json k=@t]
  ^-  (unit json)
  ?.  ?=([%o *] j)  ~
  (~(get by p.j) k)
::  +jstr: the string at a key, '' for anything that is not one.
::
++  jstr
  |=  [j=json k=@t]
  ^-  @t
  =/  v=(unit json)  (jget j k)
  ?.(?=([~ %s *] v) '' p.u.v)
--