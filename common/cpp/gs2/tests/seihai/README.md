# Scripts compiled by Seihai's GS2 compiler

`tests/seihai_test.cpp` runs these on the machine. Each `.gs2` is our own
source. Next to it is the `.gs2bc` that seihai-core's compiler wrote for it:
`compile::compile_with(src, Language::Gs2, Options { mode: Mode::Legacy,
lambda_id: Some(1) })` and then `Script::write()`, at seihai-core `b3911d5`
(#166, the official output shape). No original Graal script or capture is
here.

To refresh the bytes after a compiler change, compile each `.gs2` the same
way and write the result over its `.gs2bc`, then run
`make -C common/cpp/gs2 test`.

| File | What it checks |
|---|---|
| `semantics.gs2` | Arithmetic, `pow`, joins, `for`, `foreach`, `in`, `switch`, calls, `format`, `NULL`, `&&`/`\|\|` chains, labeled loops, members, objects, `params`, string methods, the conditional, `while` and `obj.link()`, each printed with `echo`. It also holds the variable cache (opcodes 45 to 47) |
| `helper.gs2` | A class with a plain and a public function |
| `lambdas.gs2` | Function values: kept in `temp`, passed by name and inline, and set as members of an object, where `this` is that object |
| `joiner.gs2` | `join`, a class function through `this` and by name, `setTimer` and `scheduleevent` |
