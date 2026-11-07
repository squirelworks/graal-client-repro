# Behaviours a 6.x repro still has to match

This is a checklist, not an implementation. Nothing here is ticked, because
none of it is built. There is no 6.1.1.3 folder.
`graal-6.01r1-G3D0108A` owns the Linux token `G3D0108A`.
`graal-6.03r7-G3D0511C` owns the Linux token `G3D0511C` and already says
the Windows 6.03r7 token is `G3D0311C`. A row below names the build it
was read from (6.0.3.7, 6.1.1.3, or both) and the observation that would
show a repro matching. Where the listing or the note did not contain the
fact, the row says not found.

Sources, all static reads: `protocol/v6113-hello.md`,
`protocol/v6037-hello-diff.md`, `protocol/v6113-plo.md`,
`client-internals/gs2-6113.md`, `protocol/v6113-files.md`,
`protocol/v6113-chat.md`, `protocol/v6113-udp-code.md`,
`client-internals/issho-cut.md`, `protocol/v6-repro-facts.md`,
`client-internals/unpacked-6037.md`. No decompiled code is copied here.

## Token

- [ ] 6.0.3.7 stores one scrambled eight-byte string. Decoding it yields
      `g3d0311c`. The login constructor upper-cases that buffer and sends
      the eight characters as packet id 5. The prefix, the digits `0311`
      and the final `c` are constants in that string, not a function of
      the version words. A match is a first game packet whose id is 5 and
      whose eight bytes are `G3D0311C`.
- [ ] That token is the Windows 6.03r7 token the 6.03 folder already
      names. The Linux folder keeps `G3D0511C`. The 6.01 folder keeps
      `G3D0108A`. A 6.0.3.7 repro uses `G3D0311C`.
- [ ] 6.1.1.3 stores no string that decodes to `GNP1905C`, `gnp1905c`,
      `G3D0311C` or `g3d0311c`, and it has no constructor that loads an
      eight-byte token and sends id 5. `graalversion` returns 6.113. No
      builder turns 6.113 into the digits `1905`. How those digits and
      the final letter are chosen: not found. A repro must leave that
      formula unwritten.
- [ ] A 6.1.1.3 session can still be seen to write the eight bytes
      `GNP1905C` before it has read any server byte. `sendraw` is the
      native path that can put eight bytes on the socket with no header.
      The caller that supplies `GNP1905C` is not in the image: not found.
- [ ] The rest of the 6.0.3.7 login line after the id-5 token (account,
      password, platform word, machine fields, and whether id 37 follows):
      not found. The 6.01 and 6.03 folders send `linux` and four machine
      fields for their own tokens. That line is theirs.

## Framing

- [ ] 6.0.3.7 stays on the generation-5 framer. A decoded-string search
      finds no `setprotocol`, `sendraw` or `senddata`, and the image has
      no "Cannot send data" refusal. A fresh connection seeds both
      directions with the shared generation-5 seed, steps that state by
      the Borland multiplier plus the key, keeps the key to 7 bits, and
      starts the mode field at 3.
- [ ] 6.0.3.7 writes a numbered send as the id plus 32, the body, and a
      newline. A body that contains a newline is refused with "Illegal
      characters in the outgoing data", except ids 93 and 163, which skip
      that refusal. The out buffer is flushed once its length reaches
      4096 bytes. The id-50 prefix the 6.1.1.3 send function adds for ids
      93 and 163 is not in this send function. Where 6.0.3.7 would add
      it: not found.
- [ ] 6.1.1.3 constructs the connection on that same generation-5 framer
      (same seed, same step, key masked to 7 bits, mode field starting at
      3). It is the framer in use until a script calls `setprotocol`.
      `setencryptionout` is what leaves the generation-5 cipher. The
      names it accepts are `AES` and `RC4`. Any other name clears the
      cipher. The key and the initial value come from the caller. Which
      name, key or initial value a 6.113 session used: not found.
