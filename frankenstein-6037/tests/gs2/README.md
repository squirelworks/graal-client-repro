# GS2 probes for the 3D classes

Copies of three conformance probes from Graal_analysis
(`torque/conformance/scripts/`, our own GS2, no original script), with the
bytecode seihai-core's compiler wrote for each: the text after
`//#CLIENTSIDE`, `compile::compile_with(src, Language::Gs2, Options { mode:
Mode::Legacy, lambda_id: Some(1), no_var_cache: false })`, then
`Script::write()`, at seihai-core `efa3494`, the way seihai-gserver compiles
a `weapon3d` for a 6.x client.

`tests/frankenstein_test.cpp` runs them on the 6.x GS2 machine with the 3D
classes and checks the reports against the real 5.12's answers to the same
probes (conformance `results.tsv`, C030 and C026, 5.12 Windows) and C009's
rule for `timevar3`.

| File | Conformance case |
|---|---|
| `probe_gameobject.gs2` | C030: defaults and formats of the GameObject and SceneObject members |
| `probe_typed.gs2` | C026: a slice of the typed member table |
| `probe_timevar3.gs2` | C009: `timevar3` advances |
