{ TqConsole: stock TGE 1.2 console and TorqueScript host.

  Kind: stock. Linked by 3.04 and by 3.153, which is the same monolith.
  Not linked by the 4.x or 5.0 2D engine, by the 4.2.0.8 or 5.0.0.7 3D
  DLL (no .dso and no TorqueScript compiler string), or by 5.30, 5.31
  or 6.x.

  TqCode, TqCompile and TqVM stay in the parent directory. This unit
  does not use them. No script VM is implemented here.

  Notes: Graal_analysis torque/engine-304.md, torque/scripting.md,
  torque/study-torque-clients.md. }
unit TqConsole;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ No types and no registry. A later unit would load .dso v33 and plain
  script, keep namespaces and packages, and register native commands.
  That behaviour is not in this scaffold. }

implementation

end.
