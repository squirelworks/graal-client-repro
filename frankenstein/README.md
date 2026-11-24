# Frankenstein

A community-requested experimental client: a **v6.113** host with **v5.120
Graal3D** folded in, and **UDP left enabled**. People have been calling it
a cursed mixture, and that is the right word. It is one program on purpose
made from two generations that the faithful folders keep apart.

This directory is the scaffold. There is no engine, no window, and no
protocol code yet. The first playable deliverable, later, is a **macOS**
build people can use for Graal3D testing, with **Linux** and **Windows**
builds of the same client beside it.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Goal

| Piece | What this mix keeps | Where the behaviour notes already live |
|---|---|---|
| Host | v6.113 session, scripts, and file requests | [`graal-6.1.1.3-GNP1905C`](../graal-6.1.1.3-GNP1905C/) (`graalversion` 6.113, token `GNP1905C`) and [`docs/v6-repro.md`](../docs/v6-repro.md) |
| World | v5.120 Graal3D, folded into that host | v5.120 is 5.12, written the way the 6.x builds are (6.03r7 is v6.037). The rebuilds are [`graal-5.12-G3D14097`](../graal-5.12-G3D14097/) (Windows, token `G3D14097`) and [`graal-5.12mac-G3D15097`](../graal-5.12mac-G3D15097/) (Mac OS X, token `G3D15097`, same engine source, seen on the wire in the lab). Both split the Delphi launcher from `GraalEngine.dll` and `Graal3DEngine.dll` |
| Net | UDP stays enabled, including on the game connection | Stock v6.113 leaves the datagram socket off the game connect path (`docs/v6-repro.md`, UDP). This experiment turns that path on and keeps it on |

The faithful client folders stay matched to their own real clients. Code
for this mix grows under `frankenstein/` and does not change those folders
to suit the mix.

Game data (tiles, ganis, heads, bodies, levels) is loaded from the player's
own install when a real client exists. This scaffold carries none of it.
Any picture or level a later build embeds is graal-delphi's own art, as in
the rest of the repo.

## Build targets

| Platform | Role now | Role when the client exists |
|---|---|---|
| macOS | Stub build in CI (`macos-15`), listed first | The build Graal3D testing will use. This is the first real deliverable |
| Linux | Stub build in CI | Same client, same sources |
| Windows | Stub build in CI | Same client, same sources |

`frankenstein/build.sh` writes a manifest under `build/frankenstein/` and
copies a shell stand-in. `frankenstein/test.sh` checks that manifest.
Neither script compiles a client. Output stays in `build/`, which the repo
already ignores.

The manifest records the mix and three placeholders: `<server>`, `<port>`,
`<md5>`. Those stay placeholders until a real check has a value to put
there. Loopback tests, when they exist, talk to a server the run starts.

## Releases stay on their own track

Frankenstein is cut on its own. The combined client release
([`.github/workflows/release-all.yml`](../.github/workflows/release-all.yml),
tag `vX.Y.Z`, one version for every faithful client) does not build this
folder, does not call this workflow, and does not attach these zips.
`release-all.yml` only accepts `graal-*`, `javagraal-2000`,
`zelda-online1-Z3V102`, `zelda-online2-Z3V103`, and `graalgb-1.10`.

The separate pipeline is
[`.github/workflows/frankenstein.yml`](../.github/workflows/frankenstein.yml).

- **When it runs.** Pull requests and pushes to `main` that touch
  `frankenstein/**` or that workflow file, and a manual run from the
  Actions tab. Other client work does not start it.
- **What it builds today.** The scaffold, on macOS, Linux, and Windows.
  The workflow comments mark where the real compile will go.
- **How a release is cut.** Actions → **frankenstein** → Run workflow, on
  `main`. Set version to a three-part tag such as `v0.0.1` (empty means
  build only). Publish defaults to a draft. The release tag is
  `frankenstein-v0.0.1` (prefix `frankenstein-v`, then the three-part
  version). The draft carries three zips:
  `frankenstein-v0.0.1-macos.zip`, `frankenstein-v0.0.1-linux.zip`,
  `frankenstein-v0.0.1-windows.zip`. Squirrel publishes the draft.
- **Version file.** [`VERSION`](VERSION) is `0.0.1` for this scaffold.
  Frankenstein versions are not the combined `v0.0.5` line. Notes for a
  Frankenstein release go in [`RELEASE_NOTES.md`](RELEASE_NOTES.md).

Editing `.github/workflows/frankenstein.yml` also selects every Pascal
client in the main `ci` workflow. That selector
(`scripts/ci/select_pascal_builds.py`) treats every file under
`.github/workflows/` as shared CI. This scaffold does not change that
rule. A later change that stays inside `frankenstein/` does not select
those clients.

## Layout

```
frankenstein/
  README.md            this file
  RELEASE_NOTES.md     notes for frankenstein-v* drafts
  VERSION              scaffold version (0.0.1)
  build.sh             stub build (manifest + shell stand-in)
  test.sh              checks the stub
  src/
    frankenstein.sh    shell stand-in the stub build ships
    host6113/          v6.113 host (placeholder)
    graal3d5120/       v5.120 Graal3D fold-in (placeholder)
    net/udp/           UDP-enabled connect path (placeholder)
    platform/          macos, linux, windows slots
  tests/               where client tests will live
  res/                 future embedded resources (empty of game data)
```

## Not yet

- [ ] v6.113 host under `src/host6113/` (session, scripts, files).
- [ ] v5.120 Graal3D under `src/graal3d5120/`, inside that host.
- [ ] UDP enabled on the game connection (`src/net/udp/`).
- [ ] A macOS build that can be used for Graal3D testing.
- [ ] Linux and Windows builds of that same client.
- [ ] Loopback coverage against a server the run starts (`<server>`,
      `<port>`). Digests stay `<md5>` until a real check exists.
- [ ] Replace the manifest stub in `frankenstein.yml` with the real compile.

## Rules for this folder

- Placeholders only for endpoints and digests: `<server>`, `<port>`,
  `<md5>`.
- Behaviour comes from the notes named above. No code addresses, no
  decompiler symbol names, and no decompiled C in this tree, in commits,
  or in pull requests.
- Original game files stay in the player's install, not in git.
