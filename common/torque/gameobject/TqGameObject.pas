{ TqGameObject: Graal's GameObject, constructed as a SceneObject.

  Kind: Graal-only. Not in 3.04 and not in the 4.04r2 3D DLL.
  Linked by the 4.2.0.8 3D DLL and the 5.0.0.7 3D DLL. The 2D engine
  only has the graal_setCreateGraal3DGameObject slot, not the class.
  Absent as a class in 5.30, 5.31 and 6.x.

  No object is allocated here.

  Notes: Graal_analysis torque/4208-g3d.md, torque/g3d-5007.md,
  torque/engine-and-formats.md. }
unit TqGameObject;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would be GameObject on SceneObject, and the
  GameShape classes the 5.0.0.7 note names. Not in this scaffold. }

implementation

end.
