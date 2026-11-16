unit GTorquePlay;

{ Hands the no-argument start of a 3.04 / 3.153 rebuild to graal304-torque.

  The real 3.04 and 3.153 clients are Torque programs. Their rebuild ships
  graal304-torque beside Graal304 / Graal3153 (common/torque/guigraal). With
  no arguments, those Pascal programs now start that Torque program when it
  is present. Pascal stays as a labeled fallback: --pascal, or
  GRAAL_PASCAL=1 / GRAAL_PASCAL_GAME=1. When the Torque program is missing,
  or on Linux with no DISPLAY (checked by the caller), the Pascal start
  screen runs as before. CLI runs (--server, --level, stress) stay in
  Pascal. }

interface

{ The graal304-torque beside the program in Dir, when the interactive start
  should go to it; '' otherwise. }
function TorqueProgram(const Dir: string): string;

{ Runs it and waits. Returns the exit code, or -1 when it could not start. }
function RunTorque(const Exe: string): Integer;

{ True when the caller asked for the Pascal start screen / game. }
function WantPascalGame: Boolean;

implementation

uses
  SysUtils, Process;

function CmdHasPascalFlag: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if ParamStr(I) = '--pascal' then
    begin
      Result := True;
      Exit;
    end;
end;

function WantPascalGame: Boolean;
begin
  Result := CmdHasPascalFlag or
    (GetEnvironmentVariable('GRAAL_PASCAL') = '1') or
    (GetEnvironmentVariable('GRAAL_PASCAL_GAME') = '1');
end;

function TorqueProgram(const Dir: string): string;
var
  Base, AppBin: string;
begin
  Result := '';
  if WantPascalGame then Exit;
  Base := IncludeTrailingPathDelimiter(Dir);
{$IFDEF MSWINDOWS}
  if FileExists(Base + 'graal304-torque.exe') then
  begin
    Result := Base + 'graal304-torque.exe';
    Exit;
  end;
{$ENDIF}
  if FileExists(Base + 'graal304-torque') then
  begin
    Result := Base + 'graal304-torque';
    Exit;
  end;
  { macOS release zip: the app bundle next to the Pascal program }
  AppBin := Base + 'graal304-torque.app/Contents/MacOS/graal304-torque';
  if FileExists(AppBin) then Result := AppBin;
end;

function RunTorque(const Exe: string): Integer;
var
  P: TProcess;
begin
  Result := -1;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Options := [poWaitOnExit];
    try
      P.Execute;
      Result := P.ExitStatus;
    except
      Result := -1;
    end;
  finally
    P.Free;
  end;
end;

end.
