# Issue comments (not posted)

`gh` cannot write. These are the comments this scaffold would leave. Topics are taken from the issue text. No issue was skipped.

## 151

The observatory surface is the module tree under `common/torque/`, with `CUTS.md` and `manifests/` saying which era links which directory. This change does not answer the observatory questions in code: there is no `.dso` loader here, no sim behaviour, and no engine entry points. The parked `TqCode` / `TqCompile` / `TqVM` units stay off the manifests and off `scripts/build.sh`.

## 152

The layout is not `common/torque/{full,hybrid,residual}` and not `common/cpp`. One module tree, and a manifest per program, is the wire: 3.04 lists every 3.x module, 4.x omits the ones that build dropped, 5.0.0.7 keeps the three-program split, and 5.30/5.31 list no unit. 6.x is `quattro_lib`, recorded as a cut in `CUTS.md`, and is not scaffolded. This change stays inside `common/torque/`.

## 153

No Seihai login path is added. The stubs have no handshake and no socket. The historical client source is untouched because this change does not edit a client folder.

## 154

7.x Worlds is not in this tree. No Unity client, no plugin inventory, and no `Graal3DEngine.dll` research beyond the 4.x/5.0 Torque DLL the cut line already names. Nothing under `common/torque/` is a 7.x layout.

## 155

The parked script units stay parked, and the hold stands. This branch does not put `common/torque` on the fpc path and does not change `scripts/test.sh`. `GuiGraalCtrl`'s 31 methods are named in `guigraal/README.md` with no bodies. The root `common/torque/README.md` now points at the module cut as well as at those parked units.
