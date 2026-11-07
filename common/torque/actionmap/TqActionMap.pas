{ TqActionMap: stock TGE ActionMap.

  Kind: stock. Linked by 3.04 and 3.153, by the 4.04r2 3D DLL, and by
  the 5.0.0.7 3D DLL. Not the 2D engine. The 4.2.0.8 3D note does not
  name it, so that manifest omits it. Absent in 5.30, 5.31 and 6.x.

  No map is allocated here.

  Notes: Graal_analysis torque/engine-304.md,
  torque/study-torque-clients.md, torque/g3d-5007.md. }
unit TqActionMap;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would push, pop and bind ActionMap objects.
  Not in this scaffold. }

implementation

end.
