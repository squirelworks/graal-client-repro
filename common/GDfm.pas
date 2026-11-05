{ GDfm: reads a Delphi form as the original program carries it (an RCDATA
  resource named after the form's class, such as TCONNECTFRAME, in the
  binary "TPF0" layout), so a rebuild can lay out its dialogs where the
  original's form puts its controls, read from the original program when
  it lies in the install. Nothing of the form is copied into this program.

  The layout is the Delphi streaming format: "TPF0", then a component:
  optional flags byte ($F0 or more; bit 2 adds a position), class name and
  component name as short strings, properties (a short-string name and a
  typed value) up to a 0, child components up to a 0. Value types: 1 list,
  2/3/4 8/16/32-bit integer, 5 extended, 6 string, 7 identifier, 8 false,
  9 true, 10 binary, 11 set, 12 long string, 13 nil, 14 collection, 15
  single, 16 currency, 17 date, 18 wide string, 19 int64, 20 UTF-8. }
unit GDfm;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes;

type
  TDfmProp = record
    Name: string;
    { integers in decimal, identifiers and strings as they are, sets as
      their members with commas, true/false as True/False; collections
      give one property per item field, "Columns[0].Width" }
    Value: string;
    { the bytes of a binary property (Glyph.Data, Bitmap) }
    Binary: Boolean;
  end;

  TDfmNode = class
  public
    ClassName_, Name: string;
    Props: array of TDfmProp;
    Children: TList;
    constructor Create;
    destructor Destroy; override;
    function Has(const Prop: string): Boolean;
    function Str(const Prop: string; const Default: string = ''): string;
    function Int(const Prop: string; Default: Integer = 0): Integer;
    function Bool(const Prop: string; Default: Boolean = False): Boolean;
    function Child(I: Integer): TDfmNode;
    function ChildCount: Integer;
    { This node or the first one under it named Name (case-insensitive). }
    function Find(const AName: string): TDfmNode;
  end;

{ The form in Data ("TPF0" ...), or nil when it does not read as one. }
function ParseDfm(const Data: string): TDfmNode;

{ A Delphi colour (clLime, clGreen, clBtnFace, a $00BBGGRR number) as
  $AARRGGBB; Default when it is none of these. System colours are the
  classic Windows scheme. }
function DfmColor(const Value: string; Default: Cardinal): Cardinal;

implementation

uses
  SysUtils;

constructor TDfmNode.Create;
begin
  inherited Create;
  Children := TList.Create;
end;

destructor TDfmNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to Children.Count - 1 do TDfmNode(Children[I]).Free;
  Children.Free;
  inherited Destroy;
end;

function TDfmNode.Has(const Prop: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Props) do
    if SameText(Props[I].Name, Prop) then
    begin
      Result := True;
      Exit;
    end;
end;

