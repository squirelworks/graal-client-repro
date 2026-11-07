{ TqGui: stock TGE GUI classes, patched where the hybrid engine
  draws through the host instead of a Torque display device.

  Kind: patched. Linked wherever the note names GuiCanvas / GuiControl
  as code: 3.04, the 4.x and 5.0 2D engines, and the 3D DLLs that call
  GuiCanvas. 5.30, 5.31 and 6.x keep class names only; they do not
  link this unit.

  GuiGraalCtrl is guigraal, not this unit. No control is constructed
  here.

  Notes: Graal_analysis torque/study-torque-clients.md,
  torque/4208-engine.md, torque/engine-5007.md, torque/g3d-5007.md. }
unit TqGui;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would be GuiCanvas, GuiControl and the stock
  control classes, profiles and themes. Not in this scaffold. }

implementation

end.
