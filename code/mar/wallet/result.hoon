::  mark for an account's last build, sign or broadcast
::
::
/<  wt  /lib/wallet-types.hoon
=,  wt
=,  format
|_  res=result
++  grab
  |%
  ++  noun  result
  ++  json
    |=  jon=^json
    ^-  result
    ?>  ?=([%o *] jon)
    =/  m  p.jon
    =/  text
      |=  k=@t
      ^-  (unit @t)
      =/  v  (~(get by m) k)
      ?.  ?=([~ %s *] v)  ~
      `p.u.v
    :*  (slav %tas (so:dejs (need (~(get by m) 'action'))))
        (slav %da (so:dejs (need (~(get by m) 'at'))))
        (text 'error')
        (text 'txid')
    ==
  ++  mime
    |=  [p=mite q=octs]
    ^-  result
    (json (need (de:json:html (@t q.q))))
  --
++  grow
  |%
  ++  noun  res
  ++  json
    ^-  ^json
    %-  pairs:enjs
    :~  ['action' s+action.res]
        ['at' s+(scot %da at.res)]
        ['error' ?~(error.res ~ s+u.error.res)]
        ['txid' ?~(txid.res ~ s+u.txid.res)]
    ==
  ++  mime  [/application/json (as-octs:mimes:html -:txt)]
  ++  txt   [(en:json:html json)]~
  --
--
