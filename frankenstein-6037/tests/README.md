# Tests

`frankenstein_test.cpp` (`make test`):

- the `3 ` marker rule;
- the stand-in view (sky and ground, the player's box, the inset);
- over loopback: a Login server takes the 6.03r7 login and sends 178 to
  `3 Lab`; the client logs in to the game server on TCP with the 6.03r7
  token and runs the 5.12 link on the next port over UDP against a server
  that answers the handshake and replays the recorded protocol-24 session
  (`common/cpp/graal3dengine/tests/vectors.hpp`), to login step 6 with two
  ghosts; the next frame shows the view with the player's object; closing
  sends the 3D disconnect.

`../test.sh` runs it, stages the program and checks the manifest
(v6.037, v5.120 from the 5.12 repro `graal-5.12-G3D14097`, UDP enabled,
placeholders `<server>`, `<port>`, `<md5>`). Nothing here opens a public
host. `FRANK_SHOT=FILE.png` saves the view the test drew.
