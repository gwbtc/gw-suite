::  mark for signs: flat map of acct-ref to signed transaction
::
/<  wt  /lib/wallet-types.hoon
=,  wt
=,  format
|_  dat=(map @t sign)
++  grab
  |%
  ++  noun  (map @t sign)
  ++  json
    |=  jon=^json
    ^-  (map @t sign)
    ?>  ?=([%o *] jon)
    %-  malt
    %+  turn  ~(tap by p.jon)
    |=  [k=@t v=^json]
    [k (sign-from-json v)]
  ++  mime
    |=  [p=mite q=octs]
    ^-  (map @t sign)
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
    |=  [k=@t v=sign]
    [k (sign-to-json v)]
  ++  mime  [/application/json (as-octs:mimes:html -:txt)]
  ++  txt   [(en:json:html json)]~
  --
++  sign-to-json
  |=  sig=sign
  ^-  json
  %-  pairs:enjs
  :~  ['hex' s+hex.sig]
      ['fee' (numb:enjs fee.sig)]
      ['version' (numb:enjs version.sig)]
      ['locktime' (numb:enjs locktime.sig)]
      ['sequence' (numb:enjs sequence.sig)]
  ==
++  sign-from-json
  |=  jon=json
  ^-  sign
  %.  jon
  %-  ot:dejs:format
  :~  hex+so:dejs:format
      fee+ni:dejs:format
      version+ni:dejs:format
      locktime+ni:dejs:format
      sequence+ni:dejs:format
  ==
--
