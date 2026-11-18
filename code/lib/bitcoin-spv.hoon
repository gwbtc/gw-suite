::  Bitcoin SPV (Simplified Payment Verification) Library
::
::  ENDIANNESS HANDLING:
::  Bitcoin uses mixed endianness conventions:
::  - Block headers are parsed as big-endian (MSB first)
::  - Hash fields within headers (prev-hash, merkle-root) are little-endian
::  - Block hashes (double-SHA256 output) are displayed in little-endian
::
::  This library:
::  1. Parses header hex with flipped byte list to create big-endian atom
::  2. Extracts fields using adjusted cut positions (due to flipped bytes)
::  3. Flips hash fields after extraction to convert to big-endian representation
::  4. Flips final block hash to little-endian for display/comparison
::
::  Ported from gwbtc/spv-wallet. Pure verification: nothing here
::  fetches, stores or decides policy -- give it bytes, it tells you
::  whether they are real. That is why it is the first thing ported and
::  the first thing tested.
::
/<  bsv  /lib/sur/bitcoin-spv.hoon
/<  bit  /lib/sur/bitcoin.hoon
/<  bcu  /lib/bitcoin-utils.hoon
/<  wt   /lib/wallet-types.hoon
=,  bsv
=,  bit
::  wallet-types LAST, so its `network` shadows sur/bitcoin's. The two
::  disagree -- sur/bitcoin knows %testnet, the wallet knows %testnet3,
::  %testnet4 and %signet -- and everything else in this desk, @esplora
::  included, speaks the wallet's. Verification has to name the same
::  chains the rest of the wallet does or it cannot check them.
::
=,  wt
|%
:: types
::
+$  merkle-proof
  $:  txid=@t
      siblings=(list @t)
      position=@
      block-height=@
  ==
:: crypto
::
::  +bitcoin-hash: Double-SHA256 for Bitcoin merkle trees
::
::  Concatenates two 32-byte hashes (in INTERNAL byte order) and applies double-SHA256.
::  IMPORTANT: Input hashes must be in internal byte order (actual SHA256 output).
::  APIs return hashes in display format (little-endian) which must be flipped before hashing.
::
++  bitcoin-hash
  |=  [left=@ux right=@ux]
  ^-  @ux
  ::  Concatenate left || right as byte strings
  ::  Since can builds LSB-first, we put right then left to get left||right in the result
  =/  concatenated=hexb  [64 (can 3 ~[[32 right] [32 left]])]
  ::  Apply double-SHA256
  =/  hash-result=hexb  (dsha256:bcu concatenated)
  dat.hash-result
::
++  bitcoin-hash-hex
  |=  [left=@t right=@t]
  ^-  @ux
  =/  left-hex=@ux   (rash left hex)
  =/  right-hex=@ux  (rash right hex)
  (bitcoin-hash left-hex right-hex)
::
::  +hash-to-hex: Convert a 32-byte hash to a 64-character hex string with leading zeros
::
++  hash-to-hex
  |=  hash=@ux
  ^-  @t
  =/  hex-chars=tape  "0123456789abcdef"
  =/  result=tape
    =|  acc=tape
    =/  remaining=@ux  hash
    |-  ^-  tape
    ?:  =(64 (lent acc))  acc
    =/  byte=@ud  (mod remaining 256)
    =/  high=@ud  (div byte 16)
    =/  low=@ud   (mod byte 16)
    =/  high-char=@tD  (snag high hex-chars)
    =/  low-char=@tD   (snag low hex-chars)
    $(acc (weld (trip (cat 3 high-char low-char)) acc), remaining (div remaining 256))
  (crip result)
:: verification
::
++  verify-merkle-proof
  |=  [txid=@t siblings=(list @t) pos=@ expected-root=@t]
  ^-  ?
  ::  Convert from display format (little-endian) to internal byte order for hashing
  =/  current=@ux  dat:(flip:byt:bcu [32 (rash txid hex)])
  =/  expected=@ux  dat:(flip:byt:bcu [32 (rash expected-root hex)])
  =/  position=@  pos
  |-
  ?~  siblings
    =(current expected)
  ::  Flip sibling hash to internal byte order
  =/  sibling=@ux  dat:(flip:byt:bcu [32 (rash i.siblings hex)])
  =/  is-left=?  =((mod position 2) 0)
  =/  combined=@ux
    ?:  is-left
      (bitcoin-hash current sibling)
    (bitcoin-hash sibling current)
  $(current combined, position (div position 2), siblings t.siblings)
::
++  verify-transaction-inclusion
  |=  [proof=merkle-proof block-merkle-root=@t]
  ^-  ?
  (verify-merkle-proof txid.proof siblings.proof position.proof block-merkle-root)
