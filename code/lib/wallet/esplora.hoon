::  lib/wallet/esplora: where the chain facts come from.
::
::  The wallet reads addresses, utxos and transactions from an Esplora
::  API and broadcasts there. mempool.space speaks Esplora; so does a
::  self-hosted esplora (which is what %regtest already points at), and
::  so will anything we put behind the same shape.
::
::  It lives in one place because it was written in three: a per-network
::  table in accountio, another in the nexus for address discovery, and a
::  third inline for broadcast. Three tables is three chances to point
::  half a wallet at the wrong chain.
::
::  This is also the seam the @esplora nexus plugs into. When the wallet
::  stops making its own requests, these arms are what change — one file
::  — and nothing that calls them has to know.
::
/<  wt  /lib/wallet-types.hoon
=,  wt
|%
::  +default-base: where a network is read from when nobody has said
::  otherwise. mempool.space is a default, not a decision.
::
++  default-base
  |=  =network
  ^-  tape
  ?-  network
    %main      "https://mempool.space/api"
    %testnet3  "https://mempool.space/testnet/api"
    %testnet4  "https://mempool.space/testnet4/api"
    %signet    "https://mempool.space/signet/api"
    %regtest   "http://localhost:3000"
  ==
::  +base: the api root for a network, no trailing slash. `conf` is
::  esplora.json as the wallet holds it — {"<network>": "<url>"} — so
::  pointing this ship at your own Esplora is an edit to a file, not to
::  this table. An entry that is not a string, or is not there, falls
::  back to the default for that network.
::
++  base
  |=  [conf=json =network]
  ^-  tape
  =/  said=(unit json)
    ?.  ?=([%o *] conf)  ~
    (~(get by p.conf) (scot %tas network))
  ?.  ?=([~ %s *] said)  (default-base network)
  ?:(=('' p.u.said) (default-base network) (trip p.u.said))
::  +addr-url, +utxo-url, +txs-url: what Esplora says about one address —
::  its totals, its unspent outputs, its transactions. Three endpoints off
::  the same stem, so the stem is written once.
::
++  addr-url  |=([conf=json =network address=@t] (addr-sub conf network address ""))
++  utxo-url  |=([conf=json =network address=@t] (addr-sub conf network address "/utxo"))
++  txs-url   |=([conf=json =network address=@t] (addr-sub conf network address "/txs"))
::
++  addr-sub
  |=  [conf=json =network address=@t sub=tape]
  ^-  @t
  (crip :(weld (base conf network) "/address/" (trip address) sub))
::  +price-base, +price-url: what a bitcoin is worth, asked of its OWN
::  provider under config.json's 'price' key.
::
::  A price is not chain data and /v1/prices is not Esplora -- it is
::  mempool.space's own extension, which a self-hosted Esplora will not
::  serve. Reading it off the mainnet chain provider made one config
::  value do two jobs: point `main` at your own node, which is the whole
::  reason that key exists, and the price silently stops with nothing
::  saying why. Configured apart, self-hosting the chain costs you
::  nothing here, and a provider that does not answer fails loudly as
::  itself.
::
::  Always asked of mainnet: the price of a testnet coin is the same
::  joke whichever chain you are looking at.
::
++  default-price-base  "https://mempool.space/api"
::
++  price-base
  |=  conf=json
  ^-  tape
  =/  said=(unit json)
    ?.  ?=([%o *] conf)  ~
    (~(get by p.conf) 'price')
  ?.  ?=([~ %s *] said)  default-price-base
  ?:(=('' p.u.said) default-price-base (trip p.u.said))
::
++  price-url
  |=  conf=json
  ^-  @t
  (crip (weld (price-base conf) "/v1/prices"))
::  +header-url, +height-url, +tip-url, +merkle-url: what SPV reads.
::
::    header   the 80-byte header of a block, as hex
::    height   the hash of the block at a height
::    tip      the height of the chain tip
::    merkle   the branch proving a txid is in its block
::
::  All four are standard Esplora, unlike the price: any implementation
::  serves them, so verification keeps working against your own node.
::
++  header-url
  |=  [conf=json =network hash=@t]
  ^-  @t
  (crip :(weld (base conf network) "/block/" (trip hash) "/header"))
::
++  height-url
  |=  [conf=json =network height=@t]
  ^-  @t
  (crip :(weld (base conf network) "/block-height/" (trip height)))