function TDfmNode.Str(const Prop: string; const Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  for I := 0 to High(Props) do
    if SameText(Props[I].Name, Prop) then
    begin
      Result := Props[I].Value;
      Exit;
    end;
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
  if SameText(V, 'True') then Result := True
  else if SameText(V, 'False') then Result := False
  else Result := Default;
end;

function TDfmNode.Child(I: Integer): TDfmNode;
begin
  Result := TDfmNode(Children[I]);
end;

function TDfmNode.ChildCount: Integer;
begin
  Result := Children.Count;
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
  for I := 0 to Children.Count - 1 do
  begin
    Result := Child(I).Find(AName);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

type
  EDfm = class(Exception);

  TDfmReader = class
    D: string;
    P: Integer; { 1-based }
    function Byte_: Integer;
    function Peek: Integer;
    function Bytes(N: Integer): string;
    function I32: Integer;
    function ShortStr: string;
    procedure Value(Node: TDfmNode; const Name: string);
    function Component: TDfmNode;
  end;

function TDfmReader.Peek: Integer;
begin
  if P > Length(D) then raise EDfm.Create('end of form');
  Result := Ord(D[P]);
end;

function TDfmReader.Byte_: Integer;
begin
  Result := Peek;
  Inc(P);
end;

function TDfmReader.Bytes(N: Integer): string;
begin
  if (N < 0) or (P + N - 1 > Length(D)) then raise EDfm.Create('end of form');
  Result := Copy(D, P, N);
  Inc(P, N);
end;

function TDfmReader.I32: Integer;
var
  S: string;
begin
  S := Bytes(4);
  Result := Integer(Cardinal(Ord(S[1])) or (Cardinal(Ord(S[2])) shl 8) or
    (Cardinal(Ord(S[3])) shl 16) or (Cardinal(Ord(S[4])) shl 24));
end;

function TDfmReader.ShortStr: string;
begin
  Result := Bytes(Byte_);
end;

procedure TDfmReader.Value(Node: TDfmNode; const Name: string);
var
  T, N, Item, Idx: Integer;
  V, Part: string;
  Bin: Boolean;
  Sub: TDfmNode;
  J: Integer;

  procedure Add(const AName, AValue: string; IsBin: Boolean);
  begin
    SetLength(Node.Props, Length(Node.Props) + 1);
    Node.Props[High(Node.Props)].Name := AName;
    Node.Props[High(Node.Props)].Value := AValue;
    Node.Props[High(Node.Props)].Binary := IsBin;
  end;

begin
  Bin := False;
  T := Byte_;
  case T of
    0: V := '';
    1:
      begin
        { a list: kept as its items with commas }
        V := '';
        while Peek <> 0 do
        begin
          Sub := TDfmNode.Create;
          try
            Value(Sub, 'x');
            if V <> '' then V := V + ',';
            if Length(Sub.Props) > 0 then V := V + Sub.Props[0].Value;
          finally
            Sub.Free;
          end;
        end;
        Inc(P);
      end;
    2: V := IntToStr(ShortInt(Byte_));
    3:
      begin
        Part := Bytes(2);
        V := IntToStr(SmallInt(Word(Ord(Part[1]) or (Ord(Part[2]) shl 8))));
      end;
    4: V := IntToStr(I32);
    5: begin Bytes(10); V := '0'; end;
    6, 7: V := ShortStr;
    8: V := 'False';
    9: V := 'True';
    10:
      begin
        N := I32;
        V := Bytes(N);
        Bin := True;
      end;
    11:
      begin
        V := '';
        repeat
          Part := ShortStr;
          if Part <> '' then
          begin
            if V <> '' then V := V + ',';
            V := V + Part;
          end;
        until Part = '';
      end;
    12, 20: V := Bytes(I32);
    13: V := '';
    14:
      begin
        Item := 0;
        while Peek <> 0 do
        begin
          if Peek in [2, 3, 4] then
          begin
            Sub := TDfmNode.Create;
            try
              Value(Sub, 'x');
            finally
              Sub.Free;
            end;
          end;
          if Byte_ <> 1 then raise EDfm.Create('bad collection');
          Sub := TDfmNode.Create;
          try
            while Peek <> 0 do
            begin
              Part := ShortStr;
              Value(Sub, Part);
            end;
            Inc(P);
            for J := 0 to High(Sub.Props) do
              Add(Format('%s[%d].%s', [Name, Item, Sub.Props[J].Name]), Sub.Props[J].Value,
                Sub.Props[J].Binary);
          finally
            Sub.Free;
          end;
          Inc(Item);
        end;
        Inc(P);
        Exit;
      end;
    15: begin Bytes(4); V := '0'; end;
    16, 17, 19: begin Bytes(8); V := '0'; end;
    18:
      begin
        N := I32;
        Part := Bytes(N * 2);
        V := '';
        for Idx := 0 to N - 1 do
          if Ord(Part[Idx * 2 + 2]) = 0 then V := V + Part[Idx * 2 + 1] else V := V + '?';
      end;
  else
    raise EDfm.CreateFmt('value type %d', [T]);
  end;
  Add(Name, V, Bin);
end;

function TDfmReader.Component: TDfmNode;
var
  Flags: Integer;
  Name: string;
  Sub: TDfmNode;
begin
  Result := TDfmNode.Create;
  try
    if Peek and $F0 = $F0 then
    begin
      Flags := Byte_;
      if Flags and 2 <> 0 then
      begin
        Sub := TDfmNode.Create;
        try
          Value(Sub, 'x');
        finally
          Sub.Free;
        end;
      end;
    end;
    Result.ClassName_ := ShortStr;
    Result.Name := ShortStr;
    while Peek <> 0 do
    begin
      Name := ShortStr;
      Value(Result, Name);
    end;
    Inc(P);
    while Peek <> 0 do Result.Children.Add(Component);
    Inc(P);
  except
    Result.Free;
    raise;
  end;
end;

function ParseDfm(const Data: string): TDfmNode;
var
  R: TDfmReader;
begin
  Result := nil;
  if Copy(Data, 1, 4) <> 'TPF0' then Exit;
  R := TDfmReader.Create;
  try
    R.D := Data;
    R.P := 5;
    try
      Result := R.Component;
    except
      on EDfm do Result := nil;
    end;
  finally
    R.Free;
  end;
end;

function DfmColor(const Value: string; Default: Cardinal): Cardinal;
var
  N: Int64;
  V: string;
begin
  Result := Default;
  V := LowerCase(Value);
  if V = '' then Exit;
  if V = 'clblack' then Result := $FF000000
  else if V = 'clmaroon' then Result := $FF800000
  else if V = 'clgreen' then Result := $FF008000
  else if V = 'clolive' then Result := $FF808000
  else if V = 'clnavy' then Result := $FF000080
  else if V = 'clpurple' then Result := $FF800080
  else if V = 'clteal' then Result := $FF008080
  else if V = 'clgray' then Result := $FF808080
  else if V = 'clsilver' then Result := $FFC0C0C0
  else if V = 'clred' then Result := $FFFF0000
  else if V = 'cllime' then Result := $FF00FF00
  else if V = 'clyellow' then Result := $FFFFFF00
  else if V = 'clblue' then Result := $FF0000FF
  else if V = 'clfuchsia' then Result := $FFFF00FF
  else if V = 'claqua' then Result := $FF00FFFF
  else if V = 'clwhite' then Result := $FFFFFFFF
  else if (V = 'clbtnface') or (V = 'clmenu') or (V = 'clscrollbar') then Result := $FFC0C0C0
  else if (V = 'clwindow') then Result := $FFFFFFFF
  else if (V = 'clwindowtext') or (V = 'clbtntext') or (V = 'clmenutext') then Result := $FF000000
  else if (V = 'clhighlight') or (V = 'clactivecaption') then Result := $FF000080
  else if V = 'clhighlighttext' then Result := $FFFFFFFF
  else if (V = 'clbtnshadow') or (V = 'clgraytext') then Result := $FF808080
  else if V = 'clbtnhighlight' then Result := $FFFFFFFF
  else if TryStrToInt64(Value, N) and (N >= 0) and (N <= $FFFFFF) then
    { $00BBGGRR }
    Result := $FF000000 or Cardinal((N and $FF) shl 16) or Cardinal(N and $FF00) or
      Cardinal((N shr 16) and $FF);
end;

end.
