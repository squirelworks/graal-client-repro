# Graal 1.3 test (GSERV014), 0.0.1

A first rebuild of the Graal 1.3 test client in Delphi (Object Pascal),
for Linux and Windows. It logs in the way 1.3 test did and plays a level
offline. It is early and many parts still behave like a later Graal: see
"Not yet".

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The zips hold no original Graal code, graphics, sounds or levels. The
client carries simple graphics of its own.

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the sword, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal13test` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## Where to put your Graal files

Put `Graal13test` in a folder and copy the contents of your own 1.3 test install
next to it: `levels/`, `pics1.png` and the rest, as the install has them.
The program reads only that folder. Without them it uses its own graphics
and starter level.

## What works

- The login line: id 0, `GSERV014`, account and password, sent as one
  zlib frame with no cipher.
- The level the server sends (the board first, then its name), other
  players, walking, links and warps.
- A start screen: Training plays `levels/start1.graal` from your install
  (or the built-in level), and Start offers one server address to connect
  to, as 1.3 test had no server list. It is `listserver.graal.in:14923`
  until you set `serveraddr=` and `serverport=` in `graalconfig.txt` next
  to the program.

## Not yet

Most of the game still follows a later Graal: the script commands, the
item list, sound and the editor have not been checked against 1.3 test.
No local 2 to 4 player modes, no UDP, no options page.

## Checks behind this release

The test programs run with range and overflow checks and the heap tracer
and must end with no unfreed memory; they include a fuzz run of the
receive path. CI also logs two of these clients into seihai-gserver on
loopback, has the second see the first, and walks one through a level
link.
