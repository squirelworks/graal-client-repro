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
  folder. Nothing found: the build's built-in assets (new art) fill in.

  Shared root (one folder for every client, scripts/assets/shared_root.py):

    <root>/
      Graal139.exe  Graal222.exe ...   every program
      levels/ sounds/ maps/ pics1.gif  one copy of each file, as most
                                       installs had it
      _clients/<version>/              what that version has that differs
                                       from the root copy, byte for byte
      _clients/<version>/files.txt     the root files that version's own
                                       install had, one path per line

  A folder holding _clients/ is a shared root. A build reads the first
  folder of its label that exists under _clients/ (its fallbacks are
  already folded in by the packer), then only those root files that
  files.txt names: never a file another version's install had and its own
  did not. A build with no folder under _clients/ reads no root files. }
unit GAssetDirs;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$I GVer.inc}

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
{ The first existing file Rel ('/' between folders) under the roots, else
  what AssetFallback gives (a client that carries its install's files), or
  ''. }
function AssetPath(const Rel: string): string;
{ False for a file under a shared root that this build may not read (not
  in its files.txt, or under _clients/); True for anything else. A folder
  (ending in a path delimiter) is refused only under _clients/. }
function AssetAllowed(const FullPath: string): Boolean;
{ Name looked up next to an offline level in Dir: Dir + Name when it
  exists; under a shared root, the same relative path through AssetPath,
  so the build's own copy wins and other versions' files stay hidden. }
function LevelSibling(const Dir, Name: string): string;
{ A file of the install folder Dir by name, for code that reads Dir
  directly: LevelSibling when found, else a path of that file name that
  does not exist (Dir + Name outside a shared root; inside one, a name
  under _clients/, so another version's root copy is never handed out and
  callers that fall back on the name, such as a built-in start.nw, still
  do). }
function InstallPath(const Dir, Name: string): string;

var
  { Set by a client that carries files of its install: the path of a copy
    of Rel it can give, or ''. }
  AssetFallback: function(const Rel: string): string = nil;
{ The graal-assets folder in use, or ''. }
function AssetsFolder: string;

implementation

uses
  GPaths,
  SysUtils, Classes;

var
  Roots: array of string;
  { per root: the files a shared root lets this build read, else nil }
  Allow: array of TStringList;
  Folder: string = '';
  { shared roots, each ending in a delimiter, and the files.txt list of
    each (owned by Allow) }
  Shared: array of string;
  SharedAllow: array of TStringList;

function NormRel(const Rel: string): string;
begin
  Result := LowerCase(StringReplace(Rel, '\', '/', [rfReplaceAll]));
end;

procedure ClearRoots;
var
  I: Integer;
begin
  for I := 0 to High(Allow) do Allow[I].Free;
  SetLength(Allow, 0);
  SetLength(Roots, 0);
  SetLength(Shared, 0);
  SetLength(SharedAllow, 0);
end;

procedure AddRootAllow(const Dir: string; List: TStringList);
var
  D: string;
  I: Integer;
begin
  D := WithTrailingSep(Dir);
  for I := 0 to High(Roots) do
    if Roots[I] = D then
    begin
      List.Free;
      Exit;
    end;
  SetLength(Roots, Length(Roots) + 1);
  Roots[High(Roots)] := D;
  SetLength(Allow, Length(Roots));
  Allow[High(Allow)] := List;
end;

{ A shared root D (holds _clients/): the build's own folder, then the root
  through its files.txt. }
procedure AddShared(const D, Version: string);
var
  Rest, V, C: string;
  P, I: Integer;
  List, Raw: TStringList;
begin
  { already a root (program folder = --data folder): keep the first }
  for I := 0 to High(Roots) do
    if Roots[I] = D then Exit;
  SetLength(Shared, Length(Shared) + 1);
  Shared[High(Shared)] := D;
  if Folder = '' then Folder := D;
  C := '';
  Rest := Version;
  while (Rest <> '') and (C = '') do
  begin
    P := Pos(';', Rest);
    if P = 0 then P := Length(Rest) + 1;
    V := Trim(Copy(Rest, 1, P - 1));
    Delete(Rest, 1, P);
    if (V <> '') and DirExists(D + '_clients' + DirSlash + V) then
      C := D + '_clients' + DirSlash + V + DirSlash;
  end;
  List := TStringList.Create;
  List.Sorted := True;
  List.Duplicates := dupIgnore;
{$IFNDEF GC_D5DOWN}
  { Delphi 4 and 5 lists always ignore case (Windows paths do too) }
  List.CaseSensitive := True;
{$ENDIF}
  if C <> '' then
  begin
    AddRootAllow(C, nil);
    if FileExists(C + 'files.txt') then
    begin
      Raw := TStringList.Create;
      try
        Raw.LoadFromFile(C + 'files.txt');
        for I := 0 to Raw.Count - 1 do
          if Trim(Raw[I]) <> '' then List.Add(NormRel(Trim(Raw[I])));
      finally
        Raw.Free;
      end;
    end;
  end;
  SetLength(SharedAllow, Length(Shared));
  SharedAllow[High(SharedAllow)] := List;
  AddRootAllow(D, List);
end;

procedure AddRoot(const Dir: string);
begin
  if (Dir = '') or not DirExists(Dir) then Exit;
  AddRootAllow(Dir, nil);
end;

{ One install folder D: its own files, then its graal-assets folders. }
procedure AddInstall(const Dir, Version: string);
var
  D, F, Rest, V: string;
  P: Integer;
begin
  if Dir = '' then Exit;
  D := WithTrailingSep(ExpandFileName(Dir));
  if not DirExists(D) then Exit;
  if DirExists(D + '_clients') then
  begin
    AddShared(D, Version);
    Exit;
  end;
  { only inside the folder: never a folder above it }
  F := '';
  if DirExists(D + 'common') then
    F := D
  else if DirExists(D + 'graal-assets') then
    F := D + 'graal-assets' + DirSlash;
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
  ClearRoots;
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
  R := StringReplace(Rel, '/', DirSlash, [rfReplaceAll]);
  for I := 0 to High(Roots) do
    if ((Allow[I] = nil) or (Allow[I].IndexOf(NormRel(Rel)) >= 0)) and
       FileExists(Roots[I] + R) then
    begin
      Result := Roots[I] + R;
      Exit;
    end;
  if Assigned(AssetFallback) then Result := AssetFallback(Rel);
end;

function AssetsFolder: string;
begin
  Result := Folder;
end;

{ The shared root FullPath lies in (index into Shared, -1 when outside
  every one) and its path below that root, '/' between folders. }
function SharedRel(const FullPath: string; out Root: Integer): string;
var
  I: Integer;
  F: string;
begin
  Result := '';
  Root := -1;
  if FullPath = '' then Exit;
  F := ExpandFileName(FullPath);
  if FullPath[Length(FullPath)] in ['/', '\'] then
    F := WithTrailingSep(F);
  for I := 0 to High(Shared) do
    if (Length(F) >= Length(Shared[I])) and
       (CompareText(Copy(F, 1, Length(Shared[I])), Shared[I]) = 0) then
    begin
      Root := I;
      Result := StringReplace(Copy(F, Length(Shared[I]) + 1, MaxInt), '\',
        '/', [rfReplaceAll]);
      Exit;
    end;
end;

function UnderOwnClients(const F: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Roots) do
    if (Allow[I] = nil) and (Length(F) >= Length(Roots[I])) and
       (CompareText(Copy(F, 1, Length(Roots[I])), Roots[I]) = 0) then
    begin
      Result := True;
      Exit;
    end;
end;

function AssetAllowed(const FullPath: string): Boolean;
var
  I: Integer;
  Rel, F: string;
begin
  Result := True;
  Rel := SharedRel(FullPath, I);
  if I < 0 then Exit;
  if CompareText(Copy(Rel + '/', 1, 9), '_clients/') = 0 then
  begin
    F := ExpandFileName(FullPath);
    if FullPath[Length(FullPath)] in ['/', '\'] then
      F := WithTrailingSep(F);
    Result := UnderOwnClients(F);
    Exit;
  end;
  if (Rel = '') or (Rel[Length(Rel)] = '/') or DirExists(FullPath) then
    Exit;
  Result := SharedAllow[I].IndexOf(NormRel(Rel)) >= 0;
end;

function LevelSibling(const Dir, Name: string): string;
var
  I, P: Integer;
  Rel: string;
begin
  Result := '';
  if (Dir = '') or (Name = '') then Exit;
  Rel := SharedRel(WithTrailingSep(Dir), I);
  if I < 0 then
  begin
    if FileExists(Dir + Name) then Result := Dir + Name;
    Exit;
  end;
  { the level's folder below the root, or below _clients/<version>/ }
  if CompareText(Copy(Rel, 1, 9), '_clients/') = 0 then
  begin
    Delete(Rel, 1, 9);
    P := Pos('/', Rel);
    if P = 0 then Rel := '' else Delete(Rel, 1, P);
  end;
  Result := AssetPath(Rel + StringReplace(Name, '\', '/', [rfReplaceAll]));
end;

function InstallPath(const Dir, Name: string): string;
var
  I: Integer;
begin
  Result := LevelSibling(Dir, Name);
  if (Result <> '') or (Dir = '') then Exit;
  SharedRel(WithTrailingSep(Dir), I);
  if I < 0 then
    Result := Dir + Name
  else
    Result := Shared[I] + '_clients' + DirSlash + StringReplace(Name, '/',
      DirSlash, [rfReplaceAll]);
end;

{ Delphi 5 and 7 need an initialization section before finalization }
initialization

finalization
  ClearRoots;
end.
