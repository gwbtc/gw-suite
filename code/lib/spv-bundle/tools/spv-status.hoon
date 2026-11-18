/<  tools  /lib/tools.hoon
/<  sr     /lib/spv/road.hoon
::  spv-status: how far this ship has verified the chain for itself
::
^-  tool:tools
|%
++  name  'spv_status'
++  description
  ^~  %-  crip
  ;:  weld
    "What this ship has verified of the bitcoin chain for itself. "
    "Shows the checkpoint (the oldest block it will vouch for), how far "
    "it has verified, the chain tip, and how many headers it holds. "
    "Headers here were parsed, hashed and proof-of-work checked locally "
    "-- not taken on a provider's word."
  ==
++  parameters  ^-((map @t parameter-def:tools) ~)
++  required  ~
++  handler
  ^-  tool-handler:tools
  =/  m  (fiber:fiber:nexus ,tool-result:tools)
  ^-  form:m
  ;<  stat-road=road:tarball  bind:m  (spv-road:sr [%& / %'status.json'])
  ;<  st=(unit json)  bind:m  (peek-as:io stat-road ,json)
  ::  the chain grub is read through its mark's json, which is a
  ::  summary -- the headers themselves are a noun and nobody wants
  ::  them rendered
  ;<  chain-road=road:tarball  bind:m  (spv-road:sr [%& / %'chain.spv_chain'])
  ;<  cv=view:nexus  bind:m  (peek:io chain-road `[/ %json])
  =/  ch=(unit json)
    ?.  ?=([%file *] cv)  ~
    (mole |.(!<(json (need-vase:tarball sang.cv))))
  =/  jstr
    |=  [j=json k=@t]  ^-  tape
    ?.  ?=([%o *] j)  "?"
    =/  v  (~(get by p.j) k)
    ?+  v  "?"
      [~ %s *]  (trip p.u.v)
      [~ %n *]  (trip p.u.v)
    ==
  ?~  st  (pure:m [%error 'spv has written no status yet'])
  =/  net=tape  (jstr u.st 'network')
  ::  the chain summary is keyed by network, so the fields live one
  ::  level in -- not at the top of the object
  =/  per=(unit json)
    ?~  ch  ~
    ?.  ?=([%o *] u.ch)  ~
    (~(get by p.u.ch) (crip net))
  =/  heads=tape
    ?~  per  "?"
    "{(jstr u.per 'headers')} headers, {(jstr u.per 'lowest')}-{(jstr u.per 'highest')}"
  =/  checkpoint=tape  ?~(per "?" (jstr u.per 'checkpoint'))
  %-  pure:m
  :-  %text
  %-  crip
  ;:  weld
    "network     {net}\0a"
    "state       {(jstr u.st 'state')}\0a"
    "checkpoint  {checkpoint}\0a"
    "verified to {(jstr u.st 'height')}\0a"
    "chain tip   {(jstr u.st 'tip')}\0a"
    "behind      {(jstr u.st 'behind')}\0a"
    "held        {heads}\0a"
    "as of       {(jstr u.st 'at')}"
  ==
--
