unit Engine600r4;
{ Per-build binding of the shared explicit Quattro CLI translator. }
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
interface
uses GQuattroPlay;
function EngineArguments600r4(const Input: array of string; const Dir: string;
  out Args: TQuattroArgs; out PasswordEnv: string): Boolean;
implementation
uses GQuattroCli, Protocol600r4;
function EngineArguments600r4(const Input: array of string; const Dir: string;
  out Args: TQuattroArgs; out PasswordEnv: string): Boolean;
begin
  Result := QuattroCliArguments(Input, Dir, ClientBuildLabel, FirstServerName, Args, PasswordEnv);
end;
end.
