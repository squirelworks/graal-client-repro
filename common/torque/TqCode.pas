{ TqCode: compiled TorqueScript code blocks, the DSO v33 loader, and the
  identifier table shared by the loader, the compiler and the VM.

  Source: graal_analysis torque/scripting.md (DSO v33 layout and Graal's
  opcode numbering) and the public behaviour of the Torque Game Engine 1.x
  console. Nothing here is taken from a Graal binary.

  A code block holds two string tables and two float tables (one pair for
  code at file level, one pair for code inside function bodies), the code
  as 32-bit words, and the identifier patches. Identifier words in the code
  are replaced at load time by an index into the shared intern table, so
  the VM reads an identifier as TqIdent(Code[ip]). Index 0 is the empty
  identifier. }
unit TqCode;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { Graal 3.x numbering (torque/scripting.md). 2, 3 and 72 never occur. }
  OP_FUNC_DECL = 0;
  OP_CREATE_OBJECT = 1;
  OP_ADD_OBJECT = 4;
  OP_END_OBJECT = 5;
  OP_JMPIFFNOT = 6;
  OP_JMPIFNOT = 7;
  OP_JMPIFF = 8;
  OP_JMPIF = 9;
  OP_JMPIFNOT_NP = 10;
  OP_JMPIF_NP = 11;
  OP_JMP = 12;
  OP_RETURN = 13;
  OP_CMPEQ = 14;
  OP_CMPGR = 15;
  OP_CMPGE = 16;
  OP_CMPLT = 17;
  OP_CMPLE = 18;
  OP_CMPNE = 19;
  OP_XOR = 20;
  OP_MOD = 21;
  OP_BITAND = 22;
  OP_BITOR = 23;
  OP_NOT = 24;
  OP_NOTF = 25;
  OP_ONESCOMPLEMENT = 26;
  OP_SHR = 27;
  OP_SHL = 28;
  OP_AND = 29;
  OP_OR = 30;
  OP_ADD = 31;
  OP_SUB = 32;
  OP_MUL = 33;
  OP_DIV = 34;
  OP_NEG = 35;
  OP_SETCURVAR = 36;
  OP_SETCURVAR_CREATE = 37;
  OP_SETCURVAR_ARRAY = 38;
  OP_SETCURVAR_ARRAY_CREATE = 39;
  OP_LOADVAR_UINT = 40;
  OP_LOADVAR_FLT = 41;
  OP_LOADVAR_STR = 42;
  OP_SAVEVAR_UINT = 43;
  OP_SAVEVAR_FLT = 44;
  OP_SAVEVAR_STR = 45;
  OP_SETCUROBJECT = 46;
  OP_SETCUROBJECT_NEW = 47;
  OP_SETCURFIELD = 48;
  OP_SETCURFIELD_ARRAY = 49;
  OP_LOADFIELD_UINT = 50;
  OP_LOADFIELD_FLT = 51;
  OP_LOADFIELD_STR = 52;
  OP_SAVEFIELD_UINT = 53;
  OP_SAVEFIELD_FLT = 54;
  OP_SAVEFIELD_STR = 55;
  OP_STR_TO_UINT = 56;
  OP_STR_TO_FLT = 57;
  OP_STR_TO_NONE = 58;
  OP_FLT_TO_UINT = 59;
  OP_FLT_TO_STR = 60;
  OP_FLT_TO_NONE = 61;
  OP_UINT_TO_FLT = 62;
  OP_UINT_TO_STR = 63;
  OP_UINT_TO_NONE = 64;
  OP_LOADIMMED_UINT = 65;
  OP_LOADIMMED_FLT = 66;
  OP_TAG_TO_STR = 67;
  OP_LOADIMMED_STR = 68;
  OP_LOADIMMED_IDENT = 69;
  OP_CALLFUNC_RESOLVE = 70;
  OP_CALLFUNC = 71;
  OP_ADVANCE_STR = 73;
  OP_ADVANCE_STR_APPENDCHAR = 74;
  OP_ADVANCE_STR_COMMA = 75;
  OP_ADVANCE_STR_NUL = 76;
  OP_REWIND_STR = 77;
  OP_TERMINATE_REWIND_STR = 78;
  OP_COMPARE_STR = 79;
  OP_PUSH = 80;
  OP_PUSH_FRAME = 81;
  OP_BREAK = 82;
  OP_COUNT = 83;

  { CALLFUNC call types }
  CALL_FUNCTION = 0;
  CALL_METHOD = 1;
  CALL_PARENT = 2;

