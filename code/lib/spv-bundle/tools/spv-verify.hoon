/<  tools  /lib/tools.hoon
/<  sr     /lib/spv/road.hoon
::  spv-verify: is this transaction really in the chain?
::
^-  tool:tools
|%
++  name  'spv_verify'
++  description
  ^~  %-  crip
  ;:  weld
    "Check a transaction against a block header this ship verified itself. "
    "Answers yes only if the merkle branch folds up to the merkle root of "
    "a header whose proof of work was checked here -- a provider cannot "
    "fake that without mining. A transaction older than the checkpoint "
    "answers 'outside the verified span', which is not the same as false: "
    "it means this ship cannot vouch either way."
  ==
++  parameters
  ^-  (map @t parameter-def:tools)
  (malt ~[['txid' [%string 'Transaction id (hex)']]])
++  required  ~['txid']
++  handler
  ^-  tool-handler:tools
  =/  m  (fiber:fiber:nexus ,tool-result:tools)
  ^-  form:m
  ;<  st=tool-state:tools  bind:m  (get-state-as:io ,tool-state:tools)
  ?.  (~(has jo:json-utils [%o args.st]) /txid)
    (pure:m [%error 'Missing required parameter: txid'])
  =/  txid=@t  (~(dog jo:json-utils [%o args.st]) /txid so:dejs:format)
  ::  keep the answer's road BEFORE asking for it, then poke: a keep
  ::  taken out afterwards can miss the news it exists to wait for
  ;<  eny=@uvJ  bind:m  get-entropy:io
  =/  id=@ta  (scot %uv (end [5 3] eny))
  ;<  ask-road=road:tarball  bind:m  (spv-road:sr [%& /ask (cat 3 id '.json')])
  ;<  *  bind:m  (keep:io /spv-verify ask-road ~)
  ;<  main-road=road:tarball  bind:m  (spv-road:sr [%& / %'main.sig'])
  =/  q=json
    %-  pairs:enjs:format
    :~  ['id' s+id]
        :-  'req'
        (pairs:enjs:format ~[['op' s+'verify'] ['txid' s+txid]])
    ==
  ;<  err=(unit tang)  bind:m  (poke-soft:io main-road [/ %json] q)
  ?^  err  (pure:m [%error 'spv would not take the question'])
  ::  look, then wait, until it carries a verdict
  =/  left=@ud  60
  |-
  ;<  got=(unit json)  bind:m  (peek-as:io ask-road ,json)
  =/  done=?
    ?~  got  %.n
    ?.  ?=([%o *] u.got)  %.n
    =(`[%s %done] (~(get by p.u.got) 'status'))
  ?.  done
    ?:  =(0 left)
      ;<  ~  bind:m  (drop:io /spv-verify ask-road)
      (pure:m [%error 'spv did not answer in time'])
    ;<  ~  bind:m  (sleep:io ~s1)
    $(left (dec left))
  ;<  ~  bind:m  (drop:io /spv-verify ask-road)
  ;<  *  bind:m  (cull-soft:io ask-road)
  =/  ans=json  (fall got [%o ~])
  =/  fld
    |=  k=@t  ^-  tape
    ?.  ?=([%o *] ans)  "?"
    =/  v  (~(get by p.ans) k)
    ?+  v  "?"
      [~ %s *]  (trip p.u.v)
      [~ %n *]  (trip p.u.v)
      [~ %b *]  ?:(p.u.v "yes" "no")
    ==
  %-  pure:m
  :-  %text
  %-  crip
  ;:  weld
    "txid     {(trip txid)}\0a"
    "verified {(fld 'verified')}\0a"
    "height   {(fld 'height')}\0a"
    "why      {(fld 'why')}"
  ==
--
