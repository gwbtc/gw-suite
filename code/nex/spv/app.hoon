::  spv nexus: what this ship is willing to believe about the chain.
::
::  @esplora fetches. This decides. The split matters: esplora is the
::  stranger we ask, and nothing it says is checked there -- here a
::  header is parsed, hashed, tested against the target in its own
::  nBits, and refused unless it links to the one below it. A provider
::  cannot forge that without doing the work.
::
::  It holds NO network road. Everything it knows arrives by asking
::  @esplora the way any app does, which is the whole argument for the
::  ask protocol: a component can be the authority on what is true
::  without being allowed to talk to anyone.
::
::    config.json   {network, lookback} -- which chain, and how far
::                  back the checkpoint sits from the tip
::    chain.spv-chain
::                  the verified headers, per network
::    status.json   the same thing a reader can get at without the mark
::    sync.sig      the loop that follows the chain
::
::  What it cannot do: notice a transaction the provider never mentions.
::  SPV never could. It turns "believe everything" into "can only be
::  lied to by omission", which is the upgrade on offer.
::
/<  spv      /lib/bitcoin-spv.hoon
/<  bsv      /lib/sur/bitcoin-spv.hoon
/<  wt       /lib/wallet-types.hoon
/<  esp      /lib/wallet/esplora.hoon
/<  nw       /lib/nexus-web.hoon
/<  sh       /lib/shell.hoon
/<  nex-tools  /lib/tools.hoon
/&  bundle     /lib/spv-bundle/
/<  ui-html  ./index.html
/<  ui-js    ./app.js
/<  ui-css   ./style.css
/<  ui-icon  ./icon.svg
=,  bsv
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
            :~  (line '/sys/bowl.sig' 'the entropy each question to the chain service is tagged with')
                (line '/sys/behn/' 'pace the sync so a provider is not hammered')
                (line '/sys/eyre/' 'bind /grubbery/spv and serve the status page')
                (line '@esplora/main.sig' 'ask the chain service for blocks and headers')
            ==
            :-  'peek'
            :-  %a
            :~  (line '@esplora/ask/' 'read the answers to its own questions')
                (line '/sys/link/' 'find itself by name, @spv, from its tools')
            ==
            :-  'make'
            :-  %a
            :~  (line '@esplora/ask/' 'clear its own questions once read')
            ==
        ==
      %+  spin:loader  ball
      :~  (manifest:loader 0)
          [%over %& [/ %'link.json'] [[/ %json] link-json]]
          [%over %& [/ %'weir.json'] [[/ %json] weir-json]]
          [%over %& [/ %'icon.svg'] [[/ %mime] ui-icon]]
          [%over %& [/ %'index.html'] [[/ %mime] ui-html]]
          [%over %& [/ %'app.js'] [[/ %mime] ui-js]]
          [%over %& [/ %'style.css'] [[/ %mime] ui-css]]
          [%over %& [/ %'tile.json'] [[/ %json] tile-json]]
          ::  which chain to follow, and how far back to start. The
          ::  checkpoint is a claim this ship makes -- below it nothing
          ::  is verified -- so how deep it sits is a policy, not a
          ::  constant. 1008 blocks is about a week.
          ::  grant.json: the shell writes it on approval, and a reload
          ::  keeps only what is listed here -- so it is listed, or the
          ::  sync reads "not granted" after every reload for ever
          [%stay %& [/ %'grant.json']]
          [%fall %& [/ %'config.json'] [[/ %json] init-config]]
          [%fall %& [/ %'chain.spv_chain'] [[/spv %chain] *(map network spv-chain)]]
          [%fall %& [/ %'status.json'] [[/ %json] [%o ~]]]
          ::  the same lifecycle-grub protocol @esplora answers on, so an
          ::  asker uses one arm for both: keep ask/<id>.json, poke
          ::  main.sig, read on news, drop.
          [%over %& [/ %'main.sig'] [[/ %sig] ~]]
          [%fall %| /ask empty-dir:loader]
          [%over %& [/ %'sync.sig'] [[/ %sig] ~]]
          [%over %& [/ %'web.sig'] [[/ %sig] ~]]
          ::  its tools, reachable over mcp the way the wallet's are:
          ::  call_tool with path=/apps/<app>/tools
          [%over %| /tools (seed-tools:nex-tools bundle)]
          [%fall %| /requests empty-dir:loader]
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
        ;<  ~  bind:m  (rise-wait:io prod "%spv/main: failed")
        main-loop
          [[%ask ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%spv/ask: failed")
        (run-verify rail)
          [~ %'sync.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%spv/sync: failed")
        (sync-loop rail)
          [~ %'web.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%spv/web: failed")
        ;<  ~  bind:m  (bind-http-self:io [~ /grubbery/spv])
        http-dispatch:io
          [[%requests ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%spv/req: failed")
        (serve rail name.rail)
      ==
    --
|%
++  link-json
  ^-  json
  %-  pairs:enjs:format
  :~  ['name' s+'spv']
      ['description' s+'the chain, verified rather than believed']
  ==
++  init-config
  ^-  json
  %-  pairs:enjs:format
  :~  ['network' s+'main']
      ['lookback' (numb:enjs:format 1.008)]
  ==
++  tile-json
  ^-  json
  %-  pairs:enjs:format
  :~  title+s+'SPV'
      info+s+'headers, checked not trusted.'
      color+s+'#1d2b1f'
      href+s+'/grubbery/spv'
      kind+s+'utility'
  ==
::  +sync-loop: follow the chain, verifying every step.
::
::  Each pass: find where we are, ask @esplora for the next ten blocks,
::  rebuild and check each one, seat the ones that link. When there is
::  nothing left to fetch it sleeps and asks again. A batch that fails
::  to verify stops the sync and records why rather than skipping it --
::  a gap in a chain is not a chain.
::
++  sync-loop
  |=  =rail:tarball
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  our own grubs, addressed absolutely from our rail. A relative road
  ::  to our own file is vetoed once a peek list is declared, and the
  ::  list is worth keeping: it is what the permits page shows you.
  =/  conf-road=road:tarball   (nex-road:io rail [%& / %'config.json'])
  =/  chain-road=road:tarball  (nex-road:io rail [%& / %'chain.spv_chain'])
  =/  stat-road=road:tarball   (nex-road:io rail [%& / %'status.json'])
  =/  grant-road=road:tarball  (nex-road:io rail [%& / %'grant.json'])
  |-
  ;<  conf=json  bind:m  (read-json conf-road)
  =/  net=network  (net-of (jstr conf 'network'))
  =/  lookback=@ud  (fall (jnum conf 'lookback') 1.008)
  ;<  where=(unit path)  bind:m  (esplora-base grant-road)
  ?~  where
    ;<  ~  bind:m  (note stat-road net 'waiting for @esplora to be granted')
    ;<  ~  bind:m  (sleep:io ~m1)
    $
  ;<  tip=(unit @ud)  bind:m  (ask-tip u.where net)
  ?~  tip
    ;<  ~  bind:m  (note stat-road net 'cannot reach the chain service')
    ;<  ~  bind:m  (sleep:io ~m1)
    $
  ;<  chains=(map network spv-chain)  bind:m  (read-chain chain-road)
  =/  c=spv-chain  (fall (~(get by chains) net) *spv-chain)
  ::  first run on this network: plant the checkpoint `lookback` below
  ::  the tip. Nothing below it is ever verified, so this is the oldest
  ::  block this ship will vouch for.
  ?:  =(0 checkpoint-height.c)
    =/  start=@ud  ?:((gth u.tip lookback) (sub u.tip lookback) 0)
    ;<  seed=(unit @t)  bind:m  (ask-hash u.where net start)
    ?~  seed
      ;<  ~  bind:m  (note stat-road net 'cannot read the checkpoint block')
      ;<  ~  bind:m  (sleep:io ~m1)
      $
    =/  fresh=spv-chain
      c(checkpoint-height start, checkpoint-hash `@uvI`(rash u.seed hex))
    ;<  ~  bind:m  (write-chain chain-road (~(put by chains) net fresh))
    $
  ::  where we have reached: the highest header we hold, or the
  ::  checkpoint if we hold none
  =/  have=@ud  (highest c)
  ?:  (gte have u.tip)
    ;<  ~  bind:m  (mark-synced stat-road net have u.tip)
    ;<  ~  bind:m  (sleep:io ~m5)
    $
  =/  want=@ud  (min u.tip (add have 10))
  ;<  rows=(list json)  bind:m  (ask-blocks u.where net want)
  ?~  rows
    ;<  ~  bind:m  (note stat-road net 'the chain service returned no blocks')
    ;<  ~  bind:m  (sleep:io ~m1)
    $
  ::  ascending, and only what we do not already have
  =/  todo=(list json)  (ascending-above rows have)
  =/  res=(each spv-chain @t)  (seat-all c todo)
  ?:  ?=(%| -.res)
    ;<  ~  bind:m  (note stat-road net p.res)
    ;<  ~  bind:m  (sleep:io ~m5)
    $
  ;<  ~  bind:m  (write-chain chain-road (~(put by chains) net p.res))
  ;<  ~  bind:m  (mark-progress stat-road net (highest p.res) u.tip)
  ::  a pause between batches: this is someone else's server
  ;<  ~  bind:m  (sleep:io ~s1)
  $
::  +seat-all: verify and add a batch, in order. The first one that
::  does not check stops the batch and says why.
::
++  seat-all
  |=  [c=spv-chain rows=(list json)]
  ^-  (each spv-chain @t)
  ?~  rows  &+c
  =/  j=json  i.rows
  =/  height=@ud  (fall (jnum j 'height') 0)
  =/  hed=(unit block-header:spv)
    %:  header-from-fields:spv
      height
      (jstr j 'id')
      (fall (jnum j 'version') 0)
      (jstr j 'previousblockhash')
      (jstr j 'merkle_root')
      (fall (jnum j 'timestamp') 0)
      (fall (jnum j 'bits') 0)
      (fall (jnum j 'nonce') 0)
    ==
  ?~  hed
    |+(crip "block {(a-co:co height)}: fields do not hash to the id given for them")
  ::  proof of work, against the target the header itself declares
  =/  [checked=block-header:spv pow=? work=@ud]
    (validate-header-with-hash:spv u.hed `@ux`computed-hash.u.hed)
  ?.  pow
    |+(crip "block {(a-co:co height)}: proof of work does not meet its own target")
  ::  and it has to attach to what we already believe
  =/  [ok=? parent=(unit block-header:spv)]
    (validate-chain-connection:spv checked headers.c checkpoint-hash.c)
  ?.  ok
    |+(crip "block {(a-co:co height)}: does not link to the chain below it")
  =/  final=block-header:spv
    checked(cumulative-work (calculate-cumulative-work:spv parent work))
  $(c c(headers (add-header-to-chain:spv final parent headers.c)), rows t.rows)
::  +main-loop: open a question, the way @esplora does. The asker names
::  the id so it can keep the road before there is anything there.
::
++  main-loop
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |-
  ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
  ?.  =([/ %json] p.sage)
    ~&  >>>  [%spv-unrecognized-poke mark=p.sage from=from]
    $
  =/  jon=json  (fall (mole |.(!<(json q.sage))) *json)
  =/  id=@t  (jstr jon 'id')
  =/  req=(unit json)  (junit jon 'req')
  ?:  |(=('' id) ?=(~ req))
    ~&  >>>  "%spv: poke missing id or req"
    $
  =/  =road:tarball  (cord-to-road:tarball (crip "./ask/{(trip id)}.json"))
  =/  content=json
    (pairs:enjs:format ~[['status' s+'pending'] ['request' u.req]])
  ;<  ~  bind:m  (make:io road |+[[[/ %json] content] ~])
  ;<  ~  bind:m  (gain:io road %.y)
  $
::  +run-verify: is this transaction really in the chain?
::
::  Ask @esplora for the merkle branch, then check it against a header
::  WE verified -- not against anything the provider says about the
::  block. If the branch folds up to the merkle root of our own header
::  at that height, the transaction is in a block that cost real work to
::  make. If we do not hold a header at that height, we say so rather
::  than guessing: outside the verified span is not the same as false.
::
++  run-verify
  |=  =rail:tarball
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  own=json  bind:m  (get-state-as:io ,json)
  ?.  =('pending' (jstr own 'status'))  stay:m
  =/  req=json  (fall (junit own 'request') [%o ~])
  =/  txid=@t  (jstr req 'txid')
  ?:  =('' txid)  (answer req %.n 'no txid given' ~)
  ;<  conf=json  bind:m  (read-json (nex-road:io rail [%& / %'config.json']))
  =/  net=network  (net-of (jstr conf 'network'))
  ;<  where=(unit path)  bind:m
    (esplora-base (nex-road:io rail [%& / %'grant.json']))
  ?~  where  (answer req %.n 'no road to the chain service' ~)
  ;<  proof=json  bind:m  (ask-body u.where (merkle:question:esp net txid))
  ?.  ?=([%o *] proof)  (answer req %.n 'the chain service has no proof for it' ~)
  =/  height=@ud  (fall (jnum proof 'block_height') 0)
  =/  pos=@ud  (fall (jnum proof 'pos') 0)
  =/  branch=(list @t)
    =/  br=(unit json)  (junit proof 'merkle')
    ?.  ?=([~ %a *] br)  ~
    (murn p.u.br |=(j=json ?:(?=([%s *] j) `p.j ~)))
  ;<  chains=(map network spv-chain)  bind:m
    (read-chain (nex-road:io rail [%& / %'chain.spv_chain']))
  =/  c=spv-chain  (fall (~(get by chains) net) *spv-chain)
  =/  mine=(unit block-header)  (header-at c height)
  ?~  mine
    %:  answer
      req
      %.n
      (crip "block {(a-co:co height)} is outside the span this ship has verified")
      `height
    ==
  =/  root=@t  (to-cord:hxb:bcu:spv [32 `@ux`merkle-root.u.mine])
  =/  good=?  (verify-merkle-proof:spv txid branch pos root)
  ?.  good
    (answer req %.n 'the merkle branch does not fold to our header' `height)
  (answer req %.y 'in a block this ship verified' `height)
::  +header-at: our verified header at a height, if we hold one
::
++  header-at
  |=  [c=spv-chain height=@ud]
  ^-  (unit block-header)
  =/  hs  ~(tap by headers.c)
  |-  ^-  (unit block-header)
  ?~  hs  ~
  ?:  =(height height.q.i.hs)  `q.i.hs
  $(hs t.hs)
::  +answer: the verdict, written beside the question that asked for it
::
++  answer
  |=  [req=json ok=? why=@t height=(unit @ud)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  =/  out=json
    %-  pairs:enjs:format
    :~  ['status' s+'done']
        ['request' req]
        ['ok' b+%.y]
        ['verified' b+ok]
        ['why' s+why]
        ['height' ?~(height ~ (numb:enjs:format u.height))]
        ['at' s+(scot %da now)]
    ==
  ;<  ~  bind:m  (replace:io out)
  stay:m
::  +ascending-above: a block listing comes back newest first and
::  contiguous, so flipping it is the sort. Drops anything at or below
::  what we already hold, which is how a batch overlapping our tip is
::  absorbed without seating a header twice.
::
++  ascending-above
  |=  [rows=(list json) have=@ud]
  ^-  (list json)
  =/  asc=(list json)  (flop rows)
  |-  ^-  (list json)
  ?~  asc  ~
  ?:  (gth (fall (jnum i.asc 'height') 0) have)
    [i.asc $(asc t.asc)]
  $(asc t.asc)
::  +highest: the top of what we hold, or the checkpoint
::
++  highest
  |=  c=spv-chain
  ^-  @ud
  ::  folded by hand over the map: the wet gates (turn, roll) infer a
  ::  non-empty list here, and an empty chain is the normal first case
  =/  hs  ~(tap by headers.c)
  |-  ^-  @ud
  ?~  hs  checkpoint-height.c
  =/  rest=@ud  $(hs t.hs)
  =/  h=@ud  height.q.i.hs
  ?:((gth h rest) h rest)
::  Asking @esplora. Four shapes of question, one road out.
::
++  esplora-base
  |=  grant-road=road:tarball
  =/  m  (fiber:fiber:nexus ,(unit path))
  ^-  form:m
  (alias:esp grant-road 'esplora')
::
++  ask-body
  |=  [base=path q=json]
  =/  m  (fiber:fiber:nexus ,json)
  ^-  form:m
  ;<  ans=(each (map @t json) @tas)  bind:m  (ask:esp base q)
  ?:  ?=(%| -.ans)  (pure:m ~)
  ?.  =(`[%b %.y] (~(get by p.ans) 'ok'))  (pure:m ~)
  (pure:m (fall (~(get by p.ans) 'body') ~))
::
++  ask-tip
  |=  [base=path =network]
  =/  m  (fiber:fiber:nexus ,(unit @ud))
  ^-  form:m
  ;<  got=json  bind:m  (ask-body base (tip:question:esp network))
  ?.  ?=([%n *] got)  (pure:m ~)
  (pure:m (rush p.got dem))
::
++  ask-hash
  |=  [base=path =network height=@ud]
  =/  m  (fiber:fiber:nexus ,(unit @t))
  ^-  form:m
  ;<  got=json  bind:m
    (ask-body base (block-at:question:esp network (crip (a-co:co height))))
  ?.  ?=([%s *] got)  (pure:m ~)
  (pure:m `p.got)
::
++  ask-blocks
  |=  [base=path =network height=@ud]
  =/  m  (fiber:fiber:nexus ,(list json))
  ^-  form:m
  ;<  got=json  bind:m
    (ask-body base (blocks:question:esp network (crip (a-co:co height))))
  ?.  ?=([%a *] got)  (pure:m ~)
  (pure:m p.got)
::
::  Reading and writing our own grubs.
::
++  read-json
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,json)
  ^-  form:m
  ;<  got=(unit json)  bind:m  (peek-as:io road ,json)
  (pure:m (fall got [%o ~]))
::
++  read-chain
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,(map network spv-chain))
  ^-  form:m
  ;<  v=view:nexus  bind:m  (peek:io road ~)
  ?.  ?=([%file *] v)  (pure:m ~)
  ?:  (is-boom:tarball sang.v)  (pure:m ~)
  =/  res=(each (map network spv-chain) tang)
    (mule |.(!<((map network spv-chain) (need-vase:tarball sang.v))))
  (pure:m ?:(?=(%& -.res) p.res ~))
::
++  write-chain
  |=  [=road:tarball chains=(map network spv-chain)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (put:io road [[/spv %chain] chains])
::  +note, +mark-progress, +mark-synced: status.json, which is how a
::  reader learns where the sync is without holding the chain mark.
::
++  note
  |=  [=road:tarball =network why=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  %+  put:io  road
  :-  [/ %json]
  %-  pairs:enjs:format
  :~  ['network' s+(scot %tas network)]
      ['state' s+'stalled']
      ['why' s+why]
      ['at' s+(scot %da now)]
  ==
::
++  mark-progress
  |=  [=road:tarball =network have=@ud tip=@ud]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  %+  put:io  road
  :-  [/ %json]
  %-  pairs:enjs:format
  :~  ['network' s+(scot %tas network)]
      ['state' s+'syncing']
      ['height' (numb:enjs:format have)]
      ['tip' (numb:enjs:format tip)]
      ['behind' (numb:enjs:format ?:((gth tip have) (sub tip have) 0))]
      ['at' s+(scot %da now)]
  ==
::
++  mark-synced
  |=  [=road:tarball =network have=@ud tip=@ud]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  %+  put:io  road
  :-  [/ %json]
  %-  pairs:enjs:format
  :~  ['network' s+(scot %tas network)]
      ['state' s+'synced']
      ['height' (numb:enjs:format have)]
      ['tip' (numb:enjs:format tip)]
      ['behind' (numb:enjs:format 0)]
      ['at' s+(scot %da now)]
  ==
::
++  net-of
  |=  t=@t
  ^-  network
  ?+  t  %main
    %main  %main
    %testnet3  %testnet3
    %testnet4  %testnet4
    %signet  %signet
    %regtest  %regtest
  ==
::
::  jstr is nexus-web's, which answers a STRING or ''. A field that is
::  an object or an array needs the unit, and reaching for jget there
::  hands `fall` something that is not a unit at all.
::
++  jstr  jget:nw
++  junit
  |=  [j=json k=@t]
  ^-  (unit json)
  ?.  ?=([%o *] j)  ~
  (~(get by p.j) k)
++  jnum
  |=  [j=json k=@t]
  ^-  (unit @ud)
  ?.  ?=([%o *] j)  ~
  =/  v  (~(get by p.j) k)
  ?.  ?=([~ %n *] v)  ~
  (rush p.u.v dem)
::  +serve: the status page.
::
::  +serve: the status page.
::
::  A request fiber is sandboxed, so it reaches its own nexus through
::  here:sh -- the address the shell granted us -- rather than by
::  walking up from wherever this fiber sits. Same reason the sync loop
::  uses absolute roads: a relative road to our own file is vetoed once
::  a peek list is declared, and the list is worth keeping because it
::  is what the permits page shows you.
::
++  serve
  |=  [=rail:tarball eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  [src=@p req=inbound-request:eyre]  bind:m
    (get-state-as:io ,[src=@p inbound-request:eyre])
  ;<  our=@p  bind:m  get-our:io
  ?.  =(src our)
    (reply:web:nw eyre-id 403 'Forbidden')
  ;<  base=(unit @t)  bind:m  (here:sh rail)
  ?~  base
    (reply:web:nw eyre-id 503 'SPV awaiting sandbox approval')
  =/  root=path  (stab u.base)
  =/  prefix=path  /grubbery/spv
  =/  [site=path args=quay:eyre]  (parse-url:http-utils url.request.req)
  =/  suffix=path  (slag (lent prefix) site)
  ?+    suffix  (serve-file eyre-id root ?~(suffix 'index.html' i.suffix))
      [%api %status ~]
    ;<  conf=json  bind:m  (read-json [%& %& root %'config.json'])
    ;<  st=json  bind:m  (read-json [%& %& root %'status.json'])
    ;<  chains=(map network spv-chain)  bind:m
      (read-chain [%& %& root %'chain.spv_chain'])
    =/  net=network  (net-of (jstr conf 'network'))
    =/  c=spv-chain  (fall (~(get by chains) net) *spv-chain)
    %+  send-json:web:nw  eyre-id
    %-  pairs:enjs:format
    :~  ['config' conf]
        ['status' st]
        ['headers' (numb:enjs:format ~(wyt by headers.c))]
        ['checkpoint' (numb:enjs:format checkpoint-height.c)]
    ==
  ==
::  +serve-file: one of our own mime grubs, by absolute road
::
++  serve-file
  |=  [eyre-id=@ta root=path filename=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  v=view:nexus  bind:m  (peek:io [%& %& root filename] `[/ %mime])
  ?.  ?=([%file *] v)  (reply:web:nw eyre-id 404 'Not found')
  =/  =mime  !<(mime (need-vase:tarball sang.v))
  (send-simple:http-res:io eyre-id (mime-response:http-utils mime))
--