type
  TDoubleArray = array of Double;
  TCardinalArray = array of Cardinal;

  TTqCodeBlock = class
  public
    Path: string;          { script path relative to the install root, '/' separated }
    GStr, FStr: AnsiString;
    GFlt, FFlt: TDoubleArray;
    Code: TCardinalArray;
    Version: Cardinal;
    BigEndianFloats: Boolean;
    { Text of the string table entry at Off. }
    function Str(InFunction: Boolean; Off: Cardinal): string;
    function Flt(InFunction: Boolean; Idx: Cardinal): Double;
    { Load a DSO v33 image. Returns False with Err set on a bad file. }
    function LoadDso(const Data: AnsiString; out Err: string): Boolean;
  end;

{ The shared identifier table. Lookups are case-sensitive here; the VM
  compares names case-insensitively where Torque does. }
function TqIntern(const S: string): Cardinal;
function TqIdent(Idx: Cardinal): string;

{ Number of operand words after each opcode (FUNC_DECL is variable). }
function TqOperandCount(Op: Cardinal): Integer;

implementation

uses
  SysUtils, Classes;

var
  Interned: TStringList;  { sorted index into IdentList }
  IdentList: array of string;
  IdentCount: Integer;

function TqIntern(const S: string): Cardinal;
var
  I: Integer;
begin
  if S = '' then
    Exit(0);
  if Interned.Find(S, I) then
    Exit(Cardinal(PtrUInt(Interned.Objects[I])));
  if IdentCount >= Length(IdentList) then
    SetLength(IdentList, IdentCount * 2 + 64);
  IdentList[IdentCount] := S;
  Result := IdentCount;
  Interned.AddObject(S, TObject(PtrUInt(IdentCount)));
  Inc(IdentCount);
end;

function TqIdent(Idx: Cardinal): string;
begin
  if Idx < Cardinal(IdentCount) then
    Result := IdentList[Idx]
  else
    Result := '';
end;

function TqOperandCount(Op: Cardinal): Integer;
begin
  case Op of
    OP_CREATE_OBJECT, OP_CALLFUNC, OP_CALLFUNC_RESOLVE:
      Result := 3;
    OP_ADD_OBJECT, OP_END_OBJECT, OP_JMPIFFNOT, OP_JMPIFNOT, OP_JMPIFF,
    OP_JMPIF, OP_JMPIFNOT_NP, OP_JMPIF_NP, OP_JMP, OP_SETCURVAR,
    OP_SETCURVAR_CREATE, OP_SETCURFIELD, OP_LOADIMMED_UINT,
    OP_LOADIMMED_FLT, OP_TAG_TO_STR, OP_LOADIMMED_STR, OP_LOADIMMED_IDENT,
    OP_ADVANCE_STR_APPENDCHAR:
      Result := 1;
  else
    Result := 0;
  end;
end;

function CStr(const Tab: AnsiString; Off: Cardinal): string;
var
  E: Integer;
