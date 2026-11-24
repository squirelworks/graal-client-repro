# Frankenstein 6.037

A community-requested experimental client: a **v6.037** host with **v5.120
Graal3D** folded in, and **UDP left enabled**. People have been calling it
a cursed mixture, and that is the right word. It is one program on purpose
made from two generations that the faithful folders keep apart.

This directory is the scaffold. There is no engine, no window, and no
protocol code yet. The first playable deliverable, later, is a **macOS**
build people can use for Graal3D testing, with **Linux** and **Windows**
builds of the same client beside it.

The other experimental mix, a v6.113 host with the same v5.120 fold-in,
lives in [`frankenstein/`](../frankenstein/). This tree does not change
that one. Releases, tags, and the workflow here are their own series.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Goal

| Piece | What this mix keeps | Where the behaviour notes already live |
|---|---|---|
| Host | v6.037 session, scripts, and file requests | [`graal-6.03r7win-G3D0311C`](../graal-6.03r7win-G3D0311C/) (Windows 6.03r7, token `G3D0311C`; [`docs/v6-repro.md`](../docs/v6-repro.md) says a 6.0.3.7 repro uses that token) and [`graal-6.03r7-G3D0511C`](../graal-6.03r7-G3D0511C/) (Linux 6.03r7, token `G3D0511C`, the same release). Notes: [`docs/v6-repro.md`](../docs/v6-repro.md) |
| World | v5.120 Graal3D, folded into that host | No folder in this repo is named 5.120. The Graal3D-era 5.12 rebuilds are [`graal-5.12-G3D14097`](../graal-5.12-G3D14097/) and [`graal-5.12mac-G3D15097`](../graal-5.12mac-G3D15097/). A later change has to show that v5.120 is one of those builds, or name the real 5.120 profile, before any 3D code is brought over |
| Net | UDP stays enabled, including on the game connection | [`docs/v6-repro.md`](../docs/v6-repro.md) (UDP) says a 6.x connect path does not open a datagram socket, and that whether the 6.0.3.7 game connect path calls the opener is not found. This experiment turns that path on and keeps it on |

The faithful client folders stay matched to their own real clients. Code
for this mix grows under `frankenstein-6037/` and does not change those
folders to suit the mix.

Game data (tiles, ganis, heads, bodies, levels) is loaded from the player's
own install when a real client exists. This scaffold carries none of it.
Any picture or level a later build embeds is graal-delphi's own art, as in
the rest of the repo. This repository may carry original Graal material in
the shape the other folders already use. This scaffold does not add any.

A later client may default to the community list-server hostname the 6.03
folders already name (`listserver.graal.in`). Endpoints and digests in this
scaffold stay the placeholders below.

## Build targets

| Platform | Role now | Role when the client exists |
|---|---|---|
| macOS | Stub build in CI (`macos-15`), listed first | The build Graal3D testing will use. This is the first real deliverable |
| Linux | Stub build in CI | Same client, same sources |
| Windows | Stub build in CI | Same client, same sources |

`frankenstein-6037/build.sh` writes a manifest under
`build/frankenstein-6037/` and copies a shell stand-in.
`frankenstein-6037/test.sh` checks that manifest. Neither script compiles
a client. Output stays in `build/`, which the repo already ignores.

The manifest records the mix and three placeholders: `<server>`, `<port>`,
`<md5>`. Those stay placeholders until a real check has a value to put
there. Loopback tests, when they exist, talk to a server the run starts.

## Releases stay on their own track

Frankenstein 6.037 is cut on its own. The combined client release
([`.github/workflows/release-all.yml`](../.github/workflows/release-all.yml),
tag `vX.Y.Z`, one version for every faithful client) does not build this
folder, does not call this workflow, and does not attach these zips.
`release-all.yml` only accepts `graal-*`, `javagraal-2000`,
`zelda-online1-Z3V102`, `zelda-online2-Z3V103`, and `graalgb-1.10`.
`frankenstein-6037` is outside that list. It is also outside the
[`frankenstein`](../frankenstein/) release (`frankenstein-vX.Y.Z`).

