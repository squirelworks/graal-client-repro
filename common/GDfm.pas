{ GDfm: reads a Delphi form as the original clients carry it in their
  resources (RCDATA named after the form's class, TCONNECTFRAME,
  TSERVERLISTFRAME, ...), so a rebuild can lay out its windows exactly as
  the program it rebuilds did, from that program's own file.

  The data is Delphi's binary form stream ("TPF0"): per component an
  optional prefix byte ($F0 or more: flags, then an index when bit 2 is
  set), the class name and the component name as short strings, its
  properties (a short string name and a typed value each) up to a 0, its
  child components up to a 0. Values are typed by a first byte: 0 null,
  1 list, 2/3/4 8/16/32-bit integers, 5 extended, 6 and 7 short string and
  identifier, 8 False, 9 True, 10 binary, 11 set, 12 long string, 13 nil,
  14 collection, 15 single, 16 currency, 17 date, 18 wide string, 19
  64-bit integer, 20 UTF-8 string. A collection holds items, each a list
  (1) of properties up to a 0, after an optional integer order value.

  Nothing is interpreted: integers, strings, identifiers and sets are kept
  as text (sets as "[a,b]"), binaries (pictures, glyphs) as bytes, and
  collections flattened to Name[i].Prop. }
unit GDfm;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat,
  Classes;

