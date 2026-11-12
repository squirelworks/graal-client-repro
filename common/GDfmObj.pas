{ GDfmObj: reads a Delphi binary form (the TPF0 stream a Delphi program keeps
  in its RCDATA, one per form) into a tree of objects and properties.

  The 1998 and 1999 Graal clients were Delphi 3 programs: every window
  (the start dialog, the game window, the options and editor dialogs) is
  such a form. The rebuilds carry their real client's forms (extracted by
  scripts/realres/extract_res.py) and build their windows from them, so
  sizes, captions, positions, fonts, pictures and list items are the
  original's own.

  Value types read: integers (8/16/32/64 bit), extended and single floats,
  strings (short, long, wide), identifiers, booleans, sets, lists,
  binary data (pictures, glyphs) and collections. }
unit GDfmObj;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils;

type
  TDfmStrings = array of string;
  TDfmKind = (dkNone, dkInt, dkFloat, dkStr, dkIdent, dkBool, dkSet,
    dkList, dkBinary, dkCollection, dkNil);

  TDfmValue = record
    Kind: TDfmKind;
    I: Int64;
    F: Double;
    S: string;            { string, identifier, binary bytes }
    Items: array of string; { set members, list items (as text) }
  end;

  TDfmProp = record
    Name: string;
    V: TDfmValue;
  end;

  TDfmObj = class
  public
    ClassName_: string;
    Name: string;
    Inherited_: Boolean;
    Props: array of TDfmProp;
    Children: array of TDfmObj;
    Parent: TDfmObj;
    destructor Destroy; override;
    function IndexOf(const Prop: string): Integer;
    function Has(const Prop: string): Boolean;
    function Int(const Prop: string; Default: Integer): Integer;
    function Str(const Prop: string; const Default: string): string;
    function Ident(const Prop: string; const Default: string): string;
    function Bool(const Prop: string; Default: Boolean): Boolean;
    function InSet(const Prop, Member: string): Boolean;
    function SetText(const Prop: string): string;
    function List(const Prop: string): TDfmStrings;
    function Bin(const Prop: string): string;
    { The object named Name here or below (any case), or nil. }
    function Find(const AName: string): TDfmObj;
    function IsA(const AClass: string): Boolean;
  end;

{ Parses Data (starting with 'TPF0'). Raises EDfmError on a bad stream. }
function ParseDfm(const Data: string): TDfmObj;

type
  EDfmError = class(Exception);

{ The bitmap inside a TPicture's Data property ('TBitmap' + size + BMP
  file), or a TBitmap glyph's Data (size + BMP file). '' if not a bitmap. }
