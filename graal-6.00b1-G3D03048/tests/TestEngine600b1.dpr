program TestEngine600b1;
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
uses SysUtils, GQuattroPlay, Engine600b1, Protocol600b1;
var Args: TQuattroArgs; Env, TempRoot: string; HasBeta1, HasR4, HasCommon: Boolean; SavedFormat: TFormatSettings; N, Failed, I, Count: Integer;
procedure Check(OK: Boolean; const Name: string);
begin
  Inc(N);
  if not OK then begin Inc(Failed); WriteLn('FAIL: ', Name); end;
end;
function Value(const Key: string): string;
var J: Integer;
begin
  Result := '';
  for J := 0 to High(Args)-1 do if Args[J] = Key then Exit(Args[J+1]);
end;
procedure Reject(const Input: array of string);
begin Check(not EngineArguments600b1(Input, GetTempDir, Args, Env), 'reject invalid handoff'); end;
begin
  Check(EngineArguments600b1(['--engine','--server','localhost:14900',
    '--account','guest','--password-env','TEST_PASSWORD','--seconds','2'],
    GetTempDir, Args, Env), 'online translation');
  Check(Value('--connect') = 'localhost:14900', 'endpoint');
  Check(Value('--account') = 'guest', 'account');
  Check(Value('--server-name') = 'Login', 'lobby default');
  Check(Value('--password-env') = 'GRAAL_QUATTRO_PW', 'child environment name');
  Check(Env = 'TEST_PASSWORD', 'parent environment name');
  Check(Value('--seconds') = '2', 'wall-clock duration');
  Check(Value('--offline') = '', 'online only');
  Check(EngineArguments600b1(['--engine','--level','authored.nw','--x','20',
    '--y','22','--data',GetTempDir], GetTempDir, Args, Env), 'offline translation');
  Check(Value('--offline') = 'authored.nw', 'offline path');
  Check((Value('--x') = '20') and (Value('--y') = '22'), 'coordinates');
  Check(Value('--connect') = '', 'no socket argument offline');
  Check(EngineArguments600b1(['--engine','--server','localhost:14900',
    '--account','guest','--server-name','Lab'], GetTempDir, Args, Env), 'named game');
  Check(Value('--server-name') = 'Lab', 'server name preserved');
  SavedFormat := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    Check(EngineArguments600b1(['--engine','--level','authored.nw','--x','1.5',
      '--y','-2.25'], GetTempDir, Args, Env), 'dot coordinates in comma locale');
    Check((Value('--x') = '1.5') and (Value('--y') = '-2.25'), 'dot coordinates preserved');
    Reject(['--engine','--level','authored.nw','--x','1,5']);
  finally
    DefaultFormatSettings := SavedFormat;
  end;
  Reject(['--level','authored.nw']);
  Reject(['--engine']);
  Reject(['--engine','--engine','--level','authored.nw']);
  Reject(['--engine','--level','authored.nw','--headless']);
  Reject(['--engine','--level','authored.nw','--frames','1']);
  Reject(['--engine','--level','authored.nw','--x','NaN']);
  Reject(['--engine','--level','authored.nw','--x','1,5']);
  Reject(['--engine','--level','authored.nw','--seconds','0']);
  Reject(['--engine','--level','authored.nw','--x','1','--x','2']);
  Reject(['--engine','--level','authored.nw','--server','localhost:14900','--account','guest']);
  Reject(['--engine','--server','localhost:0','--account','guest']);
  Reject(['--engine','--server','localhost:14900']);
  Reject(['--engine','--level','authored.nw','--password-env','PW']);
  Reject(['--engine','--level']);
  TempRoot := GetTempFileName(GetTempDir, 'b1');
  DeleteFile(TempRoot);
  ForceDirectories(TempRoot + '/graal-assets/6.00b1');
  ForceDirectories(TempRoot + '/graal-assets/6.00r4');
  ForceDirectories(TempRoot + '/graal-assets/6.00b2');
  ForceDirectories(TempRoot + '/graal-assets/common');
  try
    Check(EngineArguments600b1(['--engine','--level','authored.nw','--data',TempRoot],
      GetTempDir, Args, Env), 'version-specific asset translation');
    HasBeta1 := False; HasR4 := False; HasCommon := False;
    for I := 0 to High(Args)-1 do if Args[I] = '--asset-root' then
    begin
      if ExtractFileName(ExcludeTrailingPathDelimiter(Args[I+1])) = '6.00b1' then HasBeta1 := True;
      if ExtractFileName(ExcludeTrailingPathDelimiter(Args[I+1])) = 'common' then HasCommon := True;
      if (ExtractFileName(ExcludeTrailingPathDelimiter(Args[I+1])) = '6.00r4') or
        (ExtractFileName(ExcludeTrailingPathDelimiter(Args[I+1])) = '6.00b2') then HasR4 := True;
    end;
    Check(HasBeta1, 'beta1 asset root selected');
    Check(HasCommon, 'common asset root included');
    Check(not HasR4, 'sibling asset roots excluded');
  finally
    RemoveDir(TempRoot + '/graal-assets/6.00b1');
    RemoveDir(TempRoot + '/graal-assets/6.00r4');
    RemoveDir(TempRoot + '/graal-assets/6.00b2');
    RemoveDir(TempRoot + '/graal-assets/common');
    RemoveDir(TempRoot + '/graal-assets');
    RemoveDir(TempRoot);
  end;
  Count := 0;
  for I := 0 to 255 do if PLOKnown(I) then Inc(Count);
  Check(Count = 97, 'Pascal receive set count');
  Check(PLOKnown(41) and PLOKnown(165) and PLOKnown(169) and PLOKnown(175) and PLOKnown(181) and PLOKnown(184), 'documented receive ids');
  Check(not PLOKnown(111), 'distinct receive gates');
  WriteLn(N, ' checks, ', Failed, ' failures');
  if Failed <> 0 then Halt(1);
end.
