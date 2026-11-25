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

## g3d-fuzzcases

Makes malformed level content for a lab run against the real client,
one change per case, from a seed shape you supply. This is strand 3 of the
client-mapping plan: serve the cases from our own gserver to a client in a
lab VM, then write down what the client did with each one.

```
make tools
./build/g3d-fuzzcases --random 40 seed.3ds out/3ds
./build/g3d-fuzzcases seed.dts out/dts
./build/g3d-fuzzcases seed.dif out/dif
```

The structural cases come first:

- **`.3ds`:** for the first chunks of each chunk id (`--per-chunk`), it
  changes the chunk's length (0, 5, one less, one more, huge, to the end of
  the file), renames the chunk to an unknown id, and cuts the file at the
  chunk and in its middle. For vertex, face and texture-coordinate chunks
  it changes the count (0, one more, 65535) and sets NaN and far-away
  values. It also makes out-of-range and degenerate face indices.
- **`.3ds` names:** material, face-group and texture names are changed to
  upper case, empty, 300 characters, and missing their terminating NUL.
  Texture names also get every image extension and none, a folder, a
  parent folder, a space, and a texture the server lacks. Renamed strings
  keep every enclosing chunk length right.
- **`.dts`:** every version from 0 to 27, plus 255, and the exporter
  version. The block's word counts and stream starts. Each shape-header
  count set to -1, a huge value and 0. A broken first guard. Cuts inside
  and after the block.
- **`.dif`:** the resource version, the preview flag, the detail count,
  the interior version, and cuts.

`--random N` adds N cases of one to six random byte changes, repeatable
with `--seed`. A case that leaves the file as it was is dropped.

It writes `out/<prefix>NNNN.<ext>` and `out/manifest.tsv`. The manifest
has one row per case, with the change in words, its size, and what our
own reader makes of it (`ok meshes M triangles T materials K` or
`refused: <error>`). The last column is empty, for the client's
reaction. The seed is game content, so the cases are too. Keep them, and
the manifest, out of the repository.