- [ ] `setprotocol(template)` replaces the framer. The header is as long
      as the template. Each of `I`, `L`, `T` and `E` is one big-endian
      field, one to four bytes wide, the width being the run of that
      letter. Bytes of the template that are not those letters stay
      zero, because the header is cleared before the fields are written.
      A numbered send is refused, with "Cannot send data, socket is not
      in a state where data can be sent", until the template contained
      both `L` and `T`.
- [ ] On a numbered send the fields are written in this order. `T` is the
      packet id. `I`, when the template has it, is a counter that starts
      at 1 and increases by one on each numbered send. `E` is 0, 1 or 2:
      1 when the body is at least 48 bytes and the packet id equals the
      id stored for compression, 2 when that same id matches and both
      compression flags are set and the body is at least 4096 bytes,
      otherwise 0. `E` 1 compresses with zlib. `E` 2 compresses with
      bzip2 at block size 5. `L` is the header length plus the body
      length after that compression. If the compressor returns nothing,
      `E` is written again as 0 and the original body is sent.
- [ ] The template string is not in the image, so the six captured bytes
      `01 02 00 01 17 fd` are not assigned to `I`, `L`, `T` and `E`. A
      repro must not emit a guessed template. The length rule is only a
      size check against that capture: a 6-byte header plus the 273-byte
      zlib member `78 9c` is 279, and 279 is `01 17` inside that header.
      Which of an `E` 1 compress or an already-zlib body produced `78 9c`:
      not found. What builds the inflated 262 bytes: not found.
- [ ] `senddata` is the numbered send. `sendraw` is the send whose id is
      −1: it appends the caller's bytes and adds no packet id, no header
      and no new counter value. On the generation-5 path a numbered send
      is still id plus 32, the body, and a newline.
- [ ] While 6.1.1.3 is on the generation-5 framer, ids 93 and 163 first
      send id 50. That body is a three-byte length of the original body
      length plus 2, capped at the raw-data cap, each byte a seven-bit
      group plus 32. The original packet follows as id plus 32, the body,
      and a newline. Those two ids skip the newline refusal. Any other
      generation-5 body that contains a newline is refused with "Illegal
      characters in the outgoing data". The out buffer flushes once its
      length reaches 4096 bytes.
- [ ] 6.1.1.3 login calls, in the image: look up `StartScript_Connector`,
      and if that object is missing look up `StartScript_Fail`. If
      `onCreated` exists, and the call's SSL argument is set, write
      `scriptip`, then `scriptsslcipher`, then `scriptsslsubject`, then
      `scriptsslissuer`, and then run the script. The login bytes that
      script sends: not found. The Mac 6.11 names `con.png`, `con.gs`
      and `conf.gs` are not plaintext in this Windows image, so that
      fetch order was not found.

## PLO/PLI

- [ ] 6.1.1.3 incoming ids are byte pairs from `setindatahandlers`. The
      first byte is the wire id. The second byte is the handler. 255
      clears the slot. 254 stores the script sentinel, and the native
      caller does not call a function for it. 253 saves the wire id on
      the connection and clears the slot. 252 saves the wire id in a
      second connection field and points the slot at one fixed function.
      0 through 94 select that index in a table of 95 native functions.
      Index 90 is empty. A handler byte of 95 or more, apart from 252,
      253, 254 and 255, is skipped. `clearindatahandlers` zeros all 256
      slots. Until a script sends pairs, no wire id has a handler. A
      match is a client that ignores every incoming id until those pairs
      arrive, and then dispatches only the pairs it was given.
- [ ] Native slot names are a separate note still being read. A repro
      must not ship a guessed 0–94 name table.
- [ ] Wire id 104 has no compiled case. It is handled only when a script
      pair names it, and that pair is not in the image. A generation-5
      incoming switch that cases on 104: not found.
