{ XFile3D: DirectX text .x files, the level and model format of Graal3D.

  Graal3D loads its levels and its eight player meshes with Direct3D
  Retained Mode from `xof 0302txt` / `xof 0303txt` files. This unit reads
  the part of that format those files use, written from the public DirectX
  file format description:

    Mesh             vertices, faces (any polygon size), children
    MeshMaterialList material count, one index per face, then Material
                     objects or references (a name in braces) to
                     named top-level ones
    Material         face colour (RGBA), power, specular, emissive, and
                     an optional TextureFilename
    MeshTextureCoords one (u, v) per vertex
    Frame            a FrameTransformMatrix and children, any depth
    template, Header, MeshNormals and anything else are skipped.

  Commas and semicolons only separate values, so the reader ignores them
  and takes the values in order. Frame matrices are applied to the
  vertices at load, so every mesh comes out in the file's world space.
  Counts are checked against what is left of the file, so a broken or
  hostile level (they arrive from the server) cannot ask for more memory
  than its own size. }
unit XFile3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Math3D;

type
  TMaterial3D = record
    Name: string;
    R, G, B, A: Double;
    Power: Double;
    ER, EG, EB: Double; { emissive }
    Texture: string;    { file name, '' for none }
  end;

  TFace3D = record
    Idx: array of Integer;
    Mat: Integer;
  end;

  TMesh3D = class
  public
    Name: string;
    Verts: array of TVec3;
    U, V: array of Double;
    Faces: array of TFace3D;
    Materials: array of TMaterial3D;
    function VertexCount: Integer;
    function FaceCount: Integer;
    { The face's plane normal from its first three corners (Direct3D's
      clockwise front faces in a left-handed frame), unit length. }
    function FaceNormal(F: Integer): TVec3;
    procedure Bounds(out Lo, Hi: TVec3);
  end;

  TXScene = class
  private
    FMeshes: array of TMesh3D;
  public
    destructor Destroy; override;
    procedure Clear;
    procedure Add(M: TMesh3D);
    function Count: Integer;
    function Mesh(I: Integer): TMesh3D;
    { All meshes of the file; False if it is not a text .x file. }
    function LoadFromString(const Text: string): Boolean;
    function LoadFromFile(const FileName: string): Boolean;
  end;

implementation

uses
  SysUtils, Classes;

type
  TTokKind = (tkEnd, tkName, tkNumber, tkString, tkOpen, tkClose);

  TXReader = class
  private
    FText: string;
    FPos: Integer;
    FKind: TTokKind;
    FTok: string;
    FPeeked: Boolean;
    procedure Scan;
  public
    Bad: Boolean;
    constructor Create(const Text: string);
    function Next: TTokKind;
    function Peek: TTokKind;
    property Tok: string read FTok;
    function Num: Double;
    function Int: Integer;
    function Left: Integer;
    procedure SkipBlock; // after an opening brace: to the matching closing one
  end;

constructor TXReader.Create(const Text: string);
begin
  inherited Create;
  FText := Text;
  FPos := 1;
end;

function TXReader.Left: Integer;
begin
  Result := Length(FText) - FPos + 1;
end;

procedure TXReader.Scan;
var
  C: Char;
  S: Integer;
