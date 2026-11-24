::  mark for a signed transaction
::
/<  wt  /lib/wallet-types.hoon
=,  wt
=,  format
|_  sig=sign
++  grab
  |%
  ++  noun  sign
  ++  json
    |=  jon=^json
    ^-  sign
    %.  jon
    %-  ot:dejs
    :~  hex+so:dejs
        fee+ni:dejs
        version+ni:dejs
        locktime+ni:dejs
        sequence+ni:dejs
    ==
  ++  mime
    |=  [p=mite q=octs]
    ^-  sign
    (json (need (de:json:html (@t q.q))))
  --
++  grow
  |%
  ++  noun  sig
  ++  json
    ^-  ^json
    %-  pairs:enjs
    :~  ['hex' s+hex.sig]
        ['fee' (numb:enjs fee.sig)]
        ['version' (numb:enjs version.sig)]
        ['locktime' (numb:enjs locktime.sig)]
        ['sequence' (numb:enjs sequence.sig)]
    ==
  ++  mime  [/application/json (as-octs:mimes:html -:txt)]
  ++  txt   [(en:json:html json)]~
  --
--
