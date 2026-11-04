{ GAssetDirs: where a build looks for the player's own Graal files.

  One assets folder serves every rebuilt client:

    graal-assets/
      common/      files that are the same for every version
      2.05r2/      what one version has of its own (start art, tutorial
      2.17.1/      levels, arrays.dat / arrays2.dat, ...)
      2.22/

  A file is looked for in order:
    1. the data folder itself (the program's folder, or --data): a real
       install dropped there still wins;
    2. graal-assets/<version>/, then any fallback versions;
    3. graal-assets/common/.
  A build that shipped with another version's files names that version as
  a fallback: 2.17.1 came in the same folder as 2.22, so its label is
  '2.17.1;2.22' and it reads graal-assets/2.22/ with no second copy.
  graal-assets is found in the data folder, one folder up from it, or is
  the data folder itself (when it holds a common/ folder). Nothing found:
  the build's built-in assets fill in. }
unit GAssetDirs;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ Sets the folders searched, from the data folder and the build's version
  label (its folder under graal-assets, e.g. '2.05r2'). Version may list
  fallback folders after it, separated by ';' (e.g. '2.17.1;2.22'). }
procedure SetAssetRoots(const DataDir, Version: string);
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

procedure SetAssetRoots(const DataDir, Version: string);
var
  D, Up, Rest, V: string;
  P: Integer;
begin
  SetLength(Roots, 0);
  Folder := '';
  if DataDir = '' then D := '' else D := IncludeTrailingPathDelimiter(ExpandFileName(DataDir));
  if D <> '' then
  begin
    Up := ExtractFilePath(ExcludeTrailingPathDelimiter(D));
    if DirectoryExists(D + 'common') then
      Folder := D
    else if DirectoryExists(D + 'graal-assets') then
      Folder := D + 'graal-assets' + PathDelim
    else if (Up <> '') and DirectoryExists(Up + 'graal-assets') then
      Folder := Up + 'graal-assets' + PathDelim;
    if Folder <> D then AddRoot(D);
  end;
  if Folder <> '' then
  begin
    Rest := Version;
    while Rest <> '' do
    begin
      P := Pos(';', Rest);
      if P = 0 then P := Length(Rest) + 1;
      V := Trim(Copy(Rest, 1, P - 1));
      Delete(Rest, 1, P);
      if V <> '' then AddRoot(Folder + V);
    end;
    AddRoot(Folder + 'common');
  end;
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
