{ GDfm1x: reads a Delphi binary form (the TPF0 stream a Delphi program keeps
  in its RCDATA, one per form) into a tree of objects and their
  properties, so a rebuild can lay out a dialog exactly as the original
  program's form describes it. The format is Delphi's own (TReader):
  'TPF0', then per object an optional filer flag byte, the class name,
  the object name, its properties (name, typed value) up to an empty
  name, its children up to an empty entry. }
unit GDfm1x;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes;

type
  TDfmObject = class
  private
    FProps: TStringList;     { Name=text value }
    FBinary: TStringList;    { Name=index into FBin }
    FBin: array of string;
    FChildren: TList;
    function GetChild(I: Integer): TDfmObject;
  public
    ClassName_, Name: string;
    Parent: TDfmObject;
    constructor Create;
    destructor Destroy; override;
    function ChildCount: Integer;
    property Children[I: Integer]: TDfmObject read GetChild;
    { the property's text ('' when absent): numbers as digits, strings
      unquoted, identifiers and sets as written, lists one item a line }
    function Str(const Prop: string; const Def: string = ''): string;
    function Int(const Prop: string; Def: Integer = 0): Integer;
    function Bool(const Prop: string; Def: Boolean): Boolean;
    function Has(const Prop: string): Boolean;
    { a list property (Items.Strings, Lines.Strings), one entry a line }
    function List(const Prop: string): TStringList;
    { a binary property (Picture.Data); False when absent }
    function Binary(const Prop: string; out Data: string): Boolean;
    { the object named N in this subtree (any case), or nil }
    function Find(const N: string): TDfmObject;
  end;

{ The form in Data, or nil when it is not a TPF0 stream. }
function ReadDfm(const Data: string): TDfmObject;

{ The picture inside a TImage's Picture.Data: a short class name
  ('TBitmap', 'TIcon', 'TJPEGImage', ...) and, for a bitmap, a 32-bit
  size and the .bmp file. False for anything but a bitmap. }
function DfmPictureBmp(const PictureData: string; out Bmp: string): Boolean;

implementation

uses
  SysUtils;

type
  EDfm = class(Exception);

  TDfmReader = class
    S: string;
    P: Integer;  { 1-based }
    function U8: Integer;
    function I16: Integer;
    function I32: Integer;
    function Bytes(N: Integer): string;
    function SStr: string;
    function Peek: Integer;
    procedure ReadValue(O: TDfmObject; const PropName: string; out Text: string);
    function ReadObject(Parent: TDfmObject): TDfmObject;
  end;

{ ---- TDfmObject ---- }

constructor TDfmObject.Create;
begin
  inherited Create;
  FProps := TStringList.Create;
  FBinary := TStringList.Create;
  FChildren := TList.Create;
end;

destructor TDfmObject.Destroy;
var
  I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do TDfmObject(FChildren[I]).Free;
  FChildren.Free;
  FProps.Free;
  FBinary.Free;
  inherited Destroy;
end;

function TDfmObject.GetChild(I: Integer): TDfmObject;
begin
  Result := TDfmObject(FChildren[I]);
end;

function TDfmObject.ChildCount: Integer;
begin
  Result := FChildren.Count;
end;

function TDfmObject.Has(const Prop: string): Boolean;
begin
  Result := FProps.IndexOfName(Prop) >= 0;
end;

function TDfmObject.Str(const Prop, Def: string): string;
var
  I: Integer;
begin
  I := FProps.IndexOfName(Prop);
  if I < 0 then Result := Def
  else Result := Copy(FProps[I], Length(Prop) + 2, MaxInt);
end;

function TDfmObject.Int(const Prop: string; Def: Integer): Integer;
begin
  Result := StrToIntDef(Str(Prop, ''), Def);
end;

function TDfmObject.Bool(const Prop: string; Def: Boolean): Boolean;
var
  V: string;
begin
  V := Str(Prop, '');
  if V = 'True' then Result := True
  else if V = 'False' then Result := False
  else Result := Def;
end;

function TDfmObject.List(const Prop: string): TStringList;
var
  V: string;
  I: Integer;