function DfmPictureBitmap(const Data: string): string;
function DfmGlyphBitmap(const Data: string): string;
{ The icon inside a TPicture's Data property ('TIcon' + .ico file). }
function DfmPictureIcon(const Data: string): string;

implementation

type
  TReader_ = record
    B: string;
    P: Integer; { 1-based }
  end;

procedure Need(var R: TReader_; N: Integer);
begin
  if R.P + N - 1 > Length(R.B) then
    raise EDfmError.Create('form stream ends early');
end;

function U8(var R: TReader_): Integer;
begin
  Need(R, 1);
  Result := Ord(R.B[R.P]);
  Inc(R.P);
end;

function Peek(var R: TReader_): Integer;
begin
  Need(R, 1);
  Result := Ord(R.B[R.P]);
end;

function Bytes(var R: TReader_; N: Integer): string;
begin
  if N < 0 then raise EDfmError.Create('bad length');
  Need(R, N);
  Result := Copy(R.B, R.P, N);
  Inc(R.P, N);
end;

function I16(var R: TReader_): Integer;
var
  S: string;
begin
  S := Bytes(R, 2);
  Result := SmallInt(Ord(S[1]) or (Ord(S[2]) shl 8));
end;

function I32(var R: TReader_): Int64;
var
  S: string;
begin
  S := Bytes(R, 4);
  Result := LongInt(Cardinal(Ord(S[1])) or (Cardinal(Ord(S[2])) shl 8) or
    (Cardinal(Ord(S[3])) shl 16) or (Cardinal(Ord(S[4])) shl 24));
end;

function ShortStr(var R: TReader_): string;
begin
  Result := Bytes(R, U8(R));
end;

procedure AddItem(var V: TDfmValue; const S: string);
begin
  SetLength(V.Items, Length(V.Items) + 1);
  V.Items[High(V.Items)] := S;
end;

function ValueText(const V: TDfmValue): string;
begin
  case V.Kind of
    dkInt: Result := IntToStr(V.I);
    dkFloat: Result := FloatToStr(V.F);
    dkBool: if V.I <> 0 then Result := 'True' else Result := 'False';
  else
    Result := V.S;
  end;
end;

procedure ReadValue(var R: TReader_; out V: TDfmValue); forward;

procedure ReadValue(var R: TReader_; out V: TDfmValue);
var
  T, N, I: Integer;
  S: string;
  W: WideString;
  Sub: TDfmValue;
  Ex: array[0..9] of Byte;
begin
  V.Kind := dkNone;
  V.I := 0;
  V.F := 0;
  V.S := '';
  SetLength(V.Items, 0);
  T := U8(R);
  case T of
    0: V.Kind := dkNone;
    1: begin { list }
         V.Kind := dkList;
         while Peek(R) <> 0 do
         begin
           ReadValue(R, Sub);
           AddItem(V, ValueText(Sub));
         end;
         U8(R);
       end;
    2: begin V.Kind := dkInt; V.I := ShortInt(U8(R)); end;
    3: begin V.Kind := dkInt; V.I := I16(R); end;
    4: begin V.Kind := dkInt; V.I := I32(R); end;
    5: begin { extended: read the 10 bytes and convert }
         S := Bytes(R, 10);
         for I := 0 to 9 do Ex[I] := Ord(S[I + 1]);
         V.Kind := dkFloat;
         { 80-bit: 64-bit mantissa, 15-bit exponent, sign }
         N := (Ex[8] or (Ex[9] shl 8)) and $7FFF;
         V.F := 0;
         for I := 7 downto 0 do V.F := V.F * 256 + Ex[I];
         if N <> 0 then V.F := V.F * Exp((N - 16383 - 63) * Ln(2));
         if Ex[9] and $80 <> 0 then V.F := -V.F;
       end;
    6: begin V.Kind := dkStr; V.S := ShortStr(R); end;
    7: begin V.Kind := dkIdent; V.S := ShortStr(R); end;
    8: begin V.Kind := dkBool; V.I := 0; end;
    9: begin V.Kind := dkBool; V.I := 1; end;
    10: begin V.Kind := dkBinary; V.S := Bytes(R, I32(R)); end;
    11: begin { set }
          V.Kind := dkSet;
          repeat
            S := ShortStr(R);
            if S <> '' then AddItem(V, S);
          until S = '';
        end;
    12: begin V.Kind := dkStr; V.S := Bytes(R, I32(R)); end;
    13: V.Kind := dkNil;
    14: begin { collection: items of properties, kept as text }
          V.Kind := dkCollection;
          while Peek(R) <> 0 do
          begin
            if Peek(R) in [2, 3, 4] then ReadValue(R, Sub); { order index }
            if U8(R) <> 1 then raise EDfmError.Create('bad collection item');
            S := '';
            while Peek(R) <> 0 do
            begin

              S := S + ShortStr(R) + '=';
              ReadValue(R, Sub);
              S := S + ValueText(Sub) + ';';

            end;
            U8(R);
            AddItem(V, S);
          end;
          U8(R);
        end;
    15: begin { single }
          S := Bytes(R, 4);
          V.Kind := dkFloat;
          V.F := PSingle(@S[1])^;
        end;
    16: begin { currency }
          S := Bytes(R, 8);
          V.Kind := dkFloat;
          V.F := PInt64(@S[1])^ / 10000;
        end;
    17: begin { date }
          S := Bytes(R, 8);
          V.Kind := dkFloat;
          V.F := PDouble(@S[1])^;
        end;
    18: begin { wide string }
          N := I32(R);
          S := Bytes(R, N * 2);
          SetLength(W, N);
          if N > 0 then Move(S[1], W[1], N * 2);
          V.Kind := dkStr;
          V.S := string(W);
        end;
    19: begin { int64 }
          S := Bytes(R, 8);
          V.Kind := dkInt;
          V.I := PInt64(@S[1])^;
        end;
  else
    raise EDfmError.CreateFmt('unknown value type %d', [T]);
  end;
end;

function ReadObject(var R: TReader_; Parent: TDfmObj): TDfmObj;
var
  F: Integer;
  P: TDfmProp;
  C: TDfmObj;
begin
  Result := TDfmObj.Create;
  try
    Result.Parent := Parent;
    F := Peek(R);
    if F and $F0 = $F0 then
    begin
      U8(R);
      Result.Inherited_ := F and 1 <> 0;
      if F and 2 <> 0 then ReadValue(R, P.V); { child position }
    end;
    Result.ClassName_ := ShortStr(R);
    Result.Name := ShortStr(R);
    while Peek(R) <> 0 do
    begin
      P.Name := ShortStr(R);
      ReadValue(R, P.V);
      SetLength(Result.Props, Length(Result.Props) + 1);
      Result.Props[High(Result.Props)] := P;
    end;
    U8(R);
    while Peek(R) <> 0 do
    begin
      C := ReadObject(R, Result);
      SetLength(Result.Children, Length(Result.Children) + 1);
      Result.Children[High(Result.Children)] := C;
    end;
    U8(R);
  except
    Result.Free;
    raise;
  end;
end;

function ParseDfm(const Data: string): TDfmObj;
var
  R: TReader_;
begin
  if Copy(Data, 1, 4) <> 'TPF0' then
    raise EDfmError.Create('not a Delphi form stream');
  R.B := Data;
  R.P := 5;
  Result := ReadObject(R, nil);
end;

{ TDfmObj }

destructor TDfmObj.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Children) do Children[I].Free;
  inherited;
