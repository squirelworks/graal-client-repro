# 1st Graal movement evidence handoff

## Attribution and input identity

Evidence key: `GRAAL-FIRST-MOVEMENT-20261109-01`.
Research date: 2026-11-09. Supplier: the **Prepare Graal REA analysis**
research chat, consulted at the owner's request. The researcher confirmed
this address-free handoff for implementation review on 2026-11-09 and
reported rechecking the executable SHA-256 before supplying it. The retained
research record's researcher-supplied SHA-256 is
`aeca02441524144218e7add54122ef760f72287ae9803ca03ebe1fa1ab0006fc`.

The researcher supplied the following identity for the Windows x86 client:

- Name: 1st Graal, the build represented by this folder.
- Executable size: 654,336 bytes.
- SHA-256: `03d8121711f41ac7b5a6e3fe549145d8fdfd44d22040f6706329ae83c6a1a37b`.
- MD5: `07452f8941fdfcdce878b035156e701c`.

The researcher reports asserting the input digest before inspecting the
movement instructions and referenced numeric tables. This implementation
PR and its supervisor have **not independently verified the original
executable, digest, or instruction-level findings**. Matching the existing
catalogue identity identifies the supplied research input; it does not
independently authenticate a vendor release.

This handoff is original behavior prose. It includes no original source,
decompiled code, executable bytes, screenshots, internal addresses or
private retrieval locations.

## Researcher-supplied static observations

Facing order is up, left, down, right. Ordinary candidate steps are,
respectively, (0, -0.5), (-0.5, 0), (0, +0.5), (+0.5, 0) tile units.
Coordinates and constants in this bounded finding are double precision.

Six blocked-point tests are collected from the candidate position in order:

- Up: X offsets 0.6, 1.4, 1.6, 2.4, 2.525, 0.475; Y offset 1.05.
- Left: Y offsets 1.1, 1.9, 2.1, 2.9, 3.025, 0.975; X offset 0.55.
- Down: the up X offsets; Y offset 2.95.
- Right: the left Y offsets; X offset 2.45.

Probes are numbered 0 through 5. Probe 0 blocked with probes 2, 3 and 4
clear selects the positive free-axis nudge. Probes 0 and 1 clear, probe 3
blocked and probe 5 clear select the negative nudge. Each nudge is 0.125
tiles. Up/down nudge X; left/right nudge Y. These predicates do not require
all six probes to be clear, and probes are not recollected after nudging.

If any of probes 0 through 3 blocks, the forward facing-step delta is
undone; a selected sideways nudge remains. Facing-specific blocked-step
snapping is separate from this geometry correction.

## Method, inference and limits

The researcher reports decoding the referenced constants as IEEE-754
little-endian doubles and cross-checking candidate construction, ordered
probe collection, branch predicates and coordinate updates directly
against instructions, rather than relying solely on recovered pseudocode.
That is a researcher-supplied static finding, **not runtime observation**.

The implementation inference is narrow: this folder should use this
build's own probe constants and eighth-tile nudges instead of the
later-build constants previously present. The reproduction's synthetic
board tests independently demonstrate the changed behavior in the new
code; they do not execute or validate the original client.

This PR does not establish full pushing or hop behavior, exceptional state
gates, every collision-object predicate, mounted behavior, input-to-update
cadence, or complete gameplay fidelity. The reproduction's final near-grid
snap and tile classification remain inherited and unverified by this
bounded finding. No measurements from other builds are substituted.

## Relationship to public Appendix E307

The older public Graal_analysis Appendix E307 asks for the exact probe,
nudge and step tables of 1st Graal and 1.39. The research chat confirmed
that the publication checkout had not incorporated this newer finding and
could not provide a verified public commit containing it. The open public
question therefore remains the publication state; this handoff is a
separately attributed, newer researcher-supplied result for 1st Graal only.
It does not claim that public E307 has been closed or independently
resolved by the supervisor, and it establishes nothing about 1.39.