:: header parsing
::
::  +parse-hex-bytes: Parse hex string into bytes preserving order and leading zeros
::
::  Bitcoin wire format is big-endian (MSB first). Parses each hex byte pair
::  individually to preserve leading zeros, then flips the list before using can
::  (which builds LSB-first) to produce correct big-endian atom.
::
::  CRITICAL: Because we flop the list before can, byte 0 ends up at the highest
::  position in the resulting atom. This means cut operations must adjust their
::  positions accordingly: to extract bytes [pos, pos+len), use (cut 3 [(sub total (add pos len)) len])
::
++  bytes
  |=  raw-header=@t
  ^-  hexb
  =/  b=hexb  (from-cord:hxb:bcu raw-header)
  ~|  "a bitcoin header is 80 bytes, got {<wid.b>}"
  ?>  =(80 wid.b)
  b
::  +compute-block-hash: double-SHA256 of the 80 bytes, flipped because
::  a block hash is displayed in the reverse of the order it is made in
::
++  compute-block-hash
  |=  raw-header=@t
  ^-  @ux
  dat:(flip:byt:bcu (dsha256:bcu (bytes raw-header)))
::  +parse-header-fields: the six fields of a header, by where they sit.
::
::    0   4   version        little-endian number
::    4  32   prev hash      stored in the reverse of display order
::   36  32   merkle root    likewise
::   68   4   timestamp      little-endian number
::   72   4   bits           little-endian number
::   76   4   nonce          little-endian number
::
::  Every flip here is one the FORMAT asks for, and each is named for
::  what it is. An earlier version read the fields out of an atom built
::  from reversed bytes, so each offset had to be written as
::  (sub 80 (add pos len)) and every field needed a second flip to undo
::  the first. The numbers never got that second flip, which left bits
::  byte-swapped -- and a byte-swapped bits makes +bits-to-target read
::  the exponent off the wrong end and hand back a target no hash can
::  exceed, so proof of work silently passed everything.
::
++  parse-header-fields
  |=  raw-header=@t
  ^-  [version=@ud prev-hash=@ux merkle-root=@ux timestamp=@ud bits=@ux nonce=@ud]
  =/  b=hexb  (bytes raw-header)
  =/  at     |=([pos=@ud len=@ud] `hexb`(take:byt:bcu len (drop:byt:bcu pos b)))
  =/  num    |=(pos=@ud `@ud`dat:(flip:byt:bcu (at pos 4)))
  =/  hash   |=(pos=@ud `@ux`dat:(flip:byt:bcu (at pos 32)))
  :*  (num 0)
      (hash 4)
      (hash 36)
      (num 68)
      `@ux`(num 72)
      (num 76)
  ==
::  +parse-raw-to-header: Complete raw hex to block-header conversion
::
++  parse-raw-to-header
  |=  [raw-header=@t height=@ud]
  ^-  block-header
  =/  computed-hash=@ux  (compute-block-hash raw-header)
  =/  [version=@ud prev-hash=@ux merkle-root=@ux timestamp=@ud bits=@ux nonce=@ud]
    (parse-header-fields raw-header)
  :*  height=height
      version=version
      prev-hash=`@uvI`prev-hash
      merkle-root=`@uvI`merkle-root
      timestamp=timestamp
      bits=bits
      nonce=nonce
      computed-hash=`@uvI`computed-hash
      verified-pow=%.n
      cumulative-work=0
      children=*(set @uvI)
      raw=raw-header
  ==
::
:: PoW validation
::
++  bits-to-target
  |=  bits=@ux
  ^-  @ux
  ::  Bitcoin compact bits format: 0xAABBCCDD
  ::  AA = exponent, BBCCDD = mantissa
  ::  target = mantissa * 2^(8*(exponent-3))
  =/  exponent  (rsh [3 3] bits)  :: Top byte
  =/  mantissa  (end [3 3] bits)  :: Bottom 3 bytes
  ?:  (gth exponent 3)
    (lsh [3 (sub exponent 3)] mantissa)
  (rsh [3 (sub 3 exponent)] mantissa)
::
++  calculate-work
  |=  target=@ux
  ^-  @ud
  ::  Work = 2^256 / (target + 1)
  =/  max-hash=@  (bex 256)  :: 2^256
  (div max-hash +(target))
::
++  validate-header-with-hash
  |=  [header=block-header computed-hash=@ux]
  ^-  [validated-header=block-header pow-valid=? work=@ud]
  =/  target=@ux  (bits-to-target bits.header)
  =/  pow-valid=?  (lth computed-hash target)
  =/  work=@ud  (calculate-work target)
  :-  header(computed-hash `@uvI`computed-hash, verified-pow pow-valid)
  [pow-valid work]
::
:: Chain validation
::
++  validate-chain-connection
  |=  $:  header=block-header
          headers=(map @uvI block-header)
          checkpoint-hash=@uvI
      ==
  ^-  [valid=? parent=(unit block-header)]
  ::  the block that follows the checkpoint is what ties everything
  ::  above it to this ship's one unverified assumption
  ?:  =(prev-hash.header checkpoint-hash)
    [%.y ~]
  ::  otherwise it must attach to a header we already hold
  =/  parent=(unit block-header)  (~(get by headers) prev-hash.header)
  ?^  parent  [%.y parent]
  ::  an empty chain is only a licence to accept anything when there is
  ::  no checkpoint to meet -- signet and regtest are followed from
  ::  genesis, so the first block has nothing above it to check against.
  ::  With a checkpoint set, letting any header be the first would hand
  ::  the provider the choice of where our chain begins, and the
  ::  checkpoint would decide nothing.
  ?:  &(=(0 checkpoint-hash) =(0 ~(wyt by headers)))
    [%.y ~]
  [%.n ~]
