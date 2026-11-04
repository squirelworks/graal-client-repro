{ NpcNwb2: level NPCs of 2.05 rev 2, their props, drawing and scripts.

  Where NPCs come from (graal_analysis manual/02-protocol/05-plo.md,
  06-props.md):
  - offline, from the level file's NPC blocks (GLevel's TLevelNPC);
  - online, from PLO_NPCPROPS (3): i3 id + an NPCPROP stream. Ids below
    1000 are level NPCs, 1000 and up server-wide. The SCRIPT prop carries
    GS1 source text and is applied only while the NPC has none. A new NPC
    gets playerenters when the player is in its level.

  The scripts run in GGs1. TNpcManager is their host: it knows the
  built-in names (x, y, dir, playerx, ...) and runs the commands. What
  belongs to the rest of the game (hurting the player, sign text, warps,
  items, sound, baddies) goes through TNpcWorld, which the game implements
  (NpcBridgeNwb2); its defaults do nothing, so tests can use it as is.

  Timeouts run every 50 ms tick (0.05 s) offline, or online on the level
  leader (PLO_ISLEADER), or everywhere after timereverywhere.

  Written from the notes in graal_analysis (npc-library/
  gs1-command-reference-205.md, the NPC lab results of 2026-11-04), not
  from the original program. }
unit NpcNwb2;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, SysUtils, Math, GTypes, GLevel, GSurface, GGs1;

const
  NPCPROP_IMAGE = 0; NPCPROP_SCRIPT = 1; NPCPROP_X = 2; NPCPROP_Y = 3;
  NPCPROP_POWER = 4; NPCPROP_RUPEES = 5; NPCPROP_ARROWS = 6;
  NPCPROP_BOMBS = 7; NPCPROP_GLOVEPOWER = 8; NPCPROP_BOMBPOWER = 9;
  NPCPROP_SWORDIMAGE = 10; NPCPROP_SHIELDIMAGE = 11; NPCPROP_GANI = 12;
  NPCPROP_VISFLAGS = 13; NPCPROP_BLOCKFLAGS = 14; NPCPROP_MESSAGE = 15;
  NPCPROP_HURTDXDY = 16; NPCPROP_ID = 17; NPCPROP_SPRITE = 18;
  NPCPROP_COLORS = 19; NPCPROP_NICKNAME = 20; NPCPROP_HORSEIMAGE = 21;
  NPCPROP_HEADIMAGE = 22; NPCPROP_SAVE0 = 23; NPCPROP_SAVE9 = 32;
  NPCPROP_ALIGNMENT = 33; NPCPROP_IMAGEPART = 34; NPCPROP_BODYIMAGE = 35;
  NPCPROP_GATTRIB1 = 36; NPCPROP_GATTRIB5 = 40;
  { 2.05 parses 0 to 40; a higher id ends the stream }
  NpcPropLastNwb2 = 40;

  VisVisible = 1; VisOver = 2; VisUnder = 4;
  BlockNone = 1;

  PLI_NPCPROPS_ID = 3;
  PLI_FLAGSET_ID = 18;
  PLI_FLAGDEL_ID = 19;
  PLI_PUTNPC_ID = 21;
  PLI_NPCDEL_ID = 22;
  PLI_TRIGGERACTION_ID = 38;
  PLO_NPCPROPS_ID = 3;
  PLO_ISLEADER_ID = 10;
  PLO_FLAGSET_ID = 28;
  PLO_NPCDEL_ID = 29;
  PLO_FLAGDEL_ID = 31;
  PLO_HASNPCSERVER_ID = 44;

  TickSeconds = 0.05;

