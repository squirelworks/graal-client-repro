# Graal 6.0.1.5 for Windows (`G3D3007A`)

The 6.0.1.5 client, rebuilt. The original is `Graal6Setup.exe` from the
graalonline.com downloads of November 2011 (2,699,360 bytes, SHA-256
`5abaffacf35e65e3c964ff93719a108fa29b1a168e0c3c7228d6fcd18df6fe42`, PE
FileVersion 6.015, linked 2011-11-05): a self-installing client, one
protected executable, no launcher and no engine library. 6.0.0.7 (the
same download in August 2011, FileVersion 6.007) sends the same token, so
this folder stands for both.

This folder starts as a copy of `graal-6.01r1-G3D0108A` and changes only what is
known to differ. 6.0.1.5 is the Windows release two months after the Linux 6.01r1 this
folder starts from. Its protector hides the code, so nothing beyond the
token has been read from it yet; everything else is 6.01r1's, with the
Windows login tail the Windows 5.12 to 6.03r7 builds send. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| The original's download, hashes and token | Batch-1 `Web-Discovered/METADATA.md` and `TOKENS.md` (2026-11-13) |
| Token | seen on the wire: the real 6.0.0.7 and 6.0.1.5 were run in a Windows 10 lab VM (2026-11-13) and both sent `G3D3007A`, which matches the public version list |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.01r1-G3D0108A/README.md` |

## What differs from the 6.01r1 Linux rebuild

| | 6.01r1 Linux | 6.0.1.5 (this folder) |
|---|---|---|
| Game token | `G3D0108A` | `G3D3007A` |
| Login line tail | `linux` and four machine fields | `win` and four machine fields |
| OSTYPE prop | `linux` | `win` |

Server ids handled: 91, taken from 6.01r1 Linux (not read from this build).

## Units

As in `graal-6.01r1-G3D0108A`, with this folder's suffix: `Graal6015.dpr`, `Protocol6015`,
`ListServer6015`, `StartScreen6015`, `GraalClient`, `Adventure`, `RunMode`.

## Running it

Put `Graal6015` in the root of a 6.0.1.5 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.0.1.5/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal6015 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal6015 --server HOST:PORT --account NAME --server-name Classic
Graal6015 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.0.1.5/`, then
`graal-assets/common/`:

- `pics1.png` (or `pics1.gif`) at the top or in `levels/tiles/`, where a
  5.x/6.x install keeps it; `arrays.dat` (a 5.x/6.x install has none, so
  the built-in tile types are used)
- `levels/` for levels, ganis and images; `levels/heads/`, `levels/bodies/`,
  `levels/swords/`, `levels/shields/`, `levels/hats/`, `levels/images/`,
  `levels/tiles/` and `levels/images/downloads/` (where the install keeps
  `sprites.png`)
- `levels/offlinetutorial_b-2.nw` (or `.graal`) for Training, else `start.nw`
  (a 5.x/6.x install has no offline tutorial, so Training plays `start.nw`)
- `listserver.txt` (optional)

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account, the password and the platform fields after it go sealed to
a Seihai game server or list server (version token `SEI00001`,
graal-client-repro #148). Same code and settings as 2.31: see the 2.31
README, "Seihai secure login". CI logs in once more with
`--secure-login required` (`scripts/loopback.sh`).

## Not yet, or not known

- [ ] Nothing past the token has been read from 6.0.1.5 itself: its protector hides the code. The ids handled, the Login mode and the framing are 6.01r1's.
- [x] ~~The four Windows machine fields are sent as `""`~~: they now carry made-up MD5 hashes of SquirrelOS, SquirrelNIC and SquirrelBIOS strings, then the quoted Windows version, the shape the original sends.
- [ ] 6.0.0.7 is not checked separately; it is taken to behave as 6.0.1.5.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
- [ ] Everything still missing from `graal-6.01r1-G3D0108A`:

- [ ] Whether 6.01r1 draws tiles in Login mode: not recorded; 6.03r7's "no" is
  used.
- [ ] The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache), 195 (gani scripts) and 190 are accepted and ignored.
- [ ] 109 (probably a file redirect) and 198 are accepted and ignored.
- [ ] 46 (ENTERLEVEL) on level entry, 162 (the ping answer), the base-file
  requests and the keep-alive 24 are not sent.
- [ ] `GR-V1.05` levels and `GRPKG001` update packages.
- [ ] The chat font (Tempus Sans ITC 24) and nickname colours by AP.
- [ ] Whether 6.01r1 plays offline at all is not traced; Training keeps 3.153's.
