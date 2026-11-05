{ TqVM: the TorqueScript virtual machine and console object model.

  Runs code blocks from TqCode (loaded .dso) and TqCompile (compiled .cs)
  the way the TGE 1.x console does:

    * three value stacks (unsigned int, float, string); binary operators
      take the left operand from the top and the right one below it;
    * the string stack works in slots: ADVANCE opens a new slot, REWIND
      joins the top slot onto the one below, TERMINATE_REWIND drops it,
      PUSH keeps the slot as a call argument, CALLFUNC writes the result
      into the slot that was current at PUSH_FRAME;
    * variables carry the type they were last saved with (int, float or
      string), which decides how export() writes them;
    * functions live in namespaces with package layers on top; a call
      looks through the active packages (newest first), then the base
      layer (script, then native), then the parent namespace; Parent::
      continues one layer below the running function;
    * objects get ids from 1027, can be named, and a named object gets a
      namespace of its own whose parent is its class.

  Sources: graal_analysis torque/scripting.md and study-torque-clients.md
  (opcodes and the native surface the 3.04 scripts call), and the public
  TGE 1.x console behaviour. Checked against the real 3.04 client's
  console log and script load order (graal-3.04-G3D03014/tests). }
unit TqVM;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, SysUtils, TqCode;

type
  TTqVM = class;
  TTqArgs = array of string;
  TTqNative = function(VM: TTqVM; const Argv: TTqArgs): string;
  TTqKind = (tqStr, tqInt, tqFlt);

  TTqVar = class
  public
    Name: string;
    Kind: TTqKind;
    S: string;
    I: Int64;
    F: Double;
    function AsStr: string;
    function AsInt: Int64;
    function AsFlt: Double;
    procedure SetStr(const V: string);
  end;

  { name -> TTqVar, case-insensitive, keeps the first spelling }
  TTqDict = class
  private
    FList: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const Name: string): TTqVar;
    function Get(const Name: string): TTqVar;
    function Count: Integer;
    function Item(I: Integer): TTqVar;
    procedure Remove(const Name: string);
  end;

  TSimObject = class
  public
    Id: Integer;
    Name: string;
    ClassName_: string;
    Fields: TStringList;       { Name=Value, case-insensitive }
    Group: TSimObject;         { owning SimGroup }
    Sets: TList;               { SimSets this object is in }
    Children: TList;           { members, if this is a SimSet }
    IsSet, IsGroup, IsGui: Boolean;
    Awake: Boolean;
    Registered: Boolean;
    Data: TObject;             { class-specific state, owned }
    constructor Create;
    destructor Destroy; override;
    function GetField(const F: string): string;
    procedure SetField(const F, V: string);
    function IdStr: string;
    function ChildCount: Integer;
    function Child(I: Integer): TSimObject;
  end;

  TTqClassInfo = class
    Name, Parent: string;
    IsSet, IsGroup, IsGui: Boolean;
  end;

  TTqFuncDef = class
    Block: TTqCodeBlock;
    DeclIp, BodyIp: Integer;
    Name, Ns, Pkg: string;
    ArgNames: array of string;
  end;

  TTqFrame = record
    Block: TTqCodeBlock;
    Ns: string;      { namespace the running function was found in }
    Layer: Integer;  { its package layer index (see LayerList) }
    Locals: TTqDict;
  end;

  TTqLookup = record
    Def: TTqFuncDef;
    Native: TTqNative;
    Ns: string;
    Layer: Integer;
  end;

  TTqObjectHook = procedure(VM: TTqVM; Obj: TSimObject);

  TTqVM = class
  private
    FFuncs: TStringList;       { 'ns|pkg|name' -> TTqFuncDef }
    FNatives: TStringList;     { 'ns|name' -> TTqNative }
    FNsParent: TStringList;    { 'ns' -> parent ns }
    FClasses: TStringList;     { class name -> TTqClassInfo }
    FObjects: TList;           { all registered objects }
    FById: TStringList;        { id -> object (sorted, zero padded) }
    FNames: TStringList;       { name -> object }
    FBlocks: TList;            { every loaded code block (owned) }
    FNextId: Integer;
    { value stacks }
    IntS: array of Int64;
    IT: Integer;
    FltS: array of Double;
    FT: Integer;
    SS: array of string;
    ST: Integer;
    FrameStarts: array of Integer;
    FrTop: Integer;
    Frames: array of TTqFrame;
    FrameCount: Integer;
    FDirCache: TStringList;
    function FuncKey(const Ns, Pkg, Name: string): string;
    procedure PushInt(V: Int64);
    procedure PushFlt(V: Double);
    function Exec(Blk: TTqCodeBlock; Ip: Integer; InFn: Boolean): string;
    function LayerName(I: Integer): string;
    function LayerCount: Integer;
    function LookupFrom(const Ns: string; Layer: Integer; const Fn: string): TTqLookup;
    function CallLookup(const L: TTqLookup; var Argv: TTqArgs; Blk: TTqCodeBlock): string;
    function ObjNamespace(Obj: TSimObject): string;
    function ResolveCase(const Base, Rel: string): string;
  public
    AppDir, PrefDir: string;   { with trailing '/' }
    Globals: TTqDict;
    ActivePackages: TStringList;
    EchoLog: TStringList;      { every console line (echo, warn, error, engine) }
    ExecTrail: TStringList;    { scripts run, in order (relative paths) }
    Problems: TStringList;     { unknown functions, failed objects, ... }
    NativeTrail: TStringList;  { calls into stubbed natives }
    RootGroup: TSimObject;
    OnCreate: TStringList;     { class name -> TTqObjectHook, run at registration }
    constructor Create(const AAppDir, APrefDir: string);
    destructor Destroy; override;
    { registration }
    procedure RegisterFn(const Ns, Name: string; Fn: TTqNative);
    procedure RegisterClass(const Name, Parent: string; IsSet: Boolean = False;
      IsGroup: Boolean = False);
    procedure SetCreateHook(const ClassName: string; Hook: TTqObjectHook);
    function ClassInfo_(const Name: string): TTqClassInfo;
    function IsA(const ClassName, Ancestor: string): Boolean;
    { console }
    procedure Print(const S: string);
    procedure Problem(const S: string);
    { files: paths relative to the install, '/' separated }
    function FindFile(const Rel: string): string;
    function WritePath(const Rel: string): string;
    function ExpandScriptPath(const S: string): string;
    function CurrentBlockPath: string;
    function ExecScript(const Path: string): Boolean;
    function EvalString(const Src: string): string;
    function CompileAndRun(const Src, Path: string): Boolean;
    { calls }
    function CallFunction(const Name: string; const Args: array of string): string;
    function CallMethod(Obj: TSimObject; const Name: string;
      const Args: array of string; OnlyIfDefined: Boolean = True): string;
    function IsMethod(Obj: TSimObject; const Name: string): Boolean;
    function IsFunction(const Name: string): Boolean;
    { objects }
    function NewObject(const ClassName: string): TSimObject;
    function RegisterObject(Obj: TSimObject; const Name: string): Boolean;
    procedure DeleteObject(Obj: TSimObject);
    procedure AddToSet(SetObj, Obj: TSimObject);
    procedure RemoveFromSet(SetObj, Obj: TSimObject);
    procedure AssignName(Obj: TSimObject; const Name: string);
    function FindObject(const S: string): TSimObject;
    function ObjectById(Id: Integer): TSimObject;
  end;

