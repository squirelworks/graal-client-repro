{ EditorObjSets: the predefined objects (tile stamps) of the 2.05 editor.

  2.17.1 copy of the 2.05 rev 2 unit: 2.17.1 runs it as 2.05 does until a
  difference is found (see the build's README).

  Two formats (graal_analysis formats/gobjset01.md and
  client-internals/precursors-and-fan-builds.md, "objects.dat"):
    objects<set>.txt   GOBJSET01 text: "OBJECT w h name", h lines of w*2
                       base64 characters (the GLEVNW01 packing), OBJECTEND.
                       Plain objects.txt is the Standard set.
    objects.dat        the older flat list the 2.05 install ships: a name
                       ended by #10, a width byte, a height byte, then
                       w*h 32-bit little-endian tile ids; 2047 ($7FF) is a
                       transparent cell.
  A stamp only writes tile ids. Transparent cells (TransparentTile in a
  block) leave the board as it is. }
unit EditorObjSets;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  EditorDoc;

type
  TStamp = record
    Name: string;
    Block: TTileBlock;
  end;

  TObjectSet = class
  public
    Name: string;
    FileName: string;
    Stamps: array of TStamp;
    Modified: Boolean;
    function Count: Integer;
    function LoadGOBJSET(const Data: string): Boolean;
    function LoadObjectsDat(const Data: string): Boolean;
    function SaveText: string;   { GOBJSET01 }
    function SaveDat: string;    { objects.dat }
    function Save: Boolean;      { by the file's extension }
    procedure Insert(At: Integer; const S: TStamp);
    procedure Remove(At: Integer);
  end;

  TObjectSets = class
  public
    Sets: array of TObjectSet;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function Add(S: TObjectSet): Integer;
    { Reads objects*.txt (and objects.dat when there is no Standard set)
      from the folders, the first folder winning for a set name. }
    procedure LoadFromFolders(const Folders: array of string);
    { A new empty set saved as objects<Name>.txt in Folder. }
    function NewSet(const Folder, AName: string): TObjectSet;
  end;

function SetNameOf(const FileName: string): string;

implementation

uses
  SysUtils, GPaths, Classes;

const
  B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function ReadAll(const FileName: string): string;
var
  F: TFileStream;
begin
  Result := '';
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  except
    Result := '';
  end;
end;

function SetNameOf(const FileName: string): string;
var
  N: string;
begin
  N := ChangeFileExt(ExtractFileName(FileName), '');
  if LowerCase(Copy(N, 1, 7)) = 'objects' then N := Copy(N, 8, MaxInt);
  if N = '' then N := 'Standard';
  Result := N;
end;

{ TObjectSet }

function TObjectSet.Count: Integer;
begin
  Result := Length(Stamps);
end;

function TObjectSet.LoadGOBJSET(const Data: string): Boolean;
var
  L, Tok: TStringList;
  I, J, X, W, H, A, B: Integer;
  S: TStamp;
  Row: string;
begin
  Result := False;
  SetLength(Stamps, 0);
  L := TStringList.Create;
  Tok := TStringList.Create;
  try
    L.Text := Data;
    if (L.Count = 0) or (Trim(L[0]) <> 'GOBJSET01') then Exit;
    I := 1;
    while I < L.Count do
    begin
      Tok.Clear;
      ExtractStrings([' '], [], PChar(L[I]), Tok);
      if (Tok.Count >= 3) and (Tok[0] = 'OBJECT') then
      begin
        W := StrToIntDef(Tok[1], 0);
        H := StrToIntDef(Tok[2], 0);
        S.Name := Trim(Copy(L[I], Pos(Tok[2], Copy(L[I], Length(Tok[0]) + Length(Tok[1]) + 2,
          MaxInt)) + Length(Tok[0]) + Length(Tok[1]) + 1 + Length(Tok[2]), MaxInt));
        if (W > 0) and (H > 0) and (W <= 64) and (H <= 64) then
        begin
          S.Block := TileBlock(W, H, 0);
          for J := 0 to H - 1 do
          begin
            if I + 1 + J >= L.Count then Break;
            Row := Trim(L[I + 1 + J]);
            for X := 0 to W - 1 do
              if Length(Row) >= X * 2 + 2 then
              begin
                A := Pos(Row[X * 2 + 1], B64) - 1;
                B := Pos(Row[X * 2 + 2], B64) - 1;
                if (A >= 0) and (B >= 0) then S.Block.Tiles[J * W + X] := (A shl 6) or B;
              end;
          end;
          SetLength(Stamps, Length(Stamps) + 1);
          Stamps[High(Stamps)] := S;
          Inc(I, H);
        end;
      end;
      Inc(I);
    end;
    Result := True;
  finally
    Tok.Free;
    L.Free;
  end;
end;

function TObjectSet.LoadObjectsDat(const Data: string): Boolean;
var
  P, E, W, H, K, V: Integer;
  S: TStamp;
begin
  Result := False;
  SetLength(Stamps, 0);
  P := 1;
  while P <= Length(Data) do
  begin
    E := P;
    while (E <= Length(Data)) and (Data[E] <> #10) do Inc(E);
    if E + 2 > Length(Data) then Break;
    S.Name := Copy(Data, P, E - P);
    W := Ord(Data[E + 1]);
    H := Ord(Data[E + 2]);
    P := E + 3;
    if (W = 0) or (H = 0) or (P + W * H * 4 - 1 > Length(Data)) then Exit;
    S.Block := TileBlock(W, H, 0);
    for K := 0 to W * H - 1 do
    begin
      V := Ord(Data[P]) or (Ord(Data[P + 1]) shl 8) or (Ord(Data[P + 2]) shl 16) or
        (Ord(Data[P + 3]) shl 24);
      if V = 2047 then S.Block.Tiles[K] := TransparentTile
      else S.Block.Tiles[K] := V and $FFF;
      Inc(P, 4);
    end;
    SetLength(Stamps, Length(Stamps) + 1);
    Stamps[High(Stamps)] := S;
  end;
  Result := Length(Stamps) > 0;
end;

function TObjectSet.SaveText: string;
var
  I, X, Y, T: Integer;
  Row: string;
begin
  Result := 'GOBJSET01'#10;
  for I := 0 to High(Stamps) do
    with Stamps[I] do
    begin
      Result := Result + #10'OBJECT ' + IntToStr(Block.W) + ' ' + IntToStr(Block.H) + ' ' +
        Name + #10;
      for Y := 0 to Block.H - 1 do
      begin
        Row := '';
        for X := 0 to Block.W - 1 do
        begin
          T := Block.Tiles[Y * Block.W + X];
          if T = TransparentTile then T := 0;
          T := T and $FFF;
          Row := Row + B64[(T shr 6) + 1] + B64[(T and 63) + 1];
        end;
        Result := Result + Row + #10;
      end;
      Result := Result + 'OBJECTEND'#10;
    end;
end;

function TObjectSet.SaveDat: string;
var
  I, K, V: Integer;
begin
  Result := '';
  for I := 0 to High(Stamps) do
    with Stamps[I] do
    begin
      Result := Result + Name + #10 + Chr(Block.W) + Chr(Block.H);
      for K := 0 to Block.W * Block.H - 1 do
      begin
        V := Block.Tiles[K];
        if V = TransparentTile then V := 2047;
        Result := Result + Chr(V and $FF) + Chr((V shr 8) and $FF) + #0#0;
      end;
    end;
end;

function TObjectSet.Save: Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  if FileName = '' then Exit;
  if LowerCase(ExtractFileExt(FileName)) = '.dat' then S := SaveDat else S := SaveText;
  try
    F := TFileStream.Create(FileName, fmCreate);
    try
      if S <> '' then F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
    Modified := False;
    Result := True;
  except
    Result := False;
  end;
end;

procedure TObjectSet.Insert(At: Integer; const S: TStamp);
var
  I: Integer;
begin
  if At < 0 then At := 0;
  if At > Length(Stamps) then At := Length(Stamps);
  SetLength(Stamps, Length(Stamps) + 1);
  for I := High(Stamps) downto At + 1 do Stamps[I] := Stamps[I - 1];
  Stamps[At] := S;
  Modified := True;
end;

procedure TObjectSet.Remove(At: Integer);
var
  I: Integer;
begin
  if (At < 0) or (At > High(Stamps)) then Exit;
  for I := At to High(Stamps) - 1 do Stamps[I] := Stamps[I + 1];
  SetLength(Stamps, Length(Stamps) - 1);
  Modified := True;
end;

{ TObjectSets }

destructor TObjectSets.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TObjectSets.Clear;
var
  I: Integer;
begin
  for I := 0 to High(Sets) do Sets[I].Free;
  SetLength(Sets, 0);
end;

function TObjectSets.Count: Integer;
begin
  Result := Length(Sets);
end;

function TObjectSets.Add(S: TObjectSet): Integer;
begin
  SetLength(Sets, Length(Sets) + 1);
  Result := High(Sets);
  Sets[Result] := S;
end;

procedure TObjectSets.LoadFromFolders(const Folders: array of string);
var
  I, K: Integer;
  SR: TSearchRec;
  Dir, N: string;
  S: TObjectSet;
  Seen: TStringList;
begin
  Clear;
  Seen := TStringList.Create;
  try
    for I := 0 to High(Folders) do
    begin
      Dir := Folders[I];
      if Dir = '' then Continue;
      Dir := WithTrailingSep(Dir);
      if FindFirst(Dir + 'objects*.txt', faAnyFile, SR) = 0 then
      begin
        repeat
          N := SetNameOf(SR.Name);
          if Seen.IndexOf(LowerCase(N)) >= 0 then Continue;
          S := TObjectSet.Create;
          S.Name := N;
          S.FileName := Dir + SR.Name;
          if S.LoadGOBJSET(ReadAll(S.FileName)) then
          begin
            Add(S);
            Seen.Add(LowerCase(N));
          end
          else
            S.Free;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    end;
    if Seen.IndexOf('standard') < 0 then
      for I := 0 to High(Folders) do
        if (Folders[I] <> '') and FileExists(WithTrailingSep(Folders[I]) + 'objects.dat') then
        begin
          S := TObjectSet.Create;
          S.Name := 'Standard';
          S.FileName := WithTrailingSep(Folders[I]) + 'objects.dat';
          if S.LoadObjectsDat(ReadAll(S.FileName)) then
          begin
            K := Add(S);
            { the Standard set first }
            while K > 0 do
            begin
              Sets[K] := Sets[K - 1];
              Dec(K);
            end;
            Sets[0] := S;
          end
          else
            S.Free;
          Break;
        end;
  finally
    Seen.Free;
  end;
end;

function TObjectSets.NewSet(const Folder, AName: string): TObjectSet;
begin
  Result := TObjectSet.Create;
  Result.Name := AName;
  Result.FileName := WithTrailingSep(Folder) + 'objects' + AName + '.txt';
  Result.Save;
  Add(Result);
end;

end.
