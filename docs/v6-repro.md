# Behaviours a 6.x repro still has to match

This is a checklist, not an implementation. Nothing here is ticked, because
none of it is built. There is no 6.1.1.3 folder. `graal-6.01r1-G3D0108A`
and `graal-6.03r7-G3D0511C` own those two tokens. The rows below are what
the unpacked 6.0.3.7 and 6.1.1.3 listings, and the 6.113 capture notes,
actually show. Where a listing did not contain the path, the row says so.

Sources are the Graal_analysis notes. No decompiled code is copied here.

## Token

- [ ] 6.037 sends the stored string `g3d0311c`, upper-cased, as packet id 5
      on the generation-5 framer.
- [ ] 6.1.1.3 does not store `GNP1905C`. `sendraw` can write eight bytes
      with no header. The capture sends `GNP1905C` before any server byte.
      How the digits `1905` are chosen was not found, so a repro must not
      invent a formula for them.

## Framing

- [ ] 6.037 stays on the generation-5 framer. It has no `setprotocol`,
      `sendraw` or `senddata`.
- [ ] 6.1.1.3 still starts on that framer, and `setprotocol` can replace it
      with an `I` / `L` / `T` / `E` header. `L` is the header length plus
      the body length. `E` 1 is zlib. `E` 2 is bzip2 at block size 5.
      The template string is not in the image. The capture's six-byte
      header is `01 02 00 01 17 fd`, then a zlib member `78 9c`.

## Properties

- [ ] 6.1.1.3 names `tclient_setplayerprops`,
      `tclient_setotherplayerprops`, `tclient_setnpcprops` and
      `tclient_setbaddyprops`. 6.037 has none of those names.
- [ ] The bytes inside a player, NPC or baddy property stream were not
      compared. Do not invent a field difference.

## GS2

- [ ] A `.code` file shorter than eight bytes is rejected. The magic is
      `GRESCR01`. The CRC32 covers the bytes after those eight.
- [ ] Both unpacked images dispatch the same 152 cases, from 11 through
      242, with no case 48, 49 or 200. Cases 54, 121 and 201 through 242
      are present, including opcodes the Preagonal compiler does not emit.
- [ ] A full builtin table was not extracted.

## File requests

- [ ] The only `.gupd` file name in the 6.1.1.3 image is `basepackage.gupd`.
- [ ] `package_mainfiles.gupd` was not found.
- [ ] A numeric request id for `basepackage.gupd` was not recovered. The
      events `onSendUpdatePackage` and `onSendDownloadFile` are present.
- [ ] `game_console.log` is a path the client opens. The log is not in
      the analysis repo, so it supplied no request names.

## Chat

- [ ] Another player's line arrives as the script event `onToall`, from
      `tclient_settoallmsg`, on the TCP incoming path.
- [ ] The UDP receive callback does not raise `onToall`.
- [ ] No compiled PLO id is assigned to that event.

## UDP

- [ ] 6.1.1.3 can open a datagram socket. The caller is the script method
      that reports "Binding of port".
- [ ] The game connect path does not call that opener.
- [ ] The 6.113 captures have no client datagram on the TCP 14900 remotes.
      A repro must not add a peer channel on the connect path to match
      those captures.
