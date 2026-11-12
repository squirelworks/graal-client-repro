# Provenance of the Torque layer (#110)

What this tree was written from, and what it was not. The language decision (C++ for the shared TGE 1.2-style reconstruction, recorded in #110) does not change any of this.

## Summary

- **No engine source is in this tree.** No Torque Game Engine (TGE) 1.2 source, no Torque3D source, no other third-party engine code, and no code recovered from a Graal binary.
- **Everything here was written from behaviour-only notes** in [Graal_analysis](https://github.com/squirelworks/Graal_analysis) (the `torque/` and `protocol/` notes named below), from captures the project took itself, or as independently chosen rebuild policy. Each component's README says which.
- **Nothing here claims any proprietary source has been cleared.** Where a README says "stock TGE", that is a description of the original binaries: the class and command names the notes read out of the clients. It does not mean TGE code was consulted or copied.

## Per component

| Component | Written from | External engine material |
|---|---|---|
| `console/` (DSO v33 reader, `dso-inspect`) | The [DSO v33 format description](https://github.com/squirelworks/Graal_analysis/blob/main/torque/scripting.md#file-format-version-33) in Graal_analysis. Tests use a hand-written 90-byte fixture. | none |
| `console/vm/` (bounded executor) | The opcode table in `torque/scripting.md` and the [Linux 3.04 seven-operation static contract](https://github.com/squirelworks/Graal_analysis/blob/fbec314cf32a7d7e988581553637c9540fc6d546/torque/linux-304-seven-operation-contract.md) with its independently authored conformance vectors (Graal_analysis PR 348). Execution limits are rebuild policy. | none (its README: "No proprietary TGE source, recovered code or original script body is used.") |
| `console/engine/` (console engine, `tq-boot`) | The opcode table in `torque/scripting.md`; the native surface in `torque/study-torque-clients.md` section 5 and `torque/engine-304.md`; stack behaviour from operand order in the shipped 3.04 scripts; message format strings from the 3.04 Linux engine's string table; the stage 0 capture of the original 3.04 (console log, open order, exported prefs and key map) for checking. Input and the console (`input304.cpp`) follow what the shipped 3.04 bind, console and remap scripts call and expect; routing order and focus are policy until the lab key script is run. Each item is tagged observed or policy in its README. Tests are hand-assembled. | none |
| `console/compiler/` (TorqueScript compiler, `ts-compile`) | The opcode table in `torque/scripting.md`, the public TorqueScript grammar, and lab comparisons: the real 3.04 client's own compiled `prefs.cs.dso` / `config.cs.dso` (reproduced byte for byte) and recompiled decompiler output of the shipped 3.04 and 3.153 scripts. Those files stay in the lab; tests use hand-written scripts and expected words. The parked `TqCompile.pas` was not used. | none |
| `console/native/` (native function registry) | The [Linux 3.04 argument-count contract](https://github.com/squirelworks/Graal_analysis/blob/main/torque/engine-304.md#argument-counts). Lookup, lifetime and failure rules are chosen API behaviour. | none |
| `shared/` (first-frame codec, loopback transport) | Graal_analysis `protocol/` notes and the project's own wire captures, as named in each host's `login.hpp`. Uses the system zlib. | none |
| `host304/`, `host4208/` | The notes named in each host's `src/*.hpp` comments (for example `protocol/v3x-clients.md`, `torque/4208-engine.md`). The bodies of unknown controls only log. | none |
| `gui/` C++ (PNG reader, `.gft` reader, bitmap arrays, software canvas) | The `.gft` header in [`torque/study-torque-clients.md` §4](https://github.com/squirelworks/Graal_analysis/blob/main/torque/study-torque-clients.md), the PNG specification, and the project's own lab reads of the 3.04 caches, theme PNGs and stage 0 screenshot (see `gui/README.md`). Tests use hand-built fixtures. Blending and limits are rebuild policy. | none |
| `TqCode.pas`, `TqCompile.pas`, `TqVM.pas` (parked) | `torque/scripting.md` | none |
| `gui/` C++ control renderer (`profile`, `render`, `tq-shot`) | The 3.04 install's own profile, theme and `.gui` scripts run on the console engine, the theme PNGs, and the project's lab comparison with the stage 0 main-menu screenshot (see `gui/README.md`, "Stock controls"). Each rule is tagged there as observed or rebuild policy. Tests use hand-built fixtures. | none |
| Module stubs (`console/`, `sim/`, `gui/`, `actionmap/`, `gbitmap/`, `math/`, `game-tge/`, `net-torque/`, `guigraal/`, `gameobject/` `Tq*.pas`) | The notes in each unit's `Notes:` header. They are empty units: no types, no state. | none |
| `manifests/`, `CUTS.md` | The per-binary notes listed in [README.md](README.md#notes-this-scaffold-was-read-from) | none |

## Third-party code that is used

| Material | Where | Licence |
|---|---|---|
| zlib (system library, linked, not vendored) | `shared/`, both hosts, `gui/` | zlib licence |
| C++ standard library, Free Pascal RTL | everywhere | their own licences, as shipped with the compiler |

## Engines this tree does not use

- **TGE 1.2** was a commercial SDK and is not open source. None of its source is in this repository, and none was used to write it. The rebuilt classes are named after the classes the original Graal binaries register, as the notes record.
- **Torque3D** (the later, MIT-licensed engine) is not a base for this work (HANDOFF-CURSOR.md: "No modern Torque3D base"). The project compared Torque3D with Graal's engine as research, outside this repository. No Torque3D code is here. If any Torque3D code is ever brought in, its copyright notice and MIT licence text must travel with it, and this file must name the files.

## Keeping this current

A PR that brings in external engine material, or that relies on a source not listed above, adds a row here in the same PR, with the source, its licence, and the files it touches. The repository's own licence is still undecided (#116), so nothing above grants or assumes one.
