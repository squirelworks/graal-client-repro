{ GPaths checks (#114): under Free Pascal each Delphi 5 helper must give
  what the function it replaced gives. }
program TestPaths;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  GPaths in '../../common/GPaths.pas';

var
  Passed, Failed: Integer;

procedure Check(OK: Boolean; const Name: string);
begin
  if OK then
  begin
    Inc(Passed);
    WriteLn('ok    ', Name);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name);
  end;
end;

const
  Dirs: array[0..6] of string = ('', 'a', 'a/', 'a\', 'a/b', '/', 'C:');

procedure TestSeparators;
var
  I: Integer;
begin
  Check(DirSlash = PathDelim, 'DirSlash is PathDelim');
  for I := 0 to High(Dirs) do
    Check(WithTrailingSep(Dirs[I]) = IncludeTrailingPathDelimiter(Dirs[I]),
      'WithTrailingSep [' + Dirs[I] + '] matches IncludeTrailingPathDelimiter');
end;

procedure TestDirs;
var
  Root, Deep: string;
begin
  Check(TempDir = IncludeTrailingPathDelimiter(GetTempDir(False)), 'TempDir matches GetTempDir');
  Check(DirExists(TempDir), 'the temporary folder exists');
  Root := TempDir + 'graal-gpaths-' + IntToStr(GetProcessID);
  Deep := Root + DirSlash + 'a' + DirSlash + 'b';
  Check(not DirExists(Root), 'a new folder does not exist yet');
  Check(MakeDirs(Deep) and DirExists(Deep), 'MakeDirs creates missing parents');
  Check(MakeDirs(Deep), 'MakeDirs on an existing folder');
  Check(not DirExists(Deep + DirSlash + 'missing'), 'DirExists is false for a missing folder');
  RemoveDir(Deep);
  RemoveDir(Root + DirSlash + 'a');
  RemoveDir(Root);
  Check(not DirExists(Root), 'cleanup');
end;

begin
  Passed := 0;
  Failed := 0;
  TestSeparators;
  TestDirs;
  Check((BoolText(True) = BoolToStr(True, True)) and (BoolText(False) = BoolToStr(False, True)),
    'BoolText matches BoolToStr(B, True)');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
