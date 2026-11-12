{ GPaths: the path and text helpers of Delphi 6 and later, for Delphi 5.

  The shared units used IncludeTrailingPathDelimiter, PathDelim and
  BoolToStr (Delphi 6), SysUtils' DirectoryExists and ForceDirectories
  (Delphi 5 has them in FileCtrl) and Free Pascal's GetTempDir (no Delphi
  has it). Under Free Pascal each helper calls the function it replaces,
  so nothing changes there. Under Delphi 5 (Win32) each uses what that
  release has. Issue #114. }
unit GPaths;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
{$IFDEF FPC}
  DirSlash = DirectorySeparator; { SysUtils.PathDelim is this constant }
{$ELSE}
  DirSlash = '\';
{$ENDIF}

{ Dir with a path separator at its end (IncludeTrailingPathDelimiter). }
function WithTrailingSep(const Dir: string): string;
function DirExists(const Dir: string): Boolean;
{ Creates Dir and its missing parents; True when it exists afterwards. }
function MakeDirs(const Dir: string): Boolean;
{ The user's temporary folder, ending in a separator. }
function TempDir: string;
{ 'True' or 'False' (BoolToStr(B, True)). }
function BoolText(B: Boolean): string;

implementation

uses
{$IFNDEF FPC}
  Windows, FileCtrl,
{$ENDIF}
  SysUtils;

function WithTrailingSep(const Dir: string): string;
begin
{$IFDEF FPC}
  Result := IncludeTrailingPathDelimiter(Dir);
{$ELSE}
  { by hand: Delphi 4 has no IncludeTrailingBackslash }
  Result := Dir;
  if (Result = '') or (Result[Length(Result)] <> '\') then
    Result := Result + '\';
{$ENDIF}
end;

function DirExists(const Dir: string): Boolean;
begin
{$IFDEF FPC}
  Result := SysUtils.DirectoryExists(Dir);
{$ELSE}
  Result := FileCtrl.DirectoryExists(Dir);
{$ENDIF}
end;

function MakeDirs(const Dir: string): Boolean;
begin
{$IFDEF FPC}
  Result := SysUtils.ForceDirectories(Dir);
{$ELSE}
  { Delphi 5's FileCtrl.ForceDirectories is a procedure that raises on
    failure }
  try
    FileCtrl.ForceDirectories(Dir);
  except
    on EInOutError do ;
  end;
  Result := FileCtrl.DirectoryExists(Dir);
{$ENDIF}
end;

function TempDir: string;
{$IFNDEF FPC}
var
  Buf: array[0..MAX_PATH] of Char;
  N: DWORD;
{$ENDIF}
begin
{$IFDEF FPC}
  Result := WithTrailingSep(GetTempDir(False));
{$ELSE}
  N := GetTempPath(MAX_PATH, Buf);
  if (N = 0) or (N > MAX_PATH) then
    Result := WithTrailingSep(ExtractFilePath(ParamStr(0)))
  else
    SetString(Result, Buf, N);
  Result := WithTrailingSep(Result);
{$ENDIF}
end;

function BoolText(B: Boolean): string;
begin
  if B then Result := 'True' else Result := 'False';
end;

end.