begin
  FTok := '';
  while FPos <= Length(FText) do
  begin
    C := FText[FPos];
    if (C <= ' ') or (C = ',') or (C = ';') then
      Inc(FPos)
    else if (C = '/') and (FPos < Length(FText)) and (FText[FPos + 1] = '/') or (C = '#') then
    begin
      while (FPos <= Length(FText)) and (FText[FPos] <> #10) do Inc(FPos);
    end
    else if C = '<' then
    begin
      { a template GUID }
      while (FPos <= Length(FText)) and (FText[FPos] <> '>') do Inc(FPos);
      Inc(FPos);
    end
    else if C = '[' then
    begin
      while (FPos <= Length(FText)) and (FText[FPos] <> ']') do Inc(FPos);
      Inc(FPos);
    end
    else
      Break;
  end;
  if FPos > Length(FText) then
  begin
    FKind := tkEnd;
    Exit;
  end;
  C := FText[FPos];
  S := FPos;
  if C = '{' then
  begin
    FKind := tkOpen;
    Inc(FPos);
  end
  else if C = '}' then
  begin
    FKind := tkClose;
    Inc(FPos);
  end
  else if C = '"' then
  begin
    Inc(FPos);
    S := FPos;
    while (FPos <= Length(FText)) and (FText[FPos] <> '"') do Inc(FPos);
    FTok := Copy(FText, S, FPos - S);
    Inc(FPos);
    FKind := tkString;
  end
  else if (C in ['0'..'9', '-', '+', '.']) then
  begin
    while (FPos <= Length(FText)) and
      (FText[FPos] in ['0'..'9', '-', '+', '.', 'e', 'E']) do Inc(FPos);
    FTok := Copy(FText, S, FPos - S);
    FKind := tkNumber;
  end
  else
  begin
    while (FPos <= Length(FText)) and
      not (FText[FPos] in [#0..' ', '{', '}', ',', ';', '"', '<', '[']) do Inc(FPos);
    FTok := Copy(FText, S, FPos - S);
    FKind := tkName;
  end;
end;

function TXReader.Next: TTokKind;
begin
  if FPeeked then FPeeked := False
  else Scan;
  Result := FKind;
end;

function TXReader.Peek: TTokKind;
begin
  if not FPeeked then
  begin
    Scan;
    FPeeked := True;
  end;
  Result := FKind;
end;

function TXReader.Num: Double;
var
  Code: Integer;
begin
  if Next <> tkNumber then
  begin
    Bad := True;
    Result := 0;
    Exit;
  end;
  Val(FTok, Result, Code);
  if Code <> 0 then
  begin
    Bad := True;
    Result := 0;
  end;
end;

function TXReader.Int: Integer;
var
  D: Double;
begin
  D := Num;
  if (D < -2147483647) or (D > 2147483647) then
  begin
    Bad := True;
    Result := 0;
  end
  else
    Result := Trunc(D);
end;

procedure TXReader.SkipBlock;
var
  Depth: Integer;
begin
  Depth := 1;
  while Depth > 0 do
    case Next of
      tkOpen: Inc(Depth);
      tkClose: Dec(Depth);
      tkEnd: begin Bad := True; Exit; end;
    end;
end;

{ TMesh3D }

function TMesh3D.VertexCount: Integer;
begin
  Result := Length(Verts);
end;

function TMesh3D.FaceCount: Integer;
begin
  Result := Length(Faces);
end;

function TMesh3D.FaceNormal(F: Integer): TVec3;
var
  A, B, C: TVec3;
begin
  A := Verts[Faces[F].Idx[0]];
  B := Verts[Faces[F].Idx[1]];
  C := Verts[Faces[F].Idx[2]];
  Result := VNorm(VCross(VSub(B, A), VSub(C, A)));
end;

procedure TMesh3D.Bounds(out Lo, Hi: TVec3);
var
  I: Integer;
begin
  Lo := V3(0, 0, 0);
  Hi := V3(0, 0, 0);
  for I := 0 to High(Verts) do
  begin
    if (I = 0) or (Verts[I].X < Lo.X) then Lo.X := Verts[I].X;
    if (I = 0) or (Verts[I].Y < Lo.Y) then Lo.Y := Verts[I].Y;
    if (I = 0) or (Verts[I].Z < Lo.Z) then Lo.Z := Verts[I].Z;
    if (I = 0) or (Verts[I].X > Hi.X) then Hi.X := Verts[I].X;
    if (I = 0) or (Verts[I].Y > Hi.Y) then Hi.Y := Verts[I].Y;
    if (I = 0) or (Verts[I].Z > Hi.Z) then Hi.Z := Verts[I].Z;
  end;
end;

{ TXScene }

type
  TMatrix = array[0..15] of Double;

  TXLoader = class
    R: TXReader;
    Scene: TXScene;
    Named: array of TMaterial3D;
    procedure TopLevel;
    procedure ReadObject(const Kind: string; const M: TMatrix);
    procedure ReadFrame(const Parent: TMatrix);
    procedure ReadMesh(const Name: string; const M: TMatrix);
    function ReadMaterial(const Name: string): TMaterial3D;
    procedure ReadMaterialList(Mesh: TMesh3D; var FaceMat: array of Integer;
      out FaceMatCount: Integer);
    function FindNamed(const Name: string; out Mat: TMaterial3D): Boolean;
  end;

const
  Identity: TMatrix = (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
  MaxCount = 1000000;

function MulMatrix(const A, B: TMatrix): TMatrix;
var
  I, J, K: Integer;
  S: Double;
begin
  { row vectors: v * A * B }
  for I := 0 to 3 do
    for J := 0 to 3 do
    begin
      S := 0;
      for K := 0 to 3 do S := S + A[I * 4 + K] * B[K * 4 + J];
      Result[I * 4 + J] := S;
    end;
end;

function Transform(const P: TVec3; const M: TMatrix): TVec3;
begin
  Result.X := P.X * M[0] + P.Y * M[4] + P.Z * M[8] + M[12];
  Result.Y := P.X * M[1] + P.Y * M[5] + P.Z * M[9] + M[13];
  Result.Z := P.X * M[2] + P.Y * M[6] + P.Z * M[10] + M[14];
end;

function TXLoader.FindNamed(const Name: string; out Mat: TMaterial3D): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Named) do
    if CompareText(Named[I].Name, Name) = 0 then
    begin
      Mat := Named[I];
      Result := True;
      Exit;
    end;
  Result := False;
end;

function TXLoader.ReadMaterial(const Name: string): TMaterial3D;
var
  K: TTokKind;
begin
  Result.Name := Name;
  Result.R := R.Num;
  Result.G := R.Num;
  Result.B := R.Num;
  Result.A := R.Num;
  Result.Power := R.Num;
  R.Num; R.Num; R.Num; { specular }
  Result.ER := R.Num;
  Result.EG := R.Num;
  Result.EB := R.Num;
  Result.Texture := '';
  repeat
    K := R.Next;
    if K = tkName then
    begin
      if R.Peek = tkName then R.Next; { an object name }
      if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
      { only TextureFilename is read; any other child is skipped }
      if R.Peek = tkString then
      begin
        R.Next;
        Result.Texture := R.Tok;
        if R.Next <> tkClose then R.SkipBlock;
      end
      else
        R.SkipBlock;
    end
    else if K = tkOpen then
      R.SkipBlock
    else if K <> tkClose then
    begin
      R.Bad := True;
      Exit;
    end;
  until (K = tkClose) or R.Bad;
end;

procedure TXLoader.ReadMaterialList(Mesh: TMesh3D; var FaceMat: array of Integer;
  out FaceMatCount: Integer);
var
  NMat, NIdx, I: Integer;
  K: TTokKind;
  Mat: TMaterial3D;
begin
  FaceMatCount := 0;
  NMat := R.Int;
  NIdx := R.Int;
  if (NMat < 0) or (NIdx < 0) or (NIdx > R.Left) or (NMat > R.Left) then
  begin
    R.Bad := True;
    Exit;
  end;
  for I := 0 to NIdx - 1 do
  begin
    if I <= High(FaceMat) then FaceMat[I] := R.Int else R.Int;
    if R.Bad then Exit;
  end;
  FaceMatCount := NIdx;
  if FaceMatCount > Length(FaceMat) then FaceMatCount := Length(FaceMat);
  repeat
    K := R.Next;
    case K of
      tkName:
        begin
          if CompareText(R.Tok, 'Material') = 0 then
          begin
            if R.Peek = tkName then R.Next;
            if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
            Mat := ReadMaterial('');
            SetLength(Mesh.Materials, Length(Mesh.Materials) + 1);
            Mesh.Materials[High(Mesh.Materials)] := Mat;
          end
          else
          begin
            if R.Peek = tkName then R.Next;
            if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
            R.SkipBlock;
          end;
        end;
      tkOpen:
        begin
          // a name in braces: a reference to a top-level material
          K := R.Next;
          if K = tkClose then
            K := tkOpen // empty braces: keep reading the list
          else if K <> tkName then
          begin
            if K = tkOpen then R.SkipBlock;
            R.SkipBlock;
            K := tkOpen;
          end
          else
          begin
            if not FindNamed(R.Tok, Mat) then
            begin
              FillChar(Mat, SizeOf(Mat), 0);
              Mat.Name := R.Tok;
              Mat.R := 1; Mat.G := 1; Mat.B := 1; Mat.A := 1;
            end;
            SetLength(Mesh.Materials, Length(Mesh.Materials) + 1);
            Mesh.Materials[High(Mesh.Materials)] := Mat;
            if R.Next <> tkClose then R.SkipBlock;
            K := tkOpen;
          end;
        end;
      tkClose: ;
    else
      R.Bad := True;
    end;
  until (K = tkClose) or R.Bad;
end;

procedure TXLoader.ReadMesh(const Name: string; const M: TMatrix);
var
  Mesh: TMesh3D;
  NV, NF, I, J, N, NFM, Kept: Integer;
  K: TTokKind;
  FaceMat: array of Integer;
  P: TVec3;
  Ok: Boolean;
begin
  Mesh := TMesh3D.Create;
  try
    Mesh.Name := Name;
    NV := R.Int;
    if (NV < 0) or (NV > MaxCount) or (NV * 3 > R.Left) then begin R.Bad := True; Exit; end;
    SetLength(Mesh.Verts, NV);
    SetLength(Mesh.U, NV);
    SetLength(Mesh.V, NV);
    for I := 0 to NV - 1 do
    begin
      P.X := R.Num;
      P.Y := R.Num;
      P.Z := R.Num;
      Mesh.Verts[I] := Transform(P, M);
      if R.Bad then Exit;
    end;
    NF := R.Int;
    if (NF < 0) or (NF > MaxCount) or (NF * 2 > R.Left) then begin R.Bad := True; Exit; end;
    SetLength(Mesh.Faces, NF);
    SetLength(FaceMat, NF);
    Kept := 0;
    for I := 0 to NF - 1 do
    begin
      N := R.Int;
      if (N < 0) or (N > 64) then begin R.Bad := True; Exit; end;
      SetLength(Mesh.Faces[Kept].Idx, N);
      Ok := N >= 3;
      for J := 0 to N - 1 do
      begin
        Mesh.Faces[Kept].Idx[J] := R.Int;
        if (Mesh.Faces[Kept].Idx[J] < 0) or (Mesh.Faces[Kept].Idx[J] >= NV) then Ok := False;
      end;
      if R.Bad then Exit;
      Mesh.Faces[Kept].Mat := I; { the file's face number, mapped below }
      if Ok then Inc(Kept);
    end;
    NFM := 0;
    repeat
      K := R.Next;
      if K = tkName then
      begin
        if CompareText(R.Tok, 'MeshMaterialList') = 0 then
        begin
          if R.Peek = tkName then R.Next;
          if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
          ReadMaterialList(Mesh, FaceMat, NFM);
        end
        else if CompareText(R.Tok, 'MeshTextureCoords') = 0 then
        begin
          if R.Peek = tkName then R.Next;
          if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
          N := R.Int;
          if (N < 0) or (N * 2 > R.Left) then begin R.Bad := True; Exit; end;
          for I := 0 to N - 1 do
          begin
            if I < NV then
            begin
              Mesh.U[I] := R.Num;
              Mesh.V[I] := R.Num;
            end
            else
            begin
              R.Num;
              R.Num;
            end;
          end;
          if R.Next <> tkClose then R.SkipBlock;
        end
        else
        begin
          if R.Peek = tkName then R.Next;
          if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
          R.SkipBlock;
        end;
      end
      else if K = tkOpen then
        R.SkipBlock
      else if K <> tkClose then
        R.Bad := True;
    until (K = tkClose) or R.Bad;
    if R.Bad then Exit;
    { the file's face number -> its material; a short list repeats its last
      entry, and a face with no list or a bad index gets material 0 }
    SetLength(Mesh.Faces, Kept);
    for I := 0 to Kept - 1 do
    begin
      J := Mesh.Faces[I].Mat;
      if NFM = 0 then N := 0
      else if J < NFM then N := FaceMat[J]
      else N := FaceMat[NFM - 1];
      if (N < 0) or (N >= Length(Mesh.Materials)) then N := 0;
      Mesh.Faces[I].Mat := N;
    end;
    if Length(Mesh.Materials) = 0 then
    begin
      SetLength(Mesh.Materials, 1);
      FillChar(Mesh.Materials[0], SizeOf(Mesh.Materials[0]), 0);
      Mesh.Materials[0].R := 1;
      Mesh.Materials[0].G := 1;
      Mesh.Materials[0].B := 1;
      Mesh.Materials[0].A := 1;
    end;
    Scene.Add(Mesh);
    Mesh := nil;
  finally
    Mesh.Free;
  end;
end;

procedure TXLoader.ReadFrame(const Parent: TMatrix);
var
  K: TTokKind;
  Local, World: TMatrix;
  I: Integer;
  Kind: string;
begin
  World := Parent;
  repeat
    K := R.Next;
    if K = tkName then
    begin
      Kind := R.Tok;
      if CompareText(Kind, 'FrameTransformMatrix') = 0 then
      begin
        if R.Peek = tkName then R.Next;
        if R.Next <> tkOpen then begin R.Bad := True; Exit; end;
        for I := 0 to 15 do Local[I] := R.Num;
        if R.Next <> tkClose then R.SkipBlock;
        World := MulMatrix(Local, Parent);
      end
      else
        ReadObject(Kind, World);
    end
    else if K = tkOpen then
      R.SkipBlock
    else if K <> tkClose then
      R.Bad := True;
  until (K = tkClose) or R.Bad;
end;

procedure TXLoader.ReadObject(const Kind: string; const M: TMatrix);
var
  Name: string;
  Mat: TMaterial3D;
begin
  Name := '';
  if R.Peek = tkName then
  begin
    R.Next;
    Name := R.Tok;
  end;
  if R.Next <> tkOpen then
  begin
    R.Bad := True;
    Exit;
  end;
  if CompareText(Kind, 'template') = 0 then R.SkipBlock
  else if CompareText(Kind, 'Mesh') = 0 then ReadMesh(Name, M)
  else if CompareText(Kind, 'Frame') = 0 then ReadFrame(M)
  else if CompareText(Kind, 'Material') = 0 then
  begin
    Mat := ReadMaterial(Name);
    SetLength(Named, Length(Named) + 1);
    Named[High(Named)] := Mat;
  end
  else
    R.SkipBlock;
end;

procedure TXLoader.TopLevel;
var
  K: TTokKind;
  Kind: string;
begin
  repeat
    K := R.Next;
    { a copy: the reader's token changes under a const parameter }
    Kind := R.Tok;
    if K = tkName then ReadObject(Kind, Identity)
    else if K = tkOpen then R.SkipBlock
    else if K <> tkEnd then R.Bad := True;
  until (K = tkEnd) or R.Bad;
end;

destructor TXScene.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TXScene.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FMeshes) do FMeshes[I].Free;
  SetLength(FMeshes, 0);
end;

procedure TXScene.Add(M: TMesh3D);
begin
  SetLength(FMeshes, Length(FMeshes) + 1);
  FMeshes[High(FMeshes)] := M;
end;

function TXScene.Count: Integer;
begin
  Result := Length(FMeshes);
end;

function TXScene.Mesh(I: Integer): TMesh3D;
begin
  Result := FMeshes[I];
end;

function TXScene.LoadFromString(const Text: string): Boolean;
var
  L: TXLoader;
begin
  Clear;
  Result := False;
  { 'xof 0302txt 0064': the magic, a version, 'txt', the float size }
  if (Length(Text) < 16) or (Copy(Text, 1, 4) <> 'xof ') or
    (LowerCase(Copy(Text, 9, 3)) <> 'txt') then Exit;
  L := TXLoader.Create;
  try
    L.Scene := Self;
    L.R := TXReader.Create(Copy(Text, 17, MaxInt));
    try
      L.TopLevel;
      Result := not L.R.Bad;
    finally
      L.R.Free;
    end;
  finally
    L.Free;
  end;
  if not Result then Clear;
end;

function TXScene.LoadFromFile(const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(S, F.Size);
      if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
    finally
      F.Free;
    end;
  except
    Exit;
  end;
  Result := LoadFromString(S);
end;

end.
