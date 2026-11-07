{ TqGBitmap: stock TGE GBitmap.

  Kind: stock. Linked by 3.04, by the hybrid 2D engine (4.04r2,
  4.2.0.8, 5.0.0.7), by the 4.04r2 3D DLL, and by the 5.0.0.7 3D DLL.
  The 4.2.0.8 3D note does not name GBitmap, so that manifest omits
  it. Not linked for 5.30, 5.31 or 6.x.

  No bitmap is allocated here.

  Notes: Graal_analysis torque/study-torque-clients.md,
  torque/engine-and-formats.md, torque/engine-5007.md,
  torque/g3d-5007.md. }
unit TqGBitmap;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would read the bitmap formats the engine
  already names (PNG and the other GBitmap readers). Not in this
  scaffold. }

implementation

end.
