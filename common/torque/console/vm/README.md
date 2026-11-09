# Bounded Torque code-word executor

First execution slice for [#172](https://github.com/squirelworks/graal-client-repro/issues/172),
using the merged DSO reader through `execute_dso`. `execute_words` takes a vector of
decoded 32-bit words and returns a string result, instruction count and word
position, or a typed error. It has no files, network, global state or native
call hooks. Each invocation owns a fresh integer stack and string result.

The supported subset is `LOADIMMED_UINT` (65), `UINT_TO_STR` (63),
`UINT_TO_NONE` (64), `JMP` (12), `JMPIFNOT` (7), `JMPIF` (9) and `RETURN`
(13). Loads push the immediate word; conversion pops an integer into the
current string; discard pops it; conditional branches pop their condition;
return yields the current string. Integer loads preserve all32 payload bits;
conversion interprets them as signed32 decimal (`0x80000000` becomes
`-2147483648`, `0xffffffff` becomes `-1`). Branch operands are absolute word indices.

Opcode numbers and operand widths come from the published behavior-only
[Graal 3.x scripting description](https://github.com/squirelworks/Graal_analysis/blob/main/torque/scripting.md#graals-opcode-table).
Selected execution behavior now follows the published
[Linux3.04 seven-operation static contract](https://github.com/squirelworks/Graal_analysis/blob/fbec314cf32a7d7e988581553637c9540fc6d546/torque/linux-304-seven-operation-contract.md)
and its independently authored conformance vectors (analysis PR348).
It confirms bit-preserving loads, consuming branches/discard, absolute
word targets, signed decimal conversion and return of the current string.
This is exact-build researcher-supplied static evidence, not an original-client
runtime oracle or a cross-platform semantic guarantee. Fresh-state, errors,
returned-storage lifetime and instruction-count rules remain reproduction
policies; comparison on the original client remains pending. No proprietary
TGE source, recovered code or original script body is used.

## Validation and limits

The executor validates the entire supported instruction stream before running:
unknown instructions (including unreachable ones), missing operands and jumps
outside code or into operands fail before any instruction is executed. It does
not guess operand widths for unsupported instructions. Falling off the end
is an error, not a successful return. Error results clear any partial string.

Code is limited to 1,048,576 words. Caller-specified budgets default to 10,000
instructions and 1,024 integer values. A zero instruction budget executes
nothing; a zero stack budget permits a plain return but refuses a push.
Instruction counts include a fetched instruction that fails at runtime, and
exclude validation and instructions refused by the step budget. These are
reproduction validation policies, not recovered original error handling.

Run `make -C common/torque/console/vm test` in CI or a cloud build environment.
The `torque-vm` workflow covers only this component on Windows/Linux/macOS;
Linux also runs address/undefined-behavior sanitizers. macOS runner queues
are nonblocking during development under the owner's policy.

The hand-authored branch fixture `{65,0,7,8,65,99,63,13,65,42,63,13}` must
return `"42"` in five instructions at word 11. Changing its condition to 1
must return `"99"` in five instructions at word 7. The literal word stream,
expected results and counts are independent of a compiler, loader or encoder
under test. The seven independently authored published static-derived vectors
also check signed-format boundaries, one-entry discard, condition consumption
and an absolute jump preserving the lower stack value. Other tests cover both conditional paths, unconditional jumps,
stack consumption, fresh invocation state, exact budgets, infinite loops,
stack growth, unsupported instructions, operand/target validation and
discarding a partial result on failure. No external client install is needed.

## Serialized execution

`execute_dso(bytes, float_order, limits)` validates a complete DSO33 file with
the shared reader, then executes its decoded words using the same bounded VM.
It returns separate format, unresolved-relocation and VM failure statuses.
Check `DsoRunResult::returned()` before using the execution result; the nested
VM result is not run on format or relocation failure. Format diagnostics retain
the reader's byte position, while VM diagnostics use decoded word positions.

Identifier groups with any use sites are rejected before execution: there is
no linker or interning implementation yet. Unused groups are allowed. String
and float tables are parsed but the seven supported operations do not read
them. The explicit float profile does not certify platform execution fidelity.
Whole-file validation, relocation rejection and these statuses are reproduction
composition policies, not claims about original-client error handling.

The serialized test uses a literal 40-byte synthetic file with an escaped
integer payload. It verifies the signed result, every truncated prefix, trailing
bytes, unsupported code, execution/stack budgets and a valid unresolved-use
fixture that must execute zero instructions. Existing word-level branch tests
remain independent. No original file or native callback is used.

## Remaining gates

- [x] Execute the bounded integer/branch/return subset with deterministic results.
- [x] Reject malformed/unsupported code and bound execution and stack growth.
- [x] Match the published selected Linux3.04 static contract and seven vectors.
- [ ] Compare those vectors at runtime against the exact original build.
- [x] Connect decoded DSO blocks through a bounded serialized execution API.
- [ ] Link identifier uses and execute original runtime conformance fixtures.
- [ ] Add native-call, object/namespace, function, float/string-table and lifecycle contracts.
- [ ] Integrate the verified shipped boot sequence, GUI/input and gameplay.

This does not execute a complete shipped DSO or constitute a working client
VM. It deliberately has no success stubs for unsupported instructions.
