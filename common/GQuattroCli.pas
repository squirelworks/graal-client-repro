unit GQuattroCli;

{ Explicit per-build CLI translation to the existing Quattro program.
  Validation and argument preparation do not start a process or socket. }
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
interface
uses GQuattroPlay;
function QuattroCliArguments(const Input: array of string;
  const Dir, BuildLabel, LobbyName: string;
  out Args: TQuattroArgs; out PasswordEnv: string): Boolean;
implementation
uses SysUtils, Math, GAssetDirs;
function QuattroCliArguments(const Input: array of string;
  const Dir, BuildLabel, LobbyName: string;
  out Args: TQuattroArgs; out PasswordEnv: string): Boolean;
var
  I, J, Port: Integer;
  Name, Value, Data, Server: string;
  Online: Boolean;
  Coordinate: Double;
  NumberFormat: TFormatSettings;
  Roots: array of string;
  function ArgCount: Integer;
  begin Result := Length(Input); end;
  function ArgAt(N: Integer): string;
  begin Result := Input[N-1]; end;
  function Arg(const Key, Default: string): string;
  var N: Integer;
  begin
    Result := Default;
    for N := 1 to Length(Input)-1 do
      if Input[N-1] = Key then Exit(Input[N]);
  end;
  function HasArg(const Key: string): Boolean;
  var N: Integer;
  begin
    Result := False;
    for N := 0 to High(Input) do if Input[N] = Key then Exit(True);
  end;
begin
  Result := False;
  SetLength(Args, 0);
  PasswordEnv := '';
  NumberFormat := DefaultFormatSettings;
  NumberFormat.DecimalSeparator := '.';
  NumberFormat.ThousandSeparator := #0;
  if not HasArg('--engine') or HasArg('--headless') then Exit;
  I := 1;
  while I <= ArgCount do
  begin
    Name := ArgAt(I);
    for J := 1 to I - 1 do if ArgAt(J) = Name then Exit;
    if (Name = '--window') or (Name = '--engine') then Inc(I)
    else
    begin
      if (Name <> '--server') and (Name <> '--account') and
        (Name <> '--password-env') and (Name <> '--server-name') and
        (Name <> '--level') and (Name <> '--x') and (Name <> '--y') and
        (Name <> '--data') and (Name <> '--seconds') then Exit;
      if I = ArgCount then Exit;
      Value := ArgAt(I + 1);
      if (Value = '') or (Copy(Value, 1, 2) = '--') then Exit;
      Inc(I, 2);
    end;
  end;
  Server := Arg('--server', '');
  Online := Server <> '';
  if Online = (Arg('--level', '') <> '') then Exit;
  if Online then
  begin
    I := Pos(':', Server);
    if (I <= 1) or (Arg('--account', '') = '') then Exit;
    if not TryStrToInt(Copy(Server, I + 1, MaxInt), Port) or
      (Port < 1) or (Port > 65535) then Exit;
    if HasArg('--x') or HasArg('--y') then Exit;
  end
  else if HasArg('--account') or HasArg('--password-env') or
    HasArg('--server-name') then Exit;
  if HasArg('--seconds') then
    if not TryStrToInt(Arg('--seconds', ''), I) or (I <= 0) then Exit;
  if HasArg('--x') then
  begin
    if (Pos(',', Arg('--x', '')) > 0) or not TryStrToFloat(Arg('--x', ''), Coordinate, NumberFormat) then Exit;
    if IsNan(Coordinate) or IsInfinite(Coordinate) then Exit;
  end;
  if HasArg('--y') then
  begin
    if (Pos(',', Arg('--y', '')) > 0) or not TryStrToFloat(Arg('--y', ''), Coordinate, NumberFormat) then Exit;
    if IsNan(Coordinate) or IsInfinite(Coordinate) then Exit;
  end;
  Data := Arg('--data', Dir);
  if DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '_clients') or
    DirectoryExists(IncludeTrailingPathDelimiter(Data) + '_clients') then Exit;
  SetAssetRoots(Data, BuildLabel);
  SetLength(Roots, AssetRootCount);
  for I := 0 to AssetRootCount - 1 do Roots[I] := AssetRoot(I);
  Args := QuattroArgs(Dir, Roots, Arg('--level', ''), Arg('--x', '30'),
    Arg('--y', '30'), Server, Arg('--account', ''),
    Arg('--server-name', LobbyName), '');
  if HasArg('--seconds') then
  begin
    I := Length(Args);
    SetLength(Args, I + 2);
    Args[I] := '--seconds';
    Args[I + 1] := Arg('--seconds', '');
  end;
  PasswordEnv := Arg('--password-env', 'GRAAL_PW');
  Result := True;
end;
end.
