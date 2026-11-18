::  mar/spv/chain: the verified header chain, one per network.
::
::  grow:json is a SUMMARY, not the data: a caught-up mainnet chain is
::  tens of thousands of headers and nobody wants that rendered. It
::  answers the questions you actually ask of a chain -- how far does it
::  reach, from what checkpoint, is it syncing, did it break -- and the
::  headers themselves stay a noun. There is no grab:json for the same
::  reason: you cannot rebuild a chain from its summary, and pretending
::  otherwise would let a hand-edited file masquerade as verified work.
::
/<  bsv  /lib/sur/bitcoin-spv.hoon
/<  wt   /lib/wallet-types.hoon
=,  bsv
=,  wt
|_  chains=(map network spv-chain)
++  grab
  |%
  ++  noun  (map network spv-chain)
  --
++  grow
  |%
  ++  noun  chains
  ++  json
    ^-  ^json
    :-  %o
    %-  ~(gas by *(map @t ^json))
    %+  turn  ~(tap by chains)
    |=  [net=network c=spv-chain]
    ^-  [@t ^json]
    ::  folded by hand: (roll heights min) starts its accumulator at 0,
    ::  so the minimum of any chain is 0 forever
    =/  span
      |-  ^-  [low=@ud high=@ud]
      =/  hs  ~(tap by headers.c)
      |-  ^-  [low=@ud high=@ud]
      ?~  hs  [checkpoint-height.c checkpoint-height.c]
      =/  rest  $(hs t.hs)
      =/  h=@ud  height.q.i.hs
      :-  ?:((lth h low.rest) h low.rest)
      ?:((gth h high.rest) h high.rest)
    :-  (scot %tas net)
    %-  pairs:enjs:format
    ::  what the chain IS. How the sync is GOING lives in status.json --
    ::  this mark describes the thing, not the process following it.
    :~  ['headers' (numb:enjs:format ~(wyt by headers.c))]
        ['checkpoint' (numb:enjs:format checkpoint-height.c)]
        ['lowest' (numb:enjs:format low.span)]
        ['highest' (numb:enjs:format high.span)]
        :-  'error'
        ?~(sync-error.c ~ s+(crip (of-wall:format (turn u.sync-error.c |=(t=tank (of-wall:format (wash [0 80] t)))))))
    ==
  ++  mime  [/application/json (as-octs:mimes:html -:txt)]
  ++  txt   [(en:json:html json)]~
  --
--