::
++  tip-url
  |=  [conf=json =network]
  ^-  @t
  (crip (weld (base conf network) "/blocks/tip/height"))
::
++  merkle-url
  |=  [conf=json =network txid=@t]
  ^-  @t
  (crip :(weld (base conf network) "/tx/" (trip txid) "/merkle-proof"))
::  +tx-url: where a signed transaction is POSTed
::
++  tx-url
  |=  [conf=json =network]
  ^-  @t
  (crip (weld (base conf network) "/tx"))
::  +read: esplora.json from the nexus root, for a fiber that has a rail.
::  Absent or unreadable reads as "no opinion", which is the defaults.
::
++  read
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,json)
  ^-  form:m
  ;<  =view:nexus  bind:m  (peek:io road ~)
  ?.  ?=([%file *] view)  (pure:m [%o ~])
  ?:  (is-boom:tarball sang.view)  (pure:m [%o ~])
  =/  res=(each json tang)  (mule |.(!<(json (need-vase:tarball sang.view))))
  ?.  ?=(%& -.res)  (pure:m [%o ~])
  (pure:m ?.(?=([%o *] p.res) [%o ~] p.res))
::  Asking @esplora is three steps, and they are separate because not
::  every asker can afford to sit still for the middle one: a scan has
::  to stay pausable while the chain service thinks.
::
::    +open     keep a road, poke the question onto it -> that road
::    +answered has the answer landed yet? -> ~ for "not yet"
::    +shut     drop the road and cull the grub
::
::  +ask is those three for an asker with nothing else to do.
::
::  The ORDER inside +open is the thing to preserve. The asker picks the
::  id and keeps the road BEFORE the grub exists, then pokes main.sig to
::  create it. A keep taken out after the grub is already there can miss
::  the news it exists to wait for, and the asker parks for ever.
::
::  This is the lifecycle-grub flow the github, anthropic and openrouter
::  proxies use. It is also why an asker needs no write access inside
::  @esplora's tree: it pokes main.sig and reads ask/.
::
::  A failure names the step that failed, because every step here fails
::  for its own reason and they want different fixes:
::
::    %ask    the question could not be opened — we are not granted
::            @esplora, or there is no @esplora there
::    %gone   the grub stopped being a file before it was answered
::    %junk   it is a file, but not a json object
::    %slow   it was taken and not answered in time
::
::  ok:false is an answer, not a failure: the nexus was reached and the
::  provider said no, and what it said is not ours to interpret.
::
++  ask
  |=  [base=path body=json]
  =/  m  (fiber:fiber:nexus ,(each (map @t json) @tas))
  ^-  form:m
  ;<  res=(each road:tarball @tas)  bind:m  (open base body)
  ?:  ?=(%| -.res)  (pure:m |+p.res)
  ;<  ans=(each (map @t json) @tas)  bind:m  (collect p.res)
  ;<  ~  bind:m  (shut p.res)
  (pure:m ans)
::  +open: keep the road, then ask for the grub on it.
::
++  open
  |=  [base=path body=json]
  =/  m  (fiber:fiber:nexus ,(each road:tarball @tas))
  ^-  form:m
  ;<  eny=@uvJ  bind:m  get-entropy:io
  =/  id=@ta  (scot %uv (end [5 3] eny))
  =/  =road:tarball  [%& %& (weld base /ask) (cat 3 id '.json')]
  ::  keep FIRST: everything the grub does from here on is news to us,
  ::  its creation included
  ;<  *  bind:m  (keep:io /esplora-ask road ~)
  =/  poke-road=road:tarball  [%& %& base %'main.sig']
  ;<  err=(unit tang)  bind:m
    %+  poke-soft:io  poke-road
    :-  [/ %json]
    (pairs:enjs:format ~[['id' s+id] ['req' body]])
  ?^  err  (pure:m |+%ask)
  (pure:m &+road)
::  +shut: stop following, and clear the record. @esplora keeps nothing
::  after this: the grub is the whole of it.
::
++  shut
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m  (drop:io /esplora-ask road)
  ;<  *  bind:m  (cull-soft:io road)
  (pure:m ~)
