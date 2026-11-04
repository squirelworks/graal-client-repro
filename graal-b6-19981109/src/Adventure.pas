{ Adventure: the game state and frame loop of a 1998 relay client (gen 1).

  TAdventure owns the level, the local player, the two relay connections
  and the frame function that runs on a 50 ms gate, as the later builds do.
  What is particular to this build (game name, D types, level magics,
  colour count, the NR / NL start level) comes from ProtocolB6.

  Online, the client opens two connections to the same relay port, as the
  captured 1.1.9 does (graal_analysis client-internals/live-trace-early.md):
    - the fixed game (RelayGame), which it joins once and keeps;
    - the level game, RelayRoomPrefix + the level's file name, which it
      leaves and joins again on every level change.
  After each pairing it pushes its state to the partner: L, P, N, S, 7, T,
  Y (the captured order; types the build does not send are left out).
  While walking it sends P every 100 ms: x and y in half tiles, then
  frame*4 + direction.

  Each client runs its level by itself: there is no server-side level, no
  account and no login reply. "Joined" means the server gave both
  connections an id. }
unit Adventure;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GLevel, GSurface, GArrays, GAni, GBuiltin, GAssetDirs, GRelay, ProtocolB6;

const
  ScreenW = 640;
  ScreenH = 480;

  DirUp = 0;
  DirLeft = 1;
  DirDown = 2;
  DirRight = 3;

  { The colour list of the later builds (client-internals/
    body-colours-and-attributes.md); the 1998 index meaning is assumed to
    be the same. }
  ColorTable: array[0..19] of Cardinal = (
    $FFFFFFFF, $FFFFFF00, $FFFFAD6B, $FFFF8484, $FFFF0000, $FFCE1829,
    $FF84FF84, $FF00FF00, $FF00C600, $FF8484FF, $FF0000FF, $FF0000C6,
    $FF840000, $FF00FFFF, $FFFF00FF, $FF840084, $FFCECECE, $FF848484,
    $FF000008, $00000000);