::
++  add-header-to-chain
  |=  $:  header=block-header
          parent=(unit block-header)
          headers=(map @uvI block-header)
      ==
  ^-  (map @uvI block-header)
  ::  If no parent, just add header
  ?~  parent
    (~(put by headers) computed-hash.header header)
  ::  Update parent's children set, then add header
  =/  updated-parent=block-header
    u.parent(children (~(put in children.u.parent) computed-hash.header))
  =/  headers-with-parent  (~(put by headers) prev-hash.header updated-parent)
  (~(put by headers-with-parent) computed-hash.header header)
::
++  calculate-cumulative-work
  |=  [parent=(unit block-header) block-work=@ud]
  ^-  @ud
  ?~  parent
    block-work
  (add cumulative-work.u.parent block-work)
::
::  Verify parsed merkle proof against block header
::  Returns success or error tang
::
++  verify-parsed-merkle-proof
  |=  [txid=@t merkles=(list @t) pos=@ud header=block-header]
  ^-  (each ~ tang)
  %-  mule  |.
  =/  merkle-root-hex=@t
    (hash-to-hex `@ux`merkle-root.header)
  =/  verification-result=?
    (verify-merkle-proof txid merkles pos merkle-root-hex)
  ?.  verification-result
    ~|  %merkle-proof-invalid
    ~|  "Merkle proof verification failed"
    !!
  ~
::
::  Get spv-chain for a network (with safe checkpoint defaults)
::
::  +build-raw-header: the 80 bytes, rebuilt from the fields an Esplora
::  block listing gives us.
::
::  Following a chain one block at a time costs two requests each -- the
::  hash at a height, then that block's header. /blocks/:height hands
::  back ten blocks with every field a header is made of, which is the
::  difference between 5,000 requests and 100,000 on a catch-up.
::
::  The catch is that we are now trusting a provider's PARSED view
::  rather than bytes we can hash. So we rebuild the bytes ourselves and
::  check they hash to the id it claimed: if any of this serialization
::  is wrong, or the provider's fields disagree with its own hash, it
::  fails loudly here instead of quietly seating a bad header. Byte
::  order is Bitcoin's usual mess -- little-endian numbers, and the two
::  hashes stored reversed from how they are displayed.
::
++  build-raw-header
  |=  $:  version=@ud
          prev=@t
          merkle=@t
          stamp=@ud
          bits=@ud
          nonce=@ud
      ==
  ^-  @t
  =/  le4
    |=  n=@ud  ^-  hexb
    (flip:byt:bcu [4 `@ux`n])
  =/  rev32
    |=  c=@t  ^-  hexb
    (flip:byt:bcu (take:byt:bcu 32 (from-cord:hxb:bcu c)))
  %-  to-cord:hxb:bcu
  %-  cat:byt:bcu
  :~  (le4 version)
      (rev32 prev)
      (rev32 merkle)
      (le4 stamp)
      (le4 bits)
      (le4 nonce)
  ==
::  +header-from-fields: a listing entry as a verified header, or ~ when
::  the bytes we rebuilt do not hash to the id the provider gave.
::
++  header-from-fields
  |=  $:  height=@ud
          id=@t
          version=@ud
          prev=@t
          merkle=@t
          stamp=@ud
          bits=@ud
          nonce=@ud
      ==
  ^-  (unit block-header)
  =/  raw=@t  (build-raw-header version prev merkle stamp bits nonce)
  =/  hed=block-header  (parse-raw-to-header raw height)
  ?.  =(computed-hash.hed `@uvI`(rash id hex))  ~
  `hed
::
++  get-spv-chain
  |=  [net=network spv=(map network spv-chain)]
  ^-  spv-chain
  =/  chain=(unit spv-chain)  (~(get by spv) net)
  ?^  chain  u.chain
  ::  Return empty chain with network-specific checkpoint defaults
  ::  A checkpoint is a claim we make, not one the provider makes: below
  ::  it we verify nothing, so it is the oldest block this ship will
  ::  vouch for. %signet and %regtest get none -- they are cheap to
  ::  follow from genesis and their history is not worth hardcoding.
  =/  [height=@ud hash=@uvI]
    ?-  net
      %main      [925.000 `@uvI`(rash '0000000000000000000067f9f40ca6960173ebee423f6130138762dfc40630bf' hex)]
      %testnet3  [2.500.000 `@uvI`(rash '000000000000004a6039a59a81ad9ca1f6b143ad7c487f2c9e1c1d8e96e1e5ba' hex)]
      %testnet4  [111.000 `@uvI`(rash '0000000007838a124187712a910ef0573cb76104c9a612d8dc4029b964a79007' hex)]
      %signet    [0 `@uvI`0x0]
      %regtest   [0 `@uvI`0x0]
    ==
  :*  ~  ~  ~  height  hash  ~  ~  ==
--