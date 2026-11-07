# Groundwire Suite

Apps a groundwire ship installs from the jump, developed independently of
the kernel and of each other.

A suite app is an ordinary grubbery desk source: `code/bill.json` names the
nexuses installing it creates, `code/version.json` is the release tag a
following desk watches. Bump the version to release.

Right now the suite is the SPV wallet.

## Layout

    code/bill.json        which nexuses to create on install
    code/version.json     the release tag; bump to release
    code/nex/             the apps
    code/lib/             the libraries they use
    code/mar/             the marks they own
    code/man/             their readmes

The code tree is self-contained: every library an app imports ships here,
including ones the kernel also has. That is the model, not an oversight —
a guest desk resolves against its own `/code`, so distributing its whole
closure is what lets it release on its own schedule instead of the
kernel's. Content addressing means the shared copies cost nothing.
