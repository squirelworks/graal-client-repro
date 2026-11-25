# graal3dengine tools

Command-line helpers built on the library's own code. They are not part of
`Graal3DEngineRepro.dll`.

## g3d-replay

Reads a recorded 3D session back. Point it at a packet capture taken next
to a real client (pcap or pcapng; Ethernet, Linux cooked, raw IP or BSD
loopback; IPv4):

```
make tools
./build/g3d-replay capture.pcap
./build/g3d-replay --at 60 --render frame.png --size 1024x768 --res path/to/levels3d capture.pcap
```

It finds the client's challenge request (`0x1A` and the connect sequence),
makes a `Link` with that sequence in replay mode (`LinkLogin::replay`: the
server's acks name the recorded client's packets, so they are not checked
against the link's own), and feeds it every UDP datagram the server sent
to that client, in capture order. Then it prints:

- the session's addresses and connect sequence, how many packets each side
  sent and the login step the link reached;
- Graal's class table from the connect accept;
- the log, login steps and server texts with times from the challenge
  (`--quiet` leaves these out);
- the commands, the server time, the control object, the camera and the
  field of view;
- every ghost held at the end, with the fields this library reads
  (`GameObject`, `Camera`, `Sun`, `Sky`; other classes by name).

`--render` draws that world with `render/` from the files under each
`--res` folder (the client's `levels3d`, for example) as the camera ghost
saw it. `--at` stops that many seconds after the challenge, to look at an
earlier moment. `--port` picks the session by the server's UDP port when
the capture has more than one; `--protocol` is 24 unless given.

TCP segments are read but not used: the game connection's downloads and
login stay with the engine library.

Captures and the files a server sends are that server's content. Keep
them, and what this tool prints or draws from them, out of the repository.
