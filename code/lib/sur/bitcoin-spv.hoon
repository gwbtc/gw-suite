::  sur/bitcoin-spv: what a verified chain is made of.
::
::  Ported from gwbtc/spv-wallet. A header carries both what the block
::  SAYS (version, prev-hash, merkle-root, timestamp, bits, nonce) and
::  what we WORKED OUT about it (computed-hash, verified-pow,
::  cumulative-work) -- the second half is the point: it is the part a
::  provider cannot hand us.
::
::  The chain is checkpointed, not synced from genesis: `headers` holds
::  from `checkpoint-height` forward, which is what makes keeping it in
::  a grub reasonable at all.
::
|%
::  SPV (Simple Payment Verification) types
::
+$  block-hash  @ux
+$  tx-hash     @ux
+$  merkle-proof  
  $:  tx-hash=tx-hash
      merkle-path=(list @ux)
      block-hash=block-hash
  ==
::
:: Block header structure for chain validation
::
+$  block-header
  $:  height=@ud
      version=@ud
      prev-hash=@uvI
      merkle-root=@uvI
      timestamp=@
      bits=@ux
      nonce=@ud
      computed-hash=@uvI
      verified-pow=?
      cumulative-work=@ud
      children=(set @uvI)
      raw=@t
  ==
::
+$  spv-chain
  $:  headers=(map @uvI block-header)
      headers-by-height=((mop @ud (set @uvI)) lth)
      headers-by-work=((mop @ud (set @uvI)) lth)
      checkpoint-height=@ud
      checkpoint-hash=@uvI
      header-sync=(unit [pid=@ta act=? height=@ud])
      sync-error=(unit tang)
  ==
--
