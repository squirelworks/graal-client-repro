{ GResFiles: the files of a real install that a rebuild carries in its own
  resources (scripts/res/install_res.py packs them into
  src/res/<Program>Install.res: FILELIST, the paths, and one RCDATA per
  file named F_ and its path in upper case with every other character as
  _). With this unit in a program, GAssetDirs.AssetFallback hands them out
  when the program's folder holds no such file, so the rebuild runs in an
  empty folder with its original's art. }
unit GResFiles;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes;

{ The paths carried ('/' between folders, as in the install); empty when
  the program carries none. Owned by the unit. }
function ResFileList: TStrings;
{ The bytes of the carried file Rel (any case, / or \). }
function ResFile(const Rel: string; out Data: string): Boolean;
{ A copy of the carried file Rel written once to a folder of the user's
  temporary files, for code that opens files; '' when not carried. }
function ResFilePath(const Rel: string): string;

implementation

uses
  GPaths,
  SysUtils, GPeRes, GAssetDirs;

var
  List: TStringList;
  Stamp: string;

function ResName(const Rel: string): string;
var
  I: Integer;
begin
  Result := 'F_' + UpperCase(StringReplace(Rel, '\', '/', [rfReplaceAll]));
  for I := 3 to Length(Result) do
    if not (Result[I] in ['A'..'Z', '0'..'9']) then Result[I] := '_';
end;

function ResFileList: TStrings;
var
  D: string;
  I: Integer;
  H: Cardinal;
begin
  if List = nil then
  begin
    List := TStringList.Create;
    if OwnResource('FILELIST', D) then
    begin
      List.Text := D;
      for I := List.Count - 1 downto 0 do
        if Trim(List[I]) = '' then List.Delete(I);
      List.CaseSensitive := False;
      List.Sorted := True;
      { a folder per set of files, so a newer build never reads an older
        one's copies }
      H := 2166136261;
      for I := 1 to Length(D) do
        H := (H xor Ord(D[I])) * 16777619;
      Stamp := IntToHex(H, 8);
    end;
  end;
  Result := List;
end;

function Carried(const Rel: string): Boolean;
begin
  Result := ResFileList.IndexOf(StringReplace(Rel, '\', '/', [rfReplaceAll])) >= 0;
end;

function ResFile(const Rel: string; out Data: string): Boolean;
begin
  Data := '';
  Result := (Rel <> '') and Carried(Rel) and OwnResource(ResName(Rel), Data);
end;

function ResFilePath(const Rel: string): string;
var
  Key, F, D: string;
  S: TFileStream;
begin
  Result := '';
  Key := LowerCase(StringReplace(Rel, '\', '/', [rfReplaceAll]));
  if (Key = '') or (Pos('..', Key) > 0) or not Carried(Key) then Exit;
  F := TempDir + 'graal-delphi-' +
    ChangeFileExt(ExtractFileName(ParamStr(0)), '') + '-' + Stamp + DirSlash +
    StringReplace(Key, '/', DirSlash, [rfReplaceAll]);
  if FileExists(F) then
  begin
    Result := F;
    Exit;
  end;
  if not ResFile(Key, D) then Exit;
  try
    MakeDirs(ExtractFileDir(F));
    S := TFileStream.Create(F + '.part', fmCreate);
    try
      if D <> '' then S.WriteBuffer(D[1], Length(D));
    finally
      S.Free;
    end;
    if not RenameFile(F + '.part', F) then DeleteFile(F + '.part');
    if FileExists(F) then Result := F;
  except
    Result := '';
  end;
end;

initialization
  if (ResFileList.Count > 0) and not Assigned(AssetFallback) then
    AssetFallback := ResFilePath;

finalization
  FreeAndNil(List);

end.
