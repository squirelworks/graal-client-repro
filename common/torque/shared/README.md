# Shared C++ host first-frame component

This slice shares the first-frame codec and loopback lab transport used by
host304 and host4208. Their plain-frame builders remain explicit version
adapters: different tokens, message sets and platform tails. No separate copy
of the socket/compression implementation remains in either host.

Observed inputs are described in each host's login.hpp and folder tests.
The 3.04 id-34 timestamp prefix and empty 4.20r8 machine fields retain their
existing provisional status. Sharing the codec supplies no new wire evidence.

The shared transport starts Winsock before hostname lookup for both hosts.
An empty host uses loopback; a resolved non-loopback destination is rejected.
This lab restriction belongs to the rebuild, not to the historical client.

## Checks

make -C common/torque/host304 test
make -C common/torque/host4208 test

Tests independently inflate the frame and compare exact version-specific
plain bytes, exercise invalid keys/newlines/corrupt frames and binary fields,
and receive actual TCP data through numeric loopback and localhost. Python,
Make and the GitHub Actions workflow are modern test/build glue, not era code.
The dedicated cpp-hosts workflow builds and runs these tests on Linux,
Windows and macOS; it does not silently skip C++ when a compiler is missing.

## Remaining engine work

- [x] Shared first-frame codec and loopback transport for two existing hosts.
- [ ] Unified engine runtime and explicit module/script profiles.
- [ ] Evidence-backed TorqueScript/DSO execution and object model.
- [ ] GUI, input and Graal game-control integration with behavioral tests.

This is not a TGE 1.2 implementation, an original-client boot, a successful
historical login, or playable reproduction. GS2/Quattro code does not belong
here. No Torque3D or original assets are included.
