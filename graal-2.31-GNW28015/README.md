# Graal 2.31 (`GNW28015`)

The 2.31 client, rebuilt. Original: `Graal_231.exe` (FileVersion 2.3.1.0)
from the Graal Reborn 2.2.2.0 folder, a Delphi build on the same gen-5
wire as 2.22. This folder is a reproduction at **0.0.1**: it starts from
the 2.22 rebuild (`../graal-2.22-GNW03014`) and changes only what the
notes say 2.31 does differently. Nothing here has been compared side by
side with the real 2.31 yet; that is 0.0.2.

## Sources

Written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| Token, FileVersion | `client-internals/version-tokens.md` |
| What changed from 2.22 | `version-profiles/2.22-2.31.md` (and `2.22-2.31.toml`) |
| Ids handled and sent | `protocol/client-versions.md`, `version-profiles/plo-handled-ids-by-build.tsv`, `protocol/packet-layouts.md` |
| Tamper check bytes and timer | `version-profiles/tampercheck-values.tsv`, `client-internals/decomp-findings-2026-10-24-b/03-periodic-ids-2.31.md` |
| Player and NPC prop ranges, X2 / Y2 / Z2 | `protocol/player-props.md`, `version-profiles/plo-npcprops-layouts.tsv` |
| Listserver step (the same as 2.22's) | `protocol/login-frames-by-version-2026-10-25.md` |

## What differs from the 2.22 rebuild

| | 2.22 | 2.31 (this folder) |
|---|---|---|
| Login token | `GNW03014` | `GNW28015` |
| Tamper check (39) | `250e4d0f962b03ede631`, at login, after each link request and gmap edge crossing | `291655b7602e87c9eb82`, at login and then every 64 ticks (about 3.2 s) |
| `PLI_SHOWIMG` (24) every 5.1 s | only with another player in the level | always |
| `PLI_ENTERLEVEL` (46) = 1 | not sent | on every level entry (links, warps, the start level) |
| `PLI_PUTNPC` (21) | sent by `putnpc` online | not sent |
| Server ids handled | 80 | 81: no `HASNPCSERVER` (44), adds `LARGEFILESIZE` (84) and `MOVE2` (189) |
| Own props parsed | up to 74 | up to 80; stops at 50, 51, 53, 75 to 77 |
| Other players' props | up to 76 | up to 80; stops at 1, 3 to 7, 14, 22, 25 to 29, 77 |
| NPC props | up to 73 | up to 77 (41 to 43, CLASS 74, X2 / Y2 75 / 76, Z2 77); stops at 48 to 52 |
| X2 / Y2 / Z2 (78 to 80) | not parsed | parsed: `abs(v * 16) shl 1`, low bit the sign |
| Classic mode (client runs NPC props itself without an NPC server) | yes | no |
| GS1 | `common/GGs1.pas` | the same, through 2.17.1's NPC units (`#P1` to `#P30`, `addtiledef` in scripts) |
| Asset folders | `graal-assets/2.22/` | `graal-assets/2.31/`, then `graal-assets/2.22/` (2.31 shipped in the same folder as 2.22) |

The listserver step, frames, cipher, compression choice, login burst,
walking, links, gmaps and the game layer are 2.22's unchanged.

## Units

| Unit | What it does |
|---|---|
| `src/Protocol231.pas` | ids, token, tamper bytes, the 81 handled ids |
| `src/GraalClient.pas` | the socket, frames, gen-5 codec and login (2.22's) |
| `src/Adventure.pas` | game state, levels, gmaps, handlers, the 50 ms tick, drawing (2.22's, with the changes above) |
| `src/Graal231.dpr` | front end: start screen with no arguments; flags for the window, keys, frame dump, stress runs |
| `src/ListServer231.pas`, `src/StartScreen231.pas` | the listserver step and the start screen plug-in (2.22's) |
| `src/RealStart231.pas` | 2.31's own start window and server list (its own windows, 577 x 416) |
| `src/Res231.pas` | what 2.31's program carries, compiled in: generated from `res/` (see `res/README.md`) by `scripts/res/make_resunit.py` |
| `src/Npc231.pas`, `src/NpcBridge231.pas` | level NPCs and what their scripts reach (2.17.1's, with 2.31's prop range) |
| `src/Baddy231.pas`, `src/Sound231.pas`, `src/Map231.pas` | baddies, sound effects, the maps (2.17.1's) |
| `src/RunMode.pas` | stress-run support |

## Running it

The exe lives in the root: the folder that holds the game files as the
original install had them (`levels/`, `sounds/`, ...), or a
`graal-assets/` folder inside it. With nothing next to it, it runs on its
built-in stand-in art.

```
Graal231                                         # start screen
GRAAL_PW=... Graal231 --server HOST:PORT --account NAME
Graal231 --level some.nw --window                # offline
Graal231 --help
```

The listserver default is `listserver.graal.in` on 14922; `listserver.txt`
next to the program, or the install's `arrays2.dat`, wins over it.

## Seihai secure login (not in the original)

The original sends the account and the password in the clear. This build
can send them sealed instead, with the Seihai secure login (version token
`SEI00001`, Seihai `documentation/secure-login.md`; graal-client-repro
#148): a key exchange first, the server's signed key checked and pinned,
then the account and password in ChaCha20-Poly1305. The game after the
login is 2.31's own gen-5 stream, unchanged. It works on the game server
and on the list server (`common/GSecLogin.pas`, `common/GSecCrypto.pas`;
no extra library ships).

It is **off by default**, so the program logs in byte for byte as the
original does. To turn it on:

```
GRAAL_PW=... Graal231 --server HOST:PORT --account NAME --secure-login auto
```

or put one word, `off`, `auto` or `required`, in `secure_login.txt` in the
settings folder (or set `GRAAL_SECURE_LOGIN`); that covers the start
screen and the server list too.

- `auto`: try the secure login. A server that refuses it, closes, or does
  not answer within 5 s gets the original login on a new connection, and
  is not asked again (`refused_servers.txt`). Once a server's key is
  pinned, it never gets the password in the clear again: if it stops
  answering, the login stops and says so.
- `required`: never send the password in the clear.
- `--server-key KEY`: trust that key only (the pin file is left alone).

The settings folder is shared by every rebuild of the player:
`%APPDATA%\graal-delphi` on Windows, `~/.config/graal-delphi` elsewhere
(`GRAAL_SECURE_DIR` moves it). `known_servers.txt` there holds one
`host:port key` line per server, trusted on first use as with SSH; a server
whose key changed is refused, naming both fingerprints, until its line is
removed by hand. Real Graal servers do not know the token; with `auto`
they see one extra short connection the first time.

## Checks

- `tests/Test231.dpr`: the 2.22 suite adapted to 2.31 (login line with
  `GNW28015`; the first frame is 2.22's real one with 2.31's tamper bytes;
  no 39 after a link or an edge crossing; 39 once per 64 ticks; 46 on
  entering a level; X2 / Y2 / Z2 and the 77 / 80 stops; 44 dropped, 84 and
  189 known). Wire checks still use frames of a real 2.22 session
  (`Capture222.inc`), since 2.31's send path is the same code.
- `tests/TestSoundMap231.dpr`, `TestNpc231.pas`, `TestBaddy231.pas`.
- `tests/TestSecLogin231.dpr`: the secure login. Every primitive against
  its RFC vectors (SHA-256/512, HMAC, HKDF, X25519, strict Ed25519,
  ChaCha20-Poly1305, base64), the handshake against a server side written
  from the spec (a changed S1 or inner token fails, C2 opens to the classic
  tail), the pins, the modes, and the game and list wire.
- CI logs two of these into seihai-gserver (`scripts/loopback.sh`), then
  one more with `--secure-login required`.
- Loopback run, 2026-11-13, against seihai-gserver and seihai-listserver
  built from main: secure logins on both links, the pin trusted then
  matched, a changed pin and a wrong `--server-key` stop before the
  password is sent, a wrong password gets the server's usual refusal, a
  server with the secure login off gets the original login under `auto`
  (and none under `required`), a silent server falls back after 5 s, and
  through a byte-logging relay neither the account nor the password
  appears on the wire, where the original login shows both.

## Not yet, or not known (0.0.2)

- Side by side with the real `Graal_231.exe` under Wine (2026-11-05): the
  start window, its title, buttons and places, the Training window's size,
  title and chat line, and Alt+Enter match; so do the More options and
  Open URL windows, the chat line and the quit box. Training's torches,
  text and ground are in; some things stand a little lower than in 2.31
  (see RELEASE_NOTES "Not yet").
- [ ] The payload of 24 in 2.31 (2.22's value, 9, is sent).
- [ ] Whether 2.31 sends its own position as X2 / Y2; the rebuild sends X / Y
  in half tiles, as 2.22 does.
- [ ] `LARGEFILESIZE` and `MOVE2` are accepted and ignored; NPC moves are not
  animated.
- [ ] `graal://` links.
- [ ] The F1 window with four buttons, the key-config fix, GS1's `timevar2`, `downloadsize`, `onwall2`, `onwater2`.
- [ ] Everything listed under "Not yet" in the 2.22 README.
