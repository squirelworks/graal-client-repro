# Graal 5.31r4 (scaffold)

A scaffold for the late-5 client, in Delphi (Object Pascal). The original
images are one `quattro_lib` executable each (5.30r3 and 5.31r4). This
program names that cut, checks the classic line and the length header, and
exits. It does not play the game.

**Login token: tested against the real client.** The original was run in the lab and `G3D26090` was seen in its login on the wire (lab run); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- First scaffold of this folder. File versions 5.303 and 5.314, one
  executable, `quattro_lib`, no Torque link, and no stored token. The
  outbound line is opcode plus 32, the body, and a newline, flushed once
  the buffer is longer than 4095 bytes. A newline in an ordinary body is
  rejected. The two internal opcodes are recognised and not given a
  guessed wrap. Inbound frames use the 2-byte length and the long form.
- The login line sends `G3D26090` for 5.30r3 and 5.31r4. The images
  store no eight-character literal. The line still carries this
  documented token.

## What's new in v0.0.4

- This folder was not in that release.

## Not yet

Client-to-server opcode numbers, the length-wrap bytes,
the second inbound failure, and every property and script body. See the
folder README.
