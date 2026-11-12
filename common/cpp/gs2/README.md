# GS2 script machine (Track B1)

The script machine the 4.x, 5.x and 6.x clients share: the engines'
`TScriptExecutionSpace` running compiled GS2 on a `TGraalVar`. The 4.04r2 to
5.12 engine library and the late-5 and 6.x Quattro program both run their
menus and every server script on it. Plan: [docs/v3-v6-plan.md](../../../docs/v3-v6-plan.md),
step B1.

```
make -C common/cpp/gs2 test     # unit tests, gs2-dis, gs2-scan
```

Written from Graal_analysis `client-internals/gs2-vm-from-engines.md` (the
static read of the 4.2.0.8, 5.0.0.7 and 6.00 engines). Opcode names follow
the Seihai opcode note, names only. No code from the open GS2 compiler or from
Preagonal.

## What it does

- **Loader** (`loader.cpp`): the four big-endian segments (event mask,
  function table with the `public.` prefix, string table, code), the `F0`
  to `F6` operand markers, and the load-time pair fusions into opcodes 200
  to 233. A segment type outside 1 to 4 or a truncated header ends the read,
  as in the engines; a string index outside the table is refused.
- **Profiles**: the 4.2 set (154 opcodes), 5.0 (adds 48, 49, 54, 121) and
  6.00 (adds 54, 121, 234 to 242). An opcode outside the script's profile
  stops it with `unknown opcode N for engine X`.
- **Objects** (`var.cpp`): a `Var` has its own value (number, string, object
  link or array) and named children, looked up case-insensitively.
- **Machine** (`machine.cpp`): value stack capped at 10000; calls into the
  script's own functions, another object's script, or a registered command
  (signature length is the minimum argument count; `adventure.` commands
  only from a variable whose name starts with `login`); parameters bound by
  opcode 51; return into the caller's slot; `Callstack overrun` past 9999
  frames; the name search (`with` objects, the frame, `thiso`, the level,
  the universe, then `playero`) and the reserved names; frame slots 0 to
  1023; the loop limit (the 10001st check stops the script); events queued
  per object (`created`, `initialized`, scheduled and cancelled names), at
  most 9999 queued; `sleep` on the 2D clock (0.05 a pass) with a timeout due
  below 0.0001; the error recorder (`GraalScript: ... in script of NAME`, at
  most 20 distinct texts).

## Checked against the original

`gs2-scan` finds the compiled scripts a program carries as zlib streams and
loads them. On the player's own 4.04r2 `GraalEngine.dll` (not in this
repository) it finds 14 scripts with 129 functions and 15,799 instructions,
the counts Graal_analysis `client-internals/linux-404r2-embedded-scripts.md`
records for that corpus. A 5.12 install's engine DLL gives 18 scripts, 116
functions and 15,008 instructions, all readable.

What those corpora use that this machine still refuses (B2):

| Opcode | 4.04r2 | 5.12 |
|---|---|---|
| 42 `new` object, 40 inline `new` | 294, 287 | 273, 270 |
| 37 array literal end | 92 | 87 |
| 47 | 25 | 19 |
| 119 translate | | 122 |
| 115 substring, 82 index, 84 format, 163 foreach | 6, 0, 0, 1 | 6, 4, 1, 2 |

## Not yet

Each is refused with `opcode N (name) is not implemented` instead of
guessed.

- [ ] Object creation and array literals (37 to 43), which the menus need
  first (B2)
- [ ] Opcode 47 (the engines read did not open its helper), 48, 49, 54, 121
  and 234 to 242
- [ ] `waitfor` (11): which stack values it takes is not read
- [ ] `in` ranges and objects (80, 81), `index`, `type`, `format` (82 to 84),
  `log`, `getangle`, `getdir` (92, 95, 96), `indices`, `link`, the object
  compare (99, 100, 104), `substring`, `tokenize`, `translate`, `positions`
  (115, 118 to 120), multi-dimensional arrays and the array methods (133 to
  142), `foreach` (163)
- [ ] The built-in command table and its signature letters (B2)
- [ ] Joined classes: the instruction walk across a class's code, and the
  event masks OR-ed in
- [ ] The second event-mask word and `needEvent`
- [ ] What an event runs: here `created` runs the script's `onCreated`; the
  read names the queued event but not the lookup
- [ ] Number to text: `%.15g` here; the engines' format is not read
- [ ] `null` pushes an empty string; `this` is the newest `with` object or
  `thiso`; plain divide by zero gives 0 like the fused divide. Each is a
  reading, not an observed result
- [ ] `vecx`/`vecy` use the GS1 direction table (up, left, down, right);
  the engines' four entries are not read
- [ ] Running the 4.04r2 menus to `initialized` (B3, after B2)
