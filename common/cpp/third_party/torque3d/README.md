# Torque3D: the bit-stream string coder's table

Graal's Torque builds (3.04 to 5.12) code strings on the UDP link with
Torque's fixed Huffman tree. The tree comes from one 256-entry character
frequency table, the same in every Graal build (Graal_analysis
`torque/udp-session.md` §2, `torque/open-source-lineage.md`).

`huffman.hpp` / `huffman.cpp` hold that table and the tree it builds. The
table is stock Torque's, as published in the MIT-licensed Torque3D source
(`Engine/source/core/stream/bitStream.cpp`), and the tree is built the way
that source builds it (the same pairing and tie order, so the codes match
bit for bit). The copy was taken through Graal_analysis
`torque/tools/tbits.py`, which states that origin. Its copyright notice and
licence are in [LICENSE.txt](LICENSE.txt) and travel with it.

Nothing else from Torque3D is here. TGE 1.x source (proprietary) was not
read or used. `common/torque/PROVENANCE.md` names these files.