The separate pipeline is
[`.github/workflows/frankenstein-6037.yml`](../.github/workflows/frankenstein-6037.yml).

- **When it runs.** Pull requests and pushes to `main` that touch
  `frankenstein-6037/**` or that workflow file, and a manual run from the
  Actions tab. Other client work does not start it. A change under
  `frankenstein/` does not start it.
- **What it builds today.** The scaffold, on macOS, Linux, and Windows.
  The workflow comments mark where the real compile will go.
- **How a release is cut.** Actions → **frankenstein-6037** → Run
  workflow, on `main`. Set version to a three-part tag such as `v0.0.1`
  (empty means build only). Publish defaults to a draft. The release tag
  is `frankenstein-6037-v0.0.1` (prefix `frankenstein-6037-v`, then the
  three-part version). The draft carries three zips:
  `frankenstein-6037-v0.0.1-macos.zip`,
  `frankenstein-6037-v0.0.1-linux.zip`,
  `frankenstein-6037-v0.0.1-windows.zip`. Squirrel publishes the draft.
- **Version file.** [`VERSION`](VERSION) is `0.0.1` for this scaffold.
  These versions are not the combined `v0.0.5` line, and they are not the
  `frankenstein/` line. Notes for a release go in
  [`RELEASE_NOTES.md`](RELEASE_NOTES.md).

Editing `.github/workflows/frankenstein-6037.yml` also selects every
Pascal client in the main `ci` workflow. That selector
(`scripts/ci/select_pascal_builds.py`) treats every file under
`.github/workflows/` as shared CI. This scaffold does not change that
rule. A later change that stays inside `frankenstein-6037/` does not
select those clients.

## Layout

```
frankenstein-6037/
  README.md            this file
  RELEASE_NOTES.md     notes for frankenstein-6037-v* drafts
  VERSION              scaffold version (0.0.1)
  build.sh             stub build (manifest + shell stand-in)
  test.sh              checks the stub
  src/
    frankenstein.sh    shell stand-in the stub build ships
    host6037/          v6.037 host (placeholder)
    graal3d5120/       v5.120 Graal3D fold-in (placeholder)
    net/udp/           UDP-enabled connect path (placeholder)
    platform/          macos, linux, windows slots
  tests/               where client tests will live
  res/                 future embedded resources (empty of game data)
```

## Not yet

- [ ] Confirm which real build "v5.120" is, against the 5.12 folders or a
      profile of its own, before any Graal3D code is folded in.
- [ ] v6.037 host under `src/host6037/` (session, scripts, files), reading
      the Windows `G3D0311C` notes and the Linux `G3D0511C` sibling as two
      builds of the same release.
- [ ] v5.120 Graal3D under `src/graal3d5120/`, inside that host.
- [ ] UDP enabled on the game connection (`src/net/udp/`).
- [ ] A macOS build that can be used for Graal3D testing.
- [ ] Linux and Windows builds of that same client.
- [ ] Loopback coverage against a server the run starts (`<server>`,
      `<port>`). Digests stay `<md5>` until a real check exists.
- [ ] Replace the manifest stub in `frankenstein-6037.yml` with the real
      compile.

## Rules for this folder

- Placeholders only for endpoints and digests: `<server>`, `<port>`,
  `<md5>`. The community list-server hostname, when a later client needs
  one, is `listserver.graal.in`, the name the 6.03 folders already use.
- Behaviour comes from the notes named above. No code addresses, no
  decompiler symbol names, and no decompiled C in this tree, in commits,
  or in pull requests.
- The later engine is the older Quattro program the 6.03 folders use,
  with v5.120 Graal3D folded into that host. No modern Torque3D base.
  A small MIT-licensed piece from modern Torque3D is allowed only where
  that older Torque needs it (the string Huffman table already kept under
  `common/cpp/third_party/torque3d/`). This scaffold adds no engine code.
- Original game files stay in the player's install, not in git, unless a
  later change follows the shape the other folders in this repo already
  use. This scaffold adds none.
