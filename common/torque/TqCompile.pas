{ TqCompile: compiles TorqueScript source (.cs, .gui text, eval strings)
  into a TTqCodeBlock with the same opcodes the shipped .dso files use, so
  one VM runs both.

  The real 3.x client compiles every plain .cs it executes (the root
  main.cs, the prefs.cs and config.cs it writes, eval strings); this unit
  is that compiler. It follows the public TorqueScript grammar of TGE 1.x
  (operator precedence, the typed value stacks, the string-stack
  concatenation ops). The byte layout of its output is our own; only the
  behaviour has to match. }
unit TqCompile;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  TqCode;

{ Compile Src. Path is stored in the block (for "./" and "~/" lookups).
  On a syntax error returns nil and sets Err to "path line N: message". }
function TqCompileSource(const Src, Path: string; out Err: string): TTqCodeBlock;

implementation

uses
  SysUtils, Classes;

type
  TTokKind = (tkEOF, tkIdent, tkLocal, tkGlobal, tkInt, tkFloat, tkStr,
    tkTag, tkOp);

  TTok = record
    Kind: TTokKind;
    S: string;        { identifier / string text / operator }
    I: Int64;
    F: Double;
    Line: Integer;
  end;

  TReq = (rqNone, rqUint, rqFlt, rqStr);

  TNodeKind = (nkInt, nkFloat, nkStr, nkTag, nkVar, nkField, nkCall,
    nkMethod, nkBin, nkUnary, nkAssign, nkCond, nkNew, nkIncDec);

  TNode = class;
  TNodeList = array of TNode;

  TNode = class
    Kind: TNodeKind;
    I: Int64;
    F: Double;
    S: string;          { literal text, var name, field name, fn name, op }
    Ns: string;         { call namespace }
    CallType: Integer;
    A, B, C: TNode;     { operands; field: A = object (nil = new object) }
    Idx: TNodeList;     { array indices }
    Args: TNodeList;
    Fields: TNodeList;  { nkNew: assignments to fields of the new object }
    Subs: TNodeList;    { nkNew: nested new objects }
    IsDatablock: Boolean;
    ParentName: string;
    destructor Destroy; override;
  end;

  ECompile = class(Exception);

  TLoopCtx = record
    Breaks, Continues: array of Integer;
  end;

  TCompiler = class
  private
    Src: string;
    Pos, Line: Integer;
    Tok, Peek1: TTok;
    HavePeek: Boolean;
    Blk: TTqCodeBlock;
    Code: array of Cardinal;
    CodeLen: Integer;
    StrMap: TStringList;
    Floats: array of Double;
    Loops: array of TLoopCtx;
    procedure Fail(const Msg: string);
    function LexOne: TTok;
    procedure Next;
    function PeekTok: TTok;
    function IsOp(const S: string): Boolean;
    function IsWord(const S: string): Boolean;
    procedure Expect(const S: string);
    function ExpectIdent: string;
    { code emission }
    procedure Emit(W: Cardinal);
    function Here: Integer;
    procedure Patch(At: Integer; Value: Cardinal);
    function StrOff(const S: string): Cardinal;
    function FltIdx(D: Double): Cardinal;
    { parsing }
    function ParseExpr: TNode;
    function ParseAssign: TNode;
    function ParseCond: TNode;
    function ParseBin(Level: Integer): TNode;
    function ParseUnary: TNode;
    function ParsePostfix: TNode;
    function ParsePrimary: TNode;
    function ParseArgs: TNodeList;
    function ParseNew: TNode;
    procedure ParseStatement(const Pkg: string);
    procedure ParseBlockOrStatement(const Pkg: string);
    procedure ParseFunction(const Pkg: string);
    { codegen }
    function Natural(N: TNode): TReq;
    procedure Convert(From, ToReq: TReq);
    procedure Gen(N: TNode; Req: TReq);
    procedure GenStrSlot(N: TNode);
    procedure GenCond(N: TNode; JumpIfFalse: Boolean; out PatchAt: Integer);
    procedure GenNew(N: TNode; AtRoot: Boolean);
    procedure GenAssignTo(Target: TNode; ValueType: TReq);
  public
    function Run(const ASrc, APath: string): TTqCodeBlock;
  end;

destructor TNode.Destroy;
var
  X: TNode;
begin
  A.Free; B.Free; C.Free;
  for X in Idx do X.Free;
  for X in Args do X.Free;
  for X in Fields do X.Free;
  for X in Subs do X.Free;
  inherited;
end;

function NewNode(K: TNodeKind): TNode;
begin
  Result := TNode.Create;
  Result.Kind := K;
end;

procedure AddTo(var L: TNodeList; N: TNode);
begin
  SetLength(L, Length(L) + 1);
  L[High(L)] := N;
end;

{ --- lexer --- }

procedure TCompiler.Fail(const Msg: string);
begin
  raise ECompile.CreateFmt('%s line %d: %s', [Blk.Path, Tok.Line, Msg]);
end;

var
  DotFmt: TFormatSettings;

function IsIdStart(C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '_'];
end;

function IsIdChar(C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '_', '0'..'9'];
end;

