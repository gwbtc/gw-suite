::  lib/spv/road: reach the spv nexus by name, wherever it is installed.
::
::  /sys/link/spv is where the kernel records it, so a tool never
::  hardcodes a desk path and keeps working across reinstalls.
::
|%
++  spv-road
  |=  =lane:tarball
  =/  m  (fiber:fiber:nexus ,road:tarball)
  ^-  form:m
  ;<  road=(unit road:tarball)  bind:m  (resolve-link-at:io '@spv' lane)
  ?~  road  ~|(%no-spv-linked !!)
  (pure:m u.road)
--
