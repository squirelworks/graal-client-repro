unit Engine6015;
{ Per-build binding of the shared explicit Quattro CLI translator. }
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
interface
uses GQuattroPlay;
function EngineArguments6015(const Input: array of string; const Dir: string;
  out Args: TQuattroArgs; out PasswordEnv: string): Boolean;
implementation
uses GQuattroCli, Protocol6015;
function EngineArguments6015(const Input: array of string; const Dir: string;
  out Args: TQuattroArgs; out PasswordEnv: string): Boolean;
begin
  Result := QuattroCliArguments(Input, Dir, ClientBuildLabel, FirstServerName, Args, PasswordEnv);
end;
end.
