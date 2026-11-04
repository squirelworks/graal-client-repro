{ Adventure: TAdventure, the game state and frame loop of 2.05 rev 2.

  In 2.05 TAdventure is the main TDXForm: it owns the level, the local
  player, the link to the server, and the frame function that the idle
  handler calls on a 50 ms gate (graal_analysis client-internals/
  rendering-observations.md). A stall is one frame; there is no catch-up.

  This rebuild keeps that split but leaves the window out: TAdventure draws
  each frame into a TGSurface and a front end shows it (or writes it to a
  file). }
unit Adventure;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GTypes, GLevel, GSurface, GraalClient, Protocol205;

const
  { The game view. 2.05's window size is not yet read from the binary;
    640x480 is the classic default and is marked as an assumption. }
  ScreenW = 640;
  ScreenH = 480;

type
  TServerPlayer = class
  public
    Id: Integer;
    Nickname, Account, Level, HeadImage, BodyImage, SwordImage, ShieldImage,
    BowImage, Chat: string;
    X, Y: Double;       { tiles }
    Sprite, Status, MaxPower, Power, Rupees, Arrows, Bombs: Integer;
    SwordPower, ShieldPower, GlovePower, BombPower: Integer;
    Colors: array[0..4] of Integer;
    { Parses a prop stream. Stops at the first id it cannot size, the way
      2.05 does, and returns the ids applied. }
    function ApplyProps(R: TGReader): string;
  end;

  TAdventure = class
  private
    FClient: TAdventureClient;
    FLog: TStrings;
    FPendingBoard: Boolean;
    procedure HandleMessage(Id: Integer; const Data: string);
    procedure ClientLog(const Line: string);
  public
    Level: TAdventureLevel;
    Player: TServerPlayer;
    Screen: TGSurface;
    Sheet: TGSurface;    { pics1 }
    Frame: Integer;
    WorldTime: Cardinal;
    ServerMessage, DisconnectReason: string;
    LoggedIn, BoardLoaded: Boolean;
    Handled, Ignored: array[0..255] of Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Log(const S: string);
    function ConnectServer(const Host: string; Port: Word;
      const Account, Password: string): Boolean;
    { One frame: network in, game step, network out, draw. }
    procedure Tick;
    procedure Draw;
    property Client: TAdventureClient read FClient;
    property LogLines: TStrings read FLog;
  end;

{ Fallback tile sheet when pics1 is not available: each tile gets a flat
  colour derived from its index, so a frame still shows the board layout. }
procedure MakeIndexSheet(Sheet: TGSurface);

implementation

uses
  SysUtils;

procedure MakeIndexSheet(Sheet: TGSurface);
var
  T, SX, SY: Integer;
  H: Cardinal;
begin
  Sheet.SetSize(128 * TileSize, 32 * TileSize);
  for T := 0 to 4095 do
  begin
    TileSheetPos(T, SX, SY);
    H := Cardinal(T) * 2654435761;
    Sheet.FillRect(SX, SY, TileSize, TileSize, $FF000000 or (H shr 8));
    { a 1-pixel grid line keeps tiles apart in the dump }
    Sheet.FillRect(SX, SY, TileSize, 1, $FF202020);
    Sheet.FillRect(SX, SY, 1, TileSize, $FF202020);
  end;
end;

{ TServerPlayer }

function TServerPlayer.ApplyProps(R: TGReader): string;
var
  P, V, I: Integer;
