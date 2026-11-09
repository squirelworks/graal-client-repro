# Native function dispatch seam

Independent C++ console slice toward #172. `NativeFunctions` registers real
callbacks and invokes them with ordered byte-string arguments, rather than
logging command names as if their bodies ran. It is not yet wired to the
DSO reader, bytecode executor, client boot hosts or original command bodies.
It builds independently alongside the merged DSO reader and bounded VM.

The published [Linux3.04 argument-count contract](https://github.com/squirelworks/Graal_analysis/blob/main/torque/engine-304.md#argument-counts)
states that counts include the command name and max0 means no upper bound.
This component implements that convention for functions: callers supply
script arguments; the callback receives the command name at argv0 followed
by those arguments. Min/max validation runs before the callback. Methods
would also receive an object argument, but methods are deliberately outside
this slice; no object or binary callback ABI is invented.

## Reproduction API and policies

- Keys are exact `(namespace, name)` pairs. No case folding, inheritance,
  package lookup, overloads or fallback is implied. Those require the later
  VM/namespace contract. Duplicate keys fail without replacing callbacks.
- Callbacks return a string. Unknown functions, bad arity, invalid names,
  resource limits and callback exceptions have explicit statuses and no
  result string. Exception conversion is a reproduction policy.
- Registered callback state persists between calls. The active callback
  remains owned while it unregisters itself; later lookup then fails. The
  registry is noncopyable so separate registries do not silently share state.
- Limits are4096 functions,1024 total arguments including the command,1MiB
  aggregate argument bytes including the command, and1024 bytes per key part.
  Min must include at least the command; finite max must be at least min.
  Max0 is variadic subject to the resource policy. Names cannot contain NUL;
  argument strings preserve embedded NUL and arbitrary bytes.
- These registration, lookup, lifetime and failure policies are independently
  chosen API behavior, not original-client fidelity claims. Callbacks are
  trusted native code; threading, recursive-call budgets and VM scheduling
  are not provided by this registry.

## Checks

Run `make -C common/torque/console/native test` in CI/cloud. The dedicated
`torque-native` workflow checks this component on Linux/Windows/macOS and
uses Linux address/undefined-behavior sanitizers. No local capture-PC build.

Independent test callbacks record exact invocation order/bytes, return a
known value, maintain a counter, unregister themselves and throw a fixture
exception. Tests also cover min/max and variadic arity, rejected duplicates,
namespace isolation, no implicit case folding, callback non-invocation after
validation failure, resource boundaries and reusable registration slots.
No original command, script, executable, native layout or game asset is used.

## Remaining gates

- [x] Register and invoke functions with command-inclusive arity checks.
- [x] Preserve callback state and active lifetime with explicit failure results.
- [ ] Add the evidence-backed VM call adapter after this registry is reviewed.
- [ ] Verify original lookup, native argument/result and namespace behavior.
- [ ] Add real builtins and object-method/lifecycle contracts with their own tests.

Synthetic callbacks prove this API runs, not that a Graal builtin is implemented.
