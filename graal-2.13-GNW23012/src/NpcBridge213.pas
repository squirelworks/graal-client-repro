{ NpcBridge213: connects the NPC scripts (Npc213) to the game (TAdventure).

  TAdventureNpcWorld answers the NPC manager's questions about the player
  and the level, and carries script commands into the game: hurt, items,
  warps, explosions, the player's look. The game's combat events (sword
  swings, bomb blasts, arrows) come in here too and go on to the NPCs.
  Things the game does not model yet (signs, sound, projectiles) are
  logged. }
unit NpcBridge213;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, SysUtils, GNumText, Math, GTypes, GLevel, GSurface, GArrays, GFont, GGs1, Npc213,
  Baddy213, Adventure, GCompat;

type
  TAdventureNpcWorld = class(TNpcWorld)
  private
    FAdv: TAdventure;
    FWarpLevel: string;
    FWarpX, FWarpY: Double;
    FWarpPending: Boolean;
    FWasReading: Boolean;
  public
    constructor Create(Adv: TAdventure);
    function Online: Boolean; override;
    function PlayerX: Double; override;
    function PlayerY: Double; override;
    function PlayerDir: Integer; override;
    function GetPlayerVar(const Name: string; out V: Double): Boolean; override;
    function SetPlayerVar(const Name: string; V: Double): Boolean; override;
    function PlayerChat: string; override;
    function PlayerCode(const Code: string): string; override;
    function Image(const Name: string): TGSurface; override;
    function TileType(X, Y: Integer): Integer; override;
    procedure DrawCharacter(N: TNpc; Screen: TGSurface; DX, DY, Tick: Integer); override;
    procedure HurtPlayer(Power, FromX, FromY: Double); override;
    procedure ShowSign(Index: Integer); override;
    procedure Say2(const Text: string); override;
    procedure Warp(const Level: string; X, Y: Double); override;
    procedure LayItem(Item: Integer; X, Y: Double); override;
    procedure PlaySound(const Name: string; X, Y: Double; Looped: Boolean); override;
    procedure PutExplosion(Power, Radius, X, Y: Double); override;
    procedure PutBaddy(Kind: Integer; X, Y: Double; const Img: string; Power: Integer); override;
    procedure Shoot(const Kind: string; X, Y: Double; Dir: Integer); override;
    procedure SetPlayerProp(const Code, Value: string); override;
    procedure SetPlayerAni(const Gani, Params: string); override;
    procedure PlayerCommand(Op: Integer; const A: TGsArgs); override;
    procedure Send(Id: Integer; const Data: string); override;
    procedure Log(const S: string); override;
    procedure Idle; override;
    { the game's combat events }
    procedure SwordHit(X, Y, W, H: Double; Power: Integer);
    procedure BombBlast(X, Y: Double; Radius: Integer);
    function ArrowHit(X, Y: Double; Power: Integer): Boolean;
  end;

  { The baddies' view of the game. }
  TAdventureBaddyWorld = class(TBaddyWorld)
  private
    FAdv: TAdventure;
  public
    constructor Create(Adv: TAdventure);
    function Online: Boolean; override;
    function Leader: Boolean; override;
    function PlayerX: Double; override;
    function PlayerY: Double; override;
    function PlayerDir: Integer; override;
    function PlayerHere: Boolean; override;
    function Blocked(X, Y: Double): Boolean; override;
    procedure HurtPlayer(Hearts, FromX, FromY: Double); override;
    procedure Shoot(X, Y: Double; Dir, Sprite, Kind: Integer); override;
    procedure Send(Id: Integer; const Data: string); override;
    function Image(const Name: string): TGSurface; override;
    function Arrays: TGArrays; override;
    procedure DrawVerse(Screen: TGSurface; CX, Y: Integer; const Text: string); override;
    procedure AllDied; override;
  end;

{ The NPC manager for a game, with its combat events hooked up. }
function CreateNpcManager(Adv: TAdventure): TNpcManager;
{ The baddies of a game. }
function CreateBaddyManager(Adv: TAdventure): TBaddyManager;

implementation

function CreateNpcManager(Adv: TAdventure): TNpcManager;
var
  W: TAdventureNpcWorld;
begin
  W := TAdventureNpcWorld.Create(Adv);
  Result := TNpcManager.Create(W);
  Result.OwnsWorld := True;
  Adv.OnSwordHit := W.SwordHit;
  Adv.OnBombBlast := W.BombBlast;
  Adv.OnArrowHit := W.ArrowHit;
end;

function CreateBaddyManager(Adv: TAdventure): TBaddyManager;
begin
  Result := TBaddyManager.Create(TAdventureBaddyWorld.Create(Adv));
end;

constructor TAdventureNpcWorld.Create(Adv: TAdventure);
begin
  inherited Create;
  FAdv := Adv;
end;

function TAdventureNpcWorld.Online: Boolean;
begin
  Result := FAdv.IsOnline;
end;

function TAdventureNpcWorld.PlayerX: Double;
begin
  Result := FAdv.Player.X;
end;

function TAdventureNpcWorld.PlayerY: Double;
begin
  Result := FAdv.Player.Y;
end;

function TAdventureNpcWorld.PlayerDir: Integer;
begin
  Result := FAdv.Player.Dir;
end;

function TAdventureNpcWorld.GetPlayerVar(const Name: string; out V: Double): Boolean;
var
  P: TServerPlayer;
begin
  P := FAdv.Player;
  Result := True;
  if Name = 'playerrupees' then V := P.Rupees
  else if Name = 'playerdarts' then V := P.Arrows
  else if Name = 'playerbombs' then V := P.Bombs
  else if Name = 'playerhearts' then V := P.Power / 2
  else if Name = 'playerfullhearts' then V := P.MaxPower
  else if Name = 'playerglovepower' then V := P.GlovePower
  else if Name = 'playerbombpower' then V := P.BombPower
  else if Name = 'playerswordpower' then V := P.SwordPower
  else if Name = 'playershieldpower' then V := P.ShieldPower
  else if Name = 'playerap' then V := FAdv.AP
  else if Name = 'playersprite' then V := FAdv.OwnSprite div 4
  else if Name = 'playerid' then V := P.Id
  else if Name = 'playerscount' then V := FAdv.OtherCount + 1
  else if Name = 'itemscount' then V := Length(FAdv.Items)
  else if Name = 'compuscount' then V := 0
  else
  begin
    V := 0;
    Result := False;
  end;
end;

function TAdventureNpcWorld.SetPlayerVar(const Name: string; V: Double): Boolean;
var
  P: TServerPlayer;
begin
  P := FAdv.Player;
  Result := True;
  if Name = 'playerx' then P.X := V
  else if Name = 'playery' then P.Y := V
  else if Name = 'playerdir' then P.Dir := ((Trunc(V) mod 4) + 4) mod 4
  else if Name = 'playerrupees' then P.Rupees := Max(0, Min(9999999, Trunc(V)))
  else if Name = 'playerdarts' then P.Arrows := Max(0, Min(99, Trunc(V)))
  else if Name = 'playerbombs' then P.Bombs := Max(0, Min(99, Trunc(V)))
  else if Name = 'playerhearts' then
    P.Power := Max(0, Min(P.MaxPower * 2, Round(V * 2)))
  else if Name = 'playerfullhearts' then
  begin
    P.MaxPower := Max(1, Min(20, Trunc(V)));
    if P.Power > P.MaxPower * 2 then P.Power := P.MaxPower * 2;
  end
  else if Name = 'playerglovepower' then P.GlovePower := Max(0, Min(3, Trunc(V)))
  else if Name = 'playerswordpower' then P.SwordPower := Max(0, Min(4, Trunc(V)))
  else if Name = 'playershieldpower' then P.ShieldPower := Max(0, Min(3, Trunc(V)))
  else if Name = 'playerbombpower' then P.BombPower := Max(0, Min(3, Trunc(V)))
  else if Name = 'playerap' then FAdv.AP := Max(0, Min(100, Trunc(V)))
  else Result := False;
end;

function TAdventureNpcWorld.PlayerChat: string;
begin
  Result := FAdv.Player.Chat;
end;

function TAdventureNpcWorld.PlayerCode(const Code: string): string;
var
  P: TServerPlayer;
  K: Integer;
begin
  P := FAdv.Player;
  Result := '';
  if Code = 'n' then Result := P.Nickname
  else if Code = 'a' then Result := P.Account
  else if Code = '1' then Result := P.SwordImage
  else if Code = '2' then Result := P.ShieldImage
  else if Code = '3' then Result := P.HeadImage
  else if Code = '8' then Result := P.BodyImage
  else if Code = 'L' then Result := P.Level
  else if Code = 'm' then Result := P.AniName
  else if (Length(Code) = 2) and (Code[1] = 'C') and (Code[2] in ['0'..'4']) then
  begin
    K := P.Colors[Ord(Code[2]) - Ord('0')];
    if (K >= 0) and (K <= 19) then Result := GsColorNames[K];
  end
  else if (Length(Code) = 2) and (Code[1] = 'P') and (Code[2] in ['1'..'5']) then
    Result := P.Attr[Ord(Code[2]) - Ord('0')]
  else if Code = 'weapons' then
  begin
    if FAdv.WeaponsOn then Result := '1' else Result := '0';
  end
  else if Code = 'carrying' then
  begin
    if FAdv.CarryKind >= 0 then Result := '1' else Result := '0';
  end;
end;

function TAdventureNpcWorld.Image(const Name: string): TGSurface;
begin
  Result := FAdv.Assets.Image(Name, '');
end;

function TAdventureNpcWorld.TileType(X, Y: Integer): Integer;
begin
  { only walls are told apart yet: 22 blocking, 0 free }
  if (X < 0) or (Y < 0) or (X >= BoardW) or (Y >= BoardH) then
    Result := 0
  else if FAdv.Arrays.TilePassable(FAdv.Level.Tile(X, Y)) then
    Result := 0
  else
    Result := 22;
end;

type
  TNpcCharacter = class(TServerPlayer)
  end;

procedure TAdventureNpcWorld.DrawCharacter(N: TNpc; Screen: TGSurface; DX, DY, Tick: Integer);
var
  P: TServerPlayer;
  I: Integer;
begin
  if not (N.CharObj is TServerPlayer) then
  begin
    N.CharObj.Free;
    N.CharObj := TNpcCharacter.Create;
  end;
  P := TServerPlayer(N.CharObj);
  P.X := N.X;
  P.Y := N.Y;
  P.Dir := N.Dir and 3;
  P.HeadImage := N.HeadImage;
  P.BodyImage := N.BodyImage;
  P.SwordImage := N.SwordImage;
  P.ShieldImage := N.ShieldImage;
  for I := 0 to 4 do P.Colors[I] := N.Colors[I];
  for I := 1 to 5 do P.Attr[I] := N.Attr[I];
  if N.Gani <> '' then P.AniName := N.Gani else P.AniName := 'idle';
  P.AniStart := FAdv.Frame - Tick;
  P.FixedStep := -1;
  FAdv.DrawPlayer(P, Round(N.X * 16) - DX, Round(N.Y * 16) - DY);
end;

procedure TAdventureNpcWorld.HurtPlayer(Power, FromX, FromY: Double);
begin
  { GS1 hurt counts half hearts }
  if Power > 0 then FAdv.HurtFrom(Power / 2, FromX, FromY)
  else if Power < 0 then
    FAdv.Player.Power := Min(FAdv.Player.MaxPower * 2, FAdv.Player.Power - Round(Power));
end;

procedure TAdventureNpcWorld.ShowSign(Index: Integer);
begin
  { skipped while a sign is already open }
  if FAdv.Reading then Exit;
  if (Index >= 0) and (Index <= High(FAdv.Level.Signs)) then
  begin
    FAdv.ReadSign(FAdv.Level.Signs[Index].Text);
    FWasReading := True;
  end;
end;

procedure TAdventureNpcWorld.Say2(const Text: string);
begin
  if FAdv.Reading then Exit;
  { #b breaks the line }
  FAdv.ReadSign(StringReplace(Text, '#b', #10, [rfReplaceAll]));
  FWasReading := True;
end;

procedure TAdventureNpcWorld.Warp(const Level: string; X, Y: Double);
begin
  { taken after the scripts of this tick have run: an offline warp loads
    a new level, which replaces the NPCs }
  FWarpLevel := Level;
  FWarpX := X;
  FWarpY := Y;
  FWarpPending := True;
end;

procedure TAdventureNpcWorld.Idle;
var
  L: TLevelLink;
begin
  { a sign an NPC opened was closed: playerendsreading }
  if FWasReading and not FAdv.Reading then
  begin
    FWasReading := False;
    FAdv.Npcs.PlayerEndsReading;
  end;
  if not FWarpPending then Exit;
  FWarpPending := False;
  { the warp goes the way a level link does }
  L.Dest := FWarpLevel;
  L.X := 0;
  L.Y := 0;
  L.W := 0;
  L.H := 0;
  L.NewX := DotFloatToText(FWarpX, 15);
  L.NewY := DotFloatToText(FWarpY, 15);
  SetLength(FAdv.Level.Links, Length(FAdv.Level.Links) + 1);
  FAdv.Level.Links[High(FAdv.Level.Links)] := L;
  if not FAdv.FollowLink(High(FAdv.Level.Links)) then
    FAdv.Log('setlevel2 ' + FWarpLevel + ': failed');
  { online the level stays until the server answers: drop the stand-in }
  if (Length(FAdv.Level.Links) > 0) and (FAdv.Level.Links[High(FAdv.Level.Links)].Dest = FWarpLevel) and
    (FAdv.Level.Links[High(FAdv.Level.Links)].W = 0) then
    SetLength(FAdv.Level.Links, Length(FAdv.Level.Links) - 1);
end;

procedure TAdventureNpcWorld.LayItem(Item: Integer; X, Y: Double);
begin
  { 164 ticks of life, as a dropped item }
  FAdv.AddItem(X, Y, Item, 164);
end;

procedure TAdventureNpcWorld.PlaySound(const Name: string; X, Y: Double; Looped: Boolean);
begin
  FAdv.Log('PLAY ' + Name);
end;

procedure TAdventureNpcWorld.PutExplosion(Power, Radius, X, Y: Double);
begin
  FAdv.AddBlast(X - 1, Y - 1, Max(1, Round(Radius)), Trunc(Power), True);
end;

procedure TAdventureNpcWorld.PutBaddy(Kind: Integer; X, Y: Double; const Img: string; Power: Integer);
var
  B: TBaddy;
begin
  { putcomp: offline or on the leader only, as the original's AI }
  if Online and not FAdv.Npcs.IsLeader then Exit;
  B := FAdv.Baddies.Add(Kind, X, Y, '');
  if Img <> '' then B.Image := Img;
  if Power > 0 then B.Power := Power;
end;

procedure TAdventureNpcWorld.Shoot(const Kind: string; X, Y: Double; Dir: Integer);
begin
  FAdv.Log(Format('SHOOT %s %.1f,%.1f %d', [Kind, X, Y, Dir]));
end;

procedure TAdventureNpcWorld.SetPlayerProp(const Code, Value: string);
var
  P: TServerPlayer;
  C, K: Integer;
begin
  P := FAdv.Player;
  if Code = '#c' then P.Chat := Value
  else if Code = '#1' then P.SwordImage := Value
  else if Code = '#2' then P.ShieldImage := Value
  else if Code = '#3' then P.HeadImage := Value
  else if Code = '#8' then P.BodyImage := Value
  else if (Length(Code) = 3) and (Copy(Code, 1, 2) = '#C') and (Code[3] in ['0'..'4']) then
  begin
    C := ColorIndexOf(Value);
    if C >= 0 then P.Colors[Ord(Code[3]) - Ord('0')] := C;
  end
  else if (Length(Code) = 3) and (Copy(Code, 1, 2) = '#P') and (Code[3] in ['1'..'5']) then
  begin
    K := Ord(Code[3]) - Ord('0');
    P.Attr[K] := Value;
  end;
end;

procedure TAdventureNpcWorld.SetPlayerAni(const Gani, Params: string);
begin
  FAdv.Player.SetAni(Gani, FAdv.Frame);
end;

procedure TAdventureNpcWorld.PlayerCommand(Op: Integer; const A: TGsArgs);
var
  P: TServerPlayer;
  C: Integer;
begin
  P := FAdv.Player;
  case Op of
    611..615: { setskincolor .. setbeltcolor }
      begin
        C := Trunc(A.Num[0]);
        if (C >= 0) and (C <= 19) then P.Colors[Op - 611] := C;
      end;
    GsOpSetPlayerDir:
      if A.Num[0] >= 0 then P.Dir := ((Trunc(A.Num[0]) mod 4) + 4) mod 4;
    655 { sethead }: P.HeadImage := A.Str[0];
    683 { setbody }: P.BodyImage := A.Str[0];
    649 { setsword }:
      begin
        P.SwordImage := A.Str[0];
        P.SwordPower := Max(0, Min(4, Trunc(A.Num[1])));
      end;
    650 { setshield }:
      begin
        P.ShieldImage := A.Str[0];
        P.ShieldPower := Max(0, Min(3, Trunc(A.Num[1])));
      end;
    GsOpEnableWeapons: FAdv.WeaponsOn := True;
    GsOpDisableWeapons: FAdv.WeaponsOn := False;
    GsOpShowStats: FAdv.ShowStats := Trunc(A.Num[0]);
  else
    FAdv.Log('GS1 ' + GsCommands[Op - GsFirstOp].Name + ' (not modelled)');
  end;
end;

procedure TAdventureNpcWorld.Send(Id: Integer; const Data: string);
begin
  FAdv.SendPacket(Id, Data);
end;

procedure TAdventureNpcWorld.Log(const S: string);
begin
  FAdv.Log(S);
end;

procedure TAdventureNpcWorld.SwordHit(X, Y, W, H: Double; Power: Integer);
begin
  FAdv.Npcs.SwordHit(X, Y, W, H, Power);
  if FAdv.Baddies <> nil then FAdv.Baddies.SwordHit(Power);
end;

procedure TAdventureNpcWorld.BombBlast(X, Y: Double; Radius: Integer);
begin
  FAdv.Npcs.BombBlast(X, Y, Radius);
  { a blast hits a baddy whose body covers its middle, at power 4 (in
    2.05 the bomb's size times four) }
  if FAdv.Baddies <> nil then FAdv.Baddies.PointHit(X, Y, 4);
end;

function TAdventureNpcWorld.ArrowHit(X, Y: Double; Power: Integer): Boolean;
begin
  Result := FAdv.Npcs.ArrowHit(X, Y, Power);
  if not Result and (FAdv.Baddies <> nil) then Result := FAdv.Baddies.PointHit(X, Y, Power);
end;

{ ---- TAdventureBaddyWorld ---- }

constructor TAdventureBaddyWorld.Create(Adv: TAdventure);
begin
  inherited Create;
  FAdv := Adv;
end;

function TAdventureBaddyWorld.Online: Boolean;
begin
  Result := FAdv.IsOnline;
end;

function TAdventureBaddyWorld.Leader: Boolean;
begin
  Result := (FAdv.Npcs <> nil) and FAdv.Npcs.IsLeader;
end;

function TAdventureBaddyWorld.PlayerX: Double;
begin
  Result := FAdv.Player.X;
end;

function TAdventureBaddyWorld.PlayerY: Double;
begin
  Result := FAdv.Player.Y;
end;

function TAdventureBaddyWorld.PlayerDir: Integer;
begin
  Result := FAdv.Player.Dir and 3;
end;

function TAdventureBaddyWorld.PlayerHere: Boolean;
begin
  Result := FAdv.Mode <> ModeDead;
end;

function TAdventureBaddyWorld.Blocked(X, Y: Double): Boolean;
begin
  Result := (X < 0) or (Y < 0) or (X >= 64) or (Y >= 64) or FAdv.PointBlocked(X, Y);
end;

procedure TAdventureBaddyWorld.HurtPlayer(Hearts, FromX, FromY: Double);
begin
  FAdv.HurtFrom(Hearts, FromX, FromY);
end;

procedure TAdventureBaddyWorld.Shoot(X, Y: Double; Dir, Sprite, Kind: Integer);
begin
  FAdv.AddShot(X, Y, Dir, Sprite, Kind, False);
end;

procedure TAdventureBaddyWorld.Send(Id: Integer; const Data: string);
begin
  FAdv.SendPacket(Id, Data);
end;

function TAdventureBaddyWorld.Image(const Name: string): TGSurface;
begin
  { 2.05 keeps the baddies in their own folder, 2.22 in levels/baddies }
  if SameText(Name, 'wbow1.gif') then
  begin
    Result := FAdv.Assets.Image(Name, 'weapon');
    Exit;
  end;
  Result := nil;
  if SameText(Copy(Name, 1, 5), 'baddy') then
  begin
    Result := FAdv.Assets.Image('baddies(not the guild!)/' + Name, '');
    if Result = nil then Result := FAdv.Assets.Image('baddies/' + Name, '');
  end;
  if Result = nil then Result := FAdv.Assets.Image(Name, '');
end;

function TAdventureBaddyWorld.Arrays: TGArrays;
begin
  Result := FAdv.Arrays;
end;

procedure TAdventureBaddyWorld.DrawVerse(Screen: TGSurface; CX, Y: Integer; const Text: string);
begin
  DrawText(Screen, CX - TextWidth(Text, 1) div 2, Y, Text, $FFFFFFFF, 1);
end;

procedure TAdventureBaddyWorld.AllDied;
begin
  if FAdv.Npcs <> nil then FAdv.Npcs.FireAll('compusdied');
end;

end.
