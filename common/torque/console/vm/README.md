# Bounded Torque code-word executor

First execution slice for [#172](https://github.com/squirelworks/graal-client-repro/issues/172),
independent of the DSO reader in PR #181. `execute_words` takes a vector of
decoded 32-bit words and returns a string result, instruction count and word
position, or a typed error. It has no files, network, global state or native
call hooks. Each invocation owns a fresh integer stack and string result.

The supported subset is `LOADIMMED_UINT` (65), `UINT_TO_STR` (63),
`UINT_TO_NONE` (64), `JMP` (12), `JMPIFNOT` (7), `JMPIF` (9) and `RETURN`
(13). Loads push the immediate word; conversion pops an integer into the
current string; discard pops it; conditional branches pop their condition;
return yields the current string. Branch operands are absolute word indices.

Opcode numbers and operand widths come from the published behavior-only
[Graal 3.x scripting description](https://github.com/squirelworks/Graal_analysis/blob/main/torque/scripting.md#graals-opcode-table).
The execution contract follows this repository's parked `TqVM.pas` experiment
for this narrow subset. That experiment is not an original-client oracle:
branch stack effects, return behavior and unsigned decimal formatting remain
**provisional** until an exact-build original-lab comparison is published.
No proprietary TGE source, recovered code or original script body is used.

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
under test. Other tests cover both conditional paths, unconditional jumps,
stack consumption, fresh invocation state, exact budgets, infinite loops,
stack growth, unsupported instructions, operand/target validation and
discarding a partial result on failure. No external client install is needed.

## Remaining gates

- [x] Execute the bounded integer/branch/return subset with deterministic results.
- [x] Reject malformed/unsupported code and bound execution and stack growth.
- [ ] Confirm the provisional semantics against the exact original build.
- [ ] Connect decoded DSO blocks after the independent reader PR merges.
- [ ] Add native-call, object/namespace, function, float/string-table and lifecycle contracts.
- [ ] Integrate the verified shipped boot sequence, GUI/input and gameplay.

This does not execute a complete shipped DSO or constitute a working client
VM. It deliberately has no success stubs for unsupported instructions.