::  +answered: what the grub holds now. ~ means not yet — a pending grub
::  is the question, still being worked.
::
++  answered
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,(unit (each (map @t json) @tas)))
  ^-  form:m
  ;<  =view:nexus  bind:m  (peek:io road ~)
  ?.  ?=([%file *] view)  (pure:m `|+%gone)
  ?:  (is-boom:tarball sang.view)  (pure:m `|+%junk)
  =/  res=(each json tang)  (mule |.(!<(json (need-vase:tarball sang.view))))
  ?.  ?=(%& -.res)  (pure:m `|+%junk)
  ?.  ?=([%o *] p.res)  (pure:m `|+%junk)
  =/  jon=json  p.res
  ?.  ?=([~ %s %done] (~(get by p.p.res) 'status'))  (pure:m ~)
  (pure:m `&+p.p.res)
::  +collect: wait for the answer.
::
::  News is what wakes us and a peek is what reads it, since a wave
::  carries revisions and not content. The timer is not impatience: an
::  input has to be able to arrive even when no news does, or a fiber
::  that was offered its news during a peek has nothing left to wake it.
::  Running out of +patience is %slow.
::
++  collect
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,(each (map @t json) @tas))
  ^-  form:m
  =/  left=@ud  (div patience interval)
  |-
  ;<  ans=(unit (each (map @t json) @tas))  bind:m  (answered road)
  ?^  ans  (pure:m u.ans)
  ?:  =(0 left)  (pure:m |+%slow)
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m  (set-timer:io /esplora-tick (add now interval))
  ;<  *  bind:m  (take-news-or-wake-on:io /esplora-ask /esplora-tick)
  ;<  ~  bind:m  (cancel-timer:io /esplora-tick)
  $(left (dec left))
::  +interval, +patience: how often an input is guaranteed, and how long
::  to keep waiting. @esplora answers in a few seconds when the provider
::  is well.
::
++  interval  ~s2
++  patience  ~m2
::  +question: the body of an ask, built once so every caller spells the
::  ops the same way @esplora reads them.
::
++  question
  |%
  ++  address    |=([=network addr=@t] (ask-body 'address' network ~[['address' s+addr]]))
  ++  utxo       |=([=network addr=@t] (ask-body 'utxo' network ~[['address' s+addr]]))
  ++  txs        |=([=network addr=@t] (ask-body 'txs' network ~[['address' s+addr]]))
  ++  price      |=(~ (ask-body 'price' %main ~))
  ++  broadcast  |=([=network tx=@t] (ask-body 'broadcast' network ~[['tx' s+tx]]))
  ++  header     |=([=network hash=@t] (ask-body 'header' network ~[['hash' s+hash]]))
  ++  block-at   |=([=network h=@t] (ask-body 'block-at' network ~[['height' s+h]]))
  ++  tip        |=(=network (ask-body 'tip' network ~))
  ++  merkle     |=([=network txid=@t] (ask-body 'merkle' network ~[['txid' s+txid]]))
  --
::
++  ask-body
  |=  [op=@t =network rest=(list [@t json])]
  ^-  json
  %-  pairs:enjs:format
  :*  ['op' s+op]
      ['network' s+(scot %tas network)]
      rest
  ==
::  +alias: where a name the shell granted us actually lives, from our
::  own grant.json. Never a guess at the path: the shell decides where
::  an app sits, and says so here.
::
++  alias
  |=  [=road:tarball nom=@t]
  =/  m  (fiber:fiber:nexus ,(unit path))
  ^-  form:m
  ;<  =view:nexus  bind:m  (peek:io road ~)
  ?.  ?=([%file *] view)  (pure:m ~)
  =/  res=(each json tang)  (mule |.(!<(json (need-vase:tarball sang.view))))
  ?.  ?=(%& -.res)  (pure:m ~)
  ?.  ?=([%o *] p.res)  (pure:m ~)
  =/  al  (~(get by p.p.res) 'aliases')
  ?.  ?=([~ %o *] al)  (pure:m ~)
  ::  WITH the sigil: the shell writes grant aliases as "@esplora", and a
  ::  lookup of the bare name silently finds nothing (which is exactly
  ::  what +contacts-alias-path in the wallet does, and why it always
  ::  falls through to deps.json)
  =/  v  (~(get by p.u.al) (cat 3 '@' nom))
  ?.  ?=([~ %s *] v)  (pure:m ~)
  (pure:m (rush p.u.v stap))
::  +init: the config a wallet starts with — empty, meaning "the
::  defaults". Written as a row, so it is there to edit.
::
++  init  ^-(json [%o ~])
--