- [ ] `setoutdatahandlers` fills a table of 256 ids with all-ones, then
      copies the script's list over it, at most 256 entries. While the
      connection is still on the generation-5 framer, a numbered send
      writes the id plus 32, the body, and a newline.
- [ ] 6.0.3.7's incoming game switch is the fixed 92-id list recorded for
      Linux 6.03r7, not a script table. The 6.01 folder's list is that
      set without id 111. Those compiled lists belong to 6.0.3.7 and to
      the two Linux folders. A 6.1.1.3 repro takes its ids from the
      script tables above.

## Properties

- [ ] 6.1.1.3 registers `tclient_setplayerprops`,
      `tclient_setotherplayerprops`, `tclient_setnpcprops` and
      `tclient_setbaddyprops`. A decoded-string search of 6.0.3.7 finds
      none of those names, and no `tclient_` name at all. 6.0.3.7 still
      has the property messages inside its fixed incoming switch.
- [ ] The bytes inside a player, NPC or baddy property stream were not
      compared between the two images. A field difference: not found.
- [ ] The 6.01 and 6.03 folders say no 6.x property parser was read, and
      they reuse an older set plus the three fields 78, 79 and 80. That
      is those folders' stand-in. It is not a layout read from 6.0.3.7
      or 6.1.1.3.

## GS2

- [ ] On both images, a file whose name ends in `.code` and whose buffer
      is shorter than eight bytes is rejected. A longer buffer is
      compared with the magic `GRESCR01`. In 6.0.3.7 the stored
      characters have one extra leading byte and the compare starts at
      the second character, so the eight bytes that match are still
      `GRESCR01`. The CRC32 covers the bytes after those eight. A cache
      flag other than 1 returns an empty script. A match rejects a short
      file, rejects a wrong magic, and rejects a CRC that does not cover
      exactly the bytes after the magic.
- [ ] Both unpacked images dispatch the same 152 cases. The lowest is 11
      and the highest is 242. There is no case above 242. Cases 54, 121,
      104, 190 and every case from 201 through 242 are present. Cases
      48, 49 and 200 are absent. 6.0.3.7 has no case that 6.1.1.3 lacks,
      and the other way around. A repro of either build runs that set
      and does not run 48, 49 or 200.
- [ ] Builtin names are a separate note still being read. The load events
      present are `onSendWantClassScript`, `onSendWantWeaponScript` and
      `onSendWantGaniScript`. Which builtin index calls which of those:
      not found.

## File requests

- [ ] The only `.gupd` file name in the 6.1.1.3 image is
      `basepackage.gupd`. It is compared with a name being opened and
      passed into the package helpers. `package_mainfiles.gupd` was not
      found, and no other `.gupd` file name was found.
- [ ] A numeric packet id for `basepackage.gupd`, or for any other
      package name, was not recovered. The wire id is whatever the
      script's outgoing table assigns, and that table is not in the
      image. Earlier Windows captures record id 23 for this file. This
      listing does not show that id, and the 6.01 and 6.03 folders do
      not send their base-file request. A 6.1.1.3 repro must not treat
      23 as a compiled request id.
- [ ] The script events `onSendUpdatePackage` and `onSendDownloadFile`
      are present. A match raises those events for a package send and a
      file download, with the id taken from the outgoing table.
- [ ] `game_console.log` is joined onto a directory path and opened. The
      log text is not in the analysis repo, so it supplied no request
      names.
- [ ] `creationtime.dat` is a name in both unpacked images. A packet id
      for the 6.1.1.3 write: not found. The 6.03 folder accepts id 111
      and writes no `creationtime.dat`. That is the folder's known gap,
      not a reading of this Windows image.

## Chat

- [ ] On 6.1.1.3, another player's line is the script event `onToall`,
      from `tclient_settoallmsg`, on the TCP incoming path. The event is
      registered with parameter letters `o` then `s`: a player object
      and the message text. The description begins "received a toall
      message: player obj". The rest of that sentence is truncated in
      the listing: not found.
