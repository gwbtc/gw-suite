::  mark for results: flat map of acct-ref to that account's last build,
::  sign or broadcast
::
/<  wt  /lib/wallet-types.hoon
=,  wt
=,  format
|_  dat=(map @t result)
++  grab
  |%
  ++  noun  (map @t result)
  ++  json
    |=  jon=^json
    ^-  (map @t result)
    ?>  ?=([%o *] jon)
    %-  malt
    %+  turn  ~(tap by p.jon)
    |=  [k=@t v=^json]
    [k (result-from-json v)]
  ++  mime
    |=  [p=mite q=octs]
    ^-  (map @t result)
    (json (need (de:json:html (@t q.q))))
  --
++  grow
  |%
  ++  noun  dat
  ++  json
    ^-  ^json
    :-  %o
    %-  malt
    %+  turn  ~(tap by dat)
    |=  [k=@t v=result]
    [k (result-to-json v)]
  ++  mime  [/application/json (as-octs:mimes:html -:txt)]
  ++  txt   [(en:json:html json)]~
  --
::
++  result-to-json
  |=  res=result
  ^-  json
  %-  pairs:enjs
  :~  ['action' s+action.res]
      ['at' s+(scot %da at.res)]
      ['error' ?~(error.res ~ s+u.error.res)]
      ['txid' ?~(txid.res ~ s+u.txid.res)]
  ==
++  result-from-json
  |=  jon=json
  ^-  result
  ?>  ?=([%o *] jon)
  =/  m  p.jon
  =/  text
    |=  k=@t
    ^-  (unit @t)
    =/  v  (~(get by m) k)
    ?.  ?=([~ %s *] v)  ~
    `p.u.v
  :*  (slav %tas (so:dejs:format (need (~(get by m) 'action'))))
      (slav %da (so:dejs:format (need (~(get by m) 'at'))))
      (text 'error')
      (text 'txid')
  ==
--