begin
  if Off >= Cardinal(Length(Tab)) then
    Exit('');
  E := Off + 1;
  while (E <= Length(Tab)) and (Tab[E] <> #0) do
    Inc(E);
  Result := Copy(Tab, Off + 1, E - Integer(Off) - 1);
end;

function TTqCodeBlock.Str(InFunction: Boolean; Off: Cardinal): string;
begin
  if InFunction then
    Result := CStr(FStr, Off)
  else
    Result := CStr(GStr, Off);
end;

function TTqCodeBlock.Flt(InFunction: Boolean; Idx: Cardinal): Double;
begin
  Result := 0;
  if InFunction then
  begin
    if Idx < Cardinal(Length(FFlt)) then
      Result := FFlt[Idx];
  end
  else if Idx < Cardinal(Length(GFlt)) then
    Result := GFlt[Idx];
end;

function TTqCodeBlock.LoadDso(const Data: AnsiString; out Err: string): Boolean;
var
  P: Integer;

  function Need(N: Integer): Boolean;
  begin
    Result := P + N - 1 <= Length(Data);
    if not Result then
      Err := 'truncated at byte ' + IntToStr(P - 1);
  end;

  function U32(out V: Cardinal): Boolean;
  begin
    Result := Need(4);
    if Result then
    begin
      V := Cardinal(Ord(Data[P])) or (Cardinal(Ord(Data[P + 1])) shl 8) or
        (Cardinal(Ord(Data[P + 2])) shl 16) or (Cardinal(Ord(Data[P + 3])) shl 24);
      Inc(P, 4);
    end;
  end;

  function ReadF64(Pos: Integer; BigEnd: Boolean): Double;
  var
    B: array[0..7] of Byte;
    I: Integer;
  begin
    for I := 0 to 7 do
      if BigEnd then
        B[7 - I] := Ord(Data[Pos + I])
      else
        B[I] := Ord(Data[Pos + I]);
    Move(B, Result, 8);
  end;

  function Plausible(V: Double): Boolean;
  begin
    { the same test as dsodis.py: zero, or a magnitude a script would use }
    Result := (V = 0) or ((Abs(V) > 1e-30) and (Abs(V) < 1e30));
  end;

var
  N, I, J, Cnt, CodeLen, LineBreaks, IdentCnt, Off, UseCnt, IpAt: Cardinal;
  GFPos, FFPos, GFCnt, FFCnt: Integer;
  LittleOk, BigOk: Boolean;
  B: Byte;
  Id: Cardinal;
begin
  Result := False;
  Err := '';
  P := 1;
  if not U32(Version) then Exit;
  if Version <> 33 then
  begin
    Err := 'not DSO version 33 (got ' + IntToStr(Version) + ')';
    Exit;
  end;
  if not U32(N) or not Need(N) then Exit;
  GStr := Copy(Data, P, N);
  Inc(P, N);
  if not U32(Cnt) or not Need(Cnt * 8) then Exit;
  GFPos := P; GFCnt := Cnt;
  Inc(P, Cnt * 8);
  if not U32(N) or not Need(N) then Exit;
  FStr := Copy(Data, P, N);
  Inc(P, N);
  if not U32(Cnt) or not Need(Cnt * 8) then Exit;
  FFPos := P; FFCnt := Cnt;
  Inc(P, Cnt * 8);

  { The PPC Mac build (3.153) writes the F64 tables big-endian while the
    rest stays little-endian; pick the byte order whose values make sense. }
  LittleOk := True;
  BigOk := True;
  for I := 0 to GFCnt - 1 do
  begin
    LittleOk := LittleOk and Plausible(ReadF64(GFPos + Integer(I) * 8, False));
    BigOk := BigOk and Plausible(ReadF64(GFPos + Integer(I) * 8, True));
  end;
  for I := 0 to FFCnt - 1 do
  begin
    LittleOk := LittleOk and Plausible(ReadF64(FFPos + Integer(I) * 8, False));
    BigOk := BigOk and Plausible(ReadF64(FFPos + Integer(I) * 8, True));
  end;
  BigEndianFloats := (not LittleOk) and BigOk;
  SetLength(GFlt, GFCnt);
  for I := 0 to GFCnt - 1 do
    GFlt[I] := ReadF64(GFPos + Integer(I) * 8, BigEndianFloats);
  SetLength(FFlt, FFCnt);
  for I := 0 to FFCnt - 1 do
    FFlt[I] := ReadF64(FFPos + Integer(I) * 8, BigEndianFloats);

  if not U32(CodeLen) or not U32(LineBreaks) then Exit;
  SetLength(Code, CodeLen);
  for I := 0 to CodeLen - 1 do
  begin
    if not Need(1) then Exit;
    B := Ord(Data[P]);
    Inc(P);
    if B = $FF then
    begin
      if not U32(Code[I]) then Exit;
    end
    else
      Code[I] := B;
  end;
  { line/ip pairs: not used by the VM }
  if not Need(Integer(LineBreaks) * 8) then Exit;
  Inc(P, LineBreaks * 8);
  if not U32(IdentCnt) then Exit;
  { Identifier words: listed words get the string at Off (an offset past
    the table, as for an argument the body never uses, gives the empty
    identifier). An identifier word that is not listed is 0 in the file,
    which is also the empty identifier. }
  for J := 1 to IdentCnt do
  begin
    if not U32(Off) or not U32(UseCnt) then Exit;
    Id := TqIntern(CStr(GStr, Off));
    for I := 1 to UseCnt do
    begin
      if not U32(IpAt) then Exit;
      if IpAt < CodeLen then
        Code[IpAt] := Id;
    end;
  end;
  Result := True;
end;

initialization
  Interned := TStringList.Create;
  Interned.Sorted := True;
  Interned.CaseSensitive := True;
  Interned.Duplicates := dupError;
  SetLength(IdentList, 256);
  IdentList[0] := ''; { index 0 is the empty identifier }
  IdentCount := 1;

finalization
  Interned.Free;
end.