begin
  Result := TStringList.Create;
  V := Str(Prop, '');
  { kept as items separated by #1 }
  I := Pos(#1, V);
  while I > 0 do
  begin
    Result.Add(Copy(V, 1, I - 1));
    Delete(V, 1, I);
    I := Pos(#1, V);
  end;
end;

function TDfmObject.Binary(const Prop: string; out Data: string): Boolean;
var
  I: Integer;
begin
  Data := '';
  I := FBinary.IndexOfName(Prop);
  Result := I >= 0;
  if Result then Data := FBin[StrToInt(Copy(FBinary[I], Length(Prop) + 2, MaxInt))];
end;

function TDfmObject.Find(const N: string): TDfmObject;
var
  I: Integer;
begin
  if SameText(Name, N) then
  begin
    Result := Self;
    Exit;
  end;
  for I := 0 to ChildCount - 1 do
  begin
    Result := Children[I].Find(N);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

{ ---- reader ---- }

function TDfmReader.U8: Integer;
begin
  if P > Length(S) then raise EDfm.Create('form ends early');
  Result := Ord(S[P]);
  Inc(P);
end;

function TDfmReader.Peek: Integer;
begin
  if P > Length(S) then raise EDfm.Create('form ends early');
  Result := Ord(S[P]);
end;

function TDfmReader.I16: Integer;
begin
  Result := U8 or (U8 shl 8);
  if Result >= $8000 then Dec(Result, $10000);
end;

function TDfmReader.I32: Integer;
var
  V: Cardinal;
begin
  V := Cardinal(U8);
  V := V or (Cardinal(U8) shl 8);
  V := V or (Cardinal(U8) shl 16);
  V := V or (Cardinal(U8) shl 24);
  Result := Integer(V);
end;

function TDfmReader.Bytes(N: Integer): string;
begin
  if (N < 0) or (P + N - 1 > Length(S)) then raise EDfm.Create('form ends early');
  Result := Copy(S, P, N);
  Inc(P, N);
end;

function TDfmReader.SStr: string;
begin
  Result := Bytes(U8);
end;

procedure TDfmReader.ReadValue(O: TDfmObject; const PropName: string; out Text: string);
var
  T, N, I: Integer;
  Item, W: string;
begin
  T := U8;
  case T of
    0: Text := '';
    1: { a list: items up to a 0 }
      begin
        Text := '';
        while Peek <> 0 do
        begin
          ReadValue(O, PropName, Item);
          Text := Text + Item + #1;
        end;
        Inc(P);
      end;
    2: begin N := U8; if N >= $80 then Dec(N, $100); Text := IntToStr(N); end;
    3: Text := IntToStr(I16);
    4: Text := IntToStr(I32);
    5: begin Bytes(10); Text := '0'; end;  { extended: not used by the forms read here }
    6, 7: Text := SStr;
    8: Text := 'False';
    9: Text := 'True';
    10: { binary: kept whole }
      begin
        N := I32;
        I := Length(O.FBin);
        SetLength(O.FBin, I + 1);
        O.FBin[I] := Bytes(N);
        O.FBinary.Add(PropName + '=' + IntToStr(I));
        Text := '';
      end;
    11: { a set }
      begin
        Text := '[';
        repeat
          Item := SStr;
          if Item <> '' then
          begin
            if Text <> '[' then Text := Text + ', ';
            Text := Text + Item;
          end;
        until Item = '';
        Text := Text + ']';
      end;
    12: begin N := I32; Text := Bytes(N); end;
    13: Text := 'nil';
    14: { a collection: skipped }
      begin
        while Peek <> 0 do
        begin
          while Peek <> 0 do
          begin
            SStr;
            ReadValue(O, PropName, Item);
          end;
          Inc(P);
        end;
        Inc(P);
        Text := '';
      end;
    18: { a wide string: kept as Latin-1 }
      begin
        N := I32;
        W := Bytes(N * 2);
        SetLength(Text, N);
        for I := 1 to N do
          if Ord(W[2 * I]) = 0 then Text[I] := W[2 * I - 1] else Text[I] := '?';
      end;
    19: begin Bytes(8); Text := '0'; end;
  else
    raise EDfm.CreateFmt('value type %d', [T]);
  end;
end;

function TDfmReader.ReadObject(Parent: TDfmObject): TDfmObject;
var
  F: Integer;
  PN, V: string;
begin
  F := Peek;
  if F and $F0 = $F0 then
  begin
    Inc(P);
    if F and 2 <> 0 then ReadValue(nil, '', V);
  end;
  Result := TDfmObject.Create;
  try
    Result.Parent := Parent;
    Result.ClassName_ := SStr;
    Result.Name := SStr;
    while Peek <> 0 do
    begin
      PN := SStr;
      ReadValue(Result, PN, V);
      Result.FProps.Add(PN + '=' + V);
    end;
    Inc(P);
    while Peek <> 0 do
      Result.FChildren.Add(ReadObject(Result));
    Inc(P);
  except
    Result.Free;
    raise;
  end;
end;

function ReadDfm(const Data: string): TDfmObject;
var
  R: TDfmReader;
begin
  Result := nil;
  if Copy(Data, 1, 4) <> 'TPF0' then Exit;
  R := TDfmReader.Create;
  try
    R.S := Data;
    R.P := 5;
    try
      Result := R.ReadObject(nil);
    except
      on EDfm do Result := nil;
    end;
  finally
    R.Free;
  end;
end;

function DfmPictureBmp(const PictureData: string; out Bmp: string): Boolean;
var
  L, N: Integer;
begin
  Result := False;
  Bmp := '';
  if Length(PictureData) < 1 then Exit;
  L := Ord(PictureData[1]);
  if Copy(PictureData, 2, L) <> 'TBitmap' then Exit;
  if Length(PictureData) < 1 + L + 4 then Exit;
  N := Ord(PictureData[L + 2]) or (Ord(PictureData[L + 3]) shl 8) or
    (Ord(PictureData[L + 4]) shl 16) or (Ord(PictureData[L + 5]) shl 24);
  Bmp := Copy(PictureData, L + 6, N);
  Result := (Length(Bmp) = N) and (Copy(Bmp, 1, 2) = 'BM');
end;

end.
