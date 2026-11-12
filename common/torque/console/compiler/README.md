# TorqueScript compiler (DSO v33)

The Graal 3.x client compiles every plain `.cs` it executes: the root
`main.cs`, the `prefs.cs` and `config.cs` it exports on exit, and console
(F2) input. This component is that compiler. It turns TorqueScript source
into a `Torque::DsoBlock` (`../dso.hpp`) using Graal's DSO v33 opcode
numbering, so the loader, the instruction decoder and the VM handle source
and shipped `.dso` scripts the same way. It is part of
[#172](https://github.com/squirelworks/graal-client-repro/issues/172) and is
not yet wired into a boot host.

```
bool Torque::compile_script(const std::string& source, DsoBlock& out, CompileError& error);
std::vector<std::uint8_t> Torque::write_dso(const DsoBlock& block, FloatOrder order);
```

`compile_script` leaves `out` unchanged on failure and reports a 1-based line.
`write_dso` produces the on-disk layout the client writes next to a compiled
script (little-endian floats for the Linux 3.04 profile, big for the PPC
profile). `build/ts-compile IN.cs OUT.dso [--big-floats]` does both from the
command line.

Build and test with `make -C common/torque/console/compiler test`; the
`torque-dso` workflow runs it on Linux (also under address/undefined
sanitizers) and Windows.

## What it compiles

Statements: `function` (with `Namespace::` and inside `package`), `if`/`else`,
`while`, `for`, `do`/`while`, `switch` and `switch$` (`case a or b:`,
`default:`), `break`, `continue`, `return`, `datablock`, expression
statements. Expressions: number, string and tagged-string literals, `true` /
`false`, bare words (loaded as identifiers), `%local` / `$global` variables
with `[a, b]` subscripts, fields and field arrays, function, method,
`Namespace::` and `Parent::` calls, `new Class(name : parent, args) { slots;
new ...; }`, `= += -= *= /= %= &= |= ^= <<= >>=`, postfix `++` / `--`,
`?:`, `|| && | ^ & == != $= !$= < <= > >= @ SPC TAB NL << >> + - * / %` and
unary `! ~ -`, with the published TorqueScript precedence.

## Code shapes

Each expression has a natural type (none, unsigned, float, string) and is
compiled for the type its consumer wants, with one conversion opcode when they
differ. The shapes below were read off the shipped Graal files, not taken from
engine source:

- Arithmetic is float, `% & | ^ << >>` and comparisons take unsigned or
  float operands as the operator needs; the **right operand is compiled first**.
- `if`/loop tests use `JMPIFNOT` for an unsigned test and `JMPIFFNOT` for
  anything else; loops test at the top and again at the bottom (`JMPIF` back).
  `&&` / `||` use `JMPIFNOT_NP` / `JMPIF_NP`. `!` uses `NOTF` on a float or
  string operand and `NOT` otherwise.
- `return;` is a bare `RETURN`; a function body and the file each end in an
  implicit `RETURN`.
- `-1` is `1.0` then `NEG`; a number literal compiled where a string is wanted
  becomes a string constant.
- A string value being stored into an array element or field stays on the
  string stack (`ADVANCE_STR` … `TERMINATE_REWIND_STR`) while the target is
  selected. `x++` and `x op= v` select the target once with
  `SETCURVAR_CREATE`.
- Function calls use `CALLFUNC_RESOLVE` (also with a namespace); method and
  `Parent::` calls use `CALLFUNC` with call type 1 and 2.
- `new` at the root loads `0`, then pushes class, name and arguments;
  `CREATE_OBJECT` names the parent (empty when none) and jumps past
  `END_OBJECT` on failure. Slots use `SETCUROBJECT_NEW`.
- String constants and floats inside a function body go to the function
  tables (one shared set per file); identifiers always go to the global
  string table. Both string tables and the float tables are deduplicated.
- Names enter the global table in this order: a call's function name before
  its arguments, an object's parent name before its class, a slot's name
  before its value, an assigned variable after its value.
- Identifier groups are written newest first; within a group the first use
  leads and the later uses follow newest first.
- A function parameter keeps its name if that name is anywhere in the file's
  global string table when compilation ends; otherwise it points one past the
  table end (the "unused parameter" sentinel).
- Statements inside function bodies (nested ones included, a `for` step not)
  get one line/ip pair each; top-level statements get none.

## Evidence

- **Byte-exact oracle.** The real 3.04 client compiled its exported
  `prefs.cs` (104 lines) and `config.cs` (18 lines) into `.dso` files during
  the stage 0 lab capture. This compiler reproduces both files byte for byte.
  The files are not distributed; `tests/compiler_test.cpp` compares them when
  `TORQUE_ORACLE_DIR` points at a folder holding the pairs and skips otherwise.
- **Shipped-script corpus (lab only).** The 39 shipped 3.04 Linux and 44 3.153
  Mac `.dso` files were decompiled with the Graal_analysis tool and the output
  recompiled here. 26 of 39 and 28 of 44 files come out byte-identical (string
  tables, floats, code and identifier groups; line numbers are lost by the
  decompiler). The rest contain `?:` or goto shapes the decompiler does not
  rebuild as source; of the functions that do come back as source, all match
  except five whose decompiled text is itself wrong (missing parentheses,
  `x += v` printed as `x = x + v`, an assignment inside a condition printed as
  a separate statement). No original script, decompiled text or compiled file
  is in this repository.

## Not yet verified against the original

- [ ] Which line a multi-line statement records (the first token's line here).
- [ ] Shapes the shipped files never use: `do`/`while`, `switch`, string
      literals compiled as numbers (folded at compile time here), float
      literals compiled as strings (`%g` text here), and whether tagged and plain
      strings with the same text share a table entry (they do here).
- [ ] Interning order for `Namespace::fn()` calls (name before namespace here).
- [ ] Error text and recovery: the original's syntax-error messages are not
      reproduced, and the nesting limit (256) is a reproduction policy.
- [ ] Wire `compile_script` into `exec`, `eval` and the console once the VM runs
      full code blocks.
