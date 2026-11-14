program TestQuattroSecure;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses
  SysUtils, Classes,
  GSecLogin in '../../common/GSecLogin.pas',
  GQuattroPlay in '../../common/GQuattroPlay.pas';

{$IFDEF LINUX}
function SetEnv(Name, Value: PChar; Overwrite: LongInt): LongInt; cdecl;
  external 'c' name 'setenv';
function UnsetEnv(Name: PChar): LongInt; cdecl;
  external 'c' name 'unsetenv';

procedure Check(OK: Boolean; const What: string);
begin
  if not OK then raise Exception.Create(What);
  WriteLn('ok ', What);
end;

procedure TestRouting;
const
  Names: array[0..2] of string = ('DISPLAY', 'GRAAL_PASCAL_GAME', 'GRAAL_SECURE_LOGIN');
var
  Saved: array[0..2] of string;
  Dir, Exe, Mode: string;
  I: Integer;
  F: TStringList;
begin
  for I := 0 to High(Names) do Saved[I] := GetEnvironmentVariable(Names[I]);
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'quattro-secure-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  Dir := IncludeTrailingPathDelimiter(Dir);
  Exe := Dir + 'quattro-play';
  PinDirOverride := Dir;
  F := TStringList.Create;
  try
    { An installed player and display make the insecure route available.
      The file is only selected, never executed; no X server is needed. }
    F.SaveToFile(Exe);
    SetEnv('DISPLAY', ':123', 1);
    UnsetEnv('GRAAL_PASCAL_GAME');
    UnsetEnv('GRAAL_SECURE_LOGIN');
    ClearSecure;
    Check(QuattroProgram(Dir, True) = Exe, 'default off selects Quattro online');
    for I := 0 to 1 do
    begin
      if I = 0 then Mode := 'auto' else Mode := 'required';
      SetEnv('GRAAL_SECURE_LOGIN', PChar(Mode), 1);
      Check(QuattroProgram(Dir, True) = '', Mode + ' environment keeps online login in Pascal');
      Check(QuattroProgram(Dir, False) = Exe, Mode + ' environment allows offline Training');
      UnsetEnv('GRAAL_SECURE_LOGIN');
      F.Clear;
      F.Add(Mode);
      F.SaveToFile(Dir + 'secure_login.txt');
      Check(QuattroProgram(Dir, True) = '', Mode + ' settings keep online login in Pascal');
      Check(QuattroProgram(Dir, False) = Exe, Mode + ' settings allow offline Training');
      DeleteFile(Dir + 'secure_login.txt');
    end;
    SetEnv('GRAAL_SECURE_LOGIN', 'off', 1);
    SetSecure(smRequired, 'given-key');
    Check(QuattroProgram(Dir, True) = '', 'explicit required and server key override environment off');
    SetEnv('GRAAL_SECURE_LOGIN', 'required', 1);
    SetSecure(smOff, '');
    Check(QuattroProgram(Dir, True) = Exe, 'explicit off preserves the original-login route');
    ClearSecure;
    UnsetEnv('GRAAL_SECURE_LOGIN');
    SetEnv('GRAAL_PASCAL_GAME', '1', 1);
    Check(QuattroProgram(Dir, False) = '', 'Pascal override also keeps Training in Pascal');
    UnsetEnv('GRAAL_PASCAL_GAME');
    UnsetEnv('DISPLAY');
    Check(QuattroProgram(Dir, True) = '', 'headless game stays in Pascal');
  finally
    F.Free;
    ClearSecure;
    PinDirOverride := '';
    DeleteFile(Dir + 'secure_login.txt');
    DeleteFile(Exe);
    RemoveDir(Dir);
    for I := 0 to High(Names) do
      if Saved[I] = '' then UnsetEnv(PChar(Names[I]))
      else SetEnv(PChar(Names[I]), PChar(Saved[I]), 1);
  end;
end;
{$ENDIF}

begin
{$IFDEF LINUX}
  TestRouting;
{$ELSE}
  if QuattroProgram('.', True) <> '' then Halt(1);
  WriteLn('ok non-Linux games stay in Pascal');
{$ENDIF}
end.
