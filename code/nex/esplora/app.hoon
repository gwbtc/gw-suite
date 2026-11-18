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
/<  wt       /lib/wallet-types.hoon
/<  esp      /lib/wallet/esplora.hoon
/<  ui-html  ./index.html
/<  ui-js    ./app.js
/<  ui-css   ./style.css
/<  ui-icon  ./icon.svg
/<  nw       /lib/nexus-web.hoon
=,  wt
=<  ^-  nexus:nexus
    |%
    ++  on-load
      |=  =ball:tarball
      ^-  bole:tarball
      =/  weir-json=json
        =/  line
          |=([r=@t w=@t] `json`(pairs:enjs:format ~[['road' s+r] ['why' s+w]]))
        %-  pairs:enjs:format
        :~  :-  'poke'
            :-  %a
            :~  (line '/sys/bowl.sig' 'the entropy every outbound request is tagged with')
                (line '/sys/iris/' 'read the chain from an esplora api, and broadcast there')
                (line '/sys/eyre/' 'bind /grubbery/esplora and serve the status page')
            ==
            :-  'peek'  a+~
        ==
      %+  spin:loader  ball
      :~  (manifest:loader 0)
          [%over %& [/ %'link.json'] [[/ %json] link-json]]
          [%over %& [/ %'icon.svg'] [[/ %mime] ui-icon]]
          [%over %& [/ %'index.html'] [[/ %mime] ui-html]]
          [%over %& [/ %'app.js'] [[/ %mime] ui-js]]
          [%over %& [/ %'style.css'] [[/ %mime] ui-css]]
          [%over %& [/ %'tile.json'] [[/ %json] tile-json]]
          [%over %& [/ %'weir.json'] [[/ %json] weir-json]]
          ::  what we asked and what came back, newest first, capped.
          ::  A proxy that forgets is a proxy you cannot debug: when a
          ::  provider starts rate-limiting mid-scan the wallet quietly
          ::  keeps its old data, and without this nothing anywhere says
          ::  why. Summaries only — the asker already got the body, and
          ::  a txs response for a busy address is not worth keeping.
          [%fall %& [/ %'activity.json'] [[/ %json] (pairs:enjs:format ~[['entries' [%a ~]]])]]
          ::  who to ask, per network. Empty means the defaults in
          ::  lib/wallet/esplora — mempool.space.
          [%fall %& [/ %'config.json'] [[/ %json] init:esp]]
          ::  main.sig: takes the pokes that open a question
          [%over %& [/ %'main.sig'] [[/ %sig] ~]]
          ::  every question anyone has asked and not yet collected
          [%fall %| /ask empty-dir:loader]
          ::  %over, like every fiber-only grub: recreated by each load,
          ::  so a code change respins it
          [%over %& [/ %'web.sig'] [[/ %sig] ~]]
          [%fall %| /requests empty-dir:loader]
          [%stay %& [/ %'grant.json']]
      ==
    ::
    ++  on-file
      |=  [=rail:tarball =blot:tarball]
      ^-  spool:fiber:nexus
      |=  =prod:fiber:nexus
      =/  m  (fiber:fiber:nexus ,~)
      ^-  process:fiber:nexus
      ?+    rail  stay:m
          [~ %'main.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%esplora/main: failed")
        main-loop
          ::  one question, one fiber, the answer written beside it
          [[%ask ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%esplora/ask: failed")
        run-ask
          ::  web.sig: the status page — static files plus one json
          ::  endpoint, the way every other utility nexus serves itself
          [~ %'web.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%esplora/web: failed")
        ;<  ~  bind:m  (bind-http-self:io [~ /grubbery/esplora])
        http-dispatch:io
          [[%requests ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%esplora/req: failed")
        (serve rail name.rail)
      ==
    --
|%
++  link-json
  ^-  json
  %-  pairs:enjs:format
  :~  ['name' s+'esplora']
      ['description' s+'the bitcoin chain, read from an esplora api']
  ==
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
::  +read-open: every question under ask/ as the page shows it. A grub
::  that still holds the question is waiting; one holding an answer has
::  been answered and not yet collected.
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
  =/  jon=json  (fall one [%o ~])
  =/  req=json  (fall (jget jon 'request') [%o ~])
  =/  state=@t
    ?.  =('done' (jstr jon 'status'))  'waiting'
    ?:(=(`[%b %.y] (jget jon 'ok')) 'answered' 'failed')
  =/  row=json
    %-  pairs:enjs:format
    :~  ['name' s+i.names]
        ['op' s+(jstr req 'op')]
        ['network' s+(jstr req 'network')]
        ['state' s+state]
    ==
  $(names t.names, out [row out])
::
++  reply          reply:web:nw
++  send-json      send-json:web:nw
++  serve-static   serve-static:web:nw
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
  =/  jon=json  (fall (mole |.(!<(json q.sage))) *json)
  =/  id=@t  (jstr jon 'id')
  =/  req=(unit json)  (jget jon 'req')
  ?:  |(=('' id) ?=(~ req))
    ~&  >>>  "%esplora: poke missing id or req"
    $
  =/  =road:tarball  (cord-to-road:tarball (crip "./ask/{(trip id)}.json"))
  =/  content=json
    (pairs:enjs:format ~[['status' s+'pending'] ['request' u.req]])
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
  =/  op=@t       (jstr req 'op')
  =/  net=@t      (jstr req 'network')
  =/  address=@t  (jstr req 'address')
  =/  tx=@t       (jstr req 'tx')
  =/  =network
    ?+  net  %main
      %main  %main
      %testnet3  %testnet3
      %testnet4  %testnet4
      %signet  %signet
      %regtest  %regtest
    ==
  ;<  conf=json  bind:m  (read:esp [%| 1 %& / %'config.json'])
  ::  what SPV needs: a header by its hash, the hash at a height, the
  ::  tip, and the merkle branch proving a txid sits in a block. All
  ::  standard Esplora, so they work against any implementation.
  =/  hash=@t    (jstr req 'hash')
  =/  height=@t  (jstr req 'height')
  =/  txid=@t    (jstr req 'txid')
  =/  url=(unit @t)
    ?+  op  ~
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
  ?~  url  (answer req %.n 0 'bad ask' ~)
  =/  =request:http
    ?.  =(%broadcast op)
      [%'GET' u.url ~[['Accept' 'application/json']] ~]
    [%'POST' u.url ~[['content-type' 'text/plain']] `(as-octs:mimes:html tx)]
  ;<  ~  bind:m  (send-request:io request)
  ;<  resp=client-response:iris  bind:m  take-http
  ?.  ?=(%finished -.resp)  (answer req %.n 0 'no answer' ~)
  =/  code=@ud  status-code.response-header.resp
  ?~  full-file.resp  (answer req (lth code 300) code '' ~)
  =/  raw=@t  q.data.u.full-file.resp
  ::  json when it parses, the raw text when it does not: a broadcast
  ::  answers with a bare txid, and an error with a sentence
  =/  body=json  (fall (de:json:html raw) s+raw)
  (answer req (lth code 300) code '' `body)
::  +answer: the outcome, written beside the request that asked for it.
::  +stay:m, not a return: a fiber that finishes takes its grub with it
::  unless the grub was gained, and the asker may still be reading.
::
++  answer
  |=  [req=json ok=? code=@ud err=@t body=(unit json)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  out=json
    %-  pairs:enjs:format
    :~  ['status' s+'done']
        ['request' req]
        ['ok' b+ok]
        ['code' (numb:enjs:format code)]
        ['error' s+err]
        ['body' (fall body ~)]
    ==
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m
    %-  append-activity
    %-  pairs:enjs:format
    :~  ['op' s+(jstr req 'op')]
        ['network' s+(jstr req 'network')]
        ['ok' b+ok]
        ['code' (numb:enjs:format code)]
        ['error' s+err]
        ['at' s+(scot %da now)]
    ==
  ;<  ~  bind:m  (replace:io out)
  stay:m
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
++  jget
  |=  [j=json k=@t]
  ^-  (unit json)
  ?.  ?=([%o *] j)  ~
  (~(get by p.j) k)
++  jstr
  |=  [j=json k=@t]
  ^-  @t
  =/  v=(unit json)  (jget j k)
  ?.(?=([~ %s *] v) '' p.u.v)
--