- [ ] The function that feeds `onToall`, when the body is longer than
      two bytes, reads the first two bytes as an id, (first minus 32)
      times 128 plus (second minus 32). The third byte has to be at
      least 32. Its value minus 32 is the text length, and the text
      starts at the fourth byte. The event is then pushed with the
      player object for that id and that text. A body of two bytes or
      fewer does not push the event. No compiled caller of this function
      was found.
- [ ] No compiled case assigns a PLO id to `onToall`. The wire id is
      whichever pair `setindatahandlers` installed, and that pair is not
      in the image. A fixed PLO number: not found. The 6.01 and 6.03
      folders' compiled id 13 is their id, not a 6.1.1.3 constant.
- [ ] The UDP receive callback raises `onReceiveUDPData` and does not
      push `onToall`. A datagram must not be what delivers another
      player's line.
- [ ] `onSendToAllChat` is the outgoing slot, the client sending. It is
      not the line arriving from someone else. A string "received a PM
      from a player" is present. It was not traced to a wire id: not
      found.

## UDP

- [ ] 6.1.1.3 has a socket opener that takes a flag. With the flag clear
      it opens a stream socket and connects, and the connected state is
      the one that raises `onConnect`. With the flag set it opens a
      datagram socket, binds it, and marks the socket ready to send with
      `sendto`.
- [ ] The only caller of the datagram opener is the script method whose
      failure text is "Binding of port ". That method's plaintext name:
      not found. When its allow check fails it logs "Binding of port "
      plus the port and does not open a socket.
- [ ] When the open succeeds the method raises `onBind`, described as
      "the bind() call was successful", with an empty parameter list.
      When the open fails it raises `onBindFailed`, whose description
      begins "the bind() call failed, wrong port", also with an empty
      parameter list. The rest of that failure sentence is truncated:
      not found.
- [ ] The game connect path, the one that reaches the connected state,
      does not call the datagram opener. A 6.1.1.3 repro that is only
      connecting to a game server does not open a datagram socket.
- [ ] A datagram socket's receive path raises `onReceiveUDPData`. The
      parameter letters are `s`, `s`, `i`. The description begins
      "received UDP data: data, sender ip". The rest of that sentence
      is truncated: not found. That callback is not on the TCP connect
      path, and it does not raise `onToall`.
- [ ] The 6.113 captures have no client datagram on the TCP 14900
      remotes, and no datagram on UDP 14901. A repro must not add a peer
      channel on the connect path to match those captures. The datagram
      opener remains available to script.
- [ ] 6.0.3.7 also contains the strings "Binding of port ", `onBind` and
      `onReceiveUDPData`. Whether its game connect path calls the opener:
      not found. A 6.x connect path still does not open that socket.

## Torque cut

What these two images leave out. A 6.x repro matches when the same names
are absent.

- [ ] Both unpacked images are one `quattro_lib` program. The names
      present in both are `TSocket`, `TServerPlayer`, `TServerNPC`,
      `TServerLevel`, `OpenGL`, `Direct3DCreate9`, `fmod` and
      `GRESCR01`. `SimObject`, `GameConnection`, `TerrainBlock` and
      `horizSizing` are absent from both.
- [ ] `GuiWindowCtrl` and `GuiControlProfile` remain as strings in both
      images. They are not a Torque console: the console classes above
      are absent. On 6.0.3.7, `-printmap` writes Torque 2D datablock
      text and does not run a module.
- [ ] 6.1.1.3 adds the script methods `setprotocol`, `sendraw` and
      `senddata`, and the `tclient_*` handlers. A decoded-string search
      of 6.0.3.7 finds none of those names. The core under them is the
      same `quattro_lib` program.
- [ ] The 6.1.1.3 game connect path does not open a datagram socket. A
      UDP channel on the listed port plus one is the v3 to v5 Torque
      behaviour, and it is absent from this connect path.