end;

function TDfmObj.IndexOf(const Prop: string): Integer;
begin
  for Result := 0 to High(Props) do
    if SameText(Props[Result].Name, Prop) then Exit;
  Result := -1;
end;

function TDfmObj.Has(const Prop: string): Boolean;
begin
  Result := IndexOf(Prop) >= 0;
end;

function TDfmObj.Int(const Prop: string; Default: Integer): Integer;
var
  I: Integer;
begin
  I := IndexOf(Prop);
  if (I >= 0) and (Props[I].V.Kind = dkInt) then Result := Props[I].V.I
  else Result := Default;
end;

function TDfmObj.Str(const Prop: string; const Default: string): string;
var
  I: Integer;
begin
  I := IndexOf(Prop);
  if (I >= 0) and (Props[I].V.Kind in [dkStr, dkIdent]) then Result := Props[I].V.S
  else Result := Default;
end;

function TDfmObj.Ident(const Prop: string; const Default: string): string;
begin
  Result := Str(Prop, Default);
end;

function TDfmObj.Bool(const Prop: string; Default: Boolean): Boolean;
var
  I: Integer;
begin
  I := IndexOf(Prop);
  if (I >= 0) and (Props[I].V.Kind = dkBool) then Result := Props[I].V.I <> 0
  else Result := Default;
end;

function TDfmObj.InSet(const Prop, Member: string): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  I := IndexOf(Prop);
  if I < 0 then Exit;
  for J := 0 to High(Props[I].V.Items) do
    if SameText(Props[I].V.Items[J], Member) then begin Result := True; Exit; end;
end;

function TDfmObj.SetText(const Prop: string): string;
var
  I, J: Integer;
begin
  Result := '';
  I := IndexOf(Prop);
  if I < 0 then Exit;
  for J := 0 to High(Props[I].V.Items) do
  begin
    if J > 0 then Result := Result + ',';
    Result := Result + Props[I].V.Items[J];
  end;
  Result := '[' + Result + ']';
end;

function TDfmObj.List(const Prop: string): TDfmStrings;
var
  I, J: Integer;
begin
  SetLength(Result, 0);
  I := IndexOf(Prop);
  if I < 0 then Exit;
  SetLength(Result, Length(Props[I].V.Items));
  for J := 0 to High(Result) do Result[J] := Props[I].V.Items[J];
end;

function TDfmObj.Bin(const Prop: string): string;
var
  I: Integer;
begin
  I := IndexOf(Prop);
  if (I >= 0) and (Props[I].V.Kind = dkBinary) then Result := Props[I].V.S
  else Result := '';
end;

function TDfmObj.Find(const AName: string): TDfmObj;
var
  I: Integer;
begin
  if SameText(Name, AName) then begin Result := Self; Exit; end;
  for I := 0 to High(Children) do
  begin
    Result := Children[I].Find(AName);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

function TDfmObj.IsA(const AClass: string): Boolean;
begin
  Result := SameText(ClassName_, AClass);
end;

function LE32(const S: string; P: Integer): Integer;
begin
  Result := Ord(S[P]) or (Ord(S[P + 1]) shl 8) or (Ord(S[P + 2]) shl 16) or
    (Ord(S[P + 3]) shl 24);
end;

function DfmPictureBitmap(const Data: string): string;
var
  N: Integer;
begin
  Result := '';
  if Data = '' then Exit;
  N := Ord(Data[1]);
  if (N + 1 > Length(Data)) or not SameText(Copy(Data, 2, N), 'TBitmap') then Exit;
  Result := DfmGlyphBitmap(Copy(Data, N + 2, MaxInt));
end;

function DfmGlyphBitmap(const Data: string): string;
var
  Size: Integer;
begin
  Result := '';
  if Length(Data) < 6 then Exit;
  Size := LE32(Data, 1);
  if (Size <= 0) or (Size + 4 > Length(Data)) then Exit;
  Result := Copy(Data, 5, Size);
  if Copy(Result, 1, 2) <> 'BM' then Result := '';
end;

function DfmPictureIcon(const Data: string): string;
var
  N: Integer;
begin
  Result := '';
  if Data = '' then Exit;
  N := Ord(Data[1]);
  if (N + 1 > Length(Data)) or not SameText(Copy(Data, 2, N), 'TIcon') then Exit;
  Result := Copy(Data, N + 2, MaxInt);
end;

end.