type
  TNpc = class;

  { An image an NPC script shows with showimg. }
  TNpcShownImage = record
    Index: Integer;
    Image: string;
    X, Y: Double;
    PartSet: Boolean;
    PX, PY, PW, PH: Integer;
    Layer: Integer;
  end;

  TNpc = class
  public
    Id: Integer;
    X, Y: Double;            { tiles, top-left }
    Image: string;
    PartSet: Boolean;        { setimgpart: only (PX, PY, PW, PH) shows }
    PX, PY, PW, PH: Integer;
    VisFlags, BlockFlags: Integer;
    Layer: Integer;          { -1 under the player, 0 level, 1 over, 9 light }
    CanCarry, CanPush, CanPull: Boolean;
    Message: string;
    TimerShow, TimerEverywhere: Boolean;
    Timeout: Double;         { seconds left; 0 = no timeout }
    { showcharacter }
    Character: Boolean;
    Gani, GaniParams, HeadImage, BodyImage, SwordImage, ShieldImage,
    HorseImage, Nickname, Chat: string;
    Colors: array[0..4] of Integer;
    Attr: array[1..5] of string;
    Male: Boolean;
    Dir, Sprite: Integer;
    GaniStart: Integer;      { manager tick the gani started on }
    CharObj: TObject;        { the world's drawing state for a character }
    { stats }
    Power, Rupees, Arrows, Bombs, GlovePower, BombPower, SwordPower,
    ShieldPower, AP: Integer;
    HurtDX, HurtDY: Double;
    Save: array[0..9] of Integer;
    { setshape: a fixed blocking rectangle in pixels }
    ShapeW, ShapeH: Integer;
    { move }
    MoveDX, MoveDY: Double;
    MoveTicks: Integer;
    MoveEvent: Boolean;
    ShownImages: array of TNpcShownImage;
    { setcoloreffect (multiply, 0..1) and setzoomeffect }
    EffR, EffG, EffB, EffA, Zoom: Double;
    Ctx: TGsContext;
    Script: string;
    Gone: Boolean;           { destroyed: removed after the run }
    Local: Boolean;          { made offline or by putnpc: nothing to sync }
    Dirty: array[0..NpcPropLastNwb2] of Boolean;
    constructor Create;
    destructor Destroy; override;
    function Visible: Boolean;
    function Blocks: Boolean;
    procedure MarkDirty(Prop: Integer);
    function AnyDirty: Boolean;
  end;

  { The game around the NPCs. Every method has a do-nothing default. }
  TNpcWorld = class
  public
    function Online: Boolean; virtual;
    function PlayerX: Double; virtual;
    function PlayerY: Double; virtual;
    function PlayerDir: Integer; virtual;
    { playerrupees, playerhearts, ...: the 800-825 names }
    function GetPlayerVar(const Name: string; out V: Double): Boolean; virtual;
    function SetPlayerVar(const Name: string; V: Double): Boolean; virtual;
    function PlayerChat: string; virtual;
    function PlayerCode(const Code: string): string; virtual;
    function Image(const Name: string): TGSurface; virtual;
    function TileType(X, Y: Integer): Integer; virtual;
    procedure DrawCharacter(N: TNpc; Screen: TGSurface; DX, DY, Tick: Integer); virtual;
    procedure HurtPlayer(Power, FromX, FromY: Double); virtual;
    procedure ShowSign(Index: Integer); virtual;
    procedure Say2(const Text: string); virtual;
    procedure Warp(const Level: string; X, Y: Double); virtual;
    procedure LayItem(Item: Integer; X, Y: Double); virtual;
    procedure PlaySound(const Name: string; X, Y: Double; Looped: Boolean); virtual;
    procedure StopSound(const Name: string); virtual;
    procedure PutBaddy(Kind: Integer; X, Y: Double; const Img: string; Power: Integer); virtual;
    procedure Shoot(const Kind: string; X, Y: Double; Dir: Integer); virtual;
    procedure PutBomb(Power: Integer; X, Y: Double); virtual;
    procedure PutExplosion(Power, Radius, X, Y: Double); virtual;
    procedure PutLeaps(Kind: Integer; X, Y: Double); virtual;
    procedure FreezePlayer(Seconds: Double); virtual;
    procedure SetPlayerProp(const Code, Value: string); virtual;
    procedure SetPlayerAni(const Gani, Params: string); virtual;
    procedure PlayerCommand(Op: Integer; const A: TGsArgs); virtual;
    procedure Send(Id: Integer; const Data: string); virtual;
    procedure Log(const S: string); virtual;
    { After each tick's scripts: deferred work such as warps. }
    procedure Idle; virtual;
  end;

  TNpcManager = class(TGsHost)
  private
    FTick: Integer;
    FTouchCool: Integer;
    function Ctx2Npc(Ctx: TGsContext): TNpc;
    procedure ApplyProps(N: TNpc; R: TGReader; FromServer: Boolean);
    function PropBytes(N: TNpc; Prop: Integer): string;
    procedure FlushProps(N: TNpc);
    procedure RemoveGone;
    procedure SetVisible(N: TNpc; On, Local: Boolean);
    function CharProp(N: TNpc; const Code, Value: string): Boolean;
    procedure ShowImg(N: TNpc; Index: Integer; const Img: string; X, Y: Double);
    function FindImg(N: TNpc; Index: Integer): Integer;
  public
    World: TNpcWorld;
    OwnsWorld: Boolean;
    Npcs: TList;
    Flags: TStringList;      { the player's flags: name or name=value }
    IsLeader, HasNpcServer: Boolean;
    Log: TStringList;        { script errors, newest last (kept short) }
    constructor Create(AWorld: TNpcWorld);
    destructor Destroy; override;
    function Count: Integer;
    function Npc(I: Integer): TNpc;
    function FindById(Id: Integer): TNpc;
    procedure Clear;
    { Offline: the level's NPCs, each then gets playerenters. }
    procedure LoadLevel(Level: TAdventureLevel);
    { Adds an NPC and compiles its script (no event yet). }
    function Add(Id: Integer; X, Y: Double; const Img, Script: string): TNpc;
    { Runs one event on one NPC. }
    procedure Fire(N: TNpc; const Event: string; const Params: string = '');
    procedure FireAll(const Event: string; const Params: string = '');
    { A server message. True when it was an NPC message. }
    function Receive(Id: Integer; const Data: string): Boolean;
    { One 50 ms tick: timeouts and moves. }
    procedure Tick;
    { Player hooks, called by the game. }
    procedure PlayerPush(Dir: Integer; PX, PY: Double);
    procedure PlayerMoved(PX, PY: Double);
    procedure PlayerChats(const Text: string);
    procedure PlayerEndsReading;
    procedure SwordHit(X, Y, W, H, Power: Double);
    procedure BombBlast(X, Y, Radius: Double);
    { True when an NPC took the shot }
    function ArrowHit(X, Y, Power: Double): Boolean;
    { An NPC point test, for walking. }
    function PointBlocked(PX, PY: Double): Boolean;
    function NpcAt(PX, PY: Double; BlockingOnly: Boolean): TNpc;
    { The NPC's box in tiles. }
    procedure Bounds(N: TNpc; out BX, BY, BW, BH: Double);
    { Drawing: Layer < 0 under the player, 0 with the level, > 0 over. }
    procedure Draw(Screen: TGSurface; CamX, CamY: Integer; Over: Boolean);
    { flags }
    function HasFlag(const Name: string): Boolean;
    procedure PutFlag(const Name: string; On, Send: Boolean);
    { TGsHost }
    function GetVar(Ctx: TGsContext; const Name: string; Index: Integer;
      out V: Double): Boolean; override;
    function SetVar(Ctx: TGsContext; const Name: string; Index: Integer;
      V: Double): Boolean; override;
    function GetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
      const Member: string; out V: Double): Boolean; override;
    function SetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
      const Member: string; V: Double): Boolean; override;
    function CallFunc(Ctx: TGsContext; const Name: string;
      const Nums: array of Double; const Strs: array of string;
      out V: Double): Boolean; override;
    function TestFlag(Ctx: TGsContext; const Name: string): Boolean; override;
    procedure SetFlag(Ctx: TGsContext; const Name: string; On: Boolean); override;
    function MessageCode(Ctx: TGsContext; const Code, Param: string;
      out S: string): Boolean; override;
    function Command(Ctx: TGsContext; Op: Integer; const A: TGsArgs): Boolean; override;
    procedure Error(Ctx: TGsContext; const Msg: string); override;
  end;

function ColorIndexOf(const S: string): Integer;

implementation

uses
  GFont;

{ ---- TNpc ---- }

constructor TNpc.Create;
begin
  VisFlags := VisVisible;
  EffR := 1;
  EffG := 1;
  EffB := 1;
  EffA := 1;
  Zoom := 1;
  Dir := 2;
  Sprite := 2;
  Male := True;
  Gani := 'idle';
  Colors[0] := 0; { white skin? the player defaults: see ColorTable }
  Colors[1] := 9;
  Colors[2] := 0;
  Colors[3] := 12;
  Colors[4] := 18;
  HeadImage := 'head0.png';
  BodyImage := 'body.png';
  SwordImage := 'sword1.png';
  ShieldImage := 'shield1.png';
end;

destructor TNpc.Destroy;
begin
  Ctx.Free;
  CharObj.Free;
  inherited;
end;

function TNpc.Visible: Boolean;
begin
  Result := VisFlags and VisVisible <> 0;
end;

function TNpc.Blocks: Boolean;
begin
  Result := BlockFlags and BlockNone = 0;
end;

procedure TNpc.MarkDirty(Prop: Integer);
begin
  if (Prop >= 0) and (Prop <= NpcPropLastNwb2) then Dirty[Prop] := True;
end;

function TNpc.AnyDirty: Boolean;
var
  I: Integer;
begin
  for I := 0 to NpcPropLastNwb2 do
    if Dirty[I] then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ ---- TNpcWorld defaults ---- }

function TNpcWorld.Online: Boolean; begin Result := False; end;
function TNpcWorld.PlayerX: Double; begin Result := 0; end;
function TNpcWorld.PlayerY: Double; begin Result := 0; end;
function TNpcWorld.PlayerDir: Integer; begin Result := 2; end;
function TNpcWorld.GetPlayerVar(const Name: string; out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;
function TNpcWorld.SetPlayerVar(const Name: string; V: Double): Boolean; begin Result := False; end;
function TNpcWorld.PlayerChat: string; begin Result := ''; end;
function TNpcWorld.PlayerCode(const Code: string): string; begin Result := ''; end;
function TNpcWorld.Image(const Name: string): TGSurface; begin Result := nil; end;
function TNpcWorld.TileType(X, Y: Integer): Integer; begin Result := 0; end;
procedure TNpcWorld.DrawCharacter(N: TNpc; Screen: TGSurface; DX, DY, Tick: Integer); begin end;
procedure TNpcWorld.HurtPlayer(Power, FromX, FromY: Double); begin end;
procedure TNpcWorld.ShowSign(Index: Integer); begin end;
procedure TNpcWorld.Say2(const Text: string); begin end;
procedure TNpcWorld.Warp(const Level: string; X, Y: Double); begin end;
procedure TNpcWorld.LayItem(Item: Integer; X, Y: Double); begin end;
procedure TNpcWorld.PlaySound(const Name: string; X, Y: Double; Looped: Boolean); begin end;
procedure TNpcWorld.StopSound(const Name: string); begin end;
procedure TNpcWorld.PutBaddy(Kind: Integer; X, Y: Double; const Img: string; Power: Integer); begin end;
procedure TNpcWorld.Shoot(const Kind: string; X, Y: Double; Dir: Integer); begin end;
procedure TNpcWorld.PutBomb(Power: Integer; X, Y: Double); begin end;
procedure TNpcWorld.PutExplosion(Power, Radius, X, Y: Double); begin end;
procedure TNpcWorld.PutLeaps(Kind: Integer; X, Y: Double); begin end;
procedure TNpcWorld.FreezePlayer(Seconds: Double); begin end;
procedure TNpcWorld.SetPlayerProp(const Code, Value: string); begin end;
procedure TNpcWorld.SetPlayerAni(const Gani, Params: string); begin end;
procedure TNpcWorld.PlayerCommand(Op: Integer; const A: TGsArgs); begin end;
procedure TNpcWorld.Send(Id: Integer; const Data: string); begin end;
procedure TNpcWorld.Log(const S: string); begin end;
procedure TNpcWorld.Idle; begin end;

{ ---- helpers ---- }

function ColorIndexOf(const S: string): Integer;
var
  V: Integer;
begin
  Result := GsNameIndex(GsColorNames, S);
  if Result < 0 then
  begin
    if TryStrToInt(Trim(S), V) then Result := ((V mod 20) + 20) mod 20
    else Result := -1;
  end;
end;

function ClampI(V, Lo, Hi: Integer): Integer;
begin
  if V < Lo then Result := Lo else if V > Hi then Result := Hi else Result := V;
end;

function ClampF(V, Lo, Hi: Double): Double;
begin
  if V < Lo then Result := Lo else if V > Hi then Result := Hi else Result := V;
end;

{ ---- TNpcManager ---- }

constructor TNpcManager.Create(AWorld: TNpcWorld);
begin
  inherited Create;
  World := AWorld;
  if World = nil then
  begin
    World := TNpcWorld.Create;
    OwnsWorld := True;
  end;
  Npcs := TList.Create;
  Flags := TStringList.Create;
  Log := TStringList.Create;
end;

destructor TNpcManager.Destroy;
begin
  Clear;
  Npcs.Free;
  Flags.Free;
  Log.Free;
  if OwnsWorld then World.Free;
  inherited;
end;

function TNpcManager.Count: Integer;
begin
  Result := Npcs.Count;
end;

function TNpcManager.Npc(I: Integer): TNpc;
begin
  Result := TNpc(Npcs[I]);
end;

function TNpcManager.FindById(Id: Integer): TNpc;
var
  I: Integer;
begin
  for I := 0 to Npcs.Count - 1 do
    if Npc(I).Id = Id then
    begin
      Result := Npc(I);
      Exit;
    end;
  Result := nil;
end;

procedure TNpcManager.Clear;
var
  I: Integer;
begin
  for I := 0 to Npcs.Count - 1 do Npc(I).Free;
  Npcs.Clear;
  IsLeader := False;
end;

function TNpcManager.Ctx2Npc(Ctx: TGsContext): TNpc;
begin
  if (Ctx <> nil) and (Ctx.Owner is TNpc) then Result := TNpc(Ctx.Owner)
  else Result := nil;
end;

function TNpcManager.Add(Id: Integer; X, Y: Double; const Img, Script: string): TNpc;
begin
  Result := TNpc.Create;
  Result.Id := Id;
  Result.X := X;
  Result.Y := Y;
  Result.Image := Img;
  Result.Script := Script;
  Result.Ctx := TGsContext.Create(Self, Result);
  if (Script <> '') and not Result.Ctx.Load(Script) then
    Error(Result.Ctx, Result.Ctx.Script.Errors.Text);
  Npcs.Add(Result);
end;

procedure TNpcManager.LoadLevel(Level: TAdventureLevel);
var
  I, First: Integer;
begin
  Clear;
  First := Npcs.Count;
  for I := 0 to High(Level.NPCs) do
    Add(0, Level.NPCs[I].X, Level.NPCs[I].Y, Level.NPCs[I].Image,
      Level.NPCs[I].Script).Local := True;
  { offline the player is the level's only client }
  IsLeader := True;
  for I := First to Npcs.Count - 1 do
    if I < Npcs.Count then
    begin
      Fire(Npc(I), 'created');
      Fire(Npc(I), 'playerenters');
    end;
  RemoveGone;
end;

procedure TNpcManager.Error(Ctx: TGsContext; const Msg: string);
var
  N: TNpc;
  S: string;
begin
  N := Ctx2Npc(Ctx);
  if N <> nil then S := Format('npc %d at %.1f,%.1f: %s', [N.Id, N.X, N.Y, Trim(Msg)])
  else S := Trim(Msg);
  Log.Add(S);
  while Log.Count > 100 do Log.Delete(0);
  World.Log('GS1 ' + S);
end;

procedure TNpcManager.Fire(N: TNpc; const Event: string; const Params: string);
begin
  if (N = nil) or N.Gone or (N.Ctx = nil) or (N.Ctx.Script = nil) then Exit;
  if Params <> '' then N.Ctx.RunWithParams(Event, Params)
  else N.Ctx.Run(Event);
  if World.Online and not N.Local and (N.Id > 0) and N.AnyDirty then FlushProps(N);
end;

procedure TNpcManager.FireAll(const Event: string; const Params: string);
var
  I: Integer;
begin
  I := 0;
  while I < Npcs.Count do
  begin
    Fire(Npc(I), Event, Params);
    Inc(I);
  end;
  RemoveGone;
end;

procedure TNpcManager.RemoveGone;
var
  I: Integer;
begin
  for I := Npcs.Count - 1 downto 0 do
    if Npc(I).Gone and not Npc(I).Ctx.Running then
    begin
      Npc(I).Free;
      Npcs.Delete(I);
    end;
end;

{ ---- props ---- }

procedure TNpcManager.ApplyProps(N: TNpc; R: TGReader; FromServer: Boolean);
var
  P, V, L, I: Integer;
  S: string;
begin
  while not R.Eof do
  begin
    P := R.ReadGChar;
    if (P < 0) or (P > NpcPropLastNwb2) then Exit;
    case P of
      NPCPROP_IMAGE:
        begin
          N.Image := R.ReadGString;
          N.PartSet := False;
        end;
      NPCPROP_SCRIPT:
        begin
          L := R.ReadGShort;
          S := R.ReadChars(L);
          { applied only while the NPC has no script yet }
          if N.Script = '' then
          begin
            N.Script := S;
            if not N.Ctx.Load(S) then
              Error(N.Ctx, N.Ctx.Script.Errors.Text);
          end;
        end;
      NPCPROP_X: N.X := R.ReadGChar / 2;
      NPCPROP_Y: N.Y := R.ReadGChar / 2;
      NPCPROP_POWER: N.Power := R.ReadGChar;
      NPCPROP_RUPEES: N.Rupees := R.ReadGInt3;
      NPCPROP_ARROWS: N.Arrows := R.ReadGChar;
      NPCPROP_BOMBS: N.Bombs := R.ReadGChar;
      NPCPROP_GLOVEPOWER: N.GlovePower := R.ReadGChar;
      NPCPROP_BOMBPOWER: N.BombPower := R.ReadGChar;
      NPCPROP_SWORDIMAGE:
        begin
          V := R.ReadGChar;
          if V > 30 then
          begin
            N.SwordPower := V - 30;
            N.SwordImage := R.ReadGString;
          end
          else
            N.SwordPower := V;
        end;
      NPCPROP_SHIELDIMAGE:
        begin
          V := R.ReadGChar;
          if V > 10 then
          begin
            N.ShieldPower := V - 10;
            N.ShieldImage := R.ReadGString;
          end
          else
            N.ShieldPower := V;
        end;
      NPCPROP_GANI:
        begin
          S := R.ReadGString;
          if S <> N.Gani then N.GaniStart := FTick;
          N.Gani := S;
        end;
      NPCPROP_VISFLAGS:
        begin
          N.VisFlags := R.ReadGChar;
          if N.VisFlags and VisOver <> 0 then N.Layer := 1
          else if N.VisFlags and VisUnder <> 0 then N.Layer := -1
          else if N.Layer <> 9 then N.Layer := 0;
        end;
      NPCPROP_BLOCKFLAGS: N.BlockFlags := R.ReadGChar;
      NPCPROP_MESSAGE: N.Message := R.ReadGString;
      NPCPROP_HURTDXDY:
        begin
          N.HurtDX := (R.ReadGChar - 32) / 32;
          N.HurtDY := (R.ReadGChar - 32) / 32;
        end;
      NPCPROP_ID: R.ReadGInt3;
      NPCPROP_SPRITE:
        begin
          N.Sprite := R.ReadGChar;
          N.Dir := N.Sprite and 3;
        end;
      NPCPROP_COLORS:
        for I := 0 to 4 do N.Colors[I] := R.ReadGChar;
      NPCPROP_NICKNAME: N.Nickname := R.ReadGString;
      NPCPROP_HORSEIMAGE: N.HorseImage := R.ReadGString;
      NPCPROP_HEADIMAGE:
        begin
          V := R.ReadGChar;
          if V >= 100 then N.HeadImage := R.ReadChars(V - 100)
          else N.HeadImage := 'head' + IntToStr(V) + '.png';
        end;
      NPCPROP_SAVE0..NPCPROP_SAVE9: N.Save[P - NPCPROP_SAVE0] := R.ReadGChar;
      NPCPROP_ALIGNMENT: N.AP := R.ReadGChar;
      NPCPROP_IMAGEPART:
        begin
          N.PX := ClampI(R.ReadGShort, 0, 16000);
          N.PY := ClampI(R.ReadGShort, 0, 16000);
          N.PW := ClampI(R.ReadGChar, 0, 220);
          N.PH := ClampI(R.ReadGChar, 0, 220);
          N.PartSet := True;
        end;
      NPCPROP_BODYIMAGE: N.BodyImage := R.ReadGString;
      NPCPROP_GATTRIB1..NPCPROP_GATTRIB5:
        N.Attr[P - NPCPROP_GATTRIB1 + 1] := R.ReadGString;
    end;
    if R.Overrun then Exit;
  end;
end;

function TNpcManager.PropBytes(N: TNpc; Prop: Integer): string;
var
  I: Integer;
begin
  Result := GChar(Prop);
  case Prop of
    NPCPROP_IMAGE: Result := Result + GString(N.Image);
    NPCPROP_X: Result := Result + GChar(ClampI(Round(N.X * 2), 0, 223));
    NPCPROP_Y: Result := Result + GChar(ClampI(Round(N.Y * 2), 0, 223));
    NPCPROP_POWER: Result := Result + GChar(ClampI(N.Power, 0, 223));
    NPCPROP_RUPEES: Result := Result + GInt3(ClampI(N.Rupees, 0, 9999999));
    NPCPROP_ARROWS: Result := Result + GChar(ClampI(N.Arrows, 0, 223));
    NPCPROP_BOMBS: Result := Result + GChar(ClampI(N.Bombs, 0, 223));
    NPCPROP_GLOVEPOWER: Result := Result + GChar(ClampI(N.GlovePower, 0, 223));
    NPCPROP_BOMBPOWER: Result := Result + GChar(ClampI(N.BombPower, 0, 223));
    NPCPROP_SWORDIMAGE: Result := Result + GChar(ClampI(N.SwordPower + 30, 30, 223)) + GString(N.SwordImage);
    NPCPROP_SHIELDIMAGE: Result := Result + GChar(ClampI(N.ShieldPower + 10, 10, 223)) + GString(N.ShieldImage);
    NPCPROP_GANI: Result := Result + GString(N.Gani);
    NPCPROP_VISFLAGS: Result := Result + GChar(N.VisFlags);
    NPCPROP_BLOCKFLAGS: Result := Result + GChar(N.BlockFlags);
    NPCPROP_MESSAGE: Result := Result + GString(N.Message);
    NPCPROP_HURTDXDY:
      Result := Result + GChar(ClampI(Round(N.HurtDX * 32 + 32), 0, 223)) +
        GChar(ClampI(Round(N.HurtDY * 32 + 32), 0, 223));
    NPCPROP_SPRITE: Result := Result + GChar(ClampI(N.Sprite, 0, 223));
    NPCPROP_COLORS:
      for I := 0 to 4 do Result := Result + GChar(ClampI(N.Colors[I], 0, 223));
    NPCPROP_NICKNAME: Result := Result + GString(N.Nickname);
    NPCPROP_HORSEIMAGE: Result := Result + GString(N.HorseImage);
    NPCPROP_HEADIMAGE: Result := Result + GChar(ClampI(Length(N.HeadImage), 0, 123) + 100) + Copy(N.HeadImage, 1, 123);
    NPCPROP_SAVE0..NPCPROP_SAVE9: Result := Result + GChar(ClampI(N.Save[Prop - NPCPROP_SAVE0], 0, 223));
    NPCPROP_ALIGNMENT: Result := Result + GChar(ClampI(N.AP, 0, 100));
    NPCPROP_IMAGEPART:
      Result := Result + GShort(N.PX) + GShort(N.PY) + GChar(N.PW) + GChar(N.PH);
    NPCPROP_BODYIMAGE: Result := Result + GString(N.BodyImage);
    NPCPROP_GATTRIB1..NPCPROP_GATTRIB5: Result := Result + GString(N.Attr[Prop - NPCPROP_GATTRIB1 + 1]);
  else
    Result := '';
  end;
end;

procedure TNpcManager.FlushProps(N: TNpc);
var
  S: string;
  I: Integer;
begin
  S := '';
  for I := 0 to NpcPropLastNwb2 do
    if N.Dirty[I] then
    begin
      S := S + PropBytes(N, I);
      N.Dirty[I] := False;
    end;
  if S <> '' then World.Send(PLI_NPCPROPS_ID, GInt3(N.Id) + S);
end;

function TNpcManager.Receive(Id: Integer; const Data: string): Boolean;
var
  R: TGReader;
  NId, Eq: Integer;
  N: TNpc;
  IsNew: Boolean;
  S: string;
begin
  Result := True;
  case Id of
    PLO_NPCPROPS_ID:
      begin
        R := TGReader.Create(Data);
        try
          if R.Remaining <= 2 then Exit;
          NId := R.ReadGInt3;
          if NId <= 0 then Exit;
          N := FindById(NId);
          IsNew := N = nil;
          if IsNew then N := Add(NId, 0, 0, '', '');
          ApplyProps(N, R, True);
          if IsNew then
          begin
            Fire(N, 'created');
            Fire(N, 'playerenters');
            RemoveGone;
          end;
        finally
          R.Free;
        end;
      end;
    PLO_NPCDEL_ID:
      begin
        R := TGReader.Create(Data);
        try
          NId := R.ReadGInt3;
          N := FindById(NId);
          if N <> nil then
          begin
            N.Gone := True;
            RemoveGone;
          end;
        finally
          R.Free;
        end;
      end;
    PLO_ISLEADER_ID: IsLeader := True;
    PLO_HASNPCSERVER_ID: HasNpcServer := True;
    PLO_FLAGSET_ID:
      begin
        { adds the flag only if it is not already set }
        Eq := Pos('=', Data);
        if Eq > 0 then S := Copy(Data, 1, Eq - 1) else S := Data;
        if not HasFlag(S) then Flags.Add(Data);
      end;
    PLO_FLAGDEL_ID: PutFlag(Data, False, False);
  else
    Result := False;
  end;
end;

{ ---- flags ---- }

function FlagName(const S: string): string;
var
  Eq: Integer;
begin
  Eq := Pos('=', S);
  if Eq > 0 then Result := Copy(S, 1, Eq - 1) else Result := S;
end;

function TNpcManager.HasFlag(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to Flags.Count - 1 do
    if FlagName(Flags[I]) = Name then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure TNpcManager.PutFlag(const Name: string; On, Send: Boolean);
var
  I: Integer;
  N: string;
begin
  N := FlagName(Name);
  if N = '' then Exit;
  for I := Flags.Count - 1 downto 0 do
    if FlagName(Flags[I]) = N then Flags.Delete(I);
  if On then Flags.Add(Name);
  if Send and World.Online then
  begin
    if On then World.Send(PLI_FLAGSET_ID, Name)
    else World.Send(PLI_FLAGDEL_ID, N);
  end;
end;

function TNpcManager.TestFlag(Ctx: TGsContext; const Name: string): Boolean;
var
  N: TNpc;
begin
  N := Ctx2Npc(Ctx);
  if Name = 'visible' then Result := (N <> nil) and N.Visible
  else if Name = 'isleader' then Result := IsLeader
  else if Name = 'isweapon' then Result := False
  else if Name = 'playerismale' then Result := World.PlayerCode('gender') <> 'female'
  else if Name = 'playerisfemale' then Result := World.PlayerCode('gender') = 'female'
  else if Name = 'weaponsenabled' then Result := World.PlayerCode('weapons') <> '0'
  else if Name = 'carrying' then Result := World.PlayerCode('carrying') = '1'
  else Result := HasFlag(Name);
end;

procedure TNpcManager.SetFlag(Ctx: TGsContext; const Name: string; On: Boolean);
begin
  PutFlag(Trim(Name), On, True);
end;

{ ---- variables ---- }

function TNpcManager.GetVar(Ctx: TGsContext; const Name: string; Index: Integer;
  out V: Double): Boolean;
var
  N: TNpc;
  BX, BY, BW, BH: Double;
begin
  V := 0;
  Result := True;
  N := Ctx2Npc(Ctx);
  if Copy(Name, 1, 6) = 'player' then
  begin
    if Name = 'playerx' then V := World.PlayerX
    else if Name = 'playery' then V := World.PlayerY
    else if Name = 'playerdir' then V := World.PlayerDir
    else Result := World.GetPlayerVar(Name, V);
    if Result then Exit;
    { an unknown player* name falls through to flags }
    Result := False;
    Exit;
  end;
  if N <> nil then
  begin
    if Name = 'x' then V := N.X
    else if Name = 'y' then V := N.Y
    else if Name = 'dir' then V := N.Dir
    else if Name = 'sprite' then V := N.Sprite
    { reading "timeout" tests the event, not the time left }
    else if Name = 'width' then begin Bounds(N, BX, BY, BW, BH); V := BW; end
    else if Name = 'height' then begin Bounds(N, BX, BY, BW, BH); V := BH; end
    else if Name = 'rupees' then V := N.Rupees
    else if Name = 'darts' then V := N.Arrows
    else if Name = 'bombs' then V := N.Bombs
    else if Name = 'hearts' then V := N.Power / 2
    else if Name = 'glovepower' then V := N.GlovePower
    else if Name = 'swordpower' then V := N.SwordPower
    else if Name = 'shieldpower' then V := N.ShieldPower
    else if Name = 'hurtdx' then V := N.HurtDX
    else if Name = 'hurtdy' then V := N.HurtDY
    else if Name = 'id' then V := N.Id
    else if Name = 'ap' then V := N.AP
    else if Name = 'save' then
    begin
      if (Index >= 0) and (Index <= 9) then V := N.Save[Index];
    end
    else Result := False;
    if Result then Exit;
  end;
  Result := True;
  if Name = 'npcscount' then V := Npcs.Count
  else if Name = 'tokenscount' then V := Tokens.Count
  else if Name = 'paramscount' then begin if Ctx <> nil then V := Ctx.Params.Count; end
  else if Name = 'timevar' then V := FTick * TickSeconds
  else if Name = 'screenwidth' then V := 640
  else if Name = 'screenheight' then V := 480
  else if (Name = 'compuscount') or (Name = 'playerscount') or (Name = 'bombscount') or
    (Name = 'arrowscount') or (Name = 'itemscount') or (Name = 'exploscount') or
    (Name = 'horsescount') or (Name = 'signscount') or (Name = 'weaponscount') then
    Result := World.GetPlayerVar(Name, V)
  else
    Result := False;
end;

function TNpcManager.SetVar(Ctx: TGsContext; const Name: string; Index: Integer;
  V: Double): Boolean;
var
  N: TNpc;
  D: Integer;
begin
  Result := True;
  N := Ctx2Npc(Ctx);
  if Copy(Name, 1, 6) = 'player' then
  begin
    Result := World.SetPlayerVar(Name, V);
    if not Result then Result := (Name = 'playerx') or (Name = 'playery');
    Exit;
  end;
  if N = nil then
  begin
    Result := False;
    Exit;
  end;
  if Name = 'x' then
  begin
    N.X := V;
    N.MarkDirty(NPCPROP_X);
  end
  else if Name = 'y' then
  begin
    N.Y := V;
    N.MarkDirty(NPCPROP_Y);
  end
  else if (Name = 'dir') or (Name = 'sprite') then
  begin
    D := Trunc(V);
    if Name = 'dir' then
    begin
      N.Dir := ((D mod 4) + 4) mod 4;
      N.Sprite := N.Dir;
    end
    else
    begin
      N.Sprite := D;
      N.Dir := ((D mod 4) + 4) mod 4;
    end;
    N.MarkDirty(NPCPROP_SPRITE);
  end
  else if Name = 'timeout' then
  begin
    if V < 0 then V := 0;
    N.Timeout := V;
  end
  else if Name = 'rupees' then begin N.Rupees := Trunc(V); N.MarkDirty(NPCPROP_RUPEES); end
  else if Name = 'darts' then begin N.Arrows := Trunc(V); N.MarkDirty(NPCPROP_ARROWS); end
  else if Name = 'bombs' then begin N.Bombs := Trunc(V); N.MarkDirty(NPCPROP_BOMBS); end
  else if Name = 'hearts' then begin N.Power := Round(V * 2); N.MarkDirty(NPCPROP_POWER); end
  else if Name = 'glovepower' then begin N.GlovePower := Trunc(V); N.MarkDirty(NPCPROP_GLOVEPOWER); end
  else if Name = 'swordpower' then begin N.SwordPower := Trunc(V); N.MarkDirty(NPCPROP_SWORDIMAGE); end
  else if Name = 'shieldpower' then begin N.ShieldPower := Trunc(V); N.MarkDirty(NPCPROP_SHIELDIMAGE); end
  else if Name = 'hurtdx' then begin N.HurtDX := V; N.MarkDirty(NPCPROP_HURTDXDY); end
  else if Name = 'hurtdy' then begin N.HurtDY := V; N.MarkDirty(NPCPROP_HURTDXDY); end
  else if Name = 'ap' then begin N.AP := ClampI(Trunc(V), 0, 100); N.MarkDirty(NPCPROP_ALIGNMENT); end
  else if Name = 'save' then
  begin
    if (Index >= 0) and (Index <= 9) then
    begin
      N.Save[Index] := ClampI(Trunc(V), 0, 223);
      N.MarkDirty(NPCPROP_SAVE0 + Index);
    end;
  end
  else if (Name = 'width') or (Name = 'height') or (Name = 'id') then
    { read-only: the assignment is dropped }
  else
    Result := False;
end;

function TNpcManager.GetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
  const Member: string; out V: Double): Boolean;
var
  C: TGsContext;
  M: string;
  K: Integer;
begin
  V := 0;
  Result := False;
  if Obj = 'npcs' then
  begin
    if (Index < 0) or (Index >= Npcs.Count) then Exit;
    C := Npc(Index).Ctx;
    M := Member;
    K := -1;
    if Copy(M, 1, 5) = 'save[' then
    begin
      K := StrToIntDef(Copy(M, 6, Length(M) - 6), -1);
      M := 'save';
    end;
    Result := GetVar(C, M, K, V);
  end
  else if Obj = 'players' then
  begin
    if Index <> 0 then Exit;
    Result := GetVar(Ctx, 'player' + Member, -1, V);
  end
  else
    Result := World.GetPlayerVar(Obj + '[' + IntToStr(Index) + '].' + Member, V);
end;

function TNpcManager.SetMember(Ctx: TGsContext; const Obj: string; Index: Integer;
  const Member: string; V: Double): Boolean;
begin
  Result := False;
  if (Obj = 'npcs') and (Index >= 0) and (Index < Npcs.Count) then
    Result := SetVar(Npc(Index).Ctx, Member, -1, V)
  else if (Obj = 'players') and (Index = 0) then
    Result := SetVar(Ctx, 'player' + Member, -1, V);
end;

function TNpcManager.CallFunc(Ctx: TGsContext; const Name: string;
  const Nums: array of Double; const Strs: array of string; out V: Double): Boolean;
var
  T: Integer;
  N: TNpc;
  C: string;
begin
  V := 0;
  Result := True;
  if (Name = 'tiletype') and (Length(Nums) = 2) then
    V := World.TileType(Floor(Nums[0]), Floor(Nums[1]))
  else if (Name = 'onwall') and (Length(Nums) = 2) then
  begin
    { blocking tiles only: an NPC's own box would always be "on a wall" }
    T := World.TileType(Floor(Nums[0]), Floor(Nums[1]));
    V := Ord(T = 22);
  end
  else if (Name = 'onwater') and (Length(Nums) = 2) then
    V := Ord(World.TileType(Floor(Nums[0]), Floor(Nums[1])) = 11)
  else if (Name = 'testnpc') and (Length(Nums) = 2) then
  begin
    N := NpcAt(Nums[0], Nums[1], False);
    if N = nil then V := -1 else V := Npcs.IndexOf(N);
  end
  else if (Name = 'playersays') or (Name = 'playersays2') then
  begin
    { true during playerchats when the chat equals the text }
    C := World.PlayerChat;
    if (Ctx <> nil) and (Ctx.Event = 'playerchats') and (Length(Strs) >= 1) then
      V := Ord(LowerCase(C) = LowerCase(Strs[High(Strs)]));
  end
  else if Name = 'keydown' then
    Result := World.GetPlayerVar('keydown' + IntToStr(Trunc(Nums[0])), V)
  else if (Name = 'hasweapon') and (Length(Strs) = 1) then
    V := 0
  else if (Copy(Name, 1, 4) = 'test') and (Length(Nums) = 2) then
  begin
    { testcompu, testplayer, testbomb, ...: the world answers, -1 = none }
    if not World.GetPlayerVar(Name + '(' + FloatToStr(Nums[0]) + ',' +
      FloatToStr(Nums[1]) + ')', V) then V := -1;
  end
  else
    Result := False;
end;

{ ---- message codes ---- }

function TNpcManager.MessageCode(Ctx: TGsContext; const Code, Param: string;
  out S: string): Boolean;
var
  N: TNpc;
  I: Integer;
begin
  Result := True;
  S := '';
  N := Ctx2Npc(Ctx);
  if Code = 's' then
  begin
    { setstring stores name=value as a flag }
    for I := 0 to Flags.Count - 1 do
      if FlagName(Flags[I]) = Trim(Param) then
      begin
        S := Copy(Flags[I], Length(FlagName(Flags[I])) + 2, MaxInt);
        Exit;
      end;
  end
  else if Code = 'c' then S := World.PlayerChat
  else if Code = 'e' then
  begin
    { #e(start,len,text): part of a text }
    S := '';
  end
  else if (Code = 'f') and (N <> nil) then S := N.Image
  else if (Code = 'n') or (Code = 'a') or (Code = '1') or (Code = '2') or
    (Code = '3') or (Code = '5') or (Code = '8') or (Code = 'm') or
    (Code = 'L') or (Copy(Code, 1, 1) = 'C') or (Copy(Code, 1, 1) = 'P') then
    S := World.PlayerCode(Code)
  else
    { not a code the client expands (#b is the sign window's line break) }
    Result := False;
end;

{ ---- geometry ---- }

procedure TNpcManager.Bounds(N: TNpc; out BX, BY, BW, BH: Double);
var
  Img: TGSurface;
begin
  BX := N.X;
  BY := N.Y;
  if N.ShapeW > 0 then
  begin
    BW := N.ShapeW / 16;
    BH := N.ShapeH / 16;
  end
  else if N.Character then
  begin
    { a character stands like a player: its body box }
    BX := N.X + 0.5;
    BY := N.Y + 1;
    BW := 2;
    BH := 2;
  end
  else if N.PartSet then
  begin
    BW := N.PW / 16;
    BH := N.PH / 16;
  end
  else
  begin
    Img := World.Image(N.Image);
    if Img <> nil then
    begin
      BW := Img.Width / 16;
      BH := Img.Height / 16;
    end
    else
    begin
      BW := 0;
      BH := 0;
    end;
  end;
end;

function TNpcManager.NpcAt(PX, PY: Double; BlockingOnly: Boolean): TNpc;
var
  I: Integer;
  N: TNpc;
  BX, BY, BW, BH: Double;
begin
  for I := Npcs.Count - 1 downto 0 do
  begin
    N := Npc(I);
    if N.Gone or not N.Visible then Continue;
    if BlockingOnly and not N.Blocks then Continue;
    Bounds(N, BX, BY, BW, BH);
    if (BW > 0) and (PX >= BX) and (PX < BX + BW) and (PY >= BY) and (PY < BY + BH) then
    begin
      Result := N;
      Exit;
    end;
  end;
  Result := nil;
end;

function TNpcManager.PointBlocked(PX, PY: Double): Boolean;
begin
  Result := NpcAt(PX, PY, True) <> nil;
end;

{ ---- events from the game ---- }

procedure TNpcManager.PlayerPush(Dir: Integer; PX, PY: Double);
var
  N: TNpc;
  TX, TY: Double;
begin
  { the point just ahead of the body's front edge, on its centre line }
  TX := PX + 1.5;
  TY := PY + 2;
  case Dir and 3 of
    0: TY := PY + 0.75;
    1: TX := PX + 0.25;
    2: TY := PY + 3.25;
    3: TX := PX + 2.75;
  end;
  N := NpcAt(TX, TY, True);
  if N <> nil then
  begin
    Fire(N, 'playertouchsme');
    RemoveGone;
  end;
end;

procedure TNpcManager.PlayerMoved(PX, PY: Double);
var
  I: Integer;
  N: TNpc;
  BX, BY, BW, BH: Double;
begin
  { walking over an NPC that does not block touches it too }
  I := 0;
  while I < Npcs.Count do
  begin
    N := Npc(I);
    Inc(I);
    if N.Gone or not N.Visible or N.Blocks then Continue;
    Bounds(N, BX, BY, BW, BH);
    if BW <= 0 then Continue;
    if (PX + 2.5 > BX) and (PX + 0.5 < BX + BW) and (PY + 3 > BY) and (PY + 1 < BY + BH) then
      Fire(N, 'playertouchsme');
  end;
  RemoveGone;
end;

procedure TNpcManager.PlayerChats(const Text: string);
begin
  FireAll('playerchats');
end;

procedure TNpcManager.PlayerEndsReading;
begin
  FireAll('playerendsreading');
end;

procedure TNpcManager.SwordHit(X, Y, W, H, Power: Double);
var
  I: Integer;
  N: TNpc;
  BX, BY, BW, BH: Double;
begin
  I := 0;
  while I < Npcs.Count do
  begin
    N := Npc(I);
    Inc(I);
    if N.Gone or not N.Visible then Continue;
    Bounds(N, BX, BY, BW, BH);
    if BW <= 0 then Continue;
    if (X < BX + BW) and (X + W > BX) and (Y < BY + BH) and (Y + H > BY) then
      Fire(N, 'washit');
  end;
  RemoveGone;
end;

procedure TNpcManager.BombBlast(X, Y, Radius: Double);
var
  I: Integer;
  N: TNpc;
  BX, BY, BW, BH: Double;
begin
  I := 0;
  while I < Npcs.Count do
  begin
    N := Npc(I);
    Inc(I);
    if N.Gone or not N.Visible then Continue;
    Bounds(N, BX, BY, BW, BH);
    if BW <= 0 then Continue;
    if (X - Radius < BX + BW) and (X + Radius > BX) and (Y - Radius < BY + BH) and (Y + Radius > BY) then
      Fire(N, 'exploded');
  end;
  RemoveGone;
end;

function TNpcManager.ArrowHit(X, Y, Power: Double): Boolean;
var
  N: TNpc;
begin
  N := NpcAt(X, Y, False);
  Result := N <> nil;
  if N <> nil then
  begin
    Fire(N, 'wasshot');
    RemoveGone;
  end;
end;

{ ---- the tick ---- }

procedure TNpcManager.Tick;
var
  I: Integer;
  N: TNpc;
  RunTimeouts: Boolean;
begin
  Inc(FTick);
  if FTouchCool > 0 then Dec(FTouchCool);
  RunTimeouts := IsLeader or not World.Online;
  I := 0;
  while I < Npcs.Count do
  begin
    N := Npc(I);
    Inc(I);
    if N.Gone then Continue;
    if N.MoveTicks > 0 then
    begin
      N.X := N.X + N.MoveDX;
      N.Y := N.Y + N.MoveDY;
      Dec(N.MoveTicks);
      if (N.MoveTicks = 0) and N.MoveEvent then Fire(N, 'movementfinished');
    end;
    if N.Timeout > 0 then
    begin
      N.Timeout := N.Timeout - TickSeconds;
      if N.Timeout <= 0.0001 then
      begin
        N.Timeout := 0;
        if RunTimeouts or N.TimerEverywhere then Fire(N, 'timeout');
      end;
    end;
  end;
  RemoveGone;
  World.Idle;
end;

{ ---- commands ---- }

procedure TNpcManager.SetVisible(N: TNpc; On, Local: Boolean);
begin
  if On then N.VisFlags := N.VisFlags or VisVisible
  else N.VisFlags := N.VisFlags and not VisVisible;
  if not Local then N.MarkDirty(NPCPROP_VISFLAGS);
end;

function TNpcManager.CharProp(N: TNpc; const Code, Value: string): Boolean;
var
  C, K: Integer;
  Cd: string;
begin
  Result := True;
  Cd := Trim(Code);
  if Cd = '#1' then begin N.SwordImage := Value; N.MarkDirty(NPCPROP_SWORDIMAGE); end
  else if Cd = '#2' then begin N.ShieldImage := Value; N.MarkDirty(NPCPROP_SHIELDIMAGE); end
  else if Cd = '#3' then begin N.HeadImage := Value; N.MarkDirty(NPCPROP_HEADIMAGE); end
  else if Cd = '#5' then begin N.HorseImage := Value; N.MarkDirty(NPCPROP_HORSEIMAGE); end
  else if Cd = '#8' then begin N.BodyImage := Value; N.MarkDirty(NPCPROP_BODYIMAGE); end
  else if Cd = '#n' then begin N.Nickname := Value; N.MarkDirty(NPCPROP_NICKNAME); end
  else if Cd = '#c' then
  begin
    { the chat bubble; an empty text leaves it as it was on 2.05 (NPC lab
      run 2026-11-04: talker) }
    if Value <> '' then N.Chat := Value;
  end
  else if (Length(Cd) = 3) and (Copy(Cd, 1, 2) = '#C') and (Cd[3] in ['0'..'4']) then
  begin
    C := ColorIndexOf(Value);
    if C >= 0 then
    begin
      N.Colors[Ord(Cd[3]) - Ord('0')] := C;
      N.MarkDirty(NPCPROP_COLORS);
    end;
  end
  else if (Length(Cd) = 3) and (Copy(Cd, 1, 2) = '#P') and (Cd[3] in ['1'..'5']) then
  begin
    K := Ord(Cd[3]) - Ord('0');
    N.Attr[K] := Value;
    N.MarkDirty(NPCPROP_GATTRIB1 + K - 1);
  end
  else
    Result := False;
end;

function TNpcManager.FindImg(N: TNpc; Index: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(N.ShownImages) do
    if N.ShownImages[I].Index = Index then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure TNpcManager.ShowImg(N: TNpc; Index: Integer; const Img: string; X, Y: Double);
var
  I: Integer;
begin
  I := FindImg(N, Index);
  if I < 0 then
  begin
    I := Length(N.ShownImages);
    SetLength(N.ShownImages, I + 1);
    N.ShownImages[I].Index := Index;
    N.ShownImages[I].Layer := 1;
    N.ShownImages[I].PartSet := False;
    N.ShownImages[I].Image := '';
  end;
  if N.ShownImages[I].Image <> Img then N.ShownImages[I].PartSet := False;
  N.ShownImages[I].Image := Img;
  N.ShownImages[I].X := X;
  N.ShownImages[I].Y := Y;
end;

function ActionParams(const S: string): string;
begin
  if S <> '' then Result := ',' + S else Result := '';
end;

function TNpcManager.Command(Ctx: TGsContext; Op: Integer; const A: TGsArgs): Boolean;
var
  N, M: TNpc;
  I: Integer;
  CX, CY, BX, BY, BW, BH: Double;
begin
  Result := False;
  N := Ctx2Npc(Ctx);
  if N = nil then Exit;
  Bounds(N, BX, BY, BW, BH);
  CX := BX + BW / 2;
  CY := BY + BH / 2;
  case Op of
    GsOpSay: World.ShowSign(Trunc(A.Num[0]));
    GsOpSay2: World.Say2(A.Str[0]);
    GsOpMessage:
      begin
        N.Message := A.Str[0];
        N.TimerShow := False;
        N.MarkDirty(NPCPROP_MESSAGE);
      end;
    GsOpPlay: World.PlaySound(A.Str[0], N.X, N.Y, False);
    702 { playlooped }: World.PlaySound(A.Str[0], N.X, N.Y, True);
    703 { stopsound }: World.StopSound(A.Str[0]);
    GsOpSetGif, GsOpSetImg:
      begin
        N.Image := A.Str[0];
        N.PartSet := False;
        SetVisible(N, True, False);
        N.MarkDirty(NPCPROP_IMAGE);
      end;
    680, GsOpSetImgPart:
      begin
        N.Image := A.Str[0];
        N.PX := ClampI(Trunc(A.Num[1]), 0, 16000);
        N.PY := ClampI(Trunc(A.Num[2]), 0, 16000);
        N.PW := ClampI(Trunc(A.Num[3]), 0, 220);
        N.PH := ClampI(Trunc(A.Num[4]), 0, 220);
        N.PartSet := True;
        SetVisible(N, True, False);
        N.MarkDirty(NPCPROP_IMAGE);
        N.MarkDirty(NPCPROP_IMAGEPART);
      end;
    GsOpShow: SetVisible(N, True, False);
    GsOpShowLocal: SetVisible(N, True, True);
    GsOpHide, GsOpHideLocal: SetVisible(N, False, Op = GsOpHideLocal);
    GsOpDontBlock, GsOpDontBlockLocal:
      begin
        N.BlockFlags := N.BlockFlags or BlockNone;
        if Op = GsOpDontBlock then N.MarkDirty(NPCPROP_BLOCKFLAGS);
      end;
    GsOpBlockAgain, GsOpBlockAgainLocal:
      begin
        N.BlockFlags := N.BlockFlags and not BlockNone;
        N.Layer := 0;
        N.VisFlags := N.VisFlags and not (VisOver or VisUnder);
        if Op = GsOpBlockAgain then
        begin
          N.MarkDirty(NPCPROP_BLOCKFLAGS);
          N.MarkDirty(NPCPROP_VISFLAGS);
        end;
      end;
    GsOpDrawOverPlayer:
      begin
        N.Layer := 1;
        N.VisFlags := (N.VisFlags or VisOver) and not VisUnder;
        N.MarkDirty(NPCPROP_VISFLAGS);
      end;
    GsOpDrawUnderPlayer:
      begin
        N.Layer := -1;
        N.VisFlags := (N.VisFlags or VisUnder) and not VisOver;
        N.MarkDirty(NPCPROP_VISFLAGS);
      end;
    GsOpDrawAsLight: N.Layer := 9;
    727, 728:
      { setcoloreffect, setzoomeffect: online only with an NPC server }
      if not World.Online or HasNpcServer then
        if Op = 727 then
        begin
          N.EffR := ClampF(A.Num[0], 0, 1);
          N.EffG := ClampF(A.Num[1], 0, 1);
          N.EffB := ClampF(A.Num[2], 0, 1);
          N.EffA := ClampF(A.Num[3], 0, 1);
        end
        else
          N.Zoom := ClampF(A.Num[0], 0.01, 16);
    GsOpCanBeCarried: N.CanCarry := True;
    GsOpCannotBeCarried: N.CanCarry := False;
    GsOpCanBePushed: N.CanPush := True;
    GsOpCannotBePushed: N.CanPush := False;
    GsOpCanBePulled: N.CanPull := True;
    GsOpCannotBePulled: N.CanPull := False;
    GsOpTimerShow: N.TimerShow := True;
    GsOpTimerEverywhere: N.TimerEverywhere := True;
    GsOpSetShape:
      if Trunc(A.Num[0]) in [0, 1] then
      begin
        N.ShapeW := ClampI(Trunc(A.Num[1]), 0, 4096);
        N.ShapeH := ClampI(Trunc(A.Num[2]), 0, 4096);
      end;
    GsOpShowCharacter:
      if not N.Character then
      begin
        N.Character := True;
        N.Image := '#c#';
        N.MarkDirty(NPCPROP_IMAGE);
      end;
    GsOpSetCharProp: CharProp(N, A.Str[0], A.Str[1]);
    GsOpSetCharAni:
      begin
        if A.Str[0] <> N.Gani then N.GaniStart := FTick;
        N.Gani := A.Str[0];
        N.GaniParams := A.Str[1];
        N.MarkDirty(NPCPROP_GANI);
      end;
    733 { setchargender }: N.Male := LowerCase(A.Str[0]) = 'male';
    GsOpSetPlayerProp: World.SetPlayerProp(Trim(A.Str[0]), A.Str[1]);
    GsOpSetAni: World.SetPlayerAni(A.Str[0], A.Str[1]);
    GsOpHurt: World.HurtPlayer(A.Num[0], CX, CY);
    GsOpFreezePlayer: World.FreezePlayer(ClampF(A.Num[0], 0, 30));
    GsOpSetLevel:
      begin
        World.Warp(A.Str[0], World.PlayerX, World.PlayerY);
        Result := True;
      end;
    GsOpSetLevel2:
      begin
        World.Warp(A.Str[0], A.Num[1], A.Num[2]);
        Result := True;
      end;
    GsOpDestroy:
      begin
        N.Gone := True;
        if World.Online and not N.Local and (N.Id > 0) then
          World.Send(PLI_NPCDEL_ID, GInt3(N.Id));
        Result := True;
      end;
    GsOpLay:
      if A.Num[0] >= 0 then
      begin
        { next to the NPC: to the right or below, away from the player }
        if Abs(World.PlayerX - N.X) > Abs(World.PlayerY - N.Y) then
          World.LayItem(Trunc(A.Num[0]), N.X + 2, N.Y)
        else
          World.LayItem(Trunc(A.Num[0]), N.X, N.Y + 2);
      end;
    GsOpLay2:
      if A.Num[0] >= 0 then World.LayItem(Trunc(A.Num[0]), A.Num[1], A.Num[2]);
    GsOpPutComp:
      if A.Num[0] >= 0 then World.PutBaddy(Trunc(A.Num[0]), A.Num[1], A.Num[2], '', 0);
    GsOpPutNewComp:
      if A.Num[0] >= 0 then
        World.PutBaddy(Trunc(A.Num[0]), A.Num[1], A.Num[2], A.Str[3], Trunc(A.Num[4]));
    GsOpPutNpc:
      if World.Online then
        World.Send(PLI_PUTNPC_ID, GString(A.Str[0]) + GString(A.Str[1]) +
          GChar(ClampI(Round(A.Num[2] * 2), 0, 223)) + GChar(ClampI(Round(A.Num[3] * 2), 0, 223)))
      else
      begin
        M := Add(0, A.Num[2], A.Num[3], A.Str[0], World.PlayerCode('file:' + A.Str[1]));
        M.Local := True;
        Fire(M, 'playerenters');
      end;
    GsOpSleep:
      if A.Num[0] > 0 then N.Timeout := A.Num[0];
    GsOpMove:
      begin
        { dx, dy over time seconds; option 8: event when done }
        I := Max(1, Round(A.Num[2] / TickSeconds));
        N.MoveDX := A.Num[0] / I;
        N.MoveDY := A.Num[1] / I;
        N.MoveTicks := I;
        N.MoveEvent := Trunc(A.Num[3]) and 8 <> 0;
        N.MarkDirty(NPCPROP_X);
        N.MarkDirty(NPCPROP_Y);
      end;
    GsOpSetString:
      if A.Str[1] = '' then PutFlag(A.Str[0], False, True)
      else PutFlag(A.Str[0] + '=' + A.Str[1], True, True);
    GsOpCallNpc:
      begin
        I := Trunc(A.Num[0]);
        if (I >= 0) and (I < Npcs.Count) then
        begin
          M := Npc(I);
          if (M.Ctx <> nil) and not M.Ctx.Running then
            M.Ctx.Run(LowerCase(A.Str[1]));
        end;
      end;
    GsOpHitNpc:
      begin
        I := Trunc(A.Num[0]);
        if (I >= 0) and (I < Npcs.Count) and not Npc(I).Ctx.Running then
          Npc(I).Ctx.Run('washit');
      end;
    GsOpShootArrow: World.Shoot('arrow', N.X, N.Y, Trunc(A.Num[0]) and 3);
    624: World.Shoot('fireball', N.X, N.Y, Trunc(A.Num[0]) and 3);
    625: World.Shoot('fireblast', N.X, N.Y, Trunc(A.Num[0]) and 3);
    626: World.Shoot('nuke', N.X, N.Y, Trunc(A.Num[0]) and 3);
    630: World.Shoot('ball', CX, CY, -1);
    627: World.PutBomb(ClampI(Trunc(A.Num[0]), 0, 2), A.Num[1], A.Num[2]);
    628: World.PutExplosion(1, A.Num[0], A.Num[1], A.Num[2]);
    722: World.PutExplosion(A.Num[0], A.Num[1], A.Num[2], A.Num[3]);
    629: World.PutLeaps(ClampI(Trunc(A.Num[0]), 0, 5), A.Num[1], A.Num[2]);
    GsOpShowImg: ShowImg(N, Trunc(A.Num[0]), A.Str[1], A.Num[2], A.Num[3]);
    GsOpHideImg:
      begin
        I := FindImg(N, Trunc(A.Num[0]));
        if I >= 0 then
        begin
          N.ShownImages[I] := N.ShownImages[High(N.ShownImages)];
          SetLength(N.ShownImages, Length(N.ShownImages) - 1);
        end;
      end;
    GsOpChangeImgPart:
      begin
        I := FindImg(N, Trunc(A.Num[0]));
        if I >= 0 then
        begin
          N.ShownImages[I].PX := ClampI(Trunc(A.Num[1]), 0, 16000);
          N.ShownImages[I].PY := ClampI(Trunc(A.Num[2]), 0, 16000);
          N.ShownImages[I].PW := ClampI(Trunc(A.Num[3]), 0, 220);
          N.ShownImages[I].PH := ClampI(Trunc(A.Num[4]), 0, 220);
          N.ShownImages[I].PartSet := True;
        end;
      end;
    GsOpChangeImgVis:
      begin
        I := FindImg(N, Trunc(A.Num[0]));
        if I >= 0 then N.ShownImages[I].Layer := ClampI(Trunc(A.Num[1]), 0, 4);
      end;
    GsOpToInventory:
      begin
        PutFlag(A.Str[0], True, True);
        SetVisible(N, False, False);
        if not World.Online then Result := True;
      end;
    GsOpTriggerAction:
      if World.Online then
        World.Send(PLI_TRIGGERACTION_ID, GInt3(Max(N.Id, 0)) +
          GChar(ClampI(Round(A.Num[0] * 2), 0, 223)) +
          GChar(ClampI(Round(A.Num[1] * 2), 0, 223)) + A.Str[2] +
          ActionParams(A.Str[3]));
  else
    { the player's own state: colours, head, sword, weapons, stats, ... }
    World.PlayerCommand(Op, A);
  end;
end;

{ ---- drawing ---- }

{ An image part with a colour multiply, zoom around its centre, and either
  alpha blending or adding light (drawaslight). }
procedure DrawEffect(Screen, Img: TGSurface; SX, SY, W, H, DX, DY: Integer;
  N: TNpc; Light: Boolean);
var
  OW, OH, X, Y, TX, TY, I, J: Integer;
  C, D: Cardinal;
  A, R, G, B, DR, DG, DB: Double;
begin
  OW := Round(W * N.Zoom);
  OH := Round(H * N.Zoom);
  { the zoom keeps the centre where it was }
  DX := DX + (W - OW) div 2;
  DY := DY + (H - OH) div 2;
  for J := 0 to OH - 1 do
  begin
    Y := DY + J;
    if (Y < 0) or (Y >= Screen.Height) then Continue;
    TY := SY + Trunc(J / N.Zoom);
    if (TY < 0) or (TY >= Img.Height) then Continue;
    for I := 0 to OW - 1 do
    begin
      X := DX + I;
      if (X < 0) or (X >= Screen.Width) then Continue;
      TX := SX + Trunc(I / N.Zoom);
      if (TX < 0) or (TX >= Img.Width) then Continue;
      C := Img.Pixels[TX + TY * Img.Width];
      A := (C shr 24) / 255 * N.EffA;
      if A <= 0 then Continue;
      R := ((C shr 16) and $FF) * N.EffR;
      G := ((C shr 8) and $FF) * N.EffG;
      B := (C and $FF) * N.EffB;
      D := Screen.Pixels[X + Y * Screen.Width];
      DR := (D shr 16) and $FF;
      DG := (D shr 8) and $FF;
      DB := D and $FF;
      if Light then
      begin
        DR := Min(255, DR + R * A);
        DG := Min(255, DG + G * A);
        DB := Min(255, DB + B * A);
      end
      else
      begin
        DR := DR + (R - DR) * A;
        DG := DG + (G - DG) * A;
        DB := DB + (B - DB) * A;
      end;
      Screen.Pixels[X + Y * Screen.Width] := $FF000000 or (Cardinal(Round(DR)) shl 16) or
        (Cardinal(Round(DG)) shl 8) or Cardinal(Round(DB));
    end;
  end;
end;

procedure TNpcManager.Draw(Screen: TGSurface; CamX, CamY: Integer; Over: Boolean);
var
  I, K, DX, DY, TW, SX, SY, SW, SH: Integer;
  N: TNpc;
  Img: TGSurface;
  S: string;
begin
  for I := 0 to Npcs.Count - 1 do
  begin
    N := Npc(I);
    if N.Gone or not N.Visible then Continue;
    if Over <> (N.Layer > 0) then Continue;
    DX := Round(N.X * 16) - CamX;
    DY := Round(N.Y * 16) - CamY;
    if N.Character then
      World.DrawCharacter(N, Screen, DX, DY, FTick - N.GaniStart)
    else
    begin
      Img := World.Image(N.Image);
      if Img <> nil then
      begin
        if N.PartSet then
        begin
          SX := N.PX;
          SY := N.PY;
          SW := Min(N.PW, Img.Width - N.PX);
          SH := Min(N.PH, Img.Height - N.PY);
        end
        else
        begin
          SX := 0;
          SY := 0;
          SW := Img.Width;
          SH := Img.Height;
        end;
        if (N.Layer = 9) or (N.Zoom <> 1) or (N.EffR <> 1) or (N.EffG <> 1) or
          (N.EffB <> 1) or (N.EffA <> 1) then
          DrawEffect(Screen, Img, SX, SY, SW, SH, DX, DY, N, N.Layer = 9)
        else
          Screen.Blit(Img, SX, SY, SW, SH, DX, DY);
      end;
    end;
    for K := 0 to High(N.ShownImages) do
    begin
      Img := World.Image(N.ShownImages[K].Image);
      if Img = nil then Continue;
      if N.ShownImages[K].PartSet then
        Screen.Blit(Img, N.ShownImages[K].PX, N.ShownImages[K].PY,
          Min(N.ShownImages[K].PW, Img.Width - N.ShownImages[K].PX),
          Min(N.ShownImages[K].PH, Img.Height - N.ShownImages[K].PY),
          Round(N.ShownImages[K].X * 16) - CamX, Round(N.ShownImages[K].Y * 16) - CamY)
      else
        Screen.Blit(Img, 0, 0, Img.Width, Img.Height,
          Round(N.ShownImages[K].X * 16) - CamX, Round(N.ShownImages[K].Y * 16) - CamY);
    end;
    { the message, or the timer, centred over the NPC }
    S := N.Message;
    if N.TimerShow and (N.Timeout > 0) then S := IntToStr(Ceil(N.Timeout));
    if (S = '') and N.Character then S := N.Chat;
    if S <> '' then
    begin
      TW := TextWidth(S, 1);
      DrawText(Screen, DX + 24 - TW div 2, DY - 10, S, $FFFFFFFF, 1);
    end;
  end;
end;

end.
