# gui

**Patched.** The classes are stock TGE (`GuiCanvas`, `GuiControl`, the stock controls, profiles, themes). From the 4.x/5.0 2D engine onward the canvas does not draw pixels itself: each draw goes through the host pointer installed by `graal_set…`, and an empty pointer does nothing. 3.04 still draws through Torque's own OpenGL device. One unit covers both; the hybrid host is why the kind is patched rather than stock.

What it has to do later: build the control tree the shipped 3.04 scripts create, and on the hybrid engine host the same class names while the launcher or the 3D DLL supplies pixels. `GuiGraalCtrl` and `GuiGraal3DCtrl` are `guigraal`. The 4.2.0.8 script builder discards those two names so script does not construct them; that rule lives with `guigraal`.

Stock classes the 3.04 scripts actually construct include `GuiTextCtrl`, `GuiButtonCtrl`, `GuiControlProfile`, `GuiControl`, `GuiTextEditCtrl`, `GuiScrollCtrl`, `GuiWindowCtrl`, `GuiCheckBoxCtrl`, `GuiPopUpMenuCtrl`, `GuiTextListCtrl`, `GuiMLTextCtrl`, `GuiSliderCtrl`, `GuiChunkedBitmapCtrl`, plus the console, inspector, tree and editor controls named in `torque/study-torque-clients.md`.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Canvas, themes, `.gft` fonts. Scripts call `Canvas.setContent`. |
| 3.153 | Yes. |
| 4.04r2 3D | Yes. `GuiCanvas` and `GuiControl` are in that DLL. |
| 4.2.0.8 launcher | No. The launcher calls `renderGraalCanvas` and draws with DirectDraw. |
| 4.2.0.8 engine | Yes. `GuiCanvas` is the screen object (`renderFrame`, `setContentControl`, input). `Point2I` is `math`. |
| 4.2.0.8 3D | Yes. `GuiCanvas::setContentControl` installs `GUIContainer3D`. |
| 5.0.0.7 launcher | No. The note says `GuiCanvas` is absent from the exe. |
| 5.0.0.7 engine | Yes. `GuiCanvas`, `GuiControl`, `GuiScrollCtrl`, `GuiWindowCtrl`, `GuiControlProfile`. |
| 5.0.0.7 3D | Yes. `GuiCanvas` (`setContentControl`, `paint`, `mouseLock`, `showHint`). |
| 5.30 / 5.31 | Residual names, not this unit. `GuiCanvas` is absent. `GuiControl` and, in 5.31, the longer `Gui*` list remain, with Torque field names (`horizSizing`, `vertSizing`, `fillColor`, `makeFirstResponder`). |
| 6.x | Residual names, not this unit. Unpacked 6.00 reimplements the GS2 control vocabulary. `GuiGraalCtrl` is `guigraal`'s residual name. The Torque field names above are not in that 6.00 image. |
