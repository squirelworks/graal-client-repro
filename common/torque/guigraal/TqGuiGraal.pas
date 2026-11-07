{ TqGuiGraal: Graal-only GuiGraalCtrl and GuiGraal3DCtrl.

  Kind: Graal-only. 3.04 registers GuiGraalCtrl with 31 methods and
  does not register GuiGraal3DCtrl. Later hybrid engines keep both
  names; 4.2.0.8's script builder does not construct either type.
  5.30, 5.31 and 6.x keep the names and do not link this unit.

  The graal/ draw types and TGraalConnection are not console classes
  and are not declared here. No control is allocated.

  Notes: Graal_analysis torque/engine-304.md, torque/4208-engine.md,
  torque/engine-5007.md, client-internals/engine-600r2.md. }
unit TqGuiGraal;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would be GuiGraalCtrl's 3.04 method table
  and, where the version has it, the GuiGraal3DCtrl name. Not in
  this scaffold. }

implementation

end.