type
  { Images and ganis from the player's install, loaded once and kept. }
  TAssets = class
  private
    FNames: TStringList;
    function FindFile(const Name: string; const Dirs: array of string): string;
  public
    Missing: TStringList;
    constructor Create;
    destructor Destroy; override;
    function Image(const Name: string): TGSurface;
    function Ani(const Name: string): TGraalAni;
    { A level file in the install (levels/ first), or ''. }
    function LevelFile(const Name: string): string;
  end;

  { A player: the local one, or a relay partner. }
  TPeer = class
  public
    Id: string;          { the id8 the relay gave its level connection }
    Nickname, Level, Chat: string;
    X, Y: Double;        { tiles, top-left of the 3x3-tile sprite box }
    Sprite: Integer;     { frame*4 + direction, as in the P payload }
    Dir: Integer;
    Colors: array[0..4] of Integer;
    LoginTime: Int64;
    Away: Boolean;       { sent I: left the level or went to a link }
    SwordPower, ShieldPower, Power: Integer;
    AniName: string;
    AniStart: Integer;
    constructor Create;
    procedure SetAni(const Name: string; Frame: Integer);
  end;

  TAdventure = class
  private
    FFixed, FRoom: TRelayLink;
    FLog: TStrings;
    FOthers: TList;
    FLevelDir: string;
    FHost: string;
    FPort: Word;
    FMoving: Boolean;
    FSentSprite: Integer;
    FSentX, FSentY: Double;
    FLevelChosen: Boolean;
    FJoinedAt: Integer;
    FPushes: Integer;
    FBody, FBodyTinted: TGSurface;
    FBodyKey: string;
    function BodyFor(P: TPeer): TGSurface;
    function GetOther(I: Integer): TPeer;
    function GetOtherCount: Integer;
    procedure PollLink(Link: TRelayLink; IsRoom: Boolean);
    procedure PushState(Link: TRelayLink);
    procedure SendPosition;
    procedure ChooseOnlineLevel;
    procedure JoinLevelRoom;
    function PointBlocked(PX, PY: Double): Boolean;
  public
    Level: TAdventureLevel;
    Player: TPeer;
    Screen: TGSurface;
    Sheet: TGSurface;
    SheetBuiltin: Boolean;
    Arrays: TGArrays;
    Assets: TAssets;
    Frame: Integer;
    Headless, Echo: Boolean;
    { both connections have their id from the server }
    Joined: Boolean;
    BoardLoaded: Boolean;
    JoinMs: Integer;
    DataIn, DataOut: Integer;
    Keys: array[0..3] of Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Log(const S: string);
    procedure UseInstall(const Dir: string);
    procedure UseBuiltins;
    { Loads a level file (or a built-in one); checks the build's magics. }
    function LoadLevelFile(const FileName: string): Boolean;
    { Connects both relay connections and joins the games. }
    function ConnectServer(const Host: string; Port: Word; const Nick: string): Boolean;
    procedure Disconnect;
    function Connected: Boolean;
    { The level game for a level name ('' = the bare prefix). }
    function RoomFor(const LevelName: string): string;
    { Applies one D payload (after the D) from a partner. }
    procedure HandleData(const Data: string);
    function FindOther(const Id: string; Make: Boolean): TPeer;
    procedure RemoveOther(const Id: string);
    procedure WalkStep(Dir: Integer);
    function LinkAt(PX, PY: Double): Integer;
    function FollowLink(I: Integer): Boolean;
    procedure Tick;
    procedure Draw;
    procedure DrawPlayer(P: TPeer; CamX, CamY: Integer);
    property FixedLink: TRelayLink read FFixed;
    property RoomLink: TRelayLink read FRoom;
    property Others[I: Integer]: TPeer read GetOther;
    property OtherCount: Integer read GetOtherCount;
    property LogLines: TStrings read FLog;
  end;

function NowMs: Int64;

implementation

uses
  SysUtils, Math;

const
  LogKeep = 200;

function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

function EndsWith(const S, Tail: string): Boolean;
begin
  Result := (Length(S) >= Length(Tail)) and
    (LowerCase(Copy(S, Length(S) - Length(Tail) + 1, MaxInt)) = LowerCase(Tail));
end;

{ TAssets }

constructor TAssets.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FNames.Sorted := True;
  Missing := TStringList.Create;
  Missing.Sorted := True;
  Missing.Duplicates := dupIgnore;
end;

destructor TAssets.Destroy;
var
  I: Integer;
begin
  for I := 0 to FNames.Count - 1 do FNames.Objects[I].Free;
  FNames.Free;
  Missing.Free;
  inherited Destroy;
end;

function TAssets.FindFile(const Name: string; const Dirs: array of string): string;
var
  I, J, K: Integer;
  Base, Cand: string;
  Exts: array[0..2] of string;
begin
  Result := '';
  if (AssetRootCount = 0) or (Name = '') then Exit;
  Base := ChangeFileExt(Name, '');
  Exts[0] := ExtractFileExt(Name);
  Exts[1] := '.gif';
  Exts[2] := '.png';
  for K := 0 to AssetRootCount - 1 do
    for I := 0 to High(Dirs) do
      for J := 0 to 2 do
      begin
        if Exts[J] = '' then Continue;
        Cand := AssetRoot(K) + Dirs[I] + Base + Exts[J];
        if FileExists(Cand) then
        begin
          Result := Cand;
          Exit;
        end;
      end;
end;

function TAssets.LevelFile(const Name: string): string;
begin
  Result := '';
  if (Name = '') or (Pos('..', Name) > 0) or (Pos('/', Name) > 0) or
    (Pos('\', Name) > 0) then Exit;
  Result := AssetPath('levels/' + Name);
  if Result = '' then Result := AssetPath(Name);
end;

function TAssets.Image(const Name: string): TGSurface;
var
  Key, F, D: string;
  I: Integer;
  S: TGSurface;
begin
  Result := nil;
  if Name = '' then Exit;
  Key := 'img:' + LowerCase(Name);
  I := FNames.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TGSurface(FNames.Objects[I]);
    Exit;
  end;
  F := FindFile(Name, ['', 'levels/']);
  S := nil;
  if F <> '' then
  begin
    S := TGSurface.Create(0, 0);
    if not LoadImageFile(F, S) then FreeAndNil(S);
  end;
  if (S = nil) and BuiltinFile(Name, D) then
  begin
    S := TGSurface.Create(0, 0);
    if not LoadImageData(D, Name, S, False) then FreeAndNil(S);
  end;
  if S = nil then Missing.Add(Name);
  FNames.AddObject(Key, S);
  Result := S;
end;

function TAssets.Ani(const Name: string): TGraalAni;
var
  Key, D: string;
  I: Integer;
  A: TGraalAni;
begin
  { the 1998 builds have no ganis: the player is drawn with the built-in
    stand-in animations (new art), until the sprites.gif layout of these
    builds is written up }
  Key := 'ani:' + LowerCase(Name);
  I := FNames.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TGraalAni(FNames.Objects[I]);
    Exit;
  end;
  A := nil;
  if BuiltinFile(Name + '.gani', D) then
  begin
    A := TGraalAni.Create;
    if not A.LoadFromString(D) then FreeAndNil(A);
  end;
  FNames.AddObject(Key, A);
  Result := A;
end;

{ TPeer }

constructor TPeer.Create;
begin
  inherited Create;
  Nickname := 'unknown';
  Dir := DirDown;
  Sprite := DirDown;
  Colors[0] := 2;  { skin, coat, sleeves, shoes, belt: the usual defaults }
  Colors[1] := 0;
  Colors[2] := 10;
  Colors[3] := 4;
  Colors[4] := 18;
  SwordPower := 1;
  ShieldPower := 1;
  AniName := 'idle';
end;

procedure TPeer.SetAni(const Name: string; Frame: Integer);
begin
  if AniName <> Name then
  begin
    AniName := Name;
    AniStart := Frame;
  end;
end;

{ TAdventure }

constructor TAdventure.Create;
begin
  inherited Create;
  FFixed := TRelayLink.Create;
  FRoom := TRelayLink.Create;
  FLog := TStringList.Create;
  FOthers := TList.Create;
  Level := TAdventureLevel.Create;
  Player := TPeer.Create;
  Screen := TGSurface.Create(ScreenW, ScreenH);
  Sheet := TGSurface.Create(0, 0);
  Arrays := TGArrays.Create;
  Assets := TAssets.Create;
  FBodyTinted := TGSurface.Create(0, 0);
  JoinMs := -1;
  FSentSprite := -1;
  Player.LoginTime := Trunc(Now * 86400.0 * 100) mod (Int64(1) shl 50);
  UseBuiltins;
end;

destructor TAdventure.Destroy;
var
  I: Integer;
begin
  FFixed.Free;
  FRoom.Free;
  for I := 0 to FOthers.Count - 1 do TPeer(FOthers[I]).Free;
  FOthers.Free;
  Level.Free;
  Player.Free;
  Screen.Free;
  Sheet.Free;
  Arrays.Free;
  Assets.Free;
  FBody.Free;
  FBodyTinted.Free;
  FLog.Free;
  inherited Destroy;
end;

procedure TAdventure.Log(const S: string);
begin
  FLog.Add(S);
  while FLog.Count > LogKeep do FLog.Delete(0);
  if Echo then
  begin
    WriteLn(ErrOutput, S);
    Flush(ErrOutput);
  end;
end;

procedure TAdventure.UseBuiltins;
var
  D: string;
begin
  if BuiltinFile('pics1.png', D) and LoadImageData(D, 'pics1.png', Sheet, False) then
    SheetBuiltin := True;
  if BuiltinFile('arrays.dat', D) then Arrays.LoadFromString(D);
end;

function ReadFileText(const FileName: string; out Data: string): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Data := '';
  if not FileExists(FileName) then Exit;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then F.ReadBuffer(Data[1], F.Size);
    Result := True;
  finally
    F.Free;
  end;
end;

procedure TAdventure.UseInstall(const Dir: string);
var
  P, D: string;
  I: Integer;
  Ok: Boolean;
begin
  SetAssetRoots(Dir, ClientBuildLabel);
  P := AssetPath('pics1.gif');
  if P = '' then P := AssetPath('pics1.png');
  if (P <> '') and (LoadImageIndexed(P, Sheet) or LoadImageFile(P, Sheet)) then
  begin
    SheetBuiltin := False;
    { the board is drawn opaque: the 1998 pics1.gif marks its grass colour
      as the GIF's transparent one; read with its palette, the image
      reader keeps that colour, with alpha 0 }
    for I := 0 to High(Sheet.Pixels) do
      Sheet.Pixels[I] := Sheet.Pixels[I] or $FF000000;
  end;
  P := AssetPath('arrays.dat');
  if (P <> '') and ReadFileText(P, D) then
  begin
    { the 1998 arrays.dat holds fewer tables than the 25 the later builds
      read (19 in 1st Graal, 24 in 1.1.9); the missing ones at the end are
      taken as empty }
    Ok := False;
    for I := 0 to 25 do
    begin
      if Arrays.LoadFromString(D) then
      begin
        Ok := True;
        Break;
      end;
      D := D + #0#0#0#0;
    end;
    if not Ok then
    begin
      Log('warning: cannot read ' + P);
      UseBuiltins;
    end;
  end;
end;

function TAdventure.GetOther(I: Integer): TPeer;
begin
  Result := TPeer(FOthers[I]);
end;

function TAdventure.GetOtherCount: Integer;
begin
  Result := FOthers.Count;
end;

function TAdventure.FindOther(const Id: string; Make: Boolean): TPeer;
var
  I: Integer;
begin
  for I := 0 to FOthers.Count - 1 do
  begin
    Result := TPeer(FOthers[I]);
    if Result.Id = Id then Exit;
  end;
  Result := nil;
  if not Make or (Id = '') or (FOthers.Count >= 64) then Exit;
  Result := TPeer.Create;
  Result.Id := Id;
  Result.Level := Player.Level;
  FOthers.Add(Result);
end;

procedure TAdventure.RemoveOther(const Id: string);
var
  I: Integer;
begin
  for I := FOthers.Count - 1 downto 0 do
    if TPeer(FOthers[I]).Id = Id then
    begin
      Log('player ' + Id + ' left');
      TPeer(FOthers[I]).Free;
      FOthers.Delete(I);
    end;
end;

function TAdventure.LoadLevelFile(const FileName: string): Boolean;
var
  Data: string;
  Builtin: Boolean;
  L: TAdventureLevel;
begin
  Result := False;
  Builtin := False;
  if not ReadFileText(FileName, Data) then
  begin
    { a built-in stand-in level (the project's own, in the later text
      format): exempt from the build's magic check }
    if not BuiltinFile(ExtractFileName(FileName), Data) then
    begin
      Level.LastError := 'no such file: ' + FileName;
      Exit;
    end;
    Builtin := True;
  end;
  if not Builtin and not AcceptsLevel(Copy(Data, 1, 8)) then
  begin
    Level.LastError := 'this build does not read ' + Copy(Data, 1, 8) + ' levels';
    Exit;
  end;
  L := TAdventureLevel.Create;
  if not L.LoadFromString(Data) then
  begin
    Level.LastError := L.LastError;
    L.Free;
    Exit;
  end;
  L.Name := ExtractFileName(FileName);
  Level.Free;
  Level := L;
  if Builtin then FLevelDir := '' else FLevelDir := ExtractFilePath(FileName);
  Player.Level := Level.Name;
  BoardLoaded := True;
  Result := True;
end;

{ ---- the relay ---- }

function TAdventure.RoomFor(const LevelName: string): string;
begin
  if RelayZeldaRooms then
  begin
    if LevelName = '' then Result := RelayGame
    else Result := 'Z' + ChangeFileExt(LevelName, '') + '2';
  end
  else
    Result := RelayRoomPrefix + LevelName;
end;

function TAdventure.ConnectServer(const Host: string; Port: Word; const Nick: string): Boolean;
begin
  Result := False;
  FHost := Host;
  FPort := Port;
  if Nick <> '' then Player.Nickname := Nick;
  if not FFixed.Connect(Host, Port) then
  begin
    Log('connect ' + Host + ':' + IntToStr(Port) + ': ' + FFixed.LastError);
    Exit;
  end;
  if not FRoom.Connect(Host, Port) then
  begin
    Log('connect ' + Host + ':' + IntToStr(Port) + ' (level link): ' + FRoom.LastError);
    FFixed.Disconnect;
    Exit;
  end;
  Log(Format('connected to %s:%d (two links)', [Host, Port]));
  FFixed.Join(RelayGame);
  { a build that waits for the server's level choice first joins the bare
    prefix, as the captured 1.1.9 does }
  if ServerLevelChoice then FRoom.Join(RoomFor(''))
  else
  begin
    FLevelChosen := True;
    FRoom.Join(RoomFor(Player.Level));
  end;
  FJoinedAt := Frame;
  FFixed.Flush;
  FRoom.Flush;
  Result := True;
end;

function TAdventure.Connected: Boolean;
begin
  Result := FFixed.Connected and FRoom.Connected;
end;

procedure TAdventure.Disconnect;
begin
  FRoom.Disconnect;
  FFixed.Disconnect;
end;

procedure TAdventure.JoinLevelRoom;
var
  I: Integer;
begin
  if not FRoom.Connected then Exit;
  for I := FOthers.Count - 1 downto 0 do TPeer(FOthers[I]).Free;
  FOthers.Clear;
  FRoom.Join(RoomFor(Player.Level));
  Log('level game ' + FRoom.Game);
end;

{ NR then NL: the server has local levels (onlinestartlocal.graal); NR
  alone: its levels come from the web (onlinestart.graal, fetched over
  HTTP by the original; looked for locally here). }
procedure TAdventure.ChooseOnlineLevel;
var
  Name, P: string;
begin
  FLevelChosen := True;
  if FRoom.GotNL or FFixed.GotNL then Name := 'onlinestartlocal.graal'
  else if FRoom.GotNR or FFixed.GotNR then Name := 'onlinestart.graal'
  else Name := '';
  if Name <> '' then
  begin
    P := Assets.LevelFile(Name);
    if (P <> '') and LoadLevelFile(P) then
    begin
      Player.X := 30;
      Player.Y := 30;
      Log('server level choice: ' + Name);
    end
    else
      Log('server level choice: ' + Name + ' is not in the install; staying on ' + Player.Level);
  end;
  JoinLevelRoom;
end;

procedure TAdventure.PushState(Link: TRelayLink);
var
  S: string;
  I: Integer;
begin
  if SendsType('L') then Link.SendData('L' + Player.Level);
  Link.SendData('P' + RChar(Round(Player.X * 2)) + RChar(Round(Player.Y * 2)) +
    RChar(Player.Sprite));
  if SendsType('N') then Link.SendData('N' + Player.Nickname);
  if SendsType('S') then
  begin
    S := RChar(ColourCount);
    for I := 0 to ColourCount - 1 do S := S + RChar(Player.Colors[I]);
    Link.SendData('S' + S);
  end;
  if SendsType('7') then Link.SendData('7');
  if SendsType('T') then Link.SendData('T' + EncodeTime128(Player.LoginTime));
  if SendsType('Y') then
    Link.SendData('Y' + RChar(Player.SwordPower) + RChar(Player.ShieldPower) +
      RChar(Player.Power));
  Inc(FPushes);
  Inc(DataOut);
end;

procedure TAdventure.SendPosition;
begin
  if not FRoom.Connected or (FRoom.Partners.Count = 0) then Exit;
  FRoom.SendData('P' + RChar(Round(Player.X * 2)) + RChar(Round(Player.Y * 2)) +
    RChar(Player.Sprite));
  Inc(DataOut);
  FSentSprite := Player.Sprite;
  FSentX := Player.X;
  FSentY := Player.Y;
end;

procedure TAdventure.HandleData(const Data: string);
var
  Id, F: string;
  P: TPeer;
  T: Char;
  I, N: Integer;
begin
  if Length(Data) < 3 then Exit;
  Id := DecodeSid(Copy(Data, 1, 2));
  if Id = FRoom.MyId then Exit;
  T := Data[3];
  F := Copy(Data, 4, MaxInt);
  Inc(DataIn);
  P := FindOther(Id, True);
  if P = nil then Exit;
  case T of
    'P':
      if Length(F) >= 3 then
      begin
        P.X := RVal(F[1]) / 2;
        P.Y := RVal(F[2]) / 2;
        P.Sprite := RVal(F[3]);
        P.Dir := P.Sprite and 3;
        P.Away := False;
        if P.Sprite div 4 > 0 then P.SetAni('walk', Frame) else P.SetAni('idle', Frame);
      end;
    'N':
      begin
        if P.Nickname <> F then Log('other player ' + Id + ' ' + F);
        P.Nickname := Copy(F, 1, 64);
      end;
    'L': P.Level := Copy(F, 1, 128);
    'S':
      if F <> '' then
      begin
        N := RVal(F[1]);
        for I := 0 to 4 do
          if (I < N) and (I + 2 <= Length(F)) then
            P.Colors[I] := ((RVal(F[I + 2]) mod 20) + 20) mod 20;
      end;
    'T': P.LoginTime := DecodeTime128(Copy(F, 1, 10));
    'C':
      begin
        P.Chat := Copy(F, 1, 200);
        Log('chat ' + P.Nickname + ': ' + P.Chat);
      end;
    'I': P.Away := True;
    'Y':
      if Length(F) >= 3 then
      begin
        P.SwordPower := RVal(F[1]);
        P.ShieldPower := RVal(F[2]);
        P.Power := RVal(F[3]);
      end;
  end;
end;

procedure TAdventure.PollLink(Link: TRelayLink; IsRoom: Boolean);
var
  Lines: TList;
  I: Integer;
  R: PRelayLine;
begin
  if not Link.Connected then Exit;
  Lines := TList.Create;
  try
    Link.Poll(Lines);
    for I := 0 to Lines.Count - 1 do
    begin
      R := PRelayLine(Lines[I]);
      case R^.Event of
        reId: Log('relay id ' + R^.Id + ' in ' + Link.Game);
        rePaired:
          begin
            Log('paired with ' + R^.Id + ' in ' + Link.Game);
            PushState(Link);
          end;
        reUnpaired, rePeerOut:
          if IsRoom then RemoveOther(R^.Id);
        reData:
          if IsRoom then HandleData(R^.Data);
      end;
      Dispose(R);
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- walking: the rule of the later builds (graal_analysis
  client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md),
  half a tile a step; not yet checked against a 1998 build ---- }

function TileOf(V: Double): Integer;
begin
  Result := Floor(V + 0.0001);
end;

function TAdventure.PointBlocked(PX, PY: Double): Boolean;
var
  TX, TY, I: Integer;
begin
  Result := False;
  for I := 0 to High(Level.Chests) do
    if (PX >= Level.Chests[I].X) and (PX <= Level.Chests[I].X + 2) and
      (PY >= Level.Chests[I].Y) and (PY <= Level.Chests[I].Y + 2) then
    begin
      Result := True;
      Exit;
    end;
  TX := TileOf(PX);
  TY := TileOf(PY);
  if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then Exit;
  Result := not Arrays.TilePassable(Level.Tile(TX, TY));
end;

procedure TAdventure.WalkStep(Dir: Integer);
const
  StepX: array[0..3] of Double = (0, -0.5, 0, 0.5);
  StepY: array[0..3] of Double = (-0.5, 0, 0.5, 0);
  Fixed: array[0..3] of Double = (1.0, 0.5, 3.0, 2.5);
  Along: array[0..3, 0..5] of Double = (
    (0.525, 1.475, 1.525, 2.475, 2.525, 0.475),
    (1.025, 1.975, 2.025, 2.975, 3.025, 0.975),
    (0.525, 1.475, 1.525, 2.475, 2.525, 0.475),
    (1.025, 1.975, 2.025, 2.975, 3.025, 0.975));
var
  NX, NY, F: Double;
  B: array[0..5] of Boolean;
  I: Integer;
begin
  Player.Dir := Dir;
  NX := Player.X + StepX[Dir];
  NY := Player.Y + StepY[Dir];
  for I := 0 to 5 do
    if (Dir = DirUp) or (Dir = DirDown) then
      B[I] := PointBlocked(NX + Along[Dir, I], NY + Fixed[Dir])
    else
      B[I] := PointBlocked(NX + Fixed[Dir], NY + Along[Dir, I]);
  if B[0] or B[1] or B[2] or B[3] then
  begin
    if B[0] and not B[2] and not B[3] and not B[4] then
    begin
      if (Dir = DirUp) or (Dir = DirDown) then NX := NX + 0.1 else NY := NY + 0.1;
    end
    else if not B[0] and not B[1] and B[3] and not B[5] then
    begin
      if (Dir = DirUp) or (Dir = DirDown) then NX := NX - 0.1 else NY := NY - 0.1;
    end;
    NX := NX - StepX[Dir];
    NY := NY - StepY[Dir];
    case Dir of
      DirUp: if Frac(NY) > 0 then NY := Floor(NY);
      DirLeft: if Frac(NX + 0.5) > 0 then NX := Floor(NX + 0.5) - 0.5;
      DirDown: if Frac(NY) > 0 then NY := Floor(NY + 1);
      DirRight: if Frac(NX + 0.5) > 0 then NX := Floor(NX + 1.5) - 0.5;
    end;
  end;
  F := NY - Floor(NY);
  if (F < 0.0625) or (F > 0.9375) then NY := Floor(NY + 0.0625);
  F := (NX + 0.5) - Floor(NX + 0.5);
  if (F < 0.0625) or (F > 0.9375) then NX := Floor(NX + 0.5 + 0.0625) - 0.5;
  Player.X := NX;
  Player.Y := NY;
end;

function TAdventure.LinkAt(PX, PY: Double): Integer;
var
  I: Integer;
  L: TLevelLink;
begin
  for I := 0 to High(Level.Links) do
  begin
    L := Level.Links[I];
    if (PX >= L.X) and (PX < L.X + L.W) and (PY >= L.Y) and (PY < L.Y + L.H) then
    begin
      Result := I;
      Exit;
    end;
  end;
  Result := -1;
end;

function Arrival(const S: string; Keep: Double): Double;
var
  V: Double;
begin
  Result := Keep;
  if (S = '') or (LowerCase(Copy(S, 1, 6)) = 'player') then Exit;
  if TryStrToFloat(S, V) and (V >= 0) then Result := V;
end;

function TAdventure.FollowLink(I: Integer): Boolean;
var
  L: TLevelLink;
  NX, NY: Double;
  Path: string;
begin
  Result := False;
  if (I < 0) or (I > High(Level.Links)) then Exit;
  L := Level.Links[I];
  NX := Arrival(L.NewX, Player.X);
  NY := Arrival(L.NewY, Player.Y);
  Path := '';
  if (FLevelDir <> '') and FileExists(FLevelDir + L.Dest) then Path := FLevelDir + L.Dest
  else Path := Assets.LevelFile(L.Dest);
  if Path = '' then Path := L.Dest;
  { the partners hear that this player went to a link }
  if FRoom.Connected and SendsType('I') then FRoom.SendData('I');
  if not LoadLevelFile(Path) then
  begin
    Log('link to ' + L.Dest + ': ' + Level.LastError);
    Exit;
  end;
  Player.X := NX;
  Player.Y := NY;
  Log(Format('link to %s at %.1f,%.1f', [Level.Name, NX, NY]));
  if FRoom.Connected and FLevelChosen then JoinLevelRoom;
  Result := True;
end;

procedure TAdventure.Tick;
var
  D, Step: Integer;
  Moved: Boolean;
  AX, AY: Double;
begin
  Inc(Frame);
  if FFixed.Connected or FRoom.Connected then
  begin
    PollLink(FFixed, False);
    PollLink(FRoom, True);
    if not Joined and (FFixed.MyId <> '') and (FRoom.MyId <> '') then
    begin
      Joined := True;
      JoinMs := (Frame - FJoinedAt) * 50;
      Log('joined ' + FFixed.Game + ' as ' + FFixed.MyId + ' and ' + FRoom.Game +
        ' as ' + FRoom.MyId);
    end;
    { the level choice comes right after N; a server that sends none
      leaves the client on its own level after a second }
    if ServerLevelChoice and not FLevelChosen and
      ((FRoom.GotNR or FRoom.GotNL) and (FRoom.MyId <> '') or (Frame - FJoinedAt > 20)) then
      ChooseOnlineLevel;
    if not Connected then Log('link closed: ' + FFixed.LastError + FRoom.LastError);
  end;
  Moved := False;
  AX := 0;
  AY := 0;
  for D := 0 to 3 do
    if Keys[D] then
    begin
      WalkStep(D);
      Moved := True;
      case D of
        DirUp: AY := AY - 0.5;
        DirLeft: AX := AX - 0.5;
        DirDown: AY := AY + 0.5;
        DirRight: AX := AX + 0.5;
      end;
    end;
  if Moved then
  begin
    Step := 1 + (Frame div 2) mod 5;
    Player.Sprite := Step * 4 + Player.Dir;
    Player.SetAni('walk', Frame);
  end
  else
  begin
    Player.Sprite := Player.Dir;
    Player.SetAni('idle', Frame);
  end;
  if Moved then FollowLink(LinkAt(Player.X + 1.5 + AX, Player.Y + 2 + AY));
  { P every 100 ms while walking, and once more with the idle frame when
    the player stops }
  if (Moved and (Frame mod PositionEveryTicks = 0)) or
    (not Moved and FMoving) or
    (not Moved and (Player.Sprite <> FSentSprite) and (FSentSprite >= 0)) then
    SendPosition;
  FMoving := Moved;
  FFixed.Flush;
  FRoom.Flush;
  if not Headless then Draw;
end;

{ ---- drawing ---- }

{ The stand-in body recoloured with the player's colours (the palette
  slots of the built-in body: 5 skin, 6 coat, 4 sleeves, 3 shoes, 1 belt,
  0 outline, 2 clear). }
function TAdventure.BodyFor(P: TPeer): TGSurface;
var
  D, Key: string;
  I: Integer;
begin
  Result := nil;
  if FBody = nil then
  begin
    FBody := TGSurface.Create(0, 0);
    if not (BuiltinFile('body.png', D) and LoadImageData(D, 'body.png', FBody, True)) then
      Exit;
  end;
  if Length(FBody.Indices) = 0 then Exit;
  Key := '';
  for I := 0 to 4 do Key := Key + IntToStr(P.Colors[I]) + ',';
  if Key <> FBodyKey then
  begin
    FBodyTinted.SetSize(FBody.Width, FBody.Height);
    FBodyTinted.Indices := FBody.Indices;
    FBodyTinted.Palette := FBody.Palette;
    FBodyTinted.Recolor([5, 6, 4, 3, 1, 0, 2],
      [ColorTable[P.Colors[0] mod 20], ColorTable[P.Colors[1] mod 20],
       ColorTable[P.Colors[2] mod 20], ColorTable[P.Colors[3] mod 20],
       ColorTable[P.Colors[4] mod 20], ColorTable[18], 0]);
    FBodyKey := Key;
  end;
  Result := FBodyTinted;
end;

procedure TAdventure.DrawPlayer(P: TPeer; CamX, CamY: Integer);
var
  A: TGraalAni;
  St, I, BX, BY: Integer;
  Parts: TGraalAniPartList;
  Spr: TGraalAniSprite;
  Img: TGSurface;
  SheetName: string;
begin
  BX := Round(P.X * TileSize) - CamX;
  BY := Round(P.Y * TileSize) - CamY;
  A := Assets.Ani(P.AniName);
  if A = nil then A := Assets.Ani('idle');
  if A = nil then
  begin
    Screen.FillRect(BX + 8, BY + 16, 32, 32, ColorTable[P.Colors[1] mod 20]);
    Exit;
  end;
  St := A.StepAt(Frame - P.AniStart);
  if (St < 0) or (St > High(A.Steps)) then Exit;
  Parts := A.Steps[St].Dirs[P.Dir and 3];
  for I := 0 to High(Parts) do
  begin
    if not A.FindSprite(Parts[I].Sprite, Spr) then Continue;
    SheetName := UpperCase(Spr.Sheet);
    { the built-in stand-in art for every part (head0, body, sword1) }
    if SheetName = 'SPRITES' then Img := Assets.Image('sprites.png')
    else if SheetName = 'HEAD' then Img := Assets.Image('head0.png')
    else if SheetName = 'BODY' then Img := BodyFor(P)
    else if SheetName = 'SWORD' then Img := Assets.Image('sword1.png')
    else Img := nil;
    if Img <> nil then
      Screen.Blit(Img, Spr.X, Spr.Y, Spr.W, Spr.H, BX + Parts[I].X, BY + Parts[I].Y);
  end;
end;

procedure TAdventure.Draw;
var
  CamX, CamY, TX, TY, X0, Y0, I: Integer;
begin
  Screen.Fill($FF000000);
  CamX := Round((Player.X + 1.5) * TileSize) - ScreenW div 2;
  CamY := Round((Player.Y + 2) * TileSize) - ScreenH div 2;
  if CamX > BoardW * TileSize - ScreenW then CamX := BoardW * TileSize - ScreenW;
  if CamY > BoardH * TileSize - ScreenH then CamY := BoardH * TileSize - ScreenH;
  if CamX < 0 then CamX := 0;
  if CamY < 0 then CamY := 0;
  X0 := CamX div TileSize;
  Y0 := CamY div TileSize;
  if Sheet.Width > 0 then
    for TY := Y0 to Y0 + ScreenH div TileSize + 1 do
      for TX := X0 to X0 + ScreenW div TileSize + 1 do
        if (TX < BoardW) and (TY < BoardH) then
          DrawTile(Screen, Sheet, Level.Tile(TX, TY), TX * TileSize - CamX, TY * TileSize - CamY);
  for I := 0 to FOthers.Count - 1 do
    if not Others[I].Away then DrawPlayer(Others[I], CamX, CamY);
  DrawPlayer(Player, CamX, CamY);
end;

end.