type
  TDfmNode = class
  public
    ClassName_, Name: string;
    { Prop=Value, in the order the form lists them }
    Props: TStringList;
    { binary properties (Picture.Data, Glyph.Data): name -> bytes }
    Bins: TStringList;
    Children: TList;
    Parent: TDfmNode;
    constructor Create;
    destructor Destroy; override;
    function Child(I: Integer): TDfmNode;
    function Count: Integer;
    { the same as Count (the 2.0x launcher's name for it) }
    function ChildCount: Integer;
    function Has(const Prop: string): Boolean;
    function Str(const Prop: string; const Default: string = ''): string;
    function Int(const Prop: string; Default: Integer = 0): Integer;
    function Bool(const Prop: string; Default: Boolean = False): Boolean;
    function Bin(const Prop: string): string;
    { the component called Name anywhere under this one, or nil }
    function Find(const AName: string): TDfmNode;
  end;

{ The form in Data (a binary form stream), or nil when it is not one. }
function ParseDfm(const Data: string): TDfmNode;

{ A Delphi TColor (a number, or clLime, clGreen, clBtnFace, ...) as an
  ARGB surface colour; Default for names it does not know. }
function DfmColor(const Value: string; Default: Cardinal): Cardinal;

{ The picture inside a TBitmap property (Glyph.Data, Picture.Data of a
  bitmap): the bytes after the stream's own size or class name, from 'BM'
  on; '' when there is none. }
function DfmBitmap(const Data: string): string;

implementation

uses
  SysUtils;

type
  TReader_ = class
    S: string;
    P: Integer; { 1-based }
    Bad: Boolean;
    function U8: Integer;
    function I16: Integer;
    function I32: Integer;
    function Bytes(N: Integer): string;
    function SStr: string;
    function Peek: Integer;
  end;

function TReader_.Peek: Integer;
begin
  if P > Length(S) then
  begin
    Bad := True;
    Result := 0;
  end
  else Result := Ord(S[P]);
end;

function TReader_.U8: Integer;
begin
  Result := Peek;
  Inc(P);
end;

function TReader_.I16: Integer;
begin
  Result := U8 or (U8 shl 8);
  if Result >= $8000 then Dec(Result, $10000);
end;

function TReader_.I32: Integer;
var
  V: Cardinal;
begin
  V := Cardinal(U8) or (Cardinal(U8) shl 8) or (Cardinal(U8) shl 16) or
    (Cardinal(U8) shl 24);
  Result := Integer(V);
end;

function TReader_.Bytes(N: Integer): string;
begin
  if (N < 0) or (P + N - 1 > Length(S)) then
  begin
    Bad := True;
    Result := '';
    P := Length(S) + 1;
    Exit;
  end;
  Result := Copy(S, P, N);
  Inc(P, N);
end;

function TReader_.SStr: string;
begin
  Result := Bytes(U8);
end;

{ ---- nodes ---- }

constructor TDfmNode.Create;
begin
  inherited Create;
  Props := TStringList.Create;
  Bins := TStringList.Create;
  Children := TList.Create;
end;

destructor TDfmNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to Children.Count - 1 do TDfmNode(Children[I]).Free;
  Children.Free;
  for I := 0 to Bins.Count - 1 do Dispose(PString(Bins.Objects[I]));
  Bins.Free;
  Props.Free;
  inherited Destroy;
end;

function TDfmNode.Child(I: Integer): TDfmNode;
begin
  Result := TDfmNode(Children[I]);
end;

function TDfmNode.Count: Integer;
begin
  Result := Children.Count;
end;

function TDfmNode.ChildCount: Integer;
begin
  Result := Children.Count;
end;

function TDfmNode.Has(const Prop: string): Boolean;
begin
  Result := Props.IndexOfName(Prop) >= 0;
end;

function TDfmNode.Str(const Prop, Default: string): string;
var
  I: Integer;
begin
  I := Props.IndexOfName(Prop);
  if I < 0 then Result := Default
  else Result := Copy(Props[I], Length(Prop) + 2, MaxInt);
end;

function TDfmNode.Int(const Prop: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(Str(Prop, ''), Default);
end;

function TDfmNode.Bool(const Prop: string; Default: Boolean): Boolean;
var
  V: string;
begin
  V := Str(Prop, '');
  if V = 'True' then Result := True
  else if V = 'False' then Result := False
  else Result := Default;
end;

function TDfmNode.Bin(const Prop: string): string;
var
  I: Integer;
begin
  I := Bins.IndexOf(Prop);
  if I < 0 then Result := ''
  else Result := string(PString(Bins.Objects[I])^);
end;

function TDfmNode.Find(const AName: string): TDfmNode;
var
  I: Integer;
begin
  if SameText(Name, AName) then
  begin
    Result := Self;
    Exit;
  end;
  for I := 0 to Count - 1 do
  begin
    Result := Child(I).Find(AName);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

{ ---- the stream ---- }

{ One value as text; a binary goes to Node.Bins under Name, a collection
  to Name[i].Prop entries. }
procedure ReadValue(R: TReader_; Node: TDfmNode; const Name: string; out Text: string);
var
  T, N, Item: Integer;
  Sub, PName, V: string;
  Box: PString;
begin
  Text := '';
  T := R.U8;
  case T of
    0: Text := '';
    1:
      begin
        Sub := '';
        while (R.Peek <> 0) and not R.Bad do
        begin
          ReadValue(R, Node, Name, V);
          if Sub <> '' then Sub := Sub + ' ';
          Sub := Sub + V;
        end;
        R.U8;
        Text := '(' + Sub + ')';
      end;
    2: begin N := R.U8; if N >= 128 then Dec(N, 256); Text := IntToStr(N); end;
    3: Text := IntToStr(R.I16);
    4: Text := IntToStr(R.I32);
    5: begin R.Bytes(10); Text := '0'; end;
    6, 7: Text := R.SStr;
    8: Text := 'False';
    9: Text := 'True';
    10:
      begin
        N := R.I32;
        New(Box);
        Box^ := R.Bytes(N);
        Node.Bins.AddObject(Name, TObject(Box));
        Text := '{binary}';
      end;
    11:
      begin
        Sub := '';
        while not R.Bad do
        begin
          V := R.SStr;
          if V = '' then Break;
          if Sub <> '' then Sub := Sub + ',';
          Sub := Sub + V;
        end;
        Text := '[' + Sub + ']';
      end;
    12: begin N := R.I32; Text := R.Bytes(N); end;
    13: Text := 'nil';
    14:
      begin
        Item := 0;
        while (R.Peek <> 0) and not R.Bad do
        begin
          if R.Peek in [2, 3, 4] then ReadValue(R, Node, Name, V);
          if R.Peek = 1 then R.U8;
          while (R.Peek <> 0) and not R.Bad do
          begin
            PName := R.SStr;
            ReadValue(R, Node, Format('%s[%d].%s', [Name, Item, PName]), V);
            Node.Props.Add(Format('%s[%d].%s=%s', [Name, Item, PName, V]));
          end;
          R.U8;
          Inc(Item);
        end;
        R.U8;
        Text := IntToStr(Item);
      end;
    15: begin R.Bytes(4); Text := '0'; end;
    16, 17, 19: begin R.Bytes(8); Text := '0'; end;
    18: begin N := R.I32; Sub := R.Bytes(2 * N); Text := '';
          for Item := 0 to N - 1 do
            if Ord(Sub[2 * Item + 2]) = 0 then Text := Text + Sub[2 * Item + 1]
            else Text := Text + '?';
        end;
    20: begin N := R.I32; Text := R.Bytes(N); end;
  else
    R.Bad := True;
  end;
end;

function ReadComponent(R: TReader_; Parent: TDfmNode): TDfmNode;
var
  Flags: Integer;
  PName, V: string;
begin
  Result := TDfmNode.Create;
  Result.Parent := Parent;
  if (R.Peek and $F0) = $F0 then
  begin
    Flags := R.U8;
    if (Flags and 2) <> 0 then ReadValue(R, Result, '', V);
  end;
  Result.ClassName_ := R.SStr;
  Result.Name := R.SStr;
  while (R.Peek <> 0) and not R.Bad do
  begin
    PName := R.SStr;
    ReadValue(R, Result, PName, V);
    Result.Props.Add(PName + '=' + V);
  end;
  R.U8;
  while (R.Peek <> 0) and not R.Bad do
    Result.Children.Add(ReadComponent(R, Result));
  R.U8;
end;

function ParseDfm(const Data: string): TDfmNode;
var
  R: TReader_;
begin
  Result := nil;
  if Copy(Data, 1, 4) <> 'TPF0' then Exit;
  R := TReader_.Create;
  try
    R.S := Data;
    R.P := 5;
    Result := ReadComponent(R, nil);
    if R.Bad then FreeAndNil(Result);
  finally
    R.Free;
  end;
end;

function DfmColor(const Value: string; Default: Cardinal): Cardinal;
var
  V: Integer;
  C: Cardinal;
begin
  Result := Default;
  if Value = '' then Exit;
  if (Value[1] = '-') or ((Value[1] >= '0') and (Value[1] <= '9')) then
  begin
    V := StrToIntDef(Value, -1);
    if V < 0 then Exit;
    { TColor is $00BBGGRR }
    C := Cardinal(V);
    Result := $FF000000 or ((C and $FF) shl 16) or (C and $FF00) or ((C shr 16) and $FF);
    Exit;
  end;
  if SameText(Value, 'clBlack') then Result := $FF000000
  else if SameText(Value, 'clMaroon') then Result := $FF800000
  else if SameText(Value, 'clGreen') then Result := $FF008000
  else if SameText(Value, 'clOlive') then Result := $FF808000
  else if SameText(Value, 'clNavy') then Result := $FF000080
  else if SameText(Value, 'clPurple') then Result := $FF800080
  else if SameText(Value, 'clTeal') then Result := $FF008080
  else if SameText(Value, 'clGray') then Result := $FF808080
  else if SameText(Value, 'clSilver') then Result := $FFC0C0C0
  else if SameText(Value, 'clRed') then Result := $FFFF0000
  else if SameText(Value, 'clLime') then Result := $FF00FF00
  else if SameText(Value, 'clYellow') then Result := $FFFFFF00
  else if SameText(Value, 'clBlue') then Result := $FF0000FF
  else if SameText(Value, 'clFuchsia') then Result := $FFFF00FF
  else if SameText(Value, 'clAqua') then Result := $FF00FFFF
  else if SameText(Value, 'clWhite') then Result := $FFFFFFFF
  else if SameText(Value, 'clWindow') then Result := $FFFFFFFF
  else if SameText(Value, 'clWindowText') then Result := $FF000000
  else if SameText(Value, 'clBtnFace') then Result := $FFD4D0C8
  else if SameText(Value, 'clBtnText') then Result := $FF000000;
end;

function DfmBitmap(const Data: string): string;
var
  P: Integer;
begin
  P := Pos('BM', Data);
  if (P = 0) or (P > 40) then Result := ''
  else Result := Copy(Data, P, MaxInt);
end;

end.