begin
  Result := '';
  while not R.Eof do
  begin
    P := R.ReadGChar;
    case P of
      PLPROP_NICKNAME: Nickname := R.ReadGString;
      PLPROP_MAXPOWER: MaxPower := R.ReadGChar;
      PLPROP_CURPOWER: Power := R.ReadGChar;
      PLPROP_RUPEESCOUNT: Rupees := R.ReadGInt3;
      PLPROP_ARROWSCOUNT: Arrows := R.ReadGChar;
      PLPROP_BOMBSCOUNT: Bombs := R.ReadGChar;
      PLPROP_GLOVEPOWER: GlovePower := R.ReadGChar;
      PLPROP_BOMBPOWER: BombPower := R.ReadGChar;
      PLPROP_SWORDPOWER:
        begin
          V := R.ReadGChar;
          if V > 4 then
          begin
            SwordPower := V - 30;
            SwordImage := R.ReadGString;
          end
          else
            SwordPower := V;
        end;
      PLPROP_SHIELDPOWER:
        begin
          V := R.ReadGChar;
          if V > 3 then
          begin
            ShieldPower := V - 10;
            ShieldImage := R.ReadGString;
          end
          else
            ShieldPower := V;
        end;
      PLPROP_BOWGIF: { pre-2.1: c(10 + len) + image, or c(bow power) }
        begin
          V := R.ReadGChar;
          if V > 10 then
            BowImage := R.ReadChars(V - 10);
        end;
      PLPROP_HEADGIF:
        begin
          V := R.ReadGChar;
          if V >= 100 then
            HeadImage := R.ReadChars(V - 100)
          else
            HeadImage := 'head' + IntToStr(V) + '.png';
        end;
      PLPROP_CURCHAT: Chat := R.ReadGString;
      PLPROP_COLORS: for I := 0 to 4 do Colors[I] := R.ReadGChar;
      PLPROP_ID: Id := R.ReadGShort;
      PLPROP_X: X := R.ReadGChar / 2;
      PLPROP_Y: Y := R.ReadGChar / 2;
      PLPROP_SPRITE: Sprite := R.ReadGChar;
      PLPROP_STATUS: Status := R.ReadGChar;
      PLPROP_CARRYSPRITE, PLPROP_HORSEBUSHES, PLPROP_EFFECTCOLORS,
      PLPROP_MAGICPOINTS, PLPROP_ALIGNMENT, PLPROP_ADDITFLAGS,
      PLPROP_GMAPLEVELX, PLPROP_GMAPLEVELY, PLPROP_Z, PLPROP_JOINLEAVELVL,
      PLPROP_PSTATUSMSG:
        R.ReadGChar;
      PLPROP_CURLEVEL: Level := R.ReadGString;
      PLPROP_HORSEGIF, PLPROP_ACCOUNTNAME, PLPROP_BODYIMG, PLPROP_PLANGUAGE,
      PLPROP_GATTRIB1..PLPROP_GATTRIB5, PLPROP_GATTRIB6..PLPROP_GATTRIB9,
      PLPROP_GATTRIB10..PLPROP_GATTRIB30:
        begin
          if P = PLPROP_ACCOUNTNAME then Account := R.ReadGString
          else if P = PLPROP_BODYIMG then BodyImage := R.ReadGString
          else R.ReadGString;
        end;
      PLPROP_CARRYNPC, PLPROP_KILLSCOUNT, PLPROP_DEATHSCOUNT,
      PLPROP_ONLINESECS, PLPROP_UDPPORT, PLPROP_RATING:
        R.ReadGInt3;
      PLPROP_APCOUNTER: R.ReadGShort;
      PLPROP_IPADDR: R.ReadGInt5;
      PLPROP_ATTACHNPC:
        begin
          R.ReadGChar;
          R.ReadGInt3;
        end;
      PLPROP_PCONNECTED: ;
    else
      Exit; { unknown size: the rest of the stream is lost }
    end;
    if R.Overrun then Exit;
    if Result <> '' then Result := Result + ',';
    Result := Result + IntToStr(P);
  end;
end;

{ TAdventure }

constructor TAdventure.Create;
begin
  inherited Create;
  FLog := TStringList.Create;
  FClient := TAdventureClient.Create;
  FClient.OnMessage := HandleMessage;
  FClient.OnLog := ClientLog;
  Level := TAdventureLevel.Create;
  Player := TServerPlayer.Create;
  Screen := TGSurface.Create(ScreenW, ScreenH);
  Sheet := TGSurface.Create(0, 0);
end;

destructor TAdventure.Destroy;
begin
  FClient.Free;
  Level.Free;
  Player.Free;
  Screen.Free;
  Sheet.Free;
  FLog.Free;
  inherited Destroy;
end;

procedure TAdventure.Log(const S: string);
begin
  FLog.Add(Format('[%5d] %s', [Frame, S]));
end;

procedure TAdventure.ClientLog(const Line: string);
begin
  Log(Line);
end;

function TAdventure.ConnectServer(const Host: string; Port: Word;
  const Account, Password: string): Boolean;
begin
  Result := FClient.Connect(Host, Port);
  if not Result then
  begin
    Log('connect failed: ' + FClient.LastError);
    Exit;
  end;
  Log(Format('connected to %s:%d, key %d, token %s', [Host, Port, FClient.Key,
    ClientVersionToken]));
  FClient.SendLogin(Account, Password, 'English');
  FClient.Flush;
end;

procedure TAdventure.HandleMessage(Id: Integer; const Data: string);
var
  R: TGReader;
  S: string;
  V: Integer;
  L: TLevelLink;
  SG: TLevelSign;
  CH: TLevelChest;
