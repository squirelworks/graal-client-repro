{ TqNetTorque: Torque GameConnection.

  Kind: patched. Stock demo connection in 3.04 (protocol 9, Torque
  demo game string, no class table). From 3.153, and on the 3D DLL
  after that, the same class carries Graal's protocol. 5.0.0.7's 3D
  DLL accepts only protocol 24.

  TGraalConnection is not NetConnection and is not this unit.
  No socket is opened here.

  Notes: Graal_analysis torque/engine-304.md, torque/network.md,
  torque/4208-g3d.md, torque/g3d-5007.md. }
unit TqNetTorque;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types. A later unit would be GameConnection and NetConnection.
  Not in this scaffold. }

implementation

end.
