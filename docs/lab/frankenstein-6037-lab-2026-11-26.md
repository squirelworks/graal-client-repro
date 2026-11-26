# Frankenstein 6.037 lab run, 2026-11-26

First run of `frankenstein-6037` (the 6.03r7 Quattro host with the 5.12
protocol-24 link) against a real server: the Seihai gserver's `graal3d`
mode, beside the stock Linux 6.03r7 client on the same server. Derived
results only; captures, logs and screenshots stay off the repo.

## Setup

| Piece | What ran |
|---|---|
| Server | `seihai-gserver` main `5915349` (`graal3d = true`, UDP on port + 1, `lobby_port` for the 178 warp, `movetype interpolate`, a `-G3P` weapon that sends `g3dpos` at 15 s and 35 s), the lab world from the earlier 3D runs (terrain, water, sky, a cube, a ground shape). One server process serves the Login lobby and the `3 Frank Lab` game port |
| Clients | `frankenstein-6037` Linux build from main `cbfe639f` (then with this PR); stock Linux 6.03r7 (`G3D0511C`, unpacked, unchanged) |
| Network | Linux lab VM, two private network namespaces joined by a veth pair: server `10.77.0.1`, clients `10.77.0.2`. Nothing reaches outside the VM. The stock client's `loginserver` name points at `10.77.0.1` through a private `/etc/hosts` mount |
| Driving | Xvfb per client, `xdotool` keys, `xwd` screenshots; the server's `graal3d_trace` |

Not done here: the Windows build in the Windows 10 VM. The host had under
5 GB of RAM free with both Windows 10 lab clones in use by other runs, so
everything ran in the Linux VM. The Windows build is the same source and
passes the same loopback test in CI.

## Results

| Check | Frankenstein 6.037 | Stock 6.03r7 |
|---|---|---|
| Login to the Login lobby (6.03r7 token) | works | works (as `guest`) |
| 178 warp to `3 Frank Lab` | works: the warp name keeps the `3 ` tag and enters 3D | works: taken as a plain 2D server |
| UDP link on port + 1 | **failed on server main**: the server never offered a 6.03r7-token login to the UDP side, so every connect request was held until the client gave up after 15 s and closed both links. With seihai-gserver PR (6.03r7 rows may link): handshake, accept, mission phases 1 and 2, login step 6 | never opened (no UDP socket), as the static read says |
| 3D world drawn | works with the 5.12 renderer: sky, terrain textures, water, the cube and player shapes, name tags, 6.x frame as an inset. Shapes and terrain textures must be in a local `levels3d/` (`--asset-root`); without it only the sky and white terrain draw (the step-6 file downloads are not done yet) | 2D only |
| Ghosts | works: each Frankenstein's `G3DPlayer_<acct>` is ghosted to the other; the stock client's 2D player arrives as a `G2DPlayer_` ghost and moves as it walks | sees Frankenstein players as ordinary 2D players, walking |
| Server move to client (`g3dpos`, `interpolate`) | works: `player.position` (this PR) read 30 → 60 → 45.6 (mid-glide) → 30 | n/a |
| Client move to server (3D) | not sent: 0 moves received. 2D walking moves only the 2D player; the own 3D object does not follow (README "keys moving the player in 3D" is still open) | n/a |
| 2D walking in the inset | slowed 2 to 3.6 times on main (see below); real-time with this PR | works |
| GS2 timers (`setTimer(1)`) | 1.8 s (one client) to 3.6 s (two clients) per second on main; 1.0 s with this PR | normal |
| Weapons from the 3D world (`weapon3d`) | works: `-G3P` loaded and ran; its `triggerserver` lines went over the link as `events` | n/a |
| `player.position` in a 3D weapon | always `0` on main (the 6.x `player` is the 2D player); the control object's position with this PR (read only) | n/a |
| Chat | no built-in chat bar on the 6.03r7 row (scripts own it); none sent from either client. Needs a server chat-bar weapon | same |
| PMs, player list | script-driven on the 6.x row; this world sends no such scripts, so not seen in either client | same |
| Level change in 3D | not run (one level in the world) | not run |
| Disconnect | the 3D disconnect goes out and the server closes the link with the TCP session | TCP close |

## The slowdown

The 6.x program counts its timers and walking in 50 ms ticks and draws once
a tick. The software 3D renderer took about 90 ms a frame with one client
and about 180 ms with two in the 2-CPU VM, so every tick ran long and the
whole 2D game slowed by the same factor (a GS2 `setTimer(1)` loop reached
18 in about 65 s). This PR keeps the program on its clock:

- the main loop runs ticks at a fixed 50 ms rate and catches up after a
  long one (a backlog over 250 ms is dropped);
- the 3D frame is drawn at most about half the time (after a frame that
  took *t*, the next waits *t*); ticks in between reuse the last 3D frame
  under a live 6.x inset.

With both, timers ran at 1.0 s and 2D walking at full speed with two
clients drawing 3D.

## Compared with the static read

Graal_analysis `torque/3d-v6-quattro-vs-512-2026-11-26.md` (T3D-121, PR
#946) says stock 6.03r7 is a 2D Quattro client with no protocol-24 link.
The run agrees: stock 6.03r7 took the 178 to the `3 ` server as a 2D
server and opened no UDP socket; the server treated it as 2D. Everything
3D in the table above is the Frankenstein's own link, not anything stock
6.03r7 has.

## The world renderer

The 5.12 renderer has been the Frankenstein's 3D view since #461 (the
stand-in boxes only draw when no Camera is named). The open renderer PR
#463 (draw distance, grass cards) is a drop-in: its renderer files built
with this branch, the loopback test passed and a live run drew the same
world. After it merges, the host should set the draw distance from the
player's `visibledistance3D` (`setVisibleDistance3D`); without that it
uses the 1000 default, which is the 5.12 default too.

Still missing before the view matches a real 5.12 session:

- the files step 6 waits for (shapes, sky and terrain textures over TCP)
  into the renderer's `levels3d/`: today they must be installed locally;
- client 3D movement: keys or the 2D walk moving the own object and
  sending section 5/9 updates; a script setting `player.position`;
- the camera: the server's Camera ghost is drawn as sent; no mouse-look;
- name tags for `G2DPlayer_` ghosts.