function TCompiler.LexOne: TTok;
const
  Ops3: array[0..3] of string = ('!$=', '<<=', '>>=', '...');
  Ops2: array[0..19] of string = ('==', '!=', '<=', '>=', '&&', '||', '<<',
    '>>', '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '$=', '::');
var
  C: Char;
  St, J: Integer;
  S: string;
  Hex: Integer;

  function At(K: Integer): Char;
  begin
    if K <= Length(Src) then Result := Src[K] else Result := #0;
  end;

  function ReadName(Start: Integer): string;
  var
    K: Integer;
  begin
    K := Start;
    while True do
    begin
      while IsIdChar(At(K)) do Inc(K);
      if (At(K) = ':') and (At(K + 1) = ':') and IsIdStart(At(K + 2)) then
        Inc(K, 2)
      else
        Break;
    end;
    Result := Copy(Src, Start, K - Start);
    Pos := K;
  end;

begin
  { skip blanks and comments }
  while True do
  begin
    C := At(Pos);
    if C = #10 then begin Inc(Line); Inc(Pos); end
    else if C in [#1..' '] then Inc(Pos)
    else if (C = '/') and (At(Pos + 1) = '/') then
      while not (At(Pos) in [#0, #10]) do Inc(Pos)
    else if (C = '/') and (At(Pos + 1) = '*') then
    begin
      Inc(Pos, 2);
      while (At(Pos) <> #0) and not ((At(Pos) = '*') and (At(Pos + 1) = '/')) do
      begin
        if At(Pos) = #10 then Inc(Line);
        Inc(Pos);
      end;
      Inc(Pos, 2);
    end
    else
      Break;
  end;
  Result.Line := Line;
  Result.S := '';
  Result.I := 0;
  Result.F := 0;
  C := At(Pos);
  if C = #0 then
  begin
    Result.Kind := tkEOF;
    Exit;
  end;
  if IsIdStart(C) then
  begin
    Result.Kind := tkIdent;
    Result.S := ReadName(Pos);
    Exit;
  end;
  if ((C = '%') or (C = '$')) and IsIdStart(At(Pos + 1)) then
  begin
    if C = '%' then Result.Kind := tkLocal else Result.Kind := tkGlobal;
    Result.S := C + ReadName(Pos + 1);
    Exit;
  end;
  if (C in ['0'..'9']) or ((C = '.') and (At(Pos + 1) in ['0'..'9'])) then
  begin
    St := Pos;
    if (C = '0') and (At(Pos + 1) in ['x', 'X']) then
    begin
      Inc(Pos, 2);
      Hex := 0;
      while At(Pos) in ['0'..'9', 'a'..'f', 'A'..'F'] do
      begin
        Hex := Hex * 16 + StrToInt('$' + At(Pos));
        Inc(Pos);
      end;
      Result.Kind := tkInt;
      Result.I := Hex;
      Result.S := Copy(Src, St, Pos - St);
      Exit;
    end;
    while At(Pos) in ['0'..'9'] do Inc(Pos);
    Result.Kind := tkInt;
    if (At(Pos) = '.') and (At(Pos + 1) in ['0'..'9']) then
    begin
      Result.Kind := tkFloat;
      Inc(Pos);
      while At(Pos) in ['0'..'9'] do Inc(Pos);
    end;
    if (At(Pos) in ['e', 'E']) and ((At(Pos + 1) in ['0'..'9']) or
      ((At(Pos + 1) in ['+', '-']) and (At(Pos + 2) in ['0'..'9']))) then
    begin
      Result.Kind := tkFloat;
      Inc(Pos, 2);
      while At(Pos) in ['0'..'9'] do Inc(Pos);
    end;
    Result.S := Copy(Src, St, Pos - St);
    if Result.Kind = tkInt then
      Result.I := StrToInt64Def(Result.S, 0)
    else
      Result.F := StrToFloatDef(Result.S, 0, DotFmt);
    Exit;
  end;
  if (C = '"') or (C = '''') then
  begin
    if C = '"' then Result.Kind := tkStr else Result.Kind := tkTag;
    Inc(Pos);
    S := '';
    while (At(Pos) <> C) and (At(Pos) <> #0) do
    begin
      if At(Pos) = #10 then Inc(Line);
      if At(Pos) = '\' then
      begin
        Inc(Pos);
        case At(Pos) of
          'n': S := S + #10;
          't': S := S + #9;
          'r': S := S + #13;
          'x':
            begin
              Hex := 0;
              for J := 1 to 2 do
                if At(Pos + 1) in ['0'..'9', 'a'..'f', 'A'..'F'] then
                begin
                  Inc(Pos);
                  Hex := Hex * 16 + StrToInt('$' + At(Pos));
                end;
              S := S + Chr(Hex);
            end;
          'c':
            begin
              { colour codes \c0..\c9 map to bytes 2..11 (TGE escape set),
                with \cr, \cp, \co for reset, push, pop }
              Inc(Pos);
              case At(Pos) of
                '0'..'9': S := S + Chr(Ord(At(Pos)) - Ord('0') + 2);
                'r': S := S + #15;
                'p': S := S + #16;
                'o': S := S + #17;
              end;
            end;
        else
          S := S + At(Pos);
        end;
        Inc(Pos);
      end
      else
      begin
        S := S + At(Pos);
        Inc(Pos);
      end;
    end;
    Inc(Pos);
    Result.S := S;
    Exit;
  end;
  Result.Kind := tkOp;
  for S in Ops3 do
    if Copy(Src, Pos, 3) = S then
    begin
      Result.S := S;
      Inc(Pos, 3);
      Exit;
    end;
  for S in Ops2 do
    if Copy(Src, Pos, 2) = S then
    begin
      Result.S := S;
      Inc(Pos, 2);
      Exit;
    end;
  Result.S := C;
  Inc(Pos);
end;

procedure TCompiler.Next;
begin
  if HavePeek then
  begin
    Tok := Peek1;
    HavePeek := False;
  end
  else
    Tok := LexOne;
end;

function TCompiler.PeekTok: TTok;
begin
  if not HavePeek then
  begin
    Peek1 := LexOne;
    HavePeek := True;
  end;
  Result := Peek1;
end;

function TCompiler.IsOp(const S: string): Boolean;
begin
  Result := (Tok.Kind = tkOp) and (Tok.S = S);
end;

function TCompiler.IsWord(const S: string): Boolean;
begin
  Result := (Tok.Kind = tkIdent) and SameText(Tok.S, S);
end;

procedure TCompiler.Expect(const S: string);
begin
  if not IsOp(S) then
    Fail('expected "' + S + '", found "' + Tok.S + '"');
  Next;
end;

function TCompiler.ExpectIdent: string;
begin
  if Tok.Kind <> tkIdent then
    Fail('expected a name, found "' + Tok.S + '"');
  Result := Tok.S;
  Next;
end;

{ --- emission --- }

procedure TCompiler.Emit(W: Cardinal);
begin
  if CodeLen >= Length(Code) then
    SetLength(Code, CodeLen * 2 + 256);
  Code[CodeLen] := W;
  Inc(CodeLen);
end;

function TCompiler.Here: Integer;
begin
  Result := CodeLen;
end;

procedure TCompiler.Patch(At: Integer; Value: Cardinal);
begin
  Code[At] := Value;
end;

function TCompiler.StrOff(const S: string): Cardinal;
var
  I: Integer;
begin
  { exact (case-sensitive) dedupe through a hex key }
  I := StrMap.IndexOf(S);
  if I >= 0 then
    Exit(Cardinal(PtrUInt(StrMap.Objects[I])));
  Result := Length(Blk.GStr);
  Blk.GStr := Blk.GStr + S + #0;
  StrMap.AddObject(S, TObject(PtrUInt(Result)));
end;

function TCompiler.FltIdx(D: Double): Cardinal;
var
  I: Integer;
begin
  for I := 0 to High(Floats) do
    if Floats[I] = D then
      Exit(I);
  SetLength(Floats, Length(Floats) + 1);
  Floats[High(Floats)] := D;
  Result := High(Floats);
end;

{ --- parsing: expressions ---
  Precedence, lowest first (TGE 1.x grammar):
    = += ...     right
    ? :
    ||
    &&
    |
    ^
    &
    == !=
    < <= > >=
    @ SPC TAB NL $= !$=
    << >>
    + -
    * / %
    unary ! ~ - ++ --
    postfix . [] () }

function TCompiler.ParseExpr: TNode;
begin
  Result := ParseAssign;
end;

function IsAssignable(N: TNode): Boolean;
begin
  Result := N.Kind in [nkVar, nkField];
end;

function TCompiler.ParseAssign: TNode;
var
  L, R: TNode;
  Op: string;
begin
  L := ParseCond;
  if (Tok.Kind = tkOp) and ((Tok.S = '=') or (Tok.S = '+=') or (Tok.S = '-=') or
    (Tok.S = '*=') or (Tok.S = '/=') or (Tok.S = '%=') or (Tok.S = '&=') or
    (Tok.S = '|=') or (Tok.S = '^=') or (Tok.S = '<<=') or (Tok.S = '>>=')) then
  begin
    if not IsAssignable(L) then
      Fail('cannot assign to this expression');
    Op := Tok.S;
    Next;
    R := ParseAssign;
    Result := NewNode(nkAssign);
    Result.A := L;
    Result.S := Op;
    Result.B := R;
  end
  else
    Result := L;
end;

function TCompiler.ParseCond: TNode;
var
  C: TNode;
begin
  Result := ParseBin(0);
  if IsOp('?') then
  begin
    Next;
    C := NewNode(nkCond);
    C.A := Result;
    C.B := ParseAssign;
    Expect(':');
    C.C := ParseAssign;
    Result := C;
  end;
end;

function BinLevel(const T: TTok): Integer;
var
  S: string;
begin
  Result := -1;
  if T.Kind = tkIdent then
  begin
    S := UpperCase(T.S);
    if (S = 'SPC') or (S = 'TAB') or (S = 'NL') then
      Result := 8;
    Exit;
  end;
  if T.Kind <> tkOp then
    Exit;
  S := T.S;
  if S = '||' then Result := 0
  else if S = '&&' then Result := 1
  else if S = '|' then Result := 2
  else if S = '^' then Result := 3
  else if S = '&' then Result := 4
  else if (S = '==') or (S = '!=') then Result := 5
  else if (S = '<') or (S = '<=') or (S = '>') or (S = '>=') then Result := 6
  else if (S = '@') or (S = '$=') or (S = '!$=') then Result := 8
  else if (S = '<<') or (S = '>>') then Result := 9
  else if (S = '+') or (S = '-') then Result := 10
  else if (S = '*') or (S = '/') or (S = '%') then Result := 11;
end;

function TCompiler.ParseBin(Level: Integer): TNode;
var
  L, R, N: TNode;
  Op: string;
  Lv: Integer;
begin
  if Level > 11 then
    Exit(ParseUnary);
  L := ParseBin(Level + 1);
  while True do
  begin
    Lv := BinLevel(Tok);
    if Lv <> Level then
      Break;
    if Tok.Kind = tkIdent then Op := UpperCase(Tok.S) else Op := Tok.S;
    Next;
    R := ParseBin(Level + 1);
    N := NewNode(nkBin);
    N.S := Op;
    N.A := L;
    N.B := R;
    L := N;
  end;
  Result := L;
end;

function TCompiler.ParseUnary: TNode;
var
  N: TNode;
begin
  if IsOp('!') or IsOp('~') or IsOp('-') then
  begin
    N := NewNode(nkUnary);
    N.S := Tok.S;
    Next;
    N.A := ParseUnary;
    Exit(N);
  end;
  if IsOp('++') or IsOp('--') then
  begin
    N := NewNode(nkIncDec);
    N.S := Tok.S;
    Next;
    N.A := ParseUnary;
    if not IsAssignable(N.A) then
      Fail('++/-- needs a variable or field');
    Exit(N);
  end;
  Result := ParsePostfix;
end;

function TCompiler.ParseArgs: TNodeList;
begin
  Result := nil;
  Expect('(');
  if not IsOp(')') then
    while True do
    begin
      AddTo(Result, ParseExpr);
      if IsOp(',') then
        Next
      else
        Break;
    end;
  Expect(')');
end;

function TCompiler.ParsePostfix: TNode;
var
  N: TNode;
  Name: string;
begin
  Result := ParsePrimary;
  while True do
  begin
    if IsOp('.') then
    begin
      Next;
      Name := ExpectIdent;
      if IsOp('(') then
      begin
        N := NewNode(nkMethod);
        N.A := Result;
        N.S := Name;
        N.Args := ParseArgs;
      end
      else
      begin
        N := NewNode(nkField);
        N.A := Result;
        N.S := Name;
        if IsOp('[') then
        begin
          Next;
          while True do
          begin
            AddTo(N.Idx, ParseExpr);
            if IsOp(',') then Next else Break;
          end;
          Expect(']');
        end;
      end;
      Result := N;
    end
    else if IsOp('++') or IsOp('--') then
    begin
      if not IsAssignable(Result) then
        Break;
      N := NewNode(nkIncDec);
      N.S := Tok.S;
      N.A := Result;
      Next;
      Result := N;
    end
    else
      Break;
  end;
end;

function TCompiler.ParsePrimary: TNode;
var
  N: TNode;
  Name: string;
  P: Integer;
begin
  case Tok.Kind of
    tkInt:
      begin
        N := NewNode(nkInt);
        N.I := Tok.I;
        N.S := Tok.S;
        Next;
        Exit(N);
      end;
    tkFloat:
      begin
        N := NewNode(nkFloat);
        N.F := Tok.F;
        N.S := Tok.S;
        Next;
        Exit(N);
      end;
    tkStr, tkTag:
      begin
        if Tok.Kind = tkStr then N := NewNode(nkStr) else N := NewNode(nkTag);
        N.S := Tok.S;
        Next;
        Exit(N);
      end;
    tkLocal, tkGlobal:
      begin
        N := NewNode(nkVar);
        N.S := Tok.S;
        Next;
        if IsOp('[') then
        begin
          Next;
          while True do
          begin
            AddTo(N.Idx, ParseExpr);
            if IsOp(',') then Next else Break;
          end;
          Expect(']');
        end;
        Exit(N);
      end;
    tkIdent:
      begin
        if SameText(Tok.S, 'new') then
          Exit(ParseNew);
        if SameText(Tok.S, 'true') then
        begin
          Next;
          N := NewNode(nkInt); N.I := 1; N.S := '1';
          Exit(N);
        end;
        if SameText(Tok.S, 'false') then
        begin
          Next;
          N := NewNode(nkInt); N.I := 0; N.S := '0';
          Exit(N);
        end;
        Name := Tok.S;
        Next;
        if IsOp('(') then
        begin
          N := NewNode(nkCall);
          P := LastDelimiter(':', Name);
          if (P > 1) and (Copy(Name, P - 1, 2) = '::') then
          begin
            N.Ns := Copy(Name, 1, P - 2);
            N.S := Copy(Name, P + 1, MaxInt);
          end
          else
            N.S := Name;
          if SameText(N.Ns, 'Parent') then
            N.CallType := CALL_PARENT
          else
            N.CallType := CALL_FUNCTION;
          N.Args := ParseArgs;
          Exit(N);
        end;
        { a bare word is a string constant (an object name, a key name...) }
        N := NewNode(nkStr);
        N.S := Name;
        Exit(N);
      end;
    tkOp:
      if Tok.S = '(' then
      begin
        Next;
        N := ParseExpr;
        Expect(')');
        Exit(N);
      end;
  end;
  Fail('unexpected "' + Tok.S + '"');
  Result := nil;
end;

function TCompiler.ParseNew: TNode;
var
  N, F, V: TNode;
  FieldName: string;
begin
  { new Class(name[ : parent][, args...]) [{ fields; objects }] }
  Next;
  N := NewNode(nkNew);
  if IsOp('(') then
  begin
    Next;
    N.A := ParseExpr;
    Expect(')');
  end
  else
  begin
    N.A := NewNode(nkStr);
    N.A.S := ExpectIdent;
  end;
  Expect('(');
  if not IsOp(')') and not IsOp(':') and not IsOp(',') then
    N.B := ParseExpr;
  if IsOp(':') then
  begin
    Next;
    N.ParentName := ExpectIdent;
  end;
  while IsOp(',') do
  begin
    Next;
    AddTo(N.Args, ParseExpr);
  end;
  Expect(')');
  if IsOp('{') then
  begin
    Next;
    while not IsOp('}') do
    begin
      if Tok.Kind = tkEOF then
        Fail('unterminated object block');
      if IsWord('new') then
      begin
        AddTo(N.Subs, ParseNew);
        Expect(';');
        Continue;
      end;
      FieldName := ExpectIdent;
      F := NewNode(nkField);
      F.A := nil; { the object being created }
      F.S := FieldName;
      if IsOp('[') then
      begin
        Next;
        while True do
        begin
          AddTo(F.Idx, ParseExpr);
          if IsOp(',') then Next else Break;
        end;
        Expect(']');
      end;
      Expect('=');
      V := NewNode(nkAssign);
      V.S := '=';
      V.A := F;
      V.B := ParseExpr;
      AddTo(N.Fields, V);
      Expect(';');
    end;
    Next;
  end;
  Result := N;
end;

{ --- codegen --- }

function TCompiler.Natural(N: TNode): TReq;
begin
  case N.Kind of
    nkInt: Result := rqUint;
    nkFloat: Result := rqFlt;
    nkStr, nkTag, nkVar, nkField, nkCall, nkMethod: Result := rqStr;
    nkBin:
      if (N.S = '+') or (N.S = '-') or (N.S = '*') or (N.S = '/') then
        Result := rqFlt
      else if (N.S = '@') or (N.S = 'SPC') or (N.S = 'TAB') or (N.S = 'NL') then
        Result := rqStr
      else
        Result := rqUint;
    nkUnary:
      if N.S = '-' then Result := rqFlt else Result := rqUint;
    nkAssign:
      if N.S = '=' then
        Result := Natural(N.B)
      else if (N.S = '+=') or (N.S = '-=') or (N.S = '*=') or (N.S = '/=') then
        Result := rqFlt
      else
        Result := rqUint;
    nkIncDec: Result := rqFlt;
    nkCond:
      if Natural(N.B) = Natural(N.C) then
        Result := Natural(N.B)
      else
        Result := rqStr;
    nkNew: Result := rqUint;
  else
    Result := rqStr;
  end;
end;

procedure TCompiler.Convert(From, ToReq: TReq);
begin
  if From = ToReq then
    Exit;
  case From of
    rqUint:
      case ToReq of
        rqFlt: Emit(OP_UINT_TO_FLT);
        rqStr: Emit(OP_UINT_TO_STR);
        rqNone: Emit(OP_UINT_TO_NONE);
      end;
    rqFlt:
      case ToReq of
        rqUint: Emit(OP_FLT_TO_UINT);
        rqStr: Emit(OP_FLT_TO_STR);
        rqNone: Emit(OP_FLT_TO_NONE);
      end;
    rqStr:
      case ToReq of
        rqUint: Emit(OP_STR_TO_UINT);
        rqFlt: Emit(OP_STR_TO_FLT);
        rqNone: Emit(OP_STR_TO_NONE);
      end;
  end;
end;

{ Put the array name "name" @ idx1 _ idx2 ... in the current string slot. }
procedure GenArrayName(C: TCompiler; const Name: string; const Idx: TNodeList);
var
  K: Integer;
begin
  C.Emit(OP_LOADIMMED_IDENT);
  C.Emit(TqIntern(Name));
  C.Emit(OP_ADVANCE_STR);
  for K := 0 to High(Idx) do
  begin
    if K > 0 then
    begin
      C.Emit(OP_REWIND_STR);
      C.Emit(OP_ADVANCE_STR_COMMA);
    end;
    C.Gen(Idx[K], rqStr);
  end;
  C.Emit(OP_REWIND_STR);
end;

{ Select variable/field Target as the current one. Keeps whatever value the
  caller has in the current string slot: the name work happens one slot up
  and is dropped again. }
procedure GenSelect(C: TCompiler; Target: TNode; ForWrite: Boolean);
var
  K: Integer;
begin
  if Target.Kind = nkVar then
  begin
    if Length(Target.Idx) = 0 then
    begin
      if ForWrite then C.Emit(OP_SETCURVAR_CREATE) else C.Emit(OP_SETCURVAR);
      C.Emit(TqIntern(Target.S));
    end
    else
    begin
      C.Emit(OP_ADVANCE_STR);
      GenArrayName(C, Target.S, Target.Idx);
      if ForWrite then C.Emit(OP_SETCURVAR_ARRAY_CREATE) else C.Emit(OP_SETCURVAR_ARRAY);
      C.Emit(OP_TERMINATE_REWIND_STR);
    end;
  end
  else
  begin
    { field }
    if Target.A = nil then
      C.Emit(OP_SETCUROBJECT_NEW)
    else
    begin
      C.Emit(OP_ADVANCE_STR);
      C.Gen(Target.A, rqStr);
      C.Emit(OP_SETCUROBJECT);
      C.Emit(OP_TERMINATE_REWIND_STR);
    end;
    C.Emit(OP_SETCURFIELD);
    C.Emit(TqIntern(Target.S));
    if Length(Target.Idx) > 0 then
    begin
      C.Emit(OP_ADVANCE_STR);
      C.Gen(Target.Idx[0], rqStr);
      for K := 1 to High(Target.Idx) do
      begin
        C.Emit(OP_ADVANCE_STR_COMMA);
        C.Gen(Target.Idx[K], rqStr);
        C.Emit(OP_REWIND_STR);
      end;
      C.Emit(OP_SETCURFIELD_ARRAY);
      C.Emit(OP_TERMINATE_REWIND_STR);
    end;
  end;
end;

procedure TCompiler.GenAssignTo(Target: TNode; ValueType: TReq);
begin
  GenSelect(Self, Target, True);
  if Target.Kind = nkVar then
    case ValueType of
      rqUint: Emit(OP_SAVEVAR_UINT);
      rqFlt: Emit(OP_SAVEVAR_FLT);
    else
      Emit(OP_SAVEVAR_STR);
    end
  else
    case ValueType of
      rqUint: Emit(OP_SAVEFIELD_UINT);
      rqFlt: Emit(OP_SAVEFIELD_FLT);
    else
      Emit(OP_SAVEFIELD_STR);
    end;
end;

procedure GenLoad(C: TCompiler; Target: TNode; Req: TReq);
var
  R: TReq;
begin
  if Req = rqNone then
    Exit;
  GenSelect(C, Target, False);
  R := Req;
  if Target.Kind = nkVar then
    case R of
      rqUint: C.Emit(OP_LOADVAR_UINT);
      rqFlt: C.Emit(OP_LOADVAR_FLT);
    else
      C.Emit(OP_LOADVAR_STR);
    end
  else
    case R of
      rqUint: C.Emit(OP_LOADFIELD_UINT);
      rqFlt: C.Emit(OP_LOADFIELD_FLT);
    else
      C.Emit(OP_LOADFIELD_STR);
    end;
end;

procedure TCompiler.GenStrSlot(N: TNode);
begin
  Gen(N, rqStr);
end;

procedure TCompiler.GenCond(N: TNode; JumpIfFalse: Boolean; out PatchAt: Integer);
begin
  if Natural(N) = rqFlt then
  begin
    Gen(N, rqFlt);
    if JumpIfFalse then Emit(OP_JMPIFFNOT) else Emit(OP_JMPIFF);
  end
  else
  begin
    Gen(N, rqUint);
    if JumpIfFalse then Emit(OP_JMPIFNOT) else Emit(OP_JMPIF);
  end;
  PatchAt := Here;
  Emit(0);
end;

procedure TCompiler.GenNew(N: TNode; AtRoot: Boolean);
var
  K, FailAt: Integer;
  F: TNode;
begin
  Emit(OP_PUSH_FRAME);
  Gen(N.A, rqStr);
  Emit(OP_PUSH);
  if N.B <> nil then
    Gen(N.B, rqStr)
  else
  begin
    Emit(OP_LOADIMMED_STR);
    Emit(StrOff(''));
  end;
  Emit(OP_PUSH);
  for K := 0 to High(N.Args) do
  begin
    Gen(N.Args[K], rqStr);
    Emit(OP_PUSH);
  end;
  Emit(OP_CREATE_OBJECT);
  Emit(TqIntern(N.ParentName));
  Emit(Ord(N.IsDatablock));
  FailAt := Here;
  Emit(0);
  for F in N.Fields do
    Gen(F, rqNone);
  Emit(OP_ADD_OBJECT);
  Emit(Ord(AtRoot));
  for F in N.Subs do
    GenNew(F, False);
  Emit(OP_END_OBJECT);
  Emit(Ord(AtRoot));
  Patch(FailAt, Here);
end;

procedure TCompiler.Gen(N: TNode; Req: TReq);
var
  T, VT: TReq;
  J1, J2, K: Integer;
  Op: string;
  Bin: TNode;
begin
  case N.Kind of
    nkInt:
      case Req of
        rqUint: begin Emit(OP_LOADIMMED_UINT); Emit(Cardinal(N.I)); end;
        rqFlt: begin Emit(OP_LOADIMMED_FLT); Emit(FltIdx(N.I)); end;
        rqStr: begin Emit(OP_LOADIMMED_STR); Emit(StrOff(N.S)); end;
      end;
    nkFloat:
      case Req of
        rqUint: begin Emit(OP_LOADIMMED_UINT); Emit(Cardinal(Trunc(N.F))); end;
        rqFlt: begin Emit(OP_LOADIMMED_FLT); Emit(FltIdx(N.F)); end;
        rqStr: begin Emit(OP_LOADIMMED_FLT); Emit(FltIdx(N.F)); Emit(OP_FLT_TO_STR); end;
      end;
    nkStr, nkTag:
      if Req <> rqNone then
      begin
        if N.Kind = nkTag then Emit(OP_TAG_TO_STR) else Emit(OP_LOADIMMED_STR);
        Emit(StrOff(N.S));
        Convert(rqStr, Req);
      end;
    nkVar, nkField:
      GenLoad(Self, N, Req);
    nkCall, nkMethod:
      begin
        Emit(OP_PUSH_FRAME);
        if N.Kind = nkMethod then
        begin
          Gen(N.A, rqStr);
          Emit(OP_PUSH);
        end;
        for K := 0 to High(N.Args) do
        begin
          Gen(N.Args[K], rqStr);
          Emit(OP_PUSH);
        end;
        Emit(OP_CALLFUNC);
        Emit(TqIntern(N.S));
        if N.Kind = nkMethod then
        begin
          Emit(0);
          Emit(CALL_METHOD);
        end
        else
        begin
          Emit(TqIntern(N.Ns));
          Emit(N.CallType);
        end;
        Convert(rqStr, Req);
      end;
    nkUnary:
      begin
        if N.S = '-' then
        begin
          Gen(N.A, rqFlt);
          Emit(OP_NEG);
          Convert(rqFlt, Req);
        end
        else if N.S = '!' then
        begin
          if Natural(N.A) = rqFlt then
          begin
            Gen(N.A, rqFlt);
            Emit(OP_NOTF);
          end
          else
          begin
            Gen(N.A, rqUint);
            Emit(OP_NOT);
          end;
          Convert(rqUint, Req);
        end
        else
        begin
          Gen(N.A, rqUint);
          Emit(OP_ONESCOMPLEMENT);
          Convert(rqUint, Req);
        end;
      end;
    nkBin:
      begin
        Op := N.S;
        if (Op = '@') or (Op = 'SPC') or (Op = 'TAB') or (Op = 'NL') then
        begin
          Gen(N.A, rqStr);
          if Op = '@' then
            Emit(OP_ADVANCE_STR)
          else
          begin
            Emit(OP_ADVANCE_STR_APPENDCHAR);
            if Op = 'SPC' then Emit(Ord(' '))
            else if Op = 'TAB' then Emit(9)
            else Emit(10);
          end;
          Gen(N.B, rqStr);
          Emit(OP_REWIND_STR);
          Convert(rqStr, Req);
        end
        else if (Op = '$=') or (Op = '!$=') then
        begin
          Gen(N.A, rqStr);
          Emit(OP_ADVANCE_STR_NUL);
          Gen(N.B, rqStr);
          Emit(OP_COMPARE_STR);
          if Op = '!$=' then
            Emit(OP_NOT);
          Convert(rqUint, Req);
        end
        else if (Op = '&&') or (Op = '||') then
        begin
          Gen(N.A, rqUint);
          if Op = '&&' then Emit(OP_JMPIFNOT_NP) else Emit(OP_JMPIF_NP);
          J1 := Here;
          Emit(0);
          Gen(N.B, rqUint);
          Patch(J1, Here);
          Convert(rqUint, Req);
        end
        else if (Op = '+') or (Op = '-') or (Op = '*') or (Op = '/') then
        begin
          { the VM computes top OP below: put the right operand first }
          Gen(N.B, rqFlt);
          Gen(N.A, rqFlt);
          if Op = '+' then Emit(OP_ADD)
          else if Op = '-' then Emit(OP_SUB)
          else if Op = '*' then Emit(OP_MUL)
          else Emit(OP_DIV);
          Convert(rqFlt, Req);
        end
        else if (Op = '==') or (Op = '!=') or (Op = '<') or (Op = '<=') or
          (Op = '>') or (Op = '>=') then
        begin
          Gen(N.B, rqFlt);
          Gen(N.A, rqFlt);
          if Op = '==' then Emit(OP_CMPEQ)
          else if Op = '!=' then Emit(OP_CMPNE)
          else if Op = '<' then Emit(OP_CMPLT)
          else if Op = '<=' then Emit(OP_CMPLE)
          else if Op = '>' then Emit(OP_CMPGR)
          else Emit(OP_CMPGE);
          Convert(rqUint, Req);
        end
        else
        begin
          Gen(N.B, rqUint);
          Gen(N.A, rqUint);
          if Op = '%' then Emit(OP_MOD)
          else if Op = '&' then Emit(OP_BITAND)
          else if Op = '|' then Emit(OP_BITOR)
          else if Op = '^' then Emit(OP_XOR)
          else if Op = '<<' then Emit(OP_SHL)
          else Emit(OP_SHR);
          Convert(rqUint, Req);
        end;
      end;
    nkAssign:
      begin
        if N.S = '=' then
        begin
          VT := Natural(N.B);
          Gen(N.B, VT);
        end
        else
        begin
          { a op= b  ==>  a = a op b, with the target evaluated twice
            (TorqueScript does the same) }
          Bin := NewNode(nkBin);
          try
            Bin.S := Copy(N.S, 1, Length(N.S) - 1);
            Bin.A := N.A;
            Bin.B := N.B;
            VT := Natural(Bin);
            Gen(Bin, VT);
          finally
            Bin.A := nil;
            Bin.B := nil;
            Bin.Free;
          end;
        end;
        GenAssignTo(N.A, VT);
        Convert(VT, Req);
      end;
    nkIncDec:
      begin
        Gen(N.A, rqFlt);
        Emit(OP_LOADIMMED_FLT);
        Emit(FltIdx(1));
        { top = 1, below = value: value + 1 is ADD (top + below);
          value - 1 needs below - top: negate first }
        if N.S = '++' then
          Emit(OP_ADD)
        else
        begin
          Emit(OP_NEG);
          Emit(OP_ADD);
        end;
        GenAssignTo(N.A, rqFlt);
        Convert(rqFlt, Req);
      end;
    nkCond:
      begin
        T := Natural(N);
        GenCond(N.A, True, J1);
        Gen(N.B, T);
        Emit(OP_JMP);
        J2 := Here;
        Emit(0);
        Patch(J1, Here);
        Gen(N.C, T);
        Patch(J2, Here);
        Convert(T, Req);
      end;
    nkNew:
      begin
        GenNew(N, True);
        Convert(rqUint, Req);
      end;
  end;
end;

{ --- statements --- }

procedure TCompiler.ParseBlockOrStatement(const Pkg: string);
begin
  if IsOp('{') then
  begin
    Next;
    while not IsOp('}') do
    begin
      if Tok.Kind = tkEOF then
        Fail('missing "}"');
      ParseStatement(Pkg);
    end;
    Next;
  end
  else
    ParseStatement(Pkg);
end;

procedure TCompiler.ParseFunction(const Pkg: string);
var
  Name, Ns: string;
  Args: array of string;
  P, K, EndAt: Integer;
  SavedLoops: array of TLoopCtx;
begin
  Next; { 'function' }
  Name := ExpectIdent;
  Ns := '';
  P := LastDelimiter(':', Name);
  if (P > 1) and (Copy(Name, P - 1, 2) = '::') then
  begin
    Ns := Copy(Name, 1, P - 2);
    Name := Copy(Name, P + 1, MaxInt);
  end;
  Expect('(');
  Args := nil;
  while not IsOp(')') do
  begin
    if Tok.Kind <> tkLocal then
      Fail('expected a %parameter');
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := Tok.S;
    Next;
    if IsOp(',') then Next else Break;
  end;
  Expect(')');
  Emit(OP_FUNC_DECL);
  Emit(TqIntern(Name));
  Emit(TqIntern(Ns));
  Emit(TqIntern(Pkg));
  Emit(1);
  EndAt := Here;
  Emit(0);
  Emit(Length(Args));
  for K := 0 to High(Args) do
    Emit(TqIntern(Args[K]));
  SavedLoops := Loops;
  Loops := nil;
  Expect('{');
  while not IsOp('}') do
  begin
    if Tok.Kind = tkEOF then
      Fail('missing "}" at the end of function ' + Name);
    ParseStatement(Pkg);
  end;
  Next;
  Loops := SavedLoops;
  Emit(OP_LOADIMMED_STR);
  Emit(StrOff(''));
  Emit(OP_RETURN);
  Patch(EndAt, Here);
end;

procedure TCompiler.ParseStatement(const Pkg: string);
var
  N, CaseV, Sw, Sw2: TNode;
  J1, J2, Top, K, ContAt: Integer;
  PkgName: string;
  IsStrSwitch: Boolean;
  Ctx: TLoopCtx;
  Ends: array of Integer;
  Step: TNode;

  procedure SetLeaves(X, V: TNode);
  begin
    if X.S = '||' then
    begin
      SetLeaves(X.A, V);
      SetLeaves(X.B, V);
    end
    else
      X.A := V;
  end;

  procedure PushLoop;
  begin
    SetLength(Loops, Length(Loops) + 1);
    Loops[High(Loops)].Breaks := nil;
    Loops[High(Loops)].Continues := nil;
  end;

  procedure PopLoop(BreakTo, ContinueTo: Integer);
  var
    X: Integer;
  begin
    Ctx := Loops[High(Loops)];
    for X in Ctx.Breaks do Patch(X, BreakTo);
    for X in Ctx.Continues do Patch(X, ContinueTo);
    SetLength(Loops, Length(Loops) - 1);
  end;

begin
  if IsOp(';') then
  begin
    Next;
    Exit;
  end;
  if IsOp('{') then
  begin
    ParseBlockOrStatement(Pkg);
    Exit;
  end;
  if IsWord('function') then
  begin
    ParseFunction(Pkg);
    Exit;
  end;
  if IsWord('package') then
  begin
    Next;
    PkgName := ExpectIdent;
    Expect('{');
    while not IsOp('}') do
    begin
      if not IsWord('function') then
        Fail('only functions may appear in a package');
      ParseFunction(PkgName);
    end;
    Next;
    if IsOp(';') then Next;
    Exit;
  end;
  if IsWord('datablock') then
    Fail('datablock declarations are not supported yet');
  if IsWord('if') then
  begin
    Next;
    Expect('(');
    N := ParseExpr;
    Expect(')');
    try
      GenCond(N, True, J1);
    finally
      N.Free;
    end;
    ParseBlockOrStatement(Pkg);
    if IsWord('else') then
    begin
      Next;
      Emit(OP_JMP);
      J2 := Here;
      Emit(0);
      Patch(J1, Here);
      ParseBlockOrStatement(Pkg);
      Patch(J2, Here);
    end
    else
      Patch(J1, Here);
    Exit;
  end;
  if IsWord('while') then
  begin
    Next;
    Expect('(');
    N := ParseExpr;
    Expect(')');
    Top := Here;
    try
      GenCond(N, True, J1);
    finally
      N.Free;
    end;
    PushLoop;
    ParseBlockOrStatement(Pkg);
    Emit(OP_JMP);
    Emit(Top);
    Patch(J1, Here);
    PopLoop(Here, Top);
    Exit;
  end;
  if IsWord('for') then
  begin
    Next;
    Expect('(');
    if not IsOp(';') then
    begin
      N := ParseExpr;
      try Gen(N, rqNone); finally N.Free; end;
    end;
    Expect(';');
    Top := Here;
    J1 := -1;
    if not IsOp(';') then
    begin
      N := ParseExpr;
      try GenCond(N, True, J1); finally N.Free; end;
    end;
    Expect(';');
    Step := nil;
    if not IsOp(')') then
      Step := ParseExpr;
    Expect(')');
    PushLoop;
    try
      ParseBlockOrStatement(Pkg);
      ContAt := Here;
      if Step <> nil then
        Gen(Step, rqNone);
    finally
      Step.Free;
    end;
    Emit(OP_JMP);
    Emit(Top);
    if J1 >= 0 then
      Patch(J1, Here);
    PopLoop(Here, ContAt);
    Exit;
  end;
  if IsWord('break') or IsWord('continue') then
  begin
    if Length(Loops) = 0 then
      Fail(Tok.S + ' outside a loop');
    Emit(OP_JMP);
    if IsWord('break') then
    begin
      SetLength(Loops[High(Loops)].Breaks, Length(Loops[High(Loops)].Breaks) + 1);
      Loops[High(Loops)].Breaks[High(Loops[High(Loops)].Breaks)] := Here;
    end
    else
    begin
      SetLength(Loops[High(Loops)].Continues, Length(Loops[High(Loops)].Continues) + 1);
      Loops[High(Loops)].Continues[High(Loops[High(Loops)].Continues)] := Here;
    end;
    Emit(0);
    Next;
    Expect(';');
    Exit;
  end;
  if IsWord('return') then
  begin
    Next;
    if IsOp(';') then
    begin
      Emit(OP_LOADIMMED_STR);
      Emit(StrOff(''));
    end
    else
    begin
      N := ParseExpr;
      try Gen(N, rqStr); finally N.Free; end;
    end;
    Emit(OP_RETURN);
    Expect(';');
    Exit;
  end;
  if IsWord('switch') or IsWord('switch$') then
  begin
    IsStrSwitch := Tok.S[Length(Tok.S)] = '$';
    Next;
    if IsOp('$') then
    begin
      IsStrSwitch := True;
      Next;
    end;
    Expect('(');
    Sw := ParseExpr;
    Expect(')');
    Expect('{');
    Ends := nil;
    try
      while IsWord('case') do
      begin
        Next;
        { case a or b: -> if (sw == a || sw == b) }
        N := nil;
        while True do
        begin
          CaseV := ParseCond;
          Step := NewNode(nkBin);
          if IsStrSwitch then Step.S := '$=' else Step.S := '==';
          Step.B := CaseV;
          if N = nil then
            N := Step
          else
          begin
            Sw2 := NewNode(nkBin);
            Sw2.S := '||';
            Sw2.A := N;
            Sw2.B := Step;
            N := Sw2;
          end;
          if IsWord('or') then Next else Break;
        end;
        Expect(':');
        SetLeaves(N, Sw);
        GenCond(N, True, J1);
        SetLeaves(N, nil);
        N.Free;
        while not (IsWord('case') or IsWord('default') or IsOp('}')) do
          ParseStatement(Pkg);
        Emit(OP_JMP);
        SetLength(Ends, Length(Ends) + 1);
        Ends[High(Ends)] := Here;
        Emit(0);
        Patch(J1, Here);
      end;
      if IsWord('default') then
      begin
        Next;
        Expect(':');
        while not IsOp('}') do
          ParseStatement(Pkg);
      end;
      Expect('}');
      for K in Ends do
        Patch(K, Here);
    finally
      Sw.Free;
    end;
    Exit;
  end;
  { expression statement }
  N := ParseExpr;
  try
    Gen(N, rqNone);
  finally
    N.Free;
  end;
  Expect(';');
end;

function TCompiler.Run(const ASrc, APath: string): TTqCodeBlock;
begin
  Src := ASrc;
  Pos := 1;
  Line := 1;
  HavePeek := False;
  CodeLen := 0;
  Code := nil;
  Floats := nil;
  Blk := TTqCodeBlock.Create;
  Blk.Path := APath;
  Blk.Version := 33;
  StrMap := TStringList.Create;
  StrMap.CaseSensitive := True;
  try
    try
      Next;
      while Tok.Kind <> tkEOF do
        ParseStatement('');
      Emit(OP_LOADIMMED_STR);
      Emit(StrOff(''));
      Emit(OP_RETURN);
      SetLength(Code, CodeLen);
      Blk.Code := Code;
      Blk.GFlt := Floats;
      Blk.FStr := Blk.GStr;
      Blk.FFlt := Copy(Floats);
      Result := Blk;
    except
      Blk.Free;
      raise;
    end;
  finally
    StrMap.Free;
  end;
end;

function TqCompileSource(const Src, Path: string; out Err: string): TTqCodeBlock;
var
  C: TCompiler;
begin
  Err := '';
  C := TCompiler.Create;
  try
    try
      Result := C.Run(Src, Path);
    except
      on E: Exception do
      begin
        Err := E.Message;
        Result := nil;
      end;
    end;
  finally
    C.Free;
  end;
end;

initialization
  DotFmt := DefaultFormatSettings;
  DotFmt.DecimalSeparator := '.';
end.
