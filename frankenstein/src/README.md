# Source slots

Empty of engine code. Each directory is a place the later client will fill.

| Path | Later contents |
|---|---|
| `host6113/` | v6.113 host: session, scripts, file requests. Read behaviour from `graal-6.1.1.3-GNP1905C` and `docs/v6-repro.md`. |
| `graal3d5120/` | v5.120 Graal3D, folded into that host. v5.120 is 5.12: read `graal-5.12-G3D14097` (Windows) and `graal-5.12mac-G3D15097` (Mac). |
| `net/udp/` | Datagram path left enabled on the game connection. |
| `platform/` | macOS (first playable target), Linux, and Windows. |
| `frankenstein.sh` | Scaffold stand-in. The real entry point replaces it. |

`frankenstein/build.sh` does not compile anything here.