{ Torque's number formats }
function TqFmtFloat(D: Double): string;   { printf %g }
function TqAtof(const S: string): Double;
function TqAtoi(const S: string): Int64;

implementation

uses
  TqCompile;

const
  FirstDynamicId = 1027; { TGE 1.x: datablock ids 3..1026, then dynamic ids }

{ --- number formats --- }

function TqFmtFloat(D: Double): string;
var
  E, Prec: Integer;
  S: string;
  P: Integer;
  Fmt: TFormatSettings;
begin
  { C printf("%g"): 6 significant digits, trailing zeros removed,
    exponent form when exp < -4 or exp >= 6 }
  if D = 0 then
    Exit('0');
  if IsNan(D) then
    Exit('nan');
  if IsInfinite(D) then
    if D > 0 then Exit('inf') else Exit('-inf');
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Prec := 6;
  S := FloatToStrF(Abs(D), ffExponent, Prec, 0, Fmt); { d.ddddE+xx }
  E := StrToInt(Copy(S, Pos('E', S) + 1, MaxInt));
  if (E < -4) or (E >= Prec) then
  begin
    S := Copy(S, 1, Pos('E', S) - 1);
    if Pos('.', S) > 0 then
    begin
      while S[Length(S)] = '0' do Delete(S, Length(S), 1);
      if S[Length(S)] = '.' then Delete(S, Length(S), 1);
    end;
    if E < 0 then
      S := S + 'e-' + Format('%.2d', [-E])
    else
      S := S + 'e+' + Format('%.2d', [E]);
  end
  else
  begin
    S := FloatToStrF(Abs(D), ffFixed, 18, Prec - 1 - E, Fmt);
    P := Pos('.', S);
    if P > 0 then
    begin
      while S[Length(S)] = '0' do Delete(S, Length(S), 1);
      if S[Length(S)] = '.' then Delete(S, Length(S), 1);
    end;
  end;
  if D < 0 then
    S := '-' + S;
  Result := S;
end;

function TqAtof(const S: string): Double;
var
  P, St: Integer;
  Fmt: TFormatSettings;
begin
  P := 1;
  while (P <= Length(S)) and (S[P] in [' ', #9, #10, #13]) do Inc(P);
  St := P;
  if (P <= Length(S)) and (S[P] in ['+', '-']) then Inc(P);
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  if (P <= Length(S)) and (S[P] = '.') then
  begin
    Inc(P);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  end;
  if (P <= Length(S)) and (S[P] in ['e', 'E']) and (P + 1 <= Length(S)) and
    ((S[P + 1] in ['0'..'9']) or ((S[P + 1] in ['+', '-']) and (P + 2 <= Length(S))
    and (S[P + 2] in ['0'..'9']))) then
  begin
    Inc(P, 2);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  end;
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Result := StrToFloatDef(Copy(S, St, P - St), 0, Fmt);
end;

function TqAtoi(const S: string): Int64;
var
  P: Integer;
  Neg: Boolean;
begin
  Result := 0;
  P := 1;
  while (P <= Length(S)) and (S[P] in [' ', #9, #10, #13]) do Inc(P);
  Neg := False;
  if (P <= Length(S)) and (S[P] in ['+', '-']) then
  begin
    Neg := S[P] = '-';
    Inc(P);
  end;
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(S[P]) - Ord('0');
    Inc(P);
  end;
  if Neg then
    Result := -Result;
end;

{ --- TTqVar / TTqDict --- }

function TTqVar.AsStr: string;
begin
  case Kind of
    tqInt: Result := IntToStr(I);
    tqFlt: Result := TqFmtFloat(F);
  else
    Result := S;
  end;
end;

function TTqVar.AsInt: Int64;
begin
  case Kind of
    tqInt: Result := I;
    tqFlt: Result := Trunc(F);
  else
    Result := TqAtoi(S);
  end;
end;

function TTqVar.AsFlt: Double;
begin
  case Kind of
    tqInt: Result := I;
    tqFlt: Result := F;
  else
    Result := TqAtof(S);
  end;
end;

procedure TTqVar.SetStr(const V: string);
begin
  Kind := tqStr;
  S := V;
end;

constructor TTqDict.Create;
begin
  FList := TStringList.Create;
  FList.Sorted := True;
  FList.CaseSensitive := False;
  FList.Duplicates := dupIgnore;
  FList.OwnsObjects := True;
end;

destructor TTqDict.Destroy;
begin
  FList.Free;
  inherited;
end;

function TTqDict.Find(const Name: string): TTqVar;
var
  I: Integer;
begin
  if FList.Find(Name, I) then
    Result := TTqVar(FList.Objects[I])
  else
    Result := nil;
end;

function TTqDict.Get(const Name: string): TTqVar;
begin
  Result := Find(Name);
  if Result = nil then
  begin
    Result := TTqVar.Create;
    Result.Name := Name;
    FList.AddObject(Name, Result);
  end;
end;

function TTqDict.Count: Integer;
begin
  Result := FList.Count;
end;

function TTqDict.Item(I: Integer): TTqVar;
begin
  Result := TTqVar(FList.Objects[I]);
end;

procedure TTqDict.Remove(const Name: string);
var
  I: Integer;
begin
  if FList.Find(Name, I) then
    FList.Delete(I);
end;

{ --- TSimObject --- }

constructor TSimObject.Create;
begin
  Fields := TStringList.Create;
  Fields.CaseSensitive := False;
  Fields.NameValueSeparator := #1;
  Sets := TList.Create;
end;

destructor TSimObject.Destroy;
begin
  Fields.Free;
  Sets.Free;
  Children.Free;
  Data.Free;
  inherited;
end;

function TSimObject.GetField(const F: string): string;
var
  I: Integer;
begin
  I := Fields.IndexOfName(F);
  if I >= 0 then
    Result := Fields.ValueFromIndex[I]
  else
    Result := '';
end;

procedure TSimObject.SetField(const F, V: string);
var
  I: Integer;
begin
  I := Fields.IndexOfName(F);
  if I >= 0 then
    Fields[I] := Fields.Names[I] + #1 + V
  else
    Fields.Add(F + #1 + V);
end;

function TSimObject.IdStr: string;
begin
  Result := IntToStr(Id);
end;

function TSimObject.ChildCount: Integer;
begin
  if Children = nil then Result := 0 else Result := Children.Count;
end;

function TSimObject.Child(I: Integer): TSimObject;
begin
  Result := TSimObject(Children[I]);
end;

{ --- VM --- }

constructor TTqVM.Create(const AAppDir, APrefDir: string);

  function NewSorted(Owns: Boolean): TStringList;
  begin
    Result := TStringList.Create;
    Result.Sorted := True;
    Result.CaseSensitive := False;
    Result.Duplicates := dupIgnore;
    Result.OwnsObjects := Owns;
  end;

begin
  AppDir := IncludeTrailingPathDelimiter(AAppDir);
  PrefDir := IncludeTrailingPathDelimiter(APrefDir);
  FFuncs := NewSorted(True);
  FNatives := NewSorted(False);
  FNsParent := NewSorted(False);
  FClasses := NewSorted(True);
  FObjects := TList.Create;
  FById := NewSorted(False);
  FNames := NewSorted(False);
  FBlocks := TList.Create;
  FDirCache := NewSorted(True);
  OnCreate := NewSorted(False);
  Globals := TTqDict.Create;
  ActivePackages := TStringList.Create;
  ActivePackages.CaseSensitive := False;
  EchoLog := TStringList.Create;
  ExecTrail := TStringList.Create;
  Problems := TStringList.Create;
  NativeTrail := TStringList.Create;
  FNextId := FirstDynamicId;
  SetLength(IntS, 256);
  SetLength(FltS, 256);
  SetLength(SS, 1024);
  SetLength(FrameStarts, 256);
  SetLength(Frames, 256);
  IT := -1;
  FT := -1;
  ST := 0;
  SS[0] := '';
  FrTop := -1;
  RegisterClass('SimObject', '');
  RegisterClass('SimSet', 'SimObject', True);
  RegisterClass('SimGroup', 'SimSet', True, True);
  RootGroup := NewObject('SimGroup');
  RootGroup.Id := 0;
  RootGroup.Registered := True;
  AssignName(RootGroup, 'RootGroup');
  FById.AddObject(Format('%.10d', [0]), RootGroup);
  FObjects.Add(RootGroup);
end;

destructor TTqVM.Destroy;
var
  I: Integer;
begin
  for I := 0 to FObjects.Count - 1 do
    TObject(FObjects[I]).Free;
  FObjects.Free;
  for I := 0 to FBlocks.Count - 1 do
    TObject(FBlocks[I]).Free;
  FBlocks.Free;
  FFuncs.Free;
  FNatives.Free;
  FNsParent.Free;
  FClasses.Free;
  FById.Free;
  FNames.Free;
  FDirCache.Free;
  OnCreate.Free;
  Globals.Free;
  ActivePackages.Free;
  EchoLog.Free;
  ExecTrail.Free;
  Problems.Free;
  NativeTrail.Free;
  inherited;
end;

function TTqVM.FuncKey(const Ns, Pkg, Name: string): string;
begin
  Result := LowerCase(Ns + '|' + Pkg + '|' + Name);
end;

procedure TTqVM.RegisterFn(const Ns, Name: string; Fn: TTqNative);
var
  I: Integer;
  K: string;
begin
  K := LowerCase(Ns + '|' + Name);
  if FNatives.Find(K, I) then
    FNatives.Objects[I] := TObject(Pointer(@Fn))
  else
    FNatives.AddObject(K, TObject(Pointer(@Fn)));
end;

procedure TTqVM.RegisterClass(const Name, Parent: string; IsSet: Boolean;
  IsGroup: Boolean);
var
  C: TTqClassInfo;
  P: TTqClassInfo;
  I: Integer;
begin
  C := TTqClassInfo.Create;
  C.Name := Name;
  C.Parent := Parent;
  P := ClassInfo_(Parent);
  C.IsSet := IsSet or ((P <> nil) and P.IsSet);
  C.IsGroup := IsGroup or ((P <> nil) and P.IsGroup);
  C.IsGui := SameText(Name, 'GuiControl') or ((P <> nil) and P.IsGui);
  if FClasses.Find(Name, I) then
    FClasses.Delete(I);
  FClasses.AddObject(Name, C);
  if Parent <> '' then
  begin
    if FNsParent.Find(Name, I) then
      FNsParent.Delete(I);
    FNsParent.AddObject(Name, TObject(NewStr(Parent)));
  end;
end;

procedure TTqVM.SetCreateHook(const ClassName: string; Hook: TTqObjectHook);
var
  I: Integer;
begin
  if OnCreate.Find(ClassName, I) then
    OnCreate.Objects[I] := TObject(Pointer(@Hook))
  else
    OnCreate.AddObject(ClassName, TObject(Pointer(@Hook)));
end;

function TTqVM.ClassInfo_(const Name: string): TTqClassInfo;
var
  I: Integer;
begin
  if (Name <> '') and FClasses.Find(Name, I) then
    Result := TTqClassInfo(FClasses.Objects[I])
  else
    Result := nil;
end;

function TTqVM.IsA(const ClassName, Ancestor: string): Boolean;
var
  C: TTqClassInfo;
begin
  C := ClassInfo_(ClassName);
  while C <> nil do
  begin
    if SameText(C.Name, Ancestor) then
      Exit(True);
    C := ClassInfo_(C.Parent);
  end;
  Result := False;
end;

procedure TTqVM.Print(const S: string);
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.Text := S;
    if (S <> '') and (S[Length(S)] = #10) then
      L.Add('');
    if L.Count = 0 then
      L.Add('');
    for I := 0 to L.Count - 1 do
      EchoLog.Add(L[I]);
  finally
    L.Free;
  end;
end;

procedure TTqVM.Problem(const S: string);
begin
  Problems.Add(S);
  Print(S);
end;

{ --- files --- }

function TTqVM.ResolveCase(const Base, Rel: string): string;
{ Torque's resource manager matches names case-insensitively. Walk Rel
  under Base one part at a time and return the real path, or ''. }
var
  Parts: TStringList;
  Cur, Want, Found: string;
  I: Integer;
  SR: TSearchRec;
begin
  Result := '';
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '/';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Rel;
    Cur := ExcludeTrailingPathDelimiter(Base);
    for I := 0 to Parts.Count - 1 do
    begin
      Want := Parts[I];
      if (Want = '') or (Want = '.') then
        Continue;
      if FileExists(Cur + '/' + Want) or DirectoryExists(Cur + '/' + Want) then
      begin
        Cur := Cur + '/' + Want;
        Continue;
      end;
      Found := '';
      if FindFirst(Cur + '/*', faAnyFile, SR) = 0 then
      begin
        repeat
          if SameText(SR.Name, Want) then
          begin
            Found := SR.Name;
            Break;
          end;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
      if Found = '' then
        Exit('');
      Cur := Cur + '/' + Found;
    end;
    if FileExists(Cur) then
      Result := Cur;
  finally
    Parts.Free;
  end;
end;

function NormPath(const S: string): string;
var
  Parts, Outp: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  Outp := TStringList.Create;
  try
    Parts.Delimiter := '/';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := StringReplace(S, '\', '/', [rfReplaceAll]);
    for I := 0 to Parts.Count - 1 do
      if (Parts[I] = '') or (Parts[I] = '.') then
        Continue
      else if Parts[I] = '..' then
      begin
        if Outp.Count > 0 then
          Outp.Delete(Outp.Count - 1);
      end
      else
        Outp.Add(Parts[I]);
    Outp.Delimiter := '/';
    Outp.StrictDelimiter := True;
    Result := Outp.DelimitedText;
  finally
    Parts.Free;
    Outp.Free;
  end;
end;

function TTqVM.FindFile(const Rel: string): string;
var
  R: string;
begin
  R := NormPath(Rel);
  Result := ResolveCase(PrefDir, R);
  if Result = '' then
    Result := ResolveCase(AppDir, R);
end;

function TTqVM.WritePath(const Rel: string): string;
begin
  Result := PrefDir + NormPath(Rel);
  ForceDirectories(ExtractFileDir(Result));
end;

function TTqVM.CurrentBlockPath: string;
var
  I: Integer;
begin
  for I := FrameCount - 1 downto 0 do
    if Frames[I].Block <> nil then
      Exit(Frames[I].Block.Path);
  Result := '';
end;

function TTqVM.ExpandScriptPath(const S: string): string;
var
  Cur, Dir: string;
  P: Integer;
begin
  Cur := CurrentBlockPath;
  if Copy(S, 1, 2) = './' then
  begin
    Dir := ExtractFilePath(Cur);
    Result := NormPath(Dir + Copy(S, 3, MaxInt));
  end
  else if Copy(S, 1, 2) = '~/' then
  begin
    P := Pos('/', Cur);
    if P > 0 then
      Result := NormPath(Copy(Cur, 1, P) + Copy(S, 3, MaxInt))
    else
      Result := NormPath(Copy(S, 3, MaxInt));
  end
  else
    Result := NormPath(S);
end;

function ReadWhole(const FN: string): AnsiString;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FN, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function TTqVM.CompileAndRun(const Src, Path: string): Boolean;
var
  Blk: TTqCodeBlock;
  Err: string;
begin
  Blk := TqCompileSource(Src, Path, Err);
  if Blk = nil then
  begin
    Problem(Err);
    Exit(False);
  end;
  FBlocks.Add(Blk);
  Inc(FrameCount);
  if FrameCount > Length(Frames) then
    SetLength(Frames, FrameCount * 2);
  Frames[FrameCount - 1].Block := Blk;
  Frames[FrameCount - 1].Ns := '';
  Frames[FrameCount - 1].Layer := 0;
  Frames[FrameCount - 1].Locals := nil;
  try
    Exec(Blk, 0, False);
  finally
    Dec(FrameCount);
  end;
  Result := True;
end;

function TTqVM.ExecScript(const Path: string): Boolean;
var
  Rel, Src, Dso, Err: string;
  Blk: TTqCodeBlock;
begin
  Rel := NormPath(Path);
  Src := FindFile(Rel);
  if Src <> '' then
  begin
    ExecTrail.Add(Rel);
    Exit(CompileAndRun(ReadWhole(Src), Rel));
  end;
  Dso := FindFile(Rel + '.dso');
  if Dso = '' then
  begin
    Problem('Missing file: ' + Rel + '!');
    Exit(False);
  end;
  ExecTrail.Add(Rel);
  Blk := TTqCodeBlock.Create;
  Blk.Path := Rel;
  if not Blk.LoadDso(ReadWhole(Dso), Err) then
  begin
    Blk.Free;
    Problem('Bad compiled script ' + Rel + ': ' + Err);
    Exit(False);
  end;
  FBlocks.Add(Blk);
  Inc(FrameCount);
  if FrameCount > Length(Frames) then
    SetLength(Frames, FrameCount * 2);
  Frames[FrameCount - 1].Block := Blk;
  Frames[FrameCount - 1].Ns := '';
  Frames[FrameCount - 1].Layer := 0;
  Frames[FrameCount - 1].Locals := nil;
  try
    Exec(Blk, 0, False);
  finally
    Dec(FrameCount);
  end;
  Result := True;
end;

function TTqVM.EvalString(const Src: string): string;
var
  Blk: TTqCodeBlock;
  Err: string;
  Saved: Integer;
begin
  Blk := TqCompileSource(Src, CurrentBlockPath, Err);
  if Blk = nil then
  begin
    Problem('eval: ' + Err);
    Exit('');
  end;
  FBlocks.Add(Blk);
  { eval runs with the caller's locals visible, like Torque's eval }
  Saved := FrameCount;
  Inc(FrameCount);
  if FrameCount > Length(Frames) then
    SetLength(Frames, FrameCount * 2);
  Frames[FrameCount - 1] := Frames[Saved - 1];
  Frames[FrameCount - 1].Block := Blk;
  try
    Result := Exec(Blk, 0, False);
  finally
    FrameCount := Saved;
  end;
end;

{ --- namespaces and calls --- }

function TTqVM.LayerCount: Integer;
begin
  Result := ActivePackages.Count + 1;
end;

function TTqVM.LayerName(I: Integer): string;
begin
  { newest package first, the base layer ('') last }
  if I < ActivePackages.Count then
    Result := ActivePackages[ActivePackages.Count - 1 - I]
  else
    Result := '';
end;

function TTqVM.LookupFrom(const Ns: string; Layer: Integer; const Fn: string): TTqLookup;
var
  Cur, Pkg: string;
  L, I: Integer;
begin
  Result.Def := nil;
  Result.Native := nil;
  Cur := Ns;
  L := Layer;
  while True do
  begin
    while L < LayerCount do
    begin
      Pkg := LayerName(L);
      if FFuncs.Find(FuncKey(Cur, Pkg, Fn), I) then
      begin
        Result.Def := TTqFuncDef(FFuncs.Objects[I]);
        Result.Ns := Cur;
        Result.Layer := L;
        Exit;
      end;
      if (Pkg = '') and FNatives.Find(LowerCase(Cur + '|' + Fn), I) then
      begin
        Result.Native := TTqNative(Pointer(FNatives.Objects[I]));
        Result.Ns := Cur;
        Result.Layer := L;
        Exit;
      end;
      Inc(L);
    end;
    if Cur = '' then
      Exit;
    if not FNsParent.Find(Cur, I) then
      Exit;
    Cur := PString(FNsParent.Objects[I])^;
    L := 0;
  end;
end;

function TTqVM.ObjNamespace(Obj: TSimObject): string;
begin
  if Obj.Name <> '' then
    Result := Obj.Name
  else
    Result := Obj.ClassName_;
end;

function TTqVM.CallLookup(const L: TTqLookup; var Argv: TTqArgs; Blk: TTqCodeBlock): string;
var
  D: TTqFuncDef;
  Locals: TTqDict;
  K: Integer;
  V: TTqVar;
begin
  if L.Native <> nil then
    Exit(L.Native(Self, Argv));
  D := L.Def;
  Locals := TTqDict.Create;
  try
    for K := 0 to High(D.ArgNames) do
      if D.ArgNames[K] <> '' then
      begin
        V := Locals.Get(D.ArgNames[K]);
        if K + 1 <= High(Argv) then
          V.SetStr(Argv[K + 1])
        else
          V.SetStr('');
      end;
    Inc(FrameCount);
    if FrameCount > Length(Frames) then
      SetLength(Frames, FrameCount * 2);
    Frames[FrameCount - 1].Block := D.Block;
    Frames[FrameCount - 1].Ns := L.Ns;
    Frames[FrameCount - 1].Layer := L.Layer;
    Frames[FrameCount - 1].Locals := Locals;
    try
      Result := Exec(D.Block, D.BodyIp, True);
    finally
      Dec(FrameCount);
    end;
  finally
    Locals.Free;
  end;
end;

function TTqVM.CallFunction(const Name: string; const Args: array of string): string;
var
  L: TTqLookup;
  Argv: TTqArgs;
  K: Integer;
begin
  L := LookupFrom('', 0, Name);
  if (L.Def = nil) and (@L.Native = nil) then
  begin
    Problem(Format('Unable to find function %s', [Name]));
    Exit('');
  end;
  SetLength(Argv, Length(Args) + 1);
  Argv[0] := Name;
  for K := 0 to High(Args) do
    Argv[K + 1] := Args[K];
  Result := CallLookup(L, Argv, nil);
end;

function TTqVM.IsMethod(Obj: TSimObject; const Name: string): Boolean;
var
  L: TTqLookup;
begin
  L := LookupFrom(ObjNamespace(Obj), 0, Name);
  Result := (L.Def <> nil) or (@L.Native <> nil);
end;

function TTqVM.IsFunction(const Name: string): Boolean;
var
  L: TTqLookup;
begin
  L := LookupFrom('', 0, Name);
  Result := (L.Def <> nil) or (@L.Native <> nil);
end;

function TTqVM.CallMethod(Obj: TSimObject; const Name: string;
  const Args: array of string; OnlyIfDefined: Boolean): string;
var
  L: TTqLookup;
  Argv: TTqArgs;
  K: Integer;
begin
  Result := '';
  L := LookupFrom(ObjNamespace(Obj), 0, Name);
  if (L.Def = nil) and (@L.Native = nil) then
  begin
    if not OnlyIfDefined then
      Problem(Format('%s: Unknown command %s.', [Obj.ClassName_, Name]));
    Exit;
  end;
  SetLength(Argv, Length(Args) + 2);
  Argv[0] := Name;
  Argv[1] := Obj.IdStr;
  for K := 0 to High(Args) do
    Argv[K + 2] := Args[K];
  Result := CallLookup(L, Argv, nil);
end;

{ --- objects --- }

function TTqVM.NewObject(const ClassName: string): TSimObject;
var
  C: TTqClassInfo;
begin
  C := ClassInfo_(ClassName);
  if C = nil then
    Exit(nil);
  Result := TSimObject.Create;
  Result.ClassName_ := C.Name;
  Result.IsSet := C.IsSet;
  Result.IsGroup := C.IsGroup;
  Result.IsGui := C.IsGui;
  if Result.IsSet then
    Result.Children := TList.Create;
end;

procedure TTqVM.AssignName(Obj: TSimObject; const Name: string);
var
  I: Integer;
begin
  if (Obj.Name <> '') and FNames.Find(Obj.Name, I) and (FNames.Objects[I] = Obj) then
    FNames.Delete(I);
  Obj.Name := Name;
  if Name = '' then
    Exit;
  if FNames.Find(Name, I) then
    FNames.Objects[I] := Obj
  else
    FNames.AddObject(Name, Obj);
  { a named object gets its own namespace, parented to its class }
  if not SameText(Name, Obj.ClassName_) then
  begin
    if FNsParent.Find(Name, I) then
      FNsParent.Delete(I);
    FNsParent.AddObject(Name, TObject(NewStr(Obj.ClassName_)));
  end;
end;

function TTqVM.RegisterObject(Obj: TSimObject; const Name: string): Boolean;
var
  I: Integer;
  Hook: TTqObjectHook;
  C: TTqClassInfo;
begin
  Obj.Id := FNextId;
  Inc(FNextId);
  Obj.Registered := True;
  FObjects.Add(Obj);
  FById.AddObject(Format('%.10d', [Obj.Id]), Obj);
  if Name <> '' then
    AssignName(Obj, Name);
  { class hooks, most derived first }
  C := ClassInfo_(Obj.ClassName_);
  while C <> nil do
  begin
    if OnCreate.Find(C.Name, I) then
    begin
      Hook := TTqObjectHook(Pointer(OnCreate.Objects[I]));
      Hook(Self, Obj);
      Break;
    end;
    C := ClassInfo_(C.Parent);
  end;
  Result := True;
end;

procedure TTqVM.AddToSet(SetObj, Obj: TSimObject);
begin
  if (SetObj = nil) or not SetObj.IsSet or (SetObj.Children.IndexOf(Obj) >= 0) then
    Exit;
  if SetObj.IsGroup then
  begin
    if Obj.Group <> nil then
      RemoveFromSet(Obj.Group, Obj);
    Obj.Group := SetObj;
  end;
  SetObj.Children.Add(Obj);
  Obj.Sets.Add(SetObj);
end;

procedure TTqVM.RemoveFromSet(SetObj, Obj: TSimObject);
begin
  if (SetObj = nil) or (SetObj.Children = nil) then
    Exit;
  SetObj.Children.Remove(Obj);
  Obj.Sets.Remove(SetObj);
  if Obj.Group = SetObj then
    Obj.Group := nil;
end;

procedure TTqVM.DeleteObject(Obj: TSimObject);
var
  I: Integer;
begin
  if (Obj = nil) or (Obj = RootGroup) then
    Exit;
  { a group deletes its members }
  if Obj.IsGroup then
    while Obj.ChildCount > 0 do
      DeleteObject(Obj.Child(Obj.ChildCount - 1));
  while Obj.Sets.Count > 0 do
    RemoveFromSet(TSimObject(Obj.Sets[0]), Obj);
  if Obj.Children <> nil then
    while Obj.Children.Count > 0 do
      RemoveFromSet(Obj, Obj.Child(0));
  if (Obj.Name <> '') and FNames.Find(Obj.Name, I) and (FNames.Objects[I] = Obj) then
    FNames.Delete(I);
  if FById.Find(Format('%.10d', [Obj.Id]), I) then
    FById.Delete(I);
  FObjects.Remove(Obj);
  Obj.Free;
end;

function TTqVM.ObjectById(Id: Integer): TSimObject;
var
  I: Integer;
begin
  if FById.Find(Format('%.10d', [Id]), I) then
    Result := TSimObject(FById.Objects[I])
  else
    Result := nil;
end;

function TTqVM.FindObject(const S: string): TSimObject;
var
  I: Integer;
  AllDigits: Boolean;
  P: string;
  Parts: TStringList;
  K, J: Integer;
  Cur: TSimObject;
begin
  Result := nil;
  if S = '' then
    Exit;
  AllDigits := True;
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
    begin
      AllDigits := False;
      Break;
    end;
  if AllDigits then
    Exit(ObjectById(StrToIntDef(S, -1)));
  if S[1] = '/' then
  begin
    { /RootGroup/Name/Name or /Name: walk the group tree }
    Parts := TStringList.Create;
    try
      Parts.Delimiter := '/';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Copy(S, 2, MaxInt);
      Cur := RootGroup;
      for K := 0 to Parts.Count - 1 do
      begin
        P := Parts[K];
        if P = '' then Continue;
        Result := nil;
        for J := 0 to Cur.ChildCount - 1 do
          if SameText(Cur.Child(J).Name, P) then
          begin
            Result := Cur.Child(J);
            Break;
          end;
        if Result = nil then
          Exit;
        Cur := Result;
      end;
    finally
      Parts.Free;
    end;
    Exit;
  end;
  if FNames.Find(S, I) then
    Result := TSimObject(FNames.Objects[I]);
end;

{ --- the interpreter --- }

procedure TTqVM.PushInt(V: Int64);
begin
  Inc(IT);
  if IT >= Length(IntS) then
    SetLength(IntS, Length(IntS) * 2);
  IntS[IT] := V;
end;

procedure TTqVM.PushFlt(V: Double);
begin
  Inc(FT);
  if FT >= Length(FltS) then
    SetLength(FltS, Length(FltS) * 2);
  FltS[FT] := V;
end;

function TTqVM.Exec(Blk: TTqCodeBlock; Ip: Integer; InFn: Boolean): string;
var
  Code: TCardinalArray;
  Op: Cardinal;
  CurVar: TTqVar;
  CurVarIsNew: Boolean;
  CurObj: TSimObject;
  CurField, CurFieldArr: string;
  CurNewObj: TSimObject;
  NewObjStack: array of TSimObject;
  NewObjTop: Integer;
  A, B: Int64;
  FA, FB: Double;
  S, Name, Ns, FnName, VarName: string;
  CallType, K, Argc: Integer;
  Argv: TTqArgs;
  Obj, Grp: TSimObject;
  L: TTqLookup;
  Def: TTqFuncDef;
  Locals: TTqDict;
  AtRoot: Boolean;
  FailIp: Integer;

  procedure Adv;
  begin
    Inc(ST);
    if ST >= Length(SS) then
      SetLength(SS, Length(SS) * 2);
    SS[ST] := '';
  end;

  function FieldKey: string;
  begin
    Result := CurField + CurFieldArr;
  end;

  procedure SelectVar(const N: string; Create: Boolean);
  var
    D: TTqDict;
  begin
    if (N <> '') and (N[1] = '$') then
      D := Globals
    else
    begin
      Locals := Frames[FrameCount - 1].Locals;
      if Locals = nil then
      begin
        { a local at file level: Torque keeps no frame; reads give "" }
        CurVar := nil;
        if Create then
          Problem('local variable ' + N + ' used at file level in ' + Blk.Path);
        Exit;
      end;
      D := Locals;
    end;
    if Create then
      CurVar := D.Get(N)
    else
      CurVar := D.Find(N);
  end;

begin
  Result := '';
  Code := Blk.Code;
  CurVar := nil;
  CurObj := nil;
  CurField := '';
  CurFieldArr := '';
  CurNewObj := nil;
  NewObjStack := nil;
  NewObjTop := 0;
  while (Ip >= 0) and (Ip < Length(Code)) do
  begin
    Op := Code[Ip];
    Inc(Ip);
    case Op of
      OP_FUNC_DECL:
        begin
          Def := TTqFuncDef.Create;
          Def.Block := Blk;
          Def.DeclIp := Ip - 1;
          Def.Name := TqIdent(Code[Ip]);
          Def.Ns := TqIdent(Code[Ip + 1]);
          Def.Pkg := TqIdent(Code[Ip + 2]);
          Argc := Code[Ip + 5];
          SetLength(Def.ArgNames, Argc);
          for K := 0 to Argc - 1 do
            Def.ArgNames[K] := TqIdent(Code[Ip + 6 + K]);
          Def.BodyIp := Ip + 6 + Argc;
          S := FuncKey(Def.Ns, Def.Pkg, Def.Name);
          if FFuncs.Find(S, K) then
            FFuncs.Delete(K);
          FFuncs.AddObject(S, Def);
          if Code[Ip + 3] <> 0 then
            Ip := Code[Ip + 4]
          else
            Ip := Def.BodyIp;
        end;
      OP_CREATE_OBJECT:
        begin
          Name := TqIdent(Code[Ip]); { copy-from object }
          FailIp := Code[Ip + 2];
          Inc(Ip, 3);
          { frame: class, object name, constructor args }
          K := FrameStarts[FrTop];
          Dec(FrTop);
          if ST - K >= 1 then S := SS[K] else S := '';
          if ST - K >= 2 then VarName := SS[K + 1] else VarName := '';
          ST := K;
          SS[ST] := '';
          Obj := NewObject(S);
          if Obj = nil then
          begin
            Problem(Format('%s: Unable to instantiate non-conobject class %s.',
              [Blk.Path, S]));
            { a failed root object still yields 0 for its expression }
            if (FailIp >= 2) and (Code[FailIp - 1] <> 0) then
              PushInt(0);
            Ip := FailIp;
            Continue;
          end;
          Obj.Name := VarName; { kept until ADD_OBJECT registers it }
          if Name <> '' then
          begin
            Grp := FindObject(Name);
            if Grp <> nil then
              Obj.Fields.Assign(Grp.Fields)
            else
              Problem(Blk.Path + ': copy source ' + Name + ' not found');
          end;
          if NewObjTop >= Length(NewObjStack) then
            SetLength(NewObjStack, NewObjTop * 2 + 8);
          NewObjStack[NewObjTop] := CurNewObj;
          Inc(NewObjTop);
          CurNewObj := Obj;
        end;
      OP_ADD_OBJECT:
        begin
          AtRoot := Code[Ip] <> 0;
          Inc(Ip);
          Obj := CurNewObj;
          Name := Obj.Name;
          Obj.Name := '';
          RegisterObject(Obj, Name);
          if not AtRoot then
          begin
            Grp := ObjectById(IntS[IT]);
            if (Grp <> nil) and Grp.IsSet then
              AddToSet(Grp, Obj);
          end
          else if Obj.Group = nil then
            AddToSet(RootGroup, Obj);
          PushInt(Obj.Id);
        end;
      OP_END_OBJECT:
        begin
          AtRoot := Code[Ip] <> 0;
          Inc(Ip);
          if not AtRoot then
            Dec(IT);
          Dec(NewObjTop);
          CurNewObj := NewObjStack[NewObjTop];
        end;
      OP_JMPIFFNOT:
        begin
          FA := FltS[FT]; Dec(FT);
          if FA = 0 then Ip := Code[Ip] else Inc(Ip);
        end;
      OP_JMPIFNOT:
        begin
          A := IntS[IT]; Dec(IT);
          if A = 0 then Ip := Code[Ip] else Inc(Ip);
        end;
      OP_JMPIFF:
        begin
          FA := FltS[FT]; Dec(FT);
          if FA <> 0 then Ip := Code[Ip] else Inc(Ip);
        end;
      OP_JMPIF:
        begin
          A := IntS[IT]; Dec(IT);
          if A <> 0 then Ip := Code[Ip] else Inc(Ip);
        end;
      OP_JMPIFNOT_NP:
        if IntS[IT] = 0 then
          Ip := Code[Ip]
        else
        begin
          Dec(IT);
          Inc(Ip);
        end;
      OP_JMPIF_NP:
        if IntS[IT] <> 0 then
          Ip := Code[Ip]
        else
        begin
          Dec(IT);
          Inc(Ip);
        end;
      OP_JMP:
        Ip := Code[Ip];
      OP_RETURN:
        begin
          Result := SS[ST];
          Exit;
        end;
      OP_CMPEQ, OP_CMPGR, OP_CMPGE, OP_CMPLT, OP_CMPLE, OP_CMPNE:
        begin
          FA := FltS[FT];      { left }
          FB := FltS[FT - 1];  { right }
          Dec(FT, 2);
          case Op of
            OP_CMPEQ: PushInt(Ord(FA = FB));
            OP_CMPGR: PushInt(Ord(FA > FB));
            OP_CMPGE: PushInt(Ord(FA >= FB));
            OP_CMPLT: PushInt(Ord(FA < FB));
            OP_CMPLE: PushInt(Ord(FA <= FB));
          else
            PushInt(Ord(FA <> FB));
          end;
        end;
      OP_XOR, OP_MOD, OP_BITAND, OP_BITOR, OP_SHR, OP_SHL, OP_AND, OP_OR:
        begin
          A := IntS[IT];      { left }
          B := IntS[IT - 1];  { right }
          Dec(IT);
          case Op of
            OP_XOR: IntS[IT] := A xor B;
            OP_MOD: if B <> 0 then IntS[IT] := A mod B else IntS[IT] := 0;
            OP_BITAND: IntS[IT] := A and B;
            OP_BITOR: IntS[IT] := A or B;
            OP_SHR: IntS[IT] := Cardinal(A) shr (B and 31);
            OP_SHL: IntS[IT] := Cardinal(A shl (B and 31));
            OP_AND: IntS[IT] := Ord((A <> 0) and (B <> 0));
          else
            IntS[IT] := Ord((A <> 0) or (B <> 0));
          end;
        end;
      OP_NOT:
        IntS[IT] := Ord(IntS[IT] = 0);
      OP_NOTF:
        begin
          FA := FltS[FT];
          Dec(FT);
          PushInt(Ord(FA = 0));
        end;
      OP_ONESCOMPLEMENT:
        IntS[IT] := Cardinal(not Cardinal(IntS[IT]));
      OP_ADD, OP_SUB, OP_MUL, OP_DIV:
        begin
          FA := FltS[FT];
          FB := FltS[FT - 1];
          Dec(FT);
          case Op of
            OP_ADD: FltS[FT] := FA + FB;
            OP_SUB: FltS[FT] := FA - FB;
            OP_MUL: FltS[FT] := FA * FB;
          else
            if FB <> 0 then
              FltS[FT] := FA / FB
            else if FA = 0 then
              FltS[FT] := NaN
            else if FA > 0 then
              FltS[FT] := Infinity
            else
              FltS[FT] := NegInfinity;
          end;
        end;
      OP_NEG:
        FltS[FT] := -FltS[FT];
      OP_SETCURVAR, OP_SETCURVAR_CREATE:
        begin
          SelectVar(TqIdent(Code[Ip]), Op = OP_SETCURVAR_CREATE);
          Inc(Ip);
        end;
      OP_SETCURVAR_ARRAY, OP_SETCURVAR_ARRAY_CREATE:
        SelectVar(SS[ST], Op = OP_SETCURVAR_ARRAY_CREATE);
      OP_LOADVAR_UINT:
        if CurVar <> nil then PushInt(CurVar.AsInt) else PushInt(0);
      OP_LOADVAR_FLT:
        if CurVar <> nil then PushFlt(CurVar.AsFlt) else PushFlt(0);
      OP_LOADVAR_STR:
        if CurVar <> nil then SS[ST] := CurVar.AsStr else SS[ST] := '';
      OP_SAVEVAR_UINT:
        if CurVar <> nil then
        begin
          CurVar.Kind := tqInt;
          CurVar.I := IntS[IT];
        end;
      OP_SAVEVAR_FLT:
        if CurVar <> nil then
        begin
          CurVar.Kind := tqFlt;
          CurVar.F := FltS[FT];
        end;
      OP_SAVEVAR_STR:
        if CurVar <> nil then
          CurVar.SetStr(SS[ST]);
      OP_SETCUROBJECT:
        CurObj := FindObject(SS[ST]);
      OP_SETCUROBJECT_NEW:
        CurObj := CurNewObj;
      OP_SETCURFIELD:
        begin
          CurField := TqIdent(Code[Ip]);
          CurFieldArr := '';
          Inc(Ip);
        end;
      OP_SETCURFIELD_ARRAY:
        CurFieldArr := SS[ST];
      OP_LOADFIELD_UINT:
        if CurObj <> nil then PushInt(TqAtoi(CurObj.GetField(FieldKey))) else PushInt(0);
      OP_LOADFIELD_FLT:
        if CurObj <> nil then PushFlt(TqAtof(CurObj.GetField(FieldKey))) else PushFlt(0);
      OP_LOADFIELD_STR:
        if CurObj <> nil then SS[ST] := CurObj.GetField(FieldKey) else SS[ST] := '';
      OP_SAVEFIELD_UINT:
        if CurObj <> nil then CurObj.SetField(FieldKey, IntToStr(IntS[IT]));
      OP_SAVEFIELD_FLT:
        if CurObj <> nil then CurObj.SetField(FieldKey, TqFmtFloat(FltS[FT]));
      OP_SAVEFIELD_STR:
        if CurObj <> nil then CurObj.SetField(FieldKey, SS[ST]);
      OP_STR_TO_UINT:
        PushInt(TqAtoi(SS[ST]));
      OP_STR_TO_FLT:
        PushFlt(TqAtof(SS[ST]));
      OP_STR_TO_NONE:
        ;
      OP_FLT_TO_UINT:
        begin
          FA := FltS[FT];
          Dec(FT);
          if IsNan(FA) or IsInfinite(FA) then PushInt(0) else PushInt(Trunc(FA));
        end;
      OP_FLT_TO_STR:
        begin
          SS[ST] := TqFmtFloat(FltS[FT]);
          Dec(FT);
        end;
      OP_FLT_TO_NONE:
        Dec(FT);
      OP_UINT_TO_FLT:
        begin
          A := IntS[IT];
          Dec(IT);
          PushFlt(A);
        end;
      OP_UINT_TO_STR:
        begin
          SS[ST] := IntToStr(IntS[IT]);
          Dec(IT);
        end;
      OP_UINT_TO_NONE:
        Dec(IT);
      OP_LOADIMMED_UINT:
        begin
          PushInt(Code[Ip]);
          Inc(Ip);
        end;
      OP_LOADIMMED_FLT:
        begin
          PushFlt(Blk.Flt(InFn, Code[Ip]));
          Inc(Ip);
        end;
      OP_TAG_TO_STR, OP_LOADIMMED_STR:
        begin
          SS[ST] := Blk.Str(InFn, Code[Ip]);
          Inc(Ip);
        end;
      OP_LOADIMMED_IDENT:
        begin
          SS[ST] := TqIdent(Code[Ip]);
          Inc(Ip);
        end;
      OP_CALLFUNC, OP_CALLFUNC_RESOLVE:
        begin
          FnName := TqIdent(Code[Ip]);
          Ns := TqIdent(Code[Ip + 1]);
          CallType := Code[Ip + 2];
          Inc(Ip, 3);
          K := FrameStarts[FrTop];
          Dec(FrTop);
          SetLength(Argv, ST - K + 1);
          Argv[0] := FnName;
          for Argc := K to ST - 1 do
            Argv[Argc - K + 1] := SS[Argc];
          ST := K;
          S := '';
          L.Def := nil;
          L.Native := nil;
          case CallType of
            CALL_METHOD:
              begin
                if Length(Argv) < 2 then
                  Obj := nil
                else
                  Obj := FindObject(Argv[1]);
                if Obj = nil then
                begin
                  if Length(Argv) >= 2 then
                    Problem(Format('%s: Unable to find object: ''%s'' attempting to call function ''%s''',
                      [Blk.Path, Argv[1], FnName]))
                  else
                    Problem(Blk.Path + ': method call without an object: ' + FnName);
                end
                else
                begin
                  Argv[1] := Obj.IdStr;
                  L := LookupFrom(ObjNamespace(Obj), 0, FnName);
                  if (L.Def = nil) and (@L.Native = nil) then
                    Problem(Format('%s: Unknown command %s (object %s, class %s).',
                      [Blk.Path, FnName, Obj.IdStr + ' ' + Obj.Name, Obj.ClassName_]));
                end;
              end;
            CALL_PARENT:
              begin
                L := LookupFrom(Frames[FrameCount - 1].Ns,
                  Frames[FrameCount - 1].Layer + 1, FnName);
                { no parent definition is not an error in Torque }
              end;
          else
            L := LookupFrom(Ns, 0, FnName);
            if (L.Def = nil) and (@L.Native = nil) then
              if Ns <> '' then
                Problem(Format('%s: Unable to find function %s::%s', [Blk.Path, Ns, FnName]))
              else
                Problem(Format('%s: Unable to find function %s', [Blk.Path, FnName]));
          end;
          if (L.Def <> nil) or (@L.Native <> nil) then
            S := CallLookup(L, Argv, Blk);
          SS[ST] := S;
        end;
      OP_ADVANCE_STR, OP_ADVANCE_STR_NUL:
        Adv;
      OP_ADVANCE_STR_APPENDCHAR:
        begin
          SS[ST] := SS[ST] + Chr(Code[Ip] and $FF);
          Inc(Ip);
          Adv;
        end;
      OP_ADVANCE_STR_COMMA:
        begin
          SS[ST] := SS[ST] + '_';
          Adv;
        end;
      OP_REWIND_STR:
        begin
          S := SS[ST];
          Dec(ST);
          SS[ST] := SS[ST] + S;
        end;
      OP_TERMINATE_REWIND_STR:
        Dec(ST);
      OP_COMPARE_STR:
        begin
          S := SS[ST];
          Dec(ST);
          PushInt(Ord(SameText(SS[ST], S)));
          SS[ST] := '';
        end;
      OP_PUSH:
        Adv;
      OP_PUSH_FRAME:
        begin
          Inc(FrTop);
          if FrTop >= Length(FrameStarts) then
            SetLength(FrameStarts, Length(FrameStarts) * 2);
          FrameStarts[FrTop] := ST;
        end;
      OP_BREAK:
        ;
    else
      Problem(Format('%s: bad opcode %d at %d', [Blk.Path, Op, Ip - 1]));
      Exit;
    end;
  end;
end;

end.