begin
  R := TGReader.Create(Data);
  try
    case Id of
      PLO_PLAYERPROPS:
        begin
          S := Player.ApplyProps(R);
          LoggedIn := True;
          Log('PLAYERPROPS ' + S);
        end;
      PLO_PLAYERWARP: { c x*2, c y*2, level }
        begin
          Player.X := R.ReadGChar / 2;
          Player.Y := R.ReadGChar / 2;
          Player.Level := R.ReadRest;
          Log(Format('PLAYERWARP %s %.1f,%.1f', [Player.Level, Player.X, Player.Y]));
        end;
      PLO_LEVELNAME:
        begin
          Level.Clear;
          Level.Name := Data;
          BoardLoaded := False;
          FPendingBoard := True;
          Log('LEVELNAME ' + Data);
        end;
      PLO_BOARDPACKET:
        begin
          BoardLoaded := Level.LoadBoardPacket(Data);
          FPendingBoard := False;
          if BoardLoaded then
            Log('BOARDPACKET ' + Level.Name + ' loaded')
          else
            Log('BOARDPACKET rejected: ' + Level.LastError);
        end;
      PLO_LEVELLINK: { "dest x y w h newx newy" as text }
        begin
          with TStringList.Create do
          try
            Delimiter := ' ';
            DelimitedText := Data;
            if Count >= 7 then
            begin
              L.Dest := Strings[0];
              L.X := StrToIntDef(Strings[1], 0);
              L.Y := StrToIntDef(Strings[2], 0);
              L.W := StrToIntDef(Strings[3], 0);
              L.H := StrToIntDef(Strings[4], 0);
              L.NewX := Strings[5];
              L.NewY := Strings[6];
              SetLength(Level.Links, Length(Level.Links) + 1);
              Level.Links[High(Level.Links)] := L;
            end;
          finally
            Free;
          end;
        end;
      PLO_LEVELSIGN:
        begin
          SG.X := R.ReadGChar;
          SG.Y := R.ReadGChar;
          SG.Text := DecodeSignText(R.ReadRest);
          SetLength(Level.Signs, Length(Level.Signs) + 1);
          Level.Signs[High(Level.Signs)] := SG;
        end;
      PLO_LEVELCHEST: { c opened, c x, c y, c item, c sign }
        begin
          R.ReadGChar;
          CH.X := R.ReadGChar;
          CH.Y := R.ReadGChar;
          CH.Item := R.ReadGChar;
          CH.Sign := R.ReadGChar;
          SetLength(Level.Chests, Length(Level.Chests) + 1);
          Level.Chests[High(Level.Chests)] := CH;
        end;
      PLO_SIGNATURE: { 1: quit; 0: quit unless the host is loopback }
        begin
          V := R.ReadGChar;
          Log('SIGNATURE ' + IntToStr(V));
        end;
      PLO_NEWWORLDTIME: WorldTime := R.ReadGInt4;
      PLO_STARTMESSAGE: ServerMessage := Data;
      PLO_DISCMESSAGE:
        begin
          DisconnectReason := Data;
          Log('DISCMESSAGE ' + Data);
        end;
      PLO_WARPFAILED: Log('WARPFAILED ' + Data);
      PLO_TOALL: Log('TOALL ' + Data);
      PLO_SETACTIVELEVEL: Log('SETACTIVELEVEL ' + Data);
      PLO_LEVELMODTIME, PLO_ISLEADER, PLO_DEFAULTWEAPON, PLO_UNKNOWN168,
      PLO_STAFFGUILDS, PLO_HASNPCSERVER, PLO_FILEUPTODATE, PLO_FILESENDFAILED:
        ; { accepted; their effects belong to later stages }
    else
      if (Id >= 0) and (Id <= 255) then Inc(Ignored[Id]);
      Exit;
    end;
    if (Id >= 0) and (Id <= 255) then Inc(Handled[Id]);
  finally
    R.Free;
  end;
end;

procedure TAdventure.Tick;
begin
  Inc(Frame);
  if FClient.Connected then
  begin
    FClient.Poll;
    if not FClient.Connected then
      Log('link closed: ' + FClient.LastError);
  end;
  { game step goes here: movement, NPC scripts, timers }
  FClient.Flush;
  Draw;
end;

procedure TAdventure.Draw;
var
  CamX, CamY, TX, TY, X0, Y0, PX, PY: Integer;
begin
  Screen.Fill($FF000000);
  if Sheet.Width = 0 then MakeIndexSheet(Sheet);
  { centre on the player, clamped to the 64x64 board }
  CamX := Round(Player.X * TileSize) + TileSize - ScreenW div 2;
  CamY := Round(Player.Y * TileSize) + TileSize - ScreenH div 2;
  if CamX > BoardW * TileSize - ScreenW then CamX := BoardW * TileSize - ScreenW;
  if CamY > BoardH * TileSize - ScreenH then CamY := BoardH * TileSize - ScreenH;
  if CamX < 0 then CamX := 0;
  if CamY < 0 then CamY := 0;
  X0 := CamX div TileSize;
  Y0 := CamY div TileSize;
  for TY := Y0 to Y0 + ScreenH div TileSize + 1 do
    for TX := X0 to X0 + ScreenW div TileSize + 1 do
      if (TX < BoardW) and (TY < BoardH) then
        DrawTile(Screen, Sheet, Level.Tile(TX, TY), TX * TileSize - CamX,
          TY * TileSize - CamY);
  { the player: a marker until sprites/ganis are drawn (32x32 body box) }
  PX := Round(Player.X * TileSize) - CamX;
  PY := Round(Player.Y * TileSize) - CamY;
  Screen.FillRect(PX, PY, 32, 2, $FFFFFFFF);
  Screen.FillRect(PX, PY + 30, 32, 2, $FFFFFFFF);
  Screen.FillRect(PX, PY, 2, 32, $FFFFFFFF);
  Screen.FillRect(PX + 30, PY, 2, 32, $FFFFFFFF);
end;

end.
