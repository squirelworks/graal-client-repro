{ GGs1: the GS1 script language, shared by the builds that run GS1 on the
  client (2.05 rev 2 and 2.17.1 so far). It follows 2.05 rev 2; a later
  build runs the same language until a difference is found, and then the
  difference goes in that build's NPC host or in a copy of this unit.

  2.05 does not compile GS1 to bytecode. A script arrives as text (the
  level file's NPC block, or NPCPROP_SCRIPT), is compiled once into a flat
  list of statement nodes, and every event runs that list from the top
  (graal_analysis npc-library/gs1-reference-205.md and
  gs1-command-reference-205.md). This unit follows that model:

  - commands are 600 + their index in the 161-entry table below, each with
    an argument signature (R number, S/M text, F/Q file, I item, B baddy,
    C colour, D direction, L carry object, O tile object);
  - if, for, while, else, functions and braces become four internal node
    kinds: expression statement, jump, call and end of function;
  - for and while stop after 10,000 passes, calls nest at most 10,000 deep;
  - setlevel, setlevel2, destroy, a non-zero sleep, and break or continue
    outside a loop end the run; sleep remembers the next statement, and the
    next timeout event resumes there;
  - text arguments are raw text up to the next comma or semicolon (2.05
    keeps quote marks as text), trimmed, with message codes (#c, #v(...),
    #s(...), ...) expanded when the command runs.

  What the names mean (the NPC's x and y, playerx, flags, the commands
  themselves) belongs to the host: the NPC unit implements TGsHost. Written
  from the notes above, not from the original program. }
unit GGs1;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat, Classes, SysUtils, Math;

const
  GsFirstOp = 600;
  GsCommandCount = 161;
  GsMaxLoop = 10000;
  GsMaxDepth = 10000;
  { 2.05's evaluator counts a condition as true at 1.0 or more? The notes say
    "true when it evaluates to >= 1.0" for if; comparisons give 0 or 1. }
  GsTrue = 1.0;

  { Commands by opcode, as the table numbers them (600 + index). }
  GsOpSay = 600; GsOpLay = 601; GsOpTake = 602; GsOpHurt = 603; GsOpSet = 604;
  GsOpIf = 605; GsOpPlay = 606; GsOpUnset = 607; GsOpSetGif = 608;
  GsOpSetLevel = 610; GsOpSetPlayerDir = 616; GsOpPutComp = 617;
  GsOpDontBlockLocal = 619; GsOpDrawOverPlayer = 620; GsOpEnableWeapons = 621;
  GsOpDisableWeapons = 622; GsOpShootArrow = 623; GsOpTimerShow = 631;
  GsOpToInventory = 632; GsOpFollowPlayer = 633; GsOpElse = 634;
  GsOpBlockAgainLocal = 638; GsOpDrawUnderPlayer = 639;
  GsOpCanBeCarried = 641; GsOpCannotBeCarried = 642; GsOpCanBePushed = 644;
  GsOpCannotBePushed = 645; GsOpCanBePulled = 646; GsOpCannotBePulled = 647;
  GsOpMessage = 648; GsOpPutNewComp = 651; GsOpPutNpc = 652; GsOpDestroy = 653;
  GsOpFreezePlayer = 654; GsOpToWeapons = 656; GsOpShowImg = 657;
  GsOpHideImg = 658; GsOpFor = 660; GsOpHitCompu = 661; GsOpSetArray = 666;
  GsOpSleep = 667; GsOpWhile = 668; GsOpTimerEverywhere = 670;
  GsOpShowCharacter = 673; GsOpSetPlayerProp = 674; GsOpSetCharProp = 675;
  GsOpSetString = 677; GsOpShowLocal = 686; GsOpHideLocal = 687;
  GsOpDontBlock = 688; GsOpBlockAgain = 689; GsOpLay2 = 699;
  GsOpChangeImgPart = 704; GsOpSetLevel2 = 705; GsOpHitNpc = 706;
  GsOpSetAni = 708; GsOpSetCharAni = 709; GsOpCallNpc = 710; GsOpSay2 = 711;
  GsOpBreak = 712; GsOpContinue = 713; GsOpCallWeapon = 714;
  GsOpFunction = 716; GsOpReturn = 717; GsOpChangeImgVis = 718;
  GsOpSetImg = 719; GsOpSetImgPart = 720; GsOpShowStats = 723;
  GsOpSetShape = 725; GsOpDrawAsLight = 729; GsOpTokenize = 742;
  GsOpTokenize2 = 743; GsOpTriggerAction = 744; GsOpMove = 745;
  GsOpShow = 759; GsOpHide = 760;

  { The command table: name and argument signature, by index. }
  GsCommands: array[0..GsCommandCount - 1] of record
    Name, Sig: string;
  end = (
    (Name: 'say'; Sig: 'R'),
    (Name: 'lay'; Sig: 'I'),
    (Name: 'take'; Sig: 'I'),
    (Name: 'hurt'; Sig: 'R'),
    (Name: 'set'; Sig: 'M'),
    (Name: 'if'; Sig: ''),
    (Name: 'play'; Sig: 'F'),
    (Name: 'unset'; Sig: 'M'),
    (Name: 'setgif'; Sig: 'F'),
    (Name: 'removecompus'; Sig: ''),
    (Name: 'setlevel'; Sig: 'M'),
    (Name: 'setskincolor'; Sig: 'C'),
    (Name: 'setcoatcolor'; Sig: 'C'),
    (Name: 'setsleevecolor'; Sig: 'C'),
    (Name: 'setshoecolor'; Sig: 'C'),
    (Name: 'setbeltcolor'; Sig: 'C'),
    (Name: 'setplayerdir'; Sig: 'D'),
    (Name: 'putcomp'; Sig: 'BRR'),
    (Name: 'takeplayercarry'; Sig: ''),
    (Name: 'dontblocklocal'; Sig: ''),
    (Name: 'drawoverplayer'; Sig: ''),
    (Name: 'enableweapons'; Sig: ''),
    (Name: 'disableweapons'; Sig: ''),
    (Name: 'shootarrow'; Sig: 'D'),
    (Name: 'shootfireball'; Sig: 'D'),
    (Name: 'shootfireblast'; Sig: 'D'),
    (Name: 'shootnuke'; Sig: 'D'),
    (Name: 'putbomb'; Sig: 'RRR'),
    (Name: 'putexplosion'; Sig: 'RRR'),
    (Name: 'putleaps'; Sig: 'RRR'),
    (Name: 'shootball'; Sig: ''),
    (Name: 'timershow'; Sig: ''),
    (Name: 'toinventory'; Sig: 'S'),
    (Name: 'followplayer'; Sig: ''),
    (Name: 'else'; Sig: ''),
    (Name: 'openurl'; Sig: 'M'),
    (Name: 'seturllevel'; Sig: 'M'),
    (Name: 'stopmidi'; Sig: ''),
    (Name: 'blockagainlocal'; Sig: ''),
    (Name: 'drawunderplayer'; Sig: ''),
    (Name: 'puthorse'; Sig: 'MRR'),
    (Name: 'canbecarried'; Sig: ''),
    (Name: 'cannotbecarried'; Sig: ''),
    (Name: 'noplayerkilling'; Sig: ''),
    (Name: 'canbepushed'; Sig: ''),
    (Name: 'cannotbepushed'; Sig: ''),
    (Name: 'canbepulled'; Sig: ''),
    (Name: 'cannotbepulled'; Sig: ''),
    (Name: 'message'; Sig: 'S'),
    (Name: 'setsword'; Sig: 'MR'),
    (Name: 'setshield'; Sig: 'MR'),
    (Name: 'putnewcomp'; Sig: 'BRRMR'),
    (Name: 'putnpc'; Sig: 'QQRR'),
    (Name: 'destroy'; Sig: ''),
    (Name: 'freezeplayer'; Sig: 'R'),
    (Name: 'sethead'; Sig: 'F'),
    (Name: 'toweapons'; Sig: 'M'),
    (Name: 'showimg'; Sig: 'RMRR'),
    (Name: 'hideimg'; Sig: 'R'),
    (Name: 'hidesword'; Sig: 'R'),
    (Name: 'for'; Sig: ''),
    (Name: 'hitcompu'; Sig: 'RRRR'),
    (Name: 'hitplayer'; Sig: 'RRRR'),
    (Name: 'setbow'; Sig: 'S'),
    (Name: 'updateboard'; Sig: 'RRRR'),
    (Name: 'putobject'; Sig: 'ORR'),
    (Name: 'setarray'; Sig: 'RR'),
    (Name: 'sleep'; Sig: 'R'),
    (Name: 'while'; Sig: ''),
    (Name: 'hideplayer'; Sig: 'R'),
    (Name: 'timereverywhere'; Sig: ''),
    (Name: 'setminimap'; Sig: 'FFRR'),
    (Name: 'setmap'; Sig: 'FFRR'),
    (Name: 'showcharacter'; Sig: ''),
    (Name: 'setplayerprop'; Sig: 'MM'),
    (Name: 'setcharprop'; Sig: 'MM'),
    (Name: 'showfile'; Sig: 'F'),
    (Name: 'setstring'; Sig: 'SS'),
    (Name: 'setbackpal'; Sig: 'F'),
    (Name: 'setletters'; Sig: 'F'),
    (Name: 'setgifpart'; Sig: 'FRRRR'),
    (Name: 'setfocus'; Sig: 'RR'),
    (Name: 'resetfocus'; Sig: ''),
    (Name: 'setbody'; Sig: 'F'),
    (Name: 'carryobject'; Sig: 'L'),
    (Name: 'throwcarry'; Sig: ''),
    (Name: 'showlocal'; Sig: ''),
    (Name: 'hidelocal'; Sig: ''),
    (Name: 'dontblock'; Sig: ''),
    (Name: 'blockagain'; Sig: ''),
    (Name: 'setbacktile'; Sig: 'R'),
    (Name: 'takeplayerhorse'; Sig: ''),
    (Name: 'removebomb'; Sig: 'R'),
    (Name: 'removearrow'; Sig: 'R'),
    (Name: 'removeitem'; Sig: 'R'),
    (Name: 'removeexplo'; Sig: 'R'),
    (Name: 'removehorse'; Sig: 'R'),
    (Name: 'explodebomb'; Sig: 'R'),
    (Name: 'reflectarrow'; Sig: 'R'),
    (Name: 'lay2'; Sig: 'IRR'),
    (Name: 'take2'; Sig: 'R'),
    (Name: 'takehorse'; Sig: 'R'),
    (Name: 'playlooped'; Sig: 'F'),
    (Name: 'stopsound'; Sig: 'F'),
    (Name: 'changeimgpart'; Sig: 'RRRRR'),
    (Name: 'setlevel2'; Sig: 'MRR'),
    (Name: 'hitnpc'; Sig: 'RRRR'),
    (Name: 'canwarp2'; Sig: ''),
    (Name: 'setani'; Sig: 'SS'),
    (Name: 'setcharani'; Sig: 'SS'),
    (Name: 'callnpc'; Sig: 'RS'),
    (Name: 'say2'; Sig: 'S'),
    (Name: 'break'; Sig: ''),
    (Name: 'continue'; Sig: ''),
    (Name: 'callweapon'; Sig: 'RS'),
    (Name: 'spyfire'; Sig: 'RR'),
    (Name: 'function'; Sig: ''),
    (Name: 'return'; Sig: ''),
    (Name: 'changeimgvis'; Sig: 'RR'),
    (Name: 'setimg'; Sig: 'F'),
    (Name: 'setimgpart'; Sig: 'FRRRR'),
    (Name: 'drawovertrees'; Sig: ''),
    (Name: 'putexplosion2'; Sig: 'RRRR'),
    (Name: 'showstats'; Sig: 'R'),
    (Name: 'canwarp'; Sig: ''),
    (Name: 'setshape'; Sig: 'RRR'),
    (Name: 'seteffect'; Sig: 'RRRR'),
    (Name: 'setcoloreffect'; Sig: 'RRRR'),
    (Name: 'setzoomeffect'; Sig: 'R'),
    (Name: 'drawaslight'; Sig: ''),
    (Name: 'changeimgcolors'; Sig: 'RRRRR'),
    (Name: 'changeimgzoom'; Sig: 'RR'),
    (Name: 'setgender'; Sig: 'S'),
    (Name: 'setchargender'; Sig: 'S'),
    (Name: 'join'; Sig: 'S'),
    (Name: 'freezeplayer2'; Sig: ''),
    (Name: 'unfreezeplayer'; Sig: ''),
    (Name: 'enabledefmovement'; Sig: ''),
    (Name: 'disabledefmovement'; Sig: ''),
    (Name: 'setmusicvolume'; Sig: 'RR'),
    (Name: 'openurl2'; Sig: 'MRR'),
    (Name: 'hitobjects'; Sig: 'RRR'),
    (Name: 'tokenize'; Sig: 'S'),
    (Name: 'tokenize2'; Sig: 'SS'),
    (Name: 'triggeraction'; Sig: 'RRSS'),
    (Name: 'move'; Sig: 'RRRR'),
    (Name: 'addtiledef'; Sig: 'SSR'),
    (Name: 'addtiledef2'; Sig: 'SSRR'),
    (Name: 'removetiledefs'; Sig: 'S'),
    (Name: 'replaceani'; Sig: 'MM'),
    (Name: 'attachplayertoobj'; Sig: 'RR'),
    (Name: 'setshape2'; Sig: 'RRR'),
    (Name: 'detachplayer'; Sig: ''),
    (Name: 'enableselectweapons'; Sig: ''),
    (Name: 'disableselectweapons'; Sig: ''),
    (Name: 'setbacktile2'; Sig: 'RRRRR'),
    (Name: 'setz'; Sig: 'RRRRRRRR'),
    (Name: 'updateterrain'; Sig: ''),
    (Name: 'loadmap'; Sig: 'F'),
    (Name: 'show'; Sig: ''),
    (Name: 'hide'; Sig: '')
  );

  GsItemNames: array[0..24] of string = (
    'greenrupee', 'bluerupee', 'redrupee', 'bombs', 'darts', 'heart',
    'glove1', 'bow', 'bomb', 'shield', 'sword', 'fullheart', 'superbomb',
    'battleaxe', 'goldensword', 'mirrorshield', 'glove2', 'lizardshield',
    'lizardsword', 'goldrupee', 'fireball', 'fireblast', 'nukeshot',
    'joltbomb', 'spinattack');
  GsBaddyNames: array[0..9] of string = (
    'graysoldier', 'bluesoldier', 'redsoldier', 'shootingsoldier',
    'swampsoldier', 'frog', 'octopus', 'goldenwarrior', 'lizardon', 'dragon');
  GsColorNames: array[0..19] of string = (
    'white', 'yellow', 'orange', 'pink', 'red', 'darkred', 'lightgreen',
    'green', 'darkgreen', 'lightblue', 'blue', 'darkblue', 'brown',
    'cynober', 'purple', 'darkpurple', 'lightgray', 'gray', 'black',
    'transparent');
  GsCarryNames: array[0..10] of string = (
    'bush', 'sign', 'vase', 'stone', 'blackstone', 'bomb', 'hotbomb',
    'superbomb', 'joltbomb', 'hotjoltbomb', 'none');
  GsDirNames: array[0..3] of string = ('up', 'left', 'down', 'right');

  { Event flags: true only while that event runs. }
  GsEventNames: array[0..25] of string = (
    'created', 'playerenters', 'timeout', 'playertouchsme',
    'playertouchsother', 'playerendsreading', 'playerchats', 'wasshot',
    'wasshooted', 'washit', 'wasthrown', 'waspelt', 'exploded',
    'compusdied', 'compsdead', 'playerdies', 'playerhurt', 'playerhurted',
    'playerlaysitem', 'weaponfired', 'shotbyplayer', 'shotbybaddy',
    'playerleaves', 'main', 'actionserverside', 'playerlogin');

type
  TGsValues = array of Double;

  { An expression node. }
  TGsExprKind = (ekNum, ekVar, ekIndex, ekMember, ekCall, ekUnary, ekBinary,
    ekRange, ekSet, ekArray, ekPostInc, ekPreInc);

  TGsExpr = class
  public
    Kind: TGsExprKind;
    Num: Double;
    Name: string;        { variable, function or member name; operator }
    A, B: TGsExpr;       { operands; ekIndex: A = index; ekMember: A = index }
    Args: array of TGsExpr;
    StrArgs: array of string; { raw text arguments of string functions }
    destructor Destroy; override;
  end;

  TGsNodeKind = (nkCommand, nkExpr, nkJumpIfFalse, nkJump, nkCall, nkEndFunc,
    nkLoopStart, nkLoopTest, nkEnd);

  TGsNode = class
  public
    Kind: TGsNodeKind;
    Op: Integer;           { command opcode }
    Expr: TGsExpr;         { condition or statement }
    Args: array of TGsExpr; { numeric arguments (R, D, C given as numbers) }
    Raw: array of string;  { the raw text of every argument }
    Target: Integer;       { jump target; call: function start }
    Loop: Integer;         { loop counter slot }
    Name: string;          { call: function name }
    Line: Integer;
    destructor Destroy; override;
  end;

  { A compiled script. }
  TGsScript = class
  private
    FFuncs: TStringList;   { name -> start node index (Objects) }
    FOwned: TList;         { every node and expression made for this script }
  public
    Nodes: TList;
    LoopCount: Integer;
    Errors: TStringList;
    Source: string;
    constructor Create;
    destructor Destroy; override;
    function Compile(const Text: string): Boolean;
    function Node(I: Integer): TGsNode;
    function Count: Integer;
    function FunctionStart(const Name: string): Integer;
  end;

  TGsContext = class;

  { The variables of one script owner: plain names and this.* names, each an
    array (a scalar is element 0). }
  TGsVars = class
  private
    FNames: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const Name: string): Integer;
    function Get(const Name: string; Index: Integer): Double;
    procedure SetValue(const Name: string; Index: Integer; V: Double);
    procedure SetArray(const Name: string; const V: TGsValues);
    procedure Resize(const Name: string; N: Integer);
    function Len(const Name: string): Integer;
    function Exists(const Name: string): Boolean;
    procedure Clear;
  end;

  { Arguments of a command as it runs: numbers and expanded text. }
  TGsArgs = record
    Count: Integer;
    Num: array[0..7] of Double;
    Str: array[0..7] of string;
  end;

  { What a script runs against. The NPC unit implements this. }
  TGsHost = class
  public
    Globals: TGsVars;
    Tokens: TStringList;
    constructor Create;
    destructor Destroy; override;
    { A built-in variable (x, playerx, timeout, ...). Index is -1 for no
      [index]. False: not a built-in. }
    function GetVar(Ctx: TGsContext; const Name: string; Index: Integer;
      out V: Double): Boolean; virtual;
    function SetVar(Ctx: TGsContext; const Name: string; Index: Integer;
      V: Double): Boolean; virtual;
    { obj[index].member: npcs, players, compus, bombs, arrows, items, ... }
    function GetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
      const Member: string; out V: Double): Boolean; virtual;
    function SetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
      const Member: string; V: Double): Boolean; virtual;
    { A built-in function. Strs holds text arguments, Nums numbers. }
    function CallFunc(Ctx: TGsContext; const Name: string;
      const Nums: array of Double; const Strs: array of string;
      out V: Double): Boolean; virtual;
    { State flags (visible, carrying, ...) and player flags. }
    function TestFlag(Ctx: TGsContext; const Name: string): Boolean; virtual;
    procedure SetFlag(Ctx: TGsContext; const Name: string; On: Boolean); virtual;
    { The text of a message code other than #v #s #p #t #e, or False. }
    function MessageCode(Ctx: TGsContext; const Code, Param: string;
      out S: string): Boolean; virtual;
    { Runs a command. True ends the script run. }
    function Command(Ctx: TGsContext; Op: Integer; const A: TGsArgs): Boolean; virtual;
    procedure Error(Ctx: TGsContext; const Msg: string); virtual;
  end;

  { One script owner: an NPC or a weapon. }
  TGsContext = class
  private
    FLoops: array of Integer;
    FStack: array of Integer;
    FDepth: Integer;
    function Eval(E: TGsExpr): Double;
    function EvalIndex(E: TGsExpr): Integer;
    procedure Assign(E: TGsExpr; V: Double);
    function ReadLValue(E: TGsExpr): Double;
    procedure AssignArray(E: TGsExpr; Lit: TGsExpr);
    function ExprString(E: TGsExpr): string;
  public
    Host: TGsHost;
    Owner: TObject;
    Script: TGsScript;
    Locals: TGsVars;      { this.* }
    Event: string;        { the event running ('' between runs) }
    Params: TStringList;  { #p(n): the event's parameters }
    ResumeAt: Integer;    { sleep: the node the next timeout starts at, or -1 }
    Running: Boolean;
    Ended: Boolean;       { set by a command that ends the run }
    Steps: Integer;       { nodes run in the last event }
    constructor Create(AHost: TGsHost; AOwner: TObject);
    destructor Destroy; override;
    { Compiles Text (replacing any earlier script). }
    function Load(const Text: string): Boolean;
    { Runs the script with one event flag set. }
    procedure Run(const AEvent: string);
    procedure RunWithParams(const AEvent: string; const AParams: string);
    function IsEvent(const Name: string): Boolean;
    { Expands message codes in raw text and trims it. }
    function Expand(const Raw: string): string;
    function EvalText(const Raw: string): Double;
  end;

function GsCommandIndex(const Name: string): Integer;
function GsNameIndex(const Names: array of string; const S: string): Integer;
function GsFormatNum(V: Double): string;
{ Splits text on top-level commas: at most N parts, the last keeps the rest. }
procedure GsSplitArgs(const S: string; N: Integer; Parts: TStrings);

implementation

uses
  StrUtils;

{ ---- helpers ---- }

function GsNameIndex(const Names: array of string; const S: string): Integer;
var
  I: Integer;
  L: string;
begin
  L := LowerCase(Trim(S));
  for I := 0 to High(Names) do
    if Names[I] = L then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

var
  CmdIndex: TStringList;

function GsCommandIndex(const Name: string): Integer;
var
  I: Integer;
begin
  if CmdIndex = nil then
  begin
    CmdIndex := TStringList.Create;
    CmdIndex.Sorted := True;
    CmdIndex.Duplicates := dupIgnore;
    for I := 0 to GsCommandCount - 1 do
      CmdIndex.AddObject(GsCommands[I].Name, TObject(PtrInt(I)));
  end;
  I := CmdIndex.IndexOf(LowerCase(Name));
  if I < 0 then Result := -1 else Result := PtrInt(CmdIndex.Objects[I]);
end;

function GsFormatNum(V: Double): string;
var
  FS: TFormatSettings;
begin
  if (Abs(V) < 1E15) and (Frac(V) = 0) then
    Result := IntToStr(Trunc(V))
  else
  begin
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    Result := FloatToStrF(V, ffGeneral, 15, 0, FS);
  end;
end;

function ParseNumber(const S: string; out V: Double): Boolean;
var
  FS: TFormatSettings;
  T: string;
begin
  T := Trim(S);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := (T <> '') and TryStrToFloat(T, V, FS);
end;

{ The end of a #x(...) code starting at I (the '#'), or 0 when there is
  no parenthesis. }
function CodeParenEnd(const S: string; I: Integer): Integer;
var
  J, D: Integer;
begin
  Result := 0;
  J := I + 1;
  while (J <= Length(S)) and (S[J] in ['a'..'z', 'A'..'Z', '0'..'9']) and (J - I <= 2) do
    Inc(J);
  if (J > Length(S)) or (S[J] <> '(') then Exit;
  D := 0;
  while J <= Length(S) do
  begin
    if S[J] = '(' then Inc(D)
    else if S[J] = ')' then
    begin
      Dec(D);
      if D = 0 then
      begin
        Result := J;
        Exit;
      end;
    end;
    Inc(J);
  end;
end;

procedure GsSplitArgs(const S: string; N: Integer; Parts: TStrings);
var
  I, Start, D, E: Integer;
begin
  Parts.Clear;
  if N <= 0 then Exit;
  Start := 1;
  D := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '#') then
    begin
      E := CodeParenEnd(S, I);
      if E > 0 then
      begin
        I := E + 1;
        Continue;
      end;
    end;
    case S[I] of
      '(', '[', '{': Inc(D);
      ')', ']', '}': if D > 0 then Dec(D);
      ',':
        if (D = 0) and (Parts.Count < N - 1) then
        begin
          Parts.Add(Copy(S, Start, I - Start));
          Start := I + 1;
        end;
    end;
    Inc(I);
  end;
  Parts.Add(Copy(S, Start, MaxInt));
end;

{ ---- expressions ---- }

{ Nodes and expressions are owned by the script that compiled them (its
  FOwned list), so a compile error part way through a statement frees the
  half-built pieces too. Neither frees its children. }

var
  GOwner: TList; { FOwned of the script being compiled }

procedure Own(O: TObject);
begin
  if GOwner <> nil then GOwner.Add(O);
end;

destructor TGsExpr.Destroy;
begin
  inherited;
end;

destructor TGsNode.Destroy;
begin
  inherited;
end;

{ Functions whose arguments are text, not numbers. }
function IsStringFunc(const Name: string): Boolean;
begin
  Result := (Name = 'strtofloat') or (Name = 'playersays') or
    (Name = 'playersays2') or (Name = 'strequals') or
    (Name = 'strcontains') or (Name = 'hasweapon') or
    (Name = 'startswith') or (Name = 'indexof') or (Name = 'strlen') or
    (Name = 'onmapx') or (Name = 'onmapy');
end;

type
  TTokKind = (tkEnd, tkNum, tkIdent, tkOp);

  { Tokenizer and recursive-descent compiler over the whole script text. }
  TGsCompiler = class
  private
    S: string;
    P: Integer;
    Line: Integer;
    TokKind: TTokKind;
    Tok: string;
    TokNum: Double;
    TokStart: Integer;
    Script: TGsScript;
    LoopStack: array of record
      Slot, ContinueAt: Integer;
      Breaks, Continues: array of Integer;
    end;
    FuncDepth: Integer;
    { the names after "function" anywhere in the source, lower case }
    Declared: string;
    procedure SkipSpace;
    procedure Next;
    procedure Fail(const Msg: string);
    function Peek(const T: string): Boolean;
    procedure Expect(const T: string);
    function Emit(Kind: TGsNodeKind): TGsNode;
    function Here: Integer;
    { expressions }
    function ParseExpr: TGsExpr;
    function ParseOr: TGsExpr;
    function ParseAnd: TGsExpr;
    function ParseCompare: TGsExpr;
    function ParseAdd: TGsExpr;
    function ParseMul: TGsExpr;
    function ParsePow: TGsExpr;
    function ParseUnary: TGsExpr;
    function ParsePostfix: TGsExpr;
    function ParsePrimary: TGsExpr;
    function ParseList(Close: Char; Kind: TGsExprKind): TGsExpr;
    function RawUntil(Stop: Char): string;
    function RawArgsInParens: string;
    { statements }
    procedure Statement;
    procedure Block;
    procedure ExprStatement;
    procedure CommandStatement(Op: Integer);
  public
    function Compile(AScript: TGsScript; const Text: string): Boolean;
  end;

  EGsCompile = class(Exception);

procedure TGsCompiler.Fail(const Msg: string);
begin
  raise EGsCompile.CreateFmt('line %d: %s', [Line, Msg]);
end;

procedure TGsCompiler.SkipSpace;
begin
  while P <= Length(S) do
  begin
    if S[P] = #10 then
    begin
      Inc(Line);
      Inc(P);
    end
    else if S[P] in [#1..' '] then
      Inc(P)
    else if (S[P] = '/') and (P < Length(S)) and (S[P + 1] = '/') then
    begin
      while (P <= Length(S)) and (S[P] <> #10) do Inc(P);
    end
    else if (S[P] = '/') and (P < Length(S)) and (S[P + 1] = '*') then
    begin
      Inc(P, 2);
      while (P < Length(S)) and not ((S[P] = '*') and (S[P + 1] = '/')) do
      begin
        if S[P] = #10 then Inc(Line);
        Inc(P);
      end;
      Inc(P, 2);
    end
    else
      Break;
  end;
end;

procedure TGsCompiler.Next;
const
  Ops2: array[0..11] of string = ('==', '!=', '<=', '>=', '&&', '||', '+=',
    '-=', '*=', '/=', '++', '--');
var
  I: Integer;
  T: string;
  FS: TFormatSettings;
begin
  SkipSpace;
  TokStart := P;
  if P > Length(S) then
  begin
    TokKind := tkEnd;
    Tok := '';
    Exit;
  end;
  if (S[P] = '0') and (P < Length(S)) and (S[P + 1] in ['x', 'X']) then
  begin
    { a hexadecimal number, e.g. showstats 0x400 }
    I := P;
    Inc(P, 2);
    TokNum := 0;
    while (P <= Length(S)) and (S[P] in ['0'..'9', 'a'..'f', 'A'..'F']) do
    begin
      TokNum := TokNum * 16 + StrToInt('$' + S[P]);
      Inc(P);
    end;
    TokKind := tkNum;
    Tok := Copy(S, I, P - I);
    Exit;
  end;
  if (S[P] in ['0'..'9']) or ((S[P] = '.') and (P < Length(S)) and (S[P + 1] in ['0'..'9'])) then
  begin
    I := P;
    while (P <= Length(S)) and (S[P] in ['0'..'9', '.']) do Inc(P);
    T := Copy(S, I, P - I);
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    if not TryStrToFloat(T, TokNum, FS) then TokNum := 0;
    TokKind := tkNum;
    Tok := T;
    Exit;
  end;
  if S[P] in ['a'..'z', 'A'..'Z', '_'] then
  begin
    I := P;
    while (P <= Length(S)) and (S[P] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(P);
    { this.name and similar dotted names are one identifier }
    while (P < Length(S)) and (S[P] = '.') and (S[P + 1] in ['a'..'z', 'A'..'Z', '_']) do
    begin
      Inc(P);
      while (P <= Length(S)) and (S[P] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(P);
    end;
    TokKind := tkIdent;
    Tok := LowerCase(Copy(S, I, P - I));
    Exit;
  end;
  TokKind := tkOp;
  for I := 0 to High(Ops2) do
    if Copy(S, P, 2) = Ops2[I] then
    begin
      Tok := Ops2[I];
      Inc(P, 2);
      Exit;
    end;
  Tok := S[P];
  Inc(P);
end;

function TGsCompiler.Peek(const T: string): Boolean;
begin
  Result := ((TokKind = tkOp) or (TokKind = tkIdent)) and (Tok = T);
end;

procedure TGsCompiler.Expect(const T: string);
begin
  if not Peek(T) then Fail('"' + T + '" expected, found "' + Tok + '"');
  Next;
end;

function TGsCompiler.Emit(Kind: TGsNodeKind): TGsNode;
begin
  Result := TGsNode.Create;
  Own(Result);
  Result.Kind := Kind;
  Result.Line := Line;
  Result.Target := -1;
  Script.Nodes.Add(Result);
end;

function TGsCompiler.Here: Integer;
begin
  Result := Script.Nodes.Count;
end;

function MakeExpr(Kind: TGsExprKind): TGsExpr;
begin
  Result := TGsExpr.Create;
  Own(Result);
  Result.Kind := Kind;
end;

function MakeBin(const Op: string; L, R: TGsExpr): TGsExpr;
begin
  Result := MakeExpr(ekBinary);
  Result.Name := Op;
  Result.A := L;
  Result.B := R;
end;

function TGsCompiler.ParseExpr: TGsExpr;
var
  R: TGsExpr;
  Op: string;
begin
  Result := ParseOr;
  { assignment inside an expression statement }
  if (TokKind = tkOp) and ((Tok = '=') or (Tok = '+=') or (Tok = '-=') or
    (Tok = '*=') or (Tok = '/=')) then
  begin
    Op := Tok;
    Next;
    if (Op = '=') and Peek('{') then
    begin
      Next;
      R := ParseList('}', ekArray);
    end
    else
      R := ParseExpr;
    Result := MakeBin(Op, Result, R);
  end;
end;

function TGsCompiler.ParseOr: TGsExpr;
begin
  Result := ParseAnd;
  while Peek('||') do
  begin
    Next;
    Result := MakeBin('||', Result, ParseAnd);
  end;
end;

function TGsCompiler.ParseAnd: TGsExpr;
begin
  Result := ParseCompare;
  while Peek('&&') do
  begin
    Next;
    Result := MakeBin('&&', Result, ParseCompare);
  end;
end;

function TGsCompiler.ParseList(Close: Char; Kind: TGsExprKind): TGsExpr;
var
  N: Integer;
begin
  Result := MakeExpr(Kind);
  N := 0;
  if not Peek(Close) then
    repeat
      SetLength(Result.Args, N + 1);
      Result.Args[N] := ParseOr;
      Inc(N);
      if Peek(',') then Next else Break;
    until False;
  Expect(Close);
end;

function TGsCompiler.ParseCompare: TGsExpr;
var
  Op: string;
  R: TGsExpr;
begin
  Result := ParseAdd;
  while (TokKind = tkOp) and ((Tok = '==') or (Tok = '!=') or (Tok = '<') or
    (Tok = '>') or (Tok = '<=') or (Tok = '>=')) or Peek('in') do
  begin
    Op := Tok;
    Next;
    if Op = 'in' then
    begin
      if Peek('|') then
      begin
        Next;
        Result := MakeBin('in', Result, ParseList('|', ekRange));
      end
      else if Peek('{') then
      begin
        Next;
        Result := MakeBin('in', Result, ParseList('}', ekSet));
      end
      else if Peek('<') then
      begin
        { <a,b>: a range written with angle brackets (old scripts) }
        Next;
        R := MakeExpr(ekRange);
        SetLength(R.Args, 2);
        R.Args[0] := ParseAdd;
        Expect(',');
        R.Args[1] := ParseAdd;
        Expect('>');
        Result := MakeBin('in', Result, R);
      end
      else
        Fail('range or set expected after in');
    end
    else
      Result := MakeBin(Op, Result, ParseAdd);
  end;
end;

function TGsCompiler.ParseAdd: TGsExpr;
var
  Op: string;
begin
  Result := ParseMul;
  while Peek('+') or Peek('-') do
  begin
    Op := Tok;
    Next;
    Result := MakeBin(Op, Result, ParseMul);
  end;
end;

function TGsCompiler.ParseMul: TGsExpr;
var
  Op: string;
begin
  Result := ParsePow;
  while Peek('*') or Peek('/') or Peek('%') do
  begin
    Op := Tok;
    Next;
    Result := MakeBin(Op, Result, ParsePow);
  end;
end;

function TGsCompiler.ParsePow: TGsExpr;
begin
  Result := ParseUnary;
  if Peek('^') then
  begin
    Next;
    Result := MakeBin('^', Result, ParsePow);
  end;
end;

function TGsCompiler.ParseUnary: TGsExpr;
begin
  if Peek('!') then
  begin
    Next;
    Result := MakeExpr(ekUnary);
    Result.Name := '!';
    Result.A := ParseUnary;
  end
  else if Peek('-') then
  begin
    Next;
    Result := MakeExpr(ekUnary);
    Result.Name := '-';
    Result.A := ParseUnary;
  end
  else if Peek('+') then
  begin
    Next;
    Result := ParseUnary;
  end
  else if Peek('++') or Peek('--') then
  begin
    Result := MakeExpr(ekPreInc);
    Result.Name := Tok;
    Next;
    Result.A := ParsePostfix;
  end
  else
    Result := ParsePostfix;
end;

function TGsCompiler.ParsePostfix: TGsExpr;
var
  E: TGsExpr;
begin
  Result := ParsePrimary;
  if Peek('++') or Peek('--') then
  begin
    E := MakeExpr(ekPostInc);
    E.Name := Tok;
    E.A := Result;
    Result := E;
    Next;
  end;
end;

{ Raw text from P up to the matching ')' of an already-read '(' }
function TGsCompiler.RawArgsInParens: string;
var
  I, D, E: Integer;
begin
  { the token after '(' was already read: restart from its start }
  P := TokStart;
  I := P;
  D := 1;
  while P <= Length(S) do
  begin
    if S[P] = '#' then
    begin
      E := CodeParenEnd(S, P);
      if E > 0 then
      begin
        P := E + 1;
        Continue;
      end;
    end;
    if S[P] = '(' then Inc(D)
    else if S[P] = ')' then
    begin
      Dec(D);
      if D = 0 then Break;
    end
    else if S[P] = #10 then Inc(Line);
    Inc(P);
  end;
  Result := Copy(S, I, P - I);
  Inc(P); { the ')' }
  Next;
end;

function TGsCompiler.ParsePrimary: TGsExpr;
var
  Name, Raw: string;
  Parts: TStringList;
  I, N: Integer;
begin
  Result := nil;
  case TokKind of
    tkNum:
      begin
        Result := MakeExpr(ekNum);
        Result.Num := TokNum;
        Next;
      end;
    tkIdent:
      begin
        Name := Tok;
        Next;
        if Peek('(') then
        begin
          Result := MakeExpr(ekCall);
          Result.Name := Name;
          Next;
          if IsStringFunc(Name) then
          begin
            Raw := RawArgsInParens;
            Parts := TStringList.Create;
            try
              GsSplitArgs(Raw, 8, Parts);
              SetLength(Result.StrArgs, Parts.Count);
              for I := 0 to Parts.Count - 1 do Result.StrArgs[I] := Parts[I];
            finally
              Parts.Free;
            end;
          end
          else
          begin
            N := 0;
            if not Peek(')') then
              repeat
                SetLength(Result.Args, N + 1);
                Result.Args[N] := ParseOr;
                Inc(N);
                if Peek(',') then Next else Break;
              until False;
            Expect(')');
          end;
        end
        else
        begin
          Result := MakeExpr(ekVar);
          Result.Name := Name;
          if Peek('[') then
          begin
            Next;
            Result.Kind := ekIndex;
            Result.A := ParseOr;
            Expect(']');
            { obj[i].member: the tokenizer reads ".member" as an operator
              and an identifier }
            if Peek('.') then
            begin
              Next;
              if TokKind <> tkIdent then Fail('member name expected');
              Result.Kind := ekMember;
              Result.B := MakeExpr(ekVar);
              Result.B.Name := Tok;
              Next;
              if Peek('[') then
              begin
                { npcs[i].save[n] }
                Next;
                Result.B.Kind := ekIndex;
                Result.B.A := ParseOr;
                Expect(']');
              end;
            end;
          end;
        end;
      end;
    tkOp:
      if Tok = '(' then
      begin
        Next;
        Result := ParseExpr;
        Expect(')');
      end
      else if Tok = '{' then
      begin
        Next;
        Result := ParseList('}', ekArray);
      end
      else if Tok = '#' then
      begin
        { a message code used as a number, e.g. #v(...) or #p(0): kept as
          text and read as a number at run time }
        Result := MakeExpr(ekCall);
        Result.Name := 'strtofloat';
        I := TokStart;
        N := CodeParenEnd(S, I);
        if N = 0 then
        begin
          N := I + 1;
          while (N <= Length(S)) and (S[N] in ['a'..'z', 'A'..'Z']) and (N - I <= 1) do Inc(N);
          Dec(N);
        end;
        SetLength(Result.StrArgs, 1);
        Result.StrArgs[0] := Copy(S, I, N - I + 1);
        P := N + 1;
        Next;
      end
      else
        Fail('unexpected "' + Tok + '"');
  else
    Fail('unexpected end of script');
  end;
end;

{ Raw command text from P up to the next ';' outside a #x(...) code. }
function TGsCompiler.RawUntil(Stop: Char): string;
var
  I, E: Integer;
begin
  P := TokStart;
  I := P;
  while (P <= Length(S)) and (S[P] <> Stop) do
  begin
    if S[P] = '#' then
    begin
      E := CodeParenEnd(S, P);
      if E > 0 then
      begin
        P := E + 1;
        Continue;
      end;
    end;
    if S[P] = #10 then Inc(Line);
    Inc(P);
  end;
  Result := Copy(S, I, P - I);
  if P <= Length(S) then Inc(P);
  Next;
end;

procedure TGsCompiler.CommandStatement(Op: Integer);
var
  N: TGsNode;
  Sig, Raw: string;
  Parts: TStringList;
  I: Integer;
  C: TGsCompiler;
begin
  Sig := GsCommands[Op - GsFirstOp].Sig;
  N := Emit(nkCommand);
  N.Op := Op;
  if Peek(';') then
    Raw := ''
  else
    Raw := RawUntil(';');
  if Peek(';') and (Raw = '') then Next;
  Parts := TStringList.Create;
  try
    GsSplitArgs(Raw, Length(Sig), Parts);
    SetLength(N.Raw, Length(Sig));
    SetLength(N.Args, Length(Sig));
    for I := 0 to Length(Sig) - 1 do
    begin
      if I < Parts.Count then N.Raw[I] := Trim(Parts[I]) else N.Raw[I] := '';
      { numbers, and names that may be given as numbers: compiled now }
      if (Sig[I + 1] in ['R', 'D', 'C', 'I', 'B', 'L']) and (N.Raw[I] <> '') then
      begin
        if (Sig[I + 1] <> 'R') and (N.Raw[I][1] in ['a'..'z', 'A'..'Z']) and
          ((Sig[I + 1] = 'I') and (GsNameIndex(GsItemNames, N.Raw[I]) >= 0) or
           (Sig[I + 1] = 'B') and (GsNameIndex(GsBaddyNames, N.Raw[I]) >= 0) or
           (Sig[I + 1] = 'C') and (GsNameIndex(GsColorNames, N.Raw[I]) >= 0) or
           (Sig[I + 1] = 'D') and (GsNameIndex(GsDirNames, N.Raw[I]) >= 0) or
           (Sig[I + 1] = 'L') and (GsNameIndex(GsCarryNames, N.Raw[I]) >= 0)) then
          Continue;
        C := TGsCompiler.Create;
        try
          C.S := N.Raw[I];
          C.P := 1;
          C.Line := Line;
          C.Script := Script;
          C.Next;
          try
            N.Args[I] := C.ParseOr;
            if C.TokKind <> tkEnd then
            begin
              N.Args[I] := nil;
              Script.Errors.Add(Format('line %d: %s: bad number "%s"',
                [Line, GsCommands[Op - GsFirstOp].Name, N.Raw[I]]));
            end;
          except
            on E: EGsCompile do
            begin
              N.Args[I] := nil;
              Script.Errors.Add(Format('line %d: %s: bad number "%s"',
                [Line, GsCommands[Op - GsFirstOp].Name, N.Raw[I]]));
            end;
          end;
        finally
          C.Free;
        end;
      end;
    end;
  finally
    Parts.Free;
  end;
end;

procedure TGsCompiler.ExprStatement;
var
  N: TGsNode;
begin
  N := Emit(nkExpr);
  N.Expr := ParseExpr;
  if Peek(';') then Next
  else if not Peek('}') and (TokKind <> tkEnd) then
    Fail('";" expected, found "' + Tok + '"');
end;

procedure TGsCompiler.Block;
begin
  { '{' already read }
  while not Peek('}') do
  begin
    if TokKind = tkEnd then Fail('"}" expected');
    Statement;
  end;
  Next;
end;

procedure TGsCompiler.Statement;
var
  N, J: TGsNode;
  Op, Start, I, Slot, TestAt, Lv: Integer;
  StepStart, StepEnd: Integer;
  StepNodes: TList;
  Name: string;
begin
  if Peek(';') then
  begin
    Next;
    Exit;
  end;
  if Peek('{') then
  begin
    Next;
    Block;
    Exit;
  end;
  if TokKind = tkIdent then
  begin
    if Tok = 'if' then
    begin
      Next;
      Expect('(');
      N := Emit(nkJumpIfFalse);
      N.Expr := ParseExpr;
      Expect(')');
      Statement;
      if Peek('else') then
      begin
        Next;
        J := Emit(nkJump);
        N.Target := Here;
        Statement;
        J.Target := Here;
      end
      else
        N.Target := Here;
      Exit;
    end;
    if (Tok = 'while') or (Tok = 'for') then
    begin
      Slot := Script.LoopCount;
      Inc(Script.LoopCount);
      Lv := Length(LoopStack);
      SetLength(LoopStack, Lv + 1);
      LoopStack[Lv].Slot := Slot;
      if Tok = 'while' then
      begin
        Next;
        Expect('(');
        N := Emit(nkLoopStart);
        N.Loop := Slot;
        TestAt := Here;
        N := Emit(nkLoopTest);
        N.Loop := Slot;
        N.Expr := ParseExpr;
        Expect(')');
        LoopStack[Lv].ContinueAt := TestAt;
        Statement;
        J := Emit(nkJump);
        J.Target := TestAt;
        N.Target := Here;
        for I := 0 to High(LoopStack[Lv].Continues) do
          TGsNode(Script.Nodes[LoopStack[Lv].Continues[I]]).Target := TestAt;
      end
      else
      begin
        Next;
        Expect('(');
        if not Peek(';') then
        begin
          J := Emit(nkExpr);
          J.Expr := ParseExpr;
        end;
        Expect(';');
        N := Emit(nkLoopStart);
        N.Loop := Slot;
        TestAt := Here;
        N := Emit(nkLoopTest);
        N.Loop := Slot;
        if Peek(';') then
        begin
          N.Expr := MakeExpr(ekNum);
          N.Expr.Num := 1;
        end
        else
          N.Expr := ParseExpr;
        Expect(';');
        { the step is compiled now and moved after the body }
        StepStart := Here;
        if not Peek(')') then
        begin
          J := Emit(nkExpr);
          J.Expr := ParseExpr;
        end;
        Expect(')');
        StepEnd := Here;
        StepNodes := TList.Create;
        try
          for I := StepStart to StepEnd - 1 do StepNodes.Add(Script.Nodes[I]);
          for I := StepEnd - 1 downto StepStart do Script.Nodes.Delete(I);
          Statement;
          LoopStack[Lv].ContinueAt := Here;
          for I := 0 to StepNodes.Count - 1 do Script.Nodes.Add(StepNodes[I]);
        finally
          StepNodes.Free;
        end;
        J := Emit(nkJump);
        J.Target := TestAt;
        N.Target := Here;
        for I := 0 to High(LoopStack[Lv].Continues) do
          TGsNode(Script.Nodes[LoopStack[Lv].Continues[I]]).Target :=
            LoopStack[Lv].ContinueAt;
      end;
      for I := 0 to High(LoopStack[Lv].Breaks) do
        TGsNode(Script.Nodes[LoopStack[Lv].Breaks[I]]).Target := Here;
      SetLength(LoopStack, Lv);
      Exit;
    end;
    if (Tok = 'break') or (Tok = 'continue') then
    begin
      Name := Tok;
      Next;
      if Peek(';') then Next;
      Lv := High(LoopStack);
      if Lv < 0 then
      begin
        { outside a loop it ends the script }
        Emit(nkEnd);
        Exit;
      end;
      J := Emit(nkJump);
      if Name = 'break' then
      begin
        SetLength(LoopStack[Lv].Breaks, Length(LoopStack[Lv].Breaks) + 1);
        LoopStack[Lv].Breaks[High(LoopStack[Lv].Breaks)] := Here - 1;
      end
      else
      begin
        SetLength(LoopStack[Lv].Continues, Length(LoopStack[Lv].Continues) + 1);
        LoopStack[Lv].Continues[High(LoopStack[Lv].Continues)] := Here - 1;
      end;
      Exit;
    end;
    if Tok = 'return' then
    begin
      Next;
      if Peek(';') then Next;
      Emit(nkEndFunc);
      Exit;
    end;
    if Tok = 'else' then
      Fail('else without if');
    if Tok = 'function' then
    begin
      Next;
      if TokKind <> tkIdent then Fail('function name expected');
      Name := Tok;
      Next;
      Expect('(');
      Expect(')');
      J := Emit(nkJump);
      Start := Here;
      Script.FFuncs.AddObject(Name, TObject(PtrInt(Start)));
      Inc(FuncDepth);
      Expect('{');
      Block;
      Dec(FuncDepth);
      Emit(nkEndFunc);
      J.Target := Here;
      Exit;
    end;
    { name(); is a call of a script function, unless it is a command; a
      function the script declares wins over a command of the same name
      (lamps_wood.gani's setimg(), which the real 2.22 runs as its own
      function: the lab saw the flame cut from its sheet) }
    Op := GsCommandIndex(Tok);
    if (Op >= 0) and (Pos(',' + LowerCase(Tok) + ',', Declared) > 0) then
    begin
      I := P;
      while (I <= Length(S)) and (S[I] in [' ', #9]) do Inc(I);
      if (I < Length(S)) and (S[I] = '(') then Op := -1;
    end;
    if Op >= 0 then
    begin
      Op := Op + GsFirstOp;
      if (Op = GsOpElse) or (Op = GsOpFunction) or (Op = GsOpReturn) then
        Fail('misplaced ' + Tok);
      { a command name followed by an assignment operator is a variable
        (e.g. "hide = 1" is not the hide command); 2.05 matches commands
        as whole words }
      I := P;
      while (I <= Length(S)) and (S[I] in [' ', #9]) do Inc(I);
      if (I <= Length(S)) and (S[I] = '=') and ((I = Length(S)) or (S[I + 1] <> '=')) then
      begin
        ExprStatement;
        Exit;
      end;
      Next;
      CommandStatement(Op);
      Exit;
    end;
    I := P;
    while (I <= Length(S)) and (S[I] in [' ', #9]) do Inc(I);
    if (I < Length(S)) and (S[I] = '(') and (S[I + 1] = ')') then
    begin
      Name := Tok;
      Next;
      Expect('(');
      Expect(')');
      if Peek(';') then Next;
      N := Emit(nkCall);
      N.Name := Name;
      Exit;
    end;
  end;
  ExprStatement;
end;

{ ",name,name," for every "function name(" in Text }
function DeclaredFunctions(const Text: string): string;
var
  L, I, J: Integer;
  T: string;
begin
  Result := ',';
  T := LowerCase(Text);
  L := Length(T);
  I := Pos('function', T);
  while I > 0 do
  begin
    J := I + 8;
    if ((I = 1) or not (T[I - 1] in ['a'..'z', '0'..'9', '_', '.'])) and (J <= L) and
      (T[J] in [' ', #9]) then
    begin
      while (J <= L) and (T[J] in [' ', #9]) do Inc(J);
      I := J;
      while (J <= L) and (T[J] in ['a'..'z', '0'..'9', '_']) do Inc(J);
      if J > I then Result := Result + Copy(T, I, J - I) + ',';
    end;
    I := PosEx('function', T, J);
  end;
end;

function TGsCompiler.Compile(AScript: TGsScript; const Text: string): Boolean;
var
  I: Integer;
  N: TGsNode;
begin
  Script := AScript;
  { a script from the wire marks its line ends with the section sign
    (0xA7); a level file's has real line ends }
  if Pos(#10, Text) = 0 then
    S := StringReplace(Text, #$A7, #10, [rfReplaceAll])
  else
    S := Text;
  P := 1;
  Line := 1;
  FuncDepth := 0;
  Declared := DeclaredFunctions(S);
  try
    Next;
    while TokKind <> tkEnd do
    begin
      if Peek('}') then
      begin
        { a stray closing brace: skipped, as old scripts carry them }
        Next;
        Continue;
      end;
      Statement;
    end;
  except
    on E: EGsCompile do
      Script.Errors.Add(E.Message);
  end;
  Emit(nkEnd);
  { resolve calls }
  for I := 0 to Script.Nodes.Count - 1 do
  begin
    N := TGsNode(Script.Nodes[I]);
    if N.Kind = nkCall then
    begin
      N.Target := Script.FunctionStart(N.Name);
      if N.Target < 0 then
        Script.Errors.Add(Format('line %d: unknown function %s', [N.Line, N.Name]));
    end;
  end;
  Result := Script.Errors.Count = 0;
end;

{ ---- TGsScript ---- }

constructor TGsScript.Create;
begin
  Nodes := TList.Create;
  Errors := TStringList.Create;
  FFuncs := TStringList.Create;
  FOwned := TList.Create;
end;

destructor TGsScript.Destroy;
var
  I: Integer;
begin
  for I := 0 to FOwned.Count - 1 do TObject(FOwned[I]).Free;
  FOwned.Free;
  Nodes.Free;
  Errors.Free;
  FFuncs.Free;
  inherited;
end;

function TGsScript.Compile(const Text: string): Boolean;
var
  C: TGsCompiler;
  Saved: TList;
begin
  Source := Text;
  Saved := GOwner;
  GOwner := FOwned;
  C := TGsCompiler.Create;
  try
    Result := C.Compile(Self, Text);
  finally
    C.Free;
    GOwner := Saved;
  end;
end;

function TGsScript.Node(I: Integer): TGsNode;
begin
  Result := TGsNode(Nodes[I]);
end;

function TGsScript.Count: Integer;
begin
  Result := Nodes.Count;
end;

function TGsScript.FunctionStart(const Name: string): Integer;
var
  I: Integer;
begin
  I := FFuncs.IndexOf(LowerCase(Name));
  if I < 0 then Result := -1 else Result := PtrInt(FFuncs.Objects[I]);
end;

{ ---- TGsVars ---- }

type
  TGsVarBox = class
    V: TGsValues;
  end;

constructor TGsVars.Create;
begin
  FNames := TStringList.Create;
  FNames.Sorted := True;
end;

destructor TGsVars.Destroy;
begin
  Clear;
  FNames.Free;
  inherited;
end;

procedure TGsVars.Clear;
var
  I: Integer;
begin
  { Historical TStringList has no OwnsObjects property. This list owns
    variable boxes; the command/function index lists elsewhere do not. }
  if FNames = nil then Exit;
  for I := 0 to FNames.Count - 1 do FNames.Objects[I].Free;
  FNames.Clear;
end;

function TGsVars.Find(const Name: string): Integer;
begin
  Result := FNames.IndexOf(Name);
end;

function TGsVars.Exists(const Name: string): Boolean;
begin
  Result := Find(Name) >= 0;
end;

function TGsVars.Get(const Name: string; Index: Integer): Double;
var
  I: Integer;
  B: TGsVarBox;
begin
  Result := 0;
  I := Find(Name);
  if I < 0 then Exit;
  B := TGsVarBox(FNames.Objects[I]);
  if Index < 0 then Index := 0;
  if Index <= High(B.V) then Result := B.V[Index];
end;

procedure TGsVars.SetValue(const Name: string; Index: Integer; V: Double);
var
  I: Integer;
  B: TGsVarBox;
begin
  I := Find(Name);
  if I < 0 then
  begin
    B := TGsVarBox.Create;
    FNames.AddObject(Name, B);
  end
  else
    B := TGsVarBox(FNames.Objects[I]);
  if Index < 0 then Index := 0;
  if Index > High(B.V) then
  begin
    { writing past the end of an array is ignored, except element 0 of a
      new variable }
    if (Length(B.V) = 0) and (Index = 0) then SetLength(B.V, 1) else Exit;
  end;
  B.V[Index] := V;
end;

procedure TGsVars.SetArray(const Name: string; const V: TGsValues);
var
  I: Integer;
  B: TGsVarBox;
begin
  I := Find(Name);
  if I < 0 then
  begin
    B := TGsVarBox.Create;
    FNames.AddObject(Name, B);
  end
  else
    B := TGsVarBox(FNames.Objects[I]);
  B.V := Copy(V);
end;

procedure TGsVars.Resize(const Name: string; N: Integer);
var
  I, Old, K: Integer;
  B: TGsVarBox;
begin
  if N < 0 then N := 0;
  if N > 100000 then N := 100000;
  I := Find(Name);
  if I < 0 then
  begin
    B := TGsVarBox.Create;
    FNames.AddObject(Name, B);
  end
  else
    B := TGsVarBox(FNames.Objects[I]);
  Old := Length(B.V);
  SetLength(B.V, N);
  for K := Old to N - 1 do B.V[K] := 0;
end;

function TGsVars.Len(const Name: string): Integer;
var
  I: Integer;
begin
  I := Find(Name);
  if I < 0 then Result := 0 else Result := Length(TGsVarBox(FNames.Objects[I]).V);
end;

{ ---- TGsHost (defaults: nothing built in) ---- }

constructor TGsHost.Create;
begin
  Globals := TGsVars.Create;
  Tokens := TStringList.Create;
end;

destructor TGsHost.Destroy;
begin
  Globals.Free;
  Tokens.Free;
  inherited;
end;

function TGsHost.GetVar(Ctx: TGsContext; const Name: string; Index: Integer;
  out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;

function TGsHost.SetVar(Ctx: TGsContext; const Name: string; Index: Integer;
  V: Double): Boolean;
begin
  Result := False;
end;

function TGsHost.GetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
  const Member: string; out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;

function TGsHost.SetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
  const Member: string; V: Double): Boolean;
begin
  Result := False;
end;

function TGsHost.CallFunc(Ctx: TGsContext; const Name: string;
  const Nums: array of Double; const Strs: array of string; out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;

function TGsHost.TestFlag(Ctx: TGsContext; const Name: string): Boolean;
begin
  Result := False;
end;

procedure TGsHost.SetFlag(Ctx: TGsContext; const Name: string; On: Boolean);
begin
end;

function TGsHost.MessageCode(Ctx: TGsContext; const Code, Param: string;
  out S: string): Boolean;
begin
  S := '';
  Result := False;
end;

function TGsHost.Command(Ctx: TGsContext; Op: Integer; const A: TGsArgs): Boolean;
begin
  Result := False;
end;

procedure TGsHost.Error(Ctx: TGsContext; const Msg: string);
begin
end;

{ ---- TGsContext ---- }

{ Splits S on any of the delimiter characters; quotes group a token. }
procedure Tokenize(const S, Delims: string; List: TStrings);
var
  I: Integer;
  Cur: string;
  InQ, Have: Boolean;
begin
  Cur := '';
  InQ := False;
  Have := False;
  for I := 1 to Length(S) do
  begin
    if S[I] = '"' then
    begin
      InQ := not InQ;
      Have := True;
    end
    else if not InQ and (Pos(S[I], Delims) > 0) then
    begin
      if Have or (Cur <> '') then List.Add(Cur);
      Cur := '';
      Have := False;
    end
    else
      Cur := Cur + S[I];
  end;
  if Have or (Cur <> '') then List.Add(Cur);
end;

constructor TGsContext.Create(AHost: TGsHost; AOwner: TObject);
begin
  Host := AHost;
  Owner := AOwner;
  Locals := TGsVars.Create;
  Params := TStringList.Create;
  ResumeAt := -1;
end;

destructor TGsContext.Destroy;
begin
  Script.Free;
  Locals.Free;
  Params.Free;
  inherited;
end;

function TGsContext.Load(const Text: string): Boolean;
begin
  FreeAndNil(Script);
  Script := TGsScript.Create;
  Result := Script.Compile(Text);
  SetLength(FLoops, Script.LoopCount);
  ResumeAt := -1;
end;

function TGsContext.IsEvent(const Name: string): Boolean;
begin
  Result := (Event <> '') and (Name = Event);
end;

function IsEventName(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(GsEventNames) do
    if GsEventNames[I] = Name then
    begin
      Result := True;
      Exit;
    end;
  Result := Copy(Name, 1, 6) = 'action';
end;

{ Splits "this.name" into the local store; other names are global. }
function IsLocal(const Name: string; out Bare: string): Boolean;
begin
  Result := Copy(Name, 1, 5) = 'this.';
  if Result then Bare := Copy(Name, 6, MaxInt) else Bare := Name;
end;

function TGsContext.EvalIndex(E: TGsExpr): Integer;
var
  V: Double;
begin
  V := Eval(E);
  if (V > MaxInt) or (V < -MaxInt) or IsNan(V) then Result := -1
  else Result := Trunc(V);
end;

function TGsContext.ReadLValue(E: TGsExpr): Double;
begin
  Result := Eval(E);
end;

procedure TGsContext.Assign(E: TGsExpr; V: Double);
var
  Bare: string;
  Idx: Integer;
begin
  if E = nil then Exit;
  case E.Kind of
    ekVar, ekIndex:
      begin
        if E.Kind = ekIndex then Idx := EvalIndex(E.A) else Idx := -1;
        if E.Kind = ekIndex then
          if Idx < 0 then Exit;
        if IsLocal(E.Name, Bare) then
        begin
          if Host.SetVar(Self, E.Name, Idx, V) then Exit;
          Locals.SetValue(Bare, Idx, V);
        end
        else
        begin
          if Host.SetVar(Self, E.Name, Idx, V) then Exit;
          Host.Globals.SetValue(E.Name, Idx, V);
        end;
      end;
    ekMember:
      begin
        Idx := EvalIndex(E.A);
        Host.SetMember(Self, E.Name, Idx, E.B.Name, V);
      end;
  end;
end;

procedure TGsContext.AssignArray(E: TGsExpr; Lit: TGsExpr);
var
  V: TGsValues;
  I: Integer;
  Bare: string;
begin
  SetLength(V, Length(Lit.Args));
  for I := 0 to High(Lit.Args) do V[I] := Eval(Lit.Args[I]);
  if E.Kind <> ekVar then Exit;
  if IsLocal(E.Name, Bare) then Locals.SetArray(Bare, V)
  else Host.Globals.SetArray(E.Name, V);
end;

function Truthy(V: Double): Boolean;
begin
  Result := V >= GsTrue;
end;

function BoolNum(B: Boolean): Double;
begin
  if B then Result := 1 else Result := 0;
end;

function TGsContext.ExprString(E: TGsExpr): string;
begin
  Result := GsFormatNum(Eval(E));
end;

function TGsContext.Eval(E: TGsExpr): Double;
var
  V, L, R: Double;
  Bare: string;
  Idx, I: Integer;
  Nums: array of Double;
  Strs: array of string;
begin
  Result := 0;
  if E = nil then Exit;
  case E.Kind of
    ekNum: Result := E.Num;
    ekVar, ekIndex:
      begin
        if E.Kind = ekIndex then Idx := EvalIndex(E.A) else Idx := -1;
        if Host.GetVar(Self, E.Name, Idx, V) then
          Result := V
        else if IsLocal(E.Name, Bare) then
          Result := Locals.Get(Bare, Idx)
        else if IsEventName(E.Name) then
          Result := BoolNum(IsEvent(E.Name))
        else if Host.Globals.Exists(E.Name) then
          Result := Host.Globals.Get(E.Name, Idx)
        else
          Result := BoolNum(Host.TestFlag(Self, E.Name));
      end;
    ekMember:
      begin
        Idx := EvalIndex(E.A);
        if E.B.Kind = ekIndex then
        begin
          { npcs[i].save[n] }
          if Host.GetMember(Self, E.Name, Idx,
            E.B.Name + '[' + IntToStr(EvalIndex(E.B.A)) + ']', V) then
            Result := V;
        end
        else if Host.GetMember(Self, E.Name, Idx, E.B.Name, V) then
          Result := V;
      end;
    ekCall:
      begin
        SetLength(Nums, Length(E.Args));
        for I := 0 to High(E.Args) do Nums[I] := Eval(E.Args[I]);
        SetLength(Strs, Length(E.StrArgs));
        for I := 0 to High(E.StrArgs) do Strs[I] := Expand(E.StrArgs[I]);
        if (E.Name = 'strtofloat') and (Length(Strs) = 1) then
        begin
          if not ParseNumber(Strs[0], V) then V := 0;
          Result := V;
        end
        else if (E.Name = 'strequals') and (Length(Strs) = 2) then
          Result := BoolNum(Strs[0] = Strs[1])
        else if (E.Name = 'strcontains') and (Length(Strs) = 2) then
          Result := BoolNum(Pos(Strs[1], Strs[0]) > 0)
        else if (E.Name = 'startswith') and (Length(Strs) = 2) then
          Result := BoolNum(Copy(Strs[1], 1, Length(Strs[0])) = Strs[0])
        else if (E.Name = 'indexof') and (Length(Strs) = 2) then
          Result := Pos(Strs[0], Strs[1]) - 1
        else if (E.Name = 'strlen') and (Length(Strs) = 1) then
          Result := Length(Strs[0])
        else if Host.CallFunc(Self, E.Name, Nums, Strs, V) then
          Result := V
        else if (E.Name = 'abs') and (Length(Nums) = 1) then Result := Abs(Nums[0])
        else if (E.Name = 'int') and (Length(Nums) = 1) then Result := Int(Nums[0])
        else if (E.Name = 'sin') and (Length(Nums) = 1) then Result := Sin(Nums[0])
        else if (E.Name = 'cos') and (Length(Nums) = 1) then Result := Cos(Nums[0])
        else if (E.Name = 'arctan') and (Length(Nums) = 1) then Result := ArcTan(Nums[0])
        else if (E.Name = 'random') and (Length(Nums) = 2) then
          Result := Nums[0] + Random * (Nums[1] - Nums[0])
        else if (E.Name = 'arraylen') and (Length(E.Args) = 1) and (E.Args[0].Kind = ekVar) then
        begin
          if IsLocal(E.Args[0].Name, Bare) then Result := Locals.Len(Bare)
          else Result := Host.Globals.Len(E.Args[0].Name);
        end
        else if (E.Name = 'vecx') and (Length(Nums) = 1) then
          Result := Ord(Trunc(Nums[0]) and 3 = 3) - Ord(Trunc(Nums[0]) and 3 = 1)
        else if (E.Name = 'vecy') and (Length(Nums) = 1) then
          Result := Ord(Trunc(Nums[0]) and 3 = 2) - Ord(Trunc(Nums[0]) and 3 = 0)
        else
          Host.Error(Self, 'unknown function ' + E.Name);
      end;
    ekUnary:
      if E.Name = '!' then Result := BoolNum(not Truthy(Eval(E.A)))
      else Result := -Eval(E.A);
    ekPostInc, ekPreInc:
      begin
        V := Eval(E.A);
        if E.Name = '++' then Assign(E.A, V + 1) else Assign(E.A, V - 1);
        if E.Kind = ekPostInc then Result := V
        else if E.Name = '++' then Result := V + 1
        else Result := V - 1;
      end;
    ekArray:
      if Length(E.Args) > 0 then Result := Eval(E.Args[0]);
    ekBinary:
      begin
        if E.Name = '&&' then
        begin
          Result := BoolNum(Truthy(Eval(E.A)) and Truthy(Eval(E.B)));
          Exit;
        end;
        if E.Name = '||' then
        begin
          Result := BoolNum(Truthy(Eval(E.A)) or Truthy(Eval(E.B)));
          Exit;
        end;
        if (E.Name = '=') or (E.Name = '+=') or (E.Name = '-=') or
          (E.Name = '*=') or (E.Name = '/=') then
        begin
          if (E.Name = '=') and (E.B.Kind = ekArray) then
          begin
            AssignArray(E.A, E.B);
            Exit;
          end;
          R := Eval(E.B);
          if E.Name = '=' then V := R
          else
          begin
            L := ReadLValue(E.A);
            if E.Name = '+=' then V := L + R
            else if E.Name = '-=' then V := L - R
            else if E.Name = '*=' then V := L * R
            else if R <> 0 then V := L / R
            else V := 0;
          end;
          Assign(E.A, V);
          Result := V;
          Exit;
        end;
        L := Eval(E.A);
        if E.Name = 'in' then
        begin
          if E.B.Kind = ekRange then
          begin
            if Length(E.B.Args) = 2 then
              Result := BoolNum((L >= Eval(E.B.Args[0])) and (L <= Eval(E.B.Args[1])));
          end
          else
            for I := 0 to High(E.B.Args) do
              if Eval(E.B.Args[I]) = L then
              begin
                Result := 1;
                Break;
              end;
          Exit;
        end;
        R := Eval(E.B);
        if E.Name = '+' then Result := L + R
        else if E.Name = '-' then Result := L - R
        else if E.Name = '*' then Result := L * R
        else if E.Name = '/' then
        begin
          if R <> 0 then Result := L / R else Result := 0;
        end
        else if E.Name = '%' then
        begin
          if R <> 0 then Result := L - R * Floor(L / R) else Result := 0;
        end
        else if E.Name = '^' then
        begin
          if (L < 0) and (Frac(R) <> 0) then Result := 0
          else if (L = 0) and (R <= 0) then Result := 0
          else Result := Power(L, R);
        end
        else if E.Name = '==' then Result := BoolNum(L = R)
        else if E.Name = '!=' then Result := BoolNum(L <> R)
        else if E.Name = '<' then Result := BoolNum(L < R)
        else if E.Name = '>' then Result := BoolNum(L > R)
        else if E.Name = '<=' then Result := BoolNum(L <= R)
        else if E.Name = '>=' then Result := BoolNum(L >= R);
      end;
  end;
  if IsNan(Result) or IsInfinite(Result) then Result := 0;
end;

function TGsContext.EvalText(const Raw: string): Double;
var
  C: TGsScript;
  N: TGsNode;
begin
  Result := 0;
  C := TGsScript.Create;
  try
    if C.Compile(Raw + ';') and (C.Count > 0) then
    begin
      N := C.Node(0);
      if N.Kind = nkExpr then Result := Eval(N.Expr);
    end;
  finally
    C.Free;
  end;
end;

function TGsContext.Expand(const Raw: string): string;
var
  I, E, J: Integer;
  Code, Param, S: string;
begin
  Result := '';
  I := 1;
  while I <= Length(Raw) do
  begin
    if (Raw[I] = '#') and (I < Length(Raw)) and (Raw[I + 1] in ['a'..'z', 'A'..'Z', '0'..'9']) then
    begin
      E := CodeParenEnd(Raw, I);
      if E > 0 then
      begin
        J := Pos('(', Copy(Raw, I, E - I + 1)) + I - 1;
        Code := Copy(Raw, I + 1, J - I - 1);
        Param := Copy(Raw, J + 1, E - J - 1);
        I := E + 1;
      end
      else
      begin
        Code := Raw[I + 1];
        { two-letter codes: #C0..#C5 colours, #P1..#P5 attributes }
        if (Code[1] in ['C', 'P']) and (I + 2 <= Length(Raw)) and (Raw[I + 2] in ['0'..'9']) then
        begin
          Code := Code + Raw[I + 2];
          Inc(I);
        end;
        Param := '';
        Inc(I, 2);
      end;
      if Code = 'v' then
        S := GsFormatNum(EvalText(Expand(Param)))
      else if Code = 'p' then
      begin
        J := Trunc(EvalText(Param));
        if (J >= 0) and (J < Params.Count) then S := Params[J] else S := '';
      end
      else if Code = 't' then
      begin
        J := Trunc(EvalText(Param));
        if (J >= 0) and (J < Host.Tokens.Count) then S := Host.Tokens[J] else S := '';
      end
      else if not Host.MessageCode(Self, Code, Param, S) then
      begin
        { an unknown code stays as written }
        if E > 0 then S := '#' + Code + '(' + Param + ')' else S := '#' + Code;
      end;
      Result := Result + S;
    end
    else
    begin
      Result := Result + Raw[I];
      Inc(I);
    end;
  end;
  Result := Trim(Result);
end;

procedure TGsContext.Run(const AEvent: string);
var
  PC, I, Op: Integer;
  N: TGsNode;
  A: TGsArgs;
  Sig: string;
  V: Double;
  Guard: Integer;
begin
  if (Script = nil) or Running then Exit;
  Running := True;
  Ended := False;
  Event := AEvent;
  FDepth := 0;
  SetLength(FStack, 0);
  for I := 0 to High(FLoops) do FLoops[I] := 0;
  PC := 0;
  if (AEvent = 'timeout') and (ResumeAt >= 0) then
  begin
    PC := ResumeAt;
  end;
  ResumeAt := -1;
  Steps := 0;
  Guard := 0;
  try
    while (PC >= 0) and (PC < Script.Count) and not Ended do
    begin
      Inc(Steps);
      Inc(Guard);
      { a run-away script (every loop at its cap, nested) is cut off }
      if Guard > 2000000 then Break;
      N := Script.Node(PC);
      Inc(PC);
      case N.Kind of
        nkEnd: Break;
        nkJump: PC := N.Target;
        nkJumpIfFalse:
          if not Truthy(Eval(N.Expr)) then PC := N.Target;
        nkLoopStart: FLoops[N.Loop] := 0;
        nkLoopTest:
          begin
            Inc(FLoops[N.Loop]);
            if (FLoops[N.Loop] > GsMaxLoop) or not Truthy(Eval(N.Expr)) then
              PC := N.Target;
          end;
        nkExpr: Eval(N.Expr);
        nkCall:
          if N.Target >= 0 then
          begin
            if FDepth >= GsMaxDepth then Continue;
            if FDepth >= Length(FStack) then SetLength(FStack, FDepth * 2 + 8);
            FStack[FDepth] := PC;
            Inc(FDepth);
            PC := N.Target;
          end;
        nkEndFunc:
          begin
            if FDepth = 0 then Break;
            Dec(FDepth);
            PC := FStack[FDepth];
          end;
        nkCommand:
          begin
            Op := N.Op;
            Sig := GsCommands[Op - GsFirstOp].Sig;
            A.Count := Length(Sig);
            for I := 0 to A.Count - 1 do
            begin
              if (I <= High(N.Args)) and (N.Args[I] <> nil) then
              begin
                V := Eval(N.Args[I]);
                A.Num[I] := V;
                A.Str[I] := N.Raw[I];
              end
              else
              begin
                A.Num[I] := 0;
                if I <= High(N.Raw) then
                begin
                  if (I = 0) and ((Op = GsOpSetCharProp) or (Op = GsOpSetPlayerProp)) then
                    { the first argument names the prop (#3, #C1, ...) }
                    A.Str[I] := Trim(N.Raw[I])
                  else if Sig[I + 1] in ['S', 'M', 'F', 'Q', 'O'] then
                    A.Str[I] := Expand(N.Raw[I])
                  else
                    A.Str[I] := LowerCase(Trim(N.Raw[I]));
                end
                else
                  A.Str[I] := '';
                { names given for I, B, C, D, L }
                case Sig[I + 1] of
                  'I': A.Num[I] := GsNameIndex(GsItemNames, A.Str[I]);
                  'B': A.Num[I] := GsNameIndex(GsBaddyNames, A.Str[I]);
                  'C': A.Num[I] := GsNameIndex(GsColorNames, A.Str[I]);
                  'D': A.Num[I] := GsNameIndex(GsDirNames, A.Str[I]);
                  'L': A.Num[I] := GsNameIndex(GsCarryNames, A.Str[I]);
                end;
              end;
            end;
            case Op of
              GsOpSet: Host.SetFlag(Self, A.Str[0], True);
              GsOpUnset: Host.SetFlag(Self, A.Str[0], False);
              GsOpSetArray:
                if N.Raw[0] <> '' then
                begin
                  Sig := LowerCase(Trim(N.Raw[0]));
                  if Copy(Sig, 1, 5) = 'this.' then
                    Locals.Resize(Copy(Sig, 6, MaxInt), Trunc(A.Num[1]))
                  else if IsValidIdent(Sig) then
                    Host.Globals.Resize(Sig, Trunc(A.Num[1]));
                end;
              GsOpTokenize, GsOpTokenize2:
                begin
                  Host.Tokens.Clear;
                  Sig := ' ,';
                  if Op = GsOpTokenize2 then Sig := Sig + A.Str[1];
                  Tokenize(A.Str[0], Sig, Host.Tokens);
                end;
              GsOpSleep:
                begin
                  if Host.Command(Self, Op, A) then Ended := True;
                  if A.Num[0] > 0 then
                  begin
                    ResumeAt := PC;
                    Ended := True;
                  end;
                end;
            else
              if Host.Command(Self, Op, A) then Ended := True;
            end;
          end;
      end;
    end;
  finally
    Running := False;
    Event := '';
  end;
end;

procedure TGsContext.RunWithParams(const AEvent: string; const AParams: string);
begin
  Params.Clear;
  Tokenize(AParams, ',', Params);
  Run(AEvent);
  Params.Clear;
end;

initialization

finalization
  CmdIndex.Free;
end.
