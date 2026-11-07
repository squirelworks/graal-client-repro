{ TqGameTge: stock TGE game layer.

  Kind: stock. ShapeBase, Player, vehicles, items, projectiles.
  Linked by 3.04 (compiled in, unused by the shipped 2D scripts) and
  by the 4.04r2 3D DLL. Gone from the 4.2.0.8 3D DLL and from the
  5.0.0.7 3D DLL. Not the 2D engine. Not 5.30, 5.31 or 6.x.

  No player and no datablock is allocated here.

  Notes: Graal_analysis torque/engine-304.md,
  torque/engine-and-formats.md, torque/4208-g3d.md,
  torque/g3d-5007.md. }
unit TqGameTge;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would be the stock Player / ShapeBase world.
  Not in this scaffold. }

implementation

end.
