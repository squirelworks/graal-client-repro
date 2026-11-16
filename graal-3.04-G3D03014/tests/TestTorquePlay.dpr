{ Tests for the Torque default entrypoint helper (common/GTorquePlay). }
program TestTorquePlay;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTorquePlay in '../../common/GTorquePlay.pas';

var
  Passed, Failed: Integer;
  Dir, Marker, Got: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'graal-torque-play-test';
  Dir := IncludeTrailingPathDelimiter(Dir);
  if DirectoryExists(Dir) then
  begin
{$IFDEF MSWINDOWS}
    DeleteFile(Dir + 'graal304-torque.exe');
{$ELSE}
    DeleteFile(Dir + 'graal304-torque');
{$ENDIF}
  end
  else
    ForceDirectories(ExcludeTrailingPathDelimiter(Dir));
{$IFDEF MSWINDOWS}
  Marker := Dir + 'graal304-torque.exe';
{$ELSE}
  Marker := Dir + 'graal304-torque';
{$ENDIF}
  try
    with TFileStream.Create(Marker, fmCreate) do
      Free;
    Got := TorqueProgram(Dir);
    Check(Got = Marker, 'TorqueProgram finds graal304-torque beside the program');
    Check(not WantPascalGame, 'WantPascalGame is off without --pascal or env');
  finally
    DeleteFile(Marker);
    RemoveDir(Dir);
  end;
  Check(TorqueProgram('/nonexistent-folder-for-torque/') = '',
    'TorqueProgram is empty when the file is missing');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
