{ GAssetDirs: where a build looks for the player's own Graal files.

  One assets folder serves every rebuilt client:

    graal-assets/
      common/      files that are the same for every version
      2.05r2/      what one version has of its own (start art, tutorial
      2.17.1/      levels, arrays.dat / arrays2.dat, ...)
      2.22/

  A file is looked for in order:
    1. the program's own folder: the program lives in the root of an
       install, laid out as the original was (levels/, sounds/, ...);
    2. graal-assets/<version>/ next to the program, then any fallback
       versions, then graal-assets/common/;
    3. only then the folder given with --data, the same way (its own
       files, then its graal-assets/ folders).
  A build that shipped with another version's files names that version as
  a fallback: 2.17.1 came in the same folder as 2.22, so its label is
  '2.17.1;2.22' and it reads graal-assets/2.22/ with no second copy.
  A folder that holds a common/ folder is taken as a graal-assets folder
  itself. Nothing is looked for above the program's folder or the --data
  folder. Nothing found: the build's built-in assets (new art) fill in. }
unit GAssetDirs;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ Sets the folders searched, from the data folder and the build's version
  label (its folder under graal-assets, e.g. '2.05r2'). Version may list
  fallback folders after it, separated by ';' (e.g. '2.17.1;2.22'). }
procedure SetAssetRoots(const DataDir, Version: string);
{ The same with the program's folder named (tests): ProgramDir first,
  DataDir last; either may be ''. }
procedure SetAssetRootsFor(const ProgramDir, DataDir, Version: string);
{ The folders searched, in order, each ending in a path delimiter. }
function AssetRootCount: Integer;
function AssetRoot(I: Integer): string;
{ The first existing file Rel ('/' between folders) under the roots, or ''. }
function AssetPath(const Rel: string): string;
{ The graal-assets folder in use, or ''. }
function AssetsFolder: string;

implementation

uses
  SysUtils;

var
  Roots: array of string;
  Folder: string = '';

procedure AddRoot(const Dir: string);
var
  D: string;
  I: Integer;
begin
  if (Dir = '') or not DirectoryExists(Dir) then Exit;
  D := IncludeTrailingPathDelimiter(Dir);
  for I := 0 to High(Roots) do
    if Roots[I] = D then Exit;
  SetLength(Roots, Length(Roots) + 1);
  Roots[High(Roots)] := D;
end;

{ One install folder D: its own files, then its graal-assets folders. }
procedure AddInstall(const Dir, Version: string);
var
  D, F, Rest, V: string;
  P: Integer;
begin
  if Dir = '' then Exit;
  D := IncludeTrailingPathDelimiter(ExpandFileName(Dir));
  if not DirectoryExists(D) then Exit;
  { only inside the folder: never a folder above it }
  F := '';
  if DirectoryExists(D + 'common') then
    F := D
  else if DirectoryExists(D + 'graal-assets') then
    F := D + 'graal-assets' + PathDelim;
  if F <> D then AddRoot(D);
  if F = '' then Exit;
  if Folder = '' then Folder := F;
  Rest := Version;
  while Rest <> '' do
  begin
    P := Pos(';', Rest);
    if P = 0 then P := Length(Rest) + 1;
    V := Trim(Copy(Rest, 1, P - 1));
    Delete(Rest, 1, P);
    if V <> '' then AddRoot(F + V);
  end;
  AddRoot(F + 'common');
end;

{ The program's folder first, --data last (Squirrel's rule, 2026-11-04:
  the program lives in the root and finds its assets there). DataDir is
  the --data folder, or the program's folder when there is none. }
procedure SetAssetRootsFor(const ProgramDir, DataDir, Version: string);
begin
  SetLength(Roots, 0);
  Folder := '';
  AddInstall(ProgramDir, Version);
  AddInstall(DataDir, Version);
end;

procedure SetAssetRoots(const DataDir, Version: string);
begin
  SetAssetRootsFor(ExtractFilePath(ParamStr(0)), DataDir, Version);
end;

function AssetRootCount: Integer;
begin
  Result := Length(Roots);
end;

function AssetRoot(I: Integer): string;
begin
  Result := Roots[I];
end;

function AssetPath(const Rel: string): string;
var
  I: Integer;
  R: string;
begin
  Result := '';
  if Rel = '' then Exit;
  R := StringReplace(Rel, '/', PathDelim, [rfReplaceAll]);
  for I := 0 to High(Roots) do
    if FileExists(Roots[I] + R) then
    begin
      Result := Roots[I] + R;
      Exit;
    end;
end;

function AssetsFolder: string;
begin
  Result := Folder;
end;

end.
