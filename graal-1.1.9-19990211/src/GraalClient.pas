{ GraalClient: TAdventureClient, the 1.1.9 relay client.

  1.1.9 has no game server in the later sense. It talks to a lobby that
  groups connections into named games and passes text lines between
  partners (graal_analysis protocol/relay-1998.md). The line format, the
  sender ids and one connection are the shared gen-1 code in
  common/GRelay.pas. What is 1.1.9's own is here:
    - two links to the same host and port: one joins the fixed game
      "Graal8", the other the room of the current level, "G8" + the
      level's location (client-internals/live-trace-early.md);
    - which D types it sends and reads, and the state push to a new
      partner.

  The game code works on numbered events (Protocol119). This unit turns
  the relay lines into those events and the game's own sends into D
  lines, so the game code does not see the wire. }
unit GraalClient;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GRelay;

type
  TMessageEvent = procedure(Id: Integer; const Data: string) of object;
  TLogEvent = procedure(const Line: string) of object;

  TAdventureClient = class
  private
    FGame, FLevel: TRelayLink;
    FLevelName: string;
    FOnMessage: TMessageEvent;
    FOnLog: TLogEvent;
    FPushTo: TRelayLink; { while a partner's state push runs: its link }
    FRoomPeers: TStringList; { the players paired in the level room }
    procedure Log(const S: string);
    procedure Deliver(Id: Integer; const Data: string);
    procedure Send(L: TRelayLink; const Line: string);
    procedure Handle(L: TRelayLink; const R: TRelayLine);
    procedure HandleD(const Data: string);
    procedure PollLink(L: TRelayLink);
    function GetMessagesIn: Integer;
    function GetMessagesOut: Integer;
    function GetBytesIn: Int64;
    function GetBytesOut: Int64;
  public
    LastError: string;
    { When set, every line the client makes is added here as well, with
      "0 " (game link) or "1 " (level link) in front, sent or not (tests
      read what would go out without a server). }
    Sent: TStrings;
    constructor Create;
    destructor Destroy; override;
    { Opens both links and joins the fixed game and the bare level room. }
    function Connect(const Host: string; Port: Word): Boolean;
    procedure Disconnect;
    function Connected: Boolean;
    { Moves the level link to the room of Level. }
    procedure JoinLevel(const Level: string);
    { The game's sends. Only the ones 1.1.9 has a D type for go out;
      the rest are dropped and False is returned. }
    function SendPacket(Id: Integer; const Data: string): Boolean;
    { One D line of Kind with Payload: on the level link, or during a
      state push on the link that was paired. }
    procedure SendD(Kind: Char; const Payload: string);
    procedure Flush;
    procedure Poll;
    { Takes a line as if it came from a link (0 the game link, 1 the level
      link), with the bookkeeping GRelay's Poll does. Tests and the fuzzer
      use it. }
    procedure FeedLine(Link: Integer; const Line: string);
    property OnMessage: TMessageEvent read FOnMessage write FOnMessage;
    property OnLog: TLogEvent read FOnLog write FOnLog;
    property GameLink: TRelayLink read FGame;
    property LevelLink: TRelayLink read FLevel;
    { lines, both links together }
    property MessagesIn: Integer read GetMessagesIn;
    property MessagesOut: Integer read GetMessagesOut;
    property BytesIn: Int64 read GetBytesIn;
    property BytesOut: Int64 read GetBytesOut;
  end;

{ The numeric part of an id, for the game's player list. }
function IdNumber(const Id: string): Integer;

implementation

uses
  SysUtils, GTypes, Protocol119;

function IdNumber(const Id: string): Integer;
begin
  Result := StrToIntDef(Copy(Id, Length(Id) - 3, 4), 0);
  if Result < 0 then Result := 0;
end;

constructor TAdventureClient.Create;
begin
  inherited Create;
  FGame := TRelayLink.Create;
  FLevel := TRelayLink.Create;
  FRoomPeers := TStringList.Create;
end;

destructor TAdventureClient.Destroy;
begin
  FGame.Free;
  FLevel.Free;
  FRoomPeers.Free;
  inherited Destroy;
end;

procedure TAdventureClient.Log(const S: string);
begin
  if Assigned(FOnLog) then FOnLog(S);
end;

procedure TAdventureClient.Deliver(Id: Integer; const Data: string);
begin
  if Assigned(FOnMessage) then FOnMessage(Id, Data);
end;

procedure TAdventureClient.Send(L: TRelayLink; const Line: string);
begin
  { a payload holding a line end would break the framing: dropped }
  if Pos(#10, Line) > 0 then Exit;
  if Sent <> nil then
    if L = FGame then Sent.Add('0 ' + Line) else Sent.Add('1 ' + Line);
  L.SendLine(Line);
end;

function TAdventureClient.Connect(const Host: string; Port: Word): Boolean;
begin
  LastError := '';
  Result := FGame.Connect(Host, Port);
  if not Result then
  begin
    LastError := FGame.LastError;
    Exit;
  end;
  Result := FLevel.Connect(Host, Port);
  if not Result then
  begin
    LastError := FLevel.LastError;
    FGame.Disconnect;
    Exit;
  end;
  { the clients always join under the name "def" and send the real
    nickname later, inside D }
  if Sent <> nil then Sent.Add('0 N' + RelayGame + '#def');
  FGame.Join(RelayGame);
  if Sent <> nil then Sent.Add('1 N' + RelayLevelPrefix + '#def');
  FLevel.Join(RelayLevelPrefix);
  FLevelName := '';
  Flush;
end;

procedure TAdventureClient.Disconnect;
begin
  { leaving on purpose: "-", then close }
  FGame.Disconnect;
  FLevel.Disconnect;
end;

function TAdventureClient.Connected: Boolean;
begin
  Result := FGame.Connected;
end;

procedure TAdventureClient.JoinLevel(const Level: string);
var
  I: Integer;
begin
  if (Level = FLevelName) and (FLevelName <> '') then Exit;
  { the players of the old room go: the game drops what it drew of them }
  for I := 0 to FRoomPeers.Count - 1 do
    Deliver(RLO_PEERLEFT, FRoomPeers[I]);
  FRoomPeers.Clear;
  FLevelName := Level;
  if Sent <> nil then
  begin
    if FLevel.Game <> '' then
    begin
      Sent.Add('1 -');
      Sent.Add('1 C');
    end;
    Sent.Add('1 N' + RelayLevelPrefix + Level + '#def');
  end;
  { GRelay sends "-" and "C" first when the link was in a game }
  FLevel.Join(RelayLevelPrefix + Level);
end;

procedure TAdventureClient.SendD(Kind: Char; const Payload: string);
var
  L: TRelayLink;
begin
  { play traffic goes to the level room; the state push after a pairing
    goes to the link that was paired. Each link signs with its own id. }
  if FPushTo <> nil then L := FPushTo else L := FLevel;
  Send(L, 'D' + EncodeSid(L.MyId) + Kind + Payload);
end;

function TAdventureClient.SendPacket(Id: Integer; const Data: string): Boolean;
var
  W, H: Integer;
begin
  Result := False;
  case Id of
    PLI_BOARDMODIFY:
      { x, y, w, h, tiles  ->  x, y, w*8+h, tiles }
      if Length(Data) >= 4 then
      begin
        W := RVal(Data[3]);
        H := RVal(Data[4]);
        if (W < 0) or (H < 0) or (W > 7) or (H > 7) then Exit;
        SendD('B', Copy(Data, 1, 2) + RChar(W * 8 + H) + Copy(Data, 5, MaxInt));
        Result := True;
      end;
  end;
end;

procedure TAdventureClient.Flush;
begin
  FGame.Flush;
  FLevel.Flush;
end;

procedure TAdventureClient.HandleD(const Data: string);
var
  P, S: string;
  Kind: Char;
  I, N, W, H, Who: Integer;
begin
  { sid:2, type:1, payload (the D is already gone) }
  if Length(Data) < 3 then Exit;
  Who := IdNumber(DecodeSid(Copy(Data, 1, 2)));
  Kind := Data[3];
  P := Copy(Data, 4, MaxInt);
  case Kind of
    'P': { x, y in half tiles, sprite = frame*4 + direction }
      if Length(P) >= 3 then
        Deliver(PLO_OTHERPLPROPS, GShort(Who) +
          GChar(PLPROP_X) + P[1] + GChar(PLPROP_Y) + P[2] +
          GChar(PLPROP_SPRITE) + P[3]);
    'N':
      Deliver(PLO_OTHERPLPROPS, GShort(Who) + GChar(PLPROP_NICKNAME) + GString(P));
    'C':
      Deliver(PLO_OTHERPLPROPS, GShort(Who) + GChar(PLPROP_CURCHAT) + GString(P));
    'S': { count, then that many colour indices }
      if Length(P) >= 1 then
      begin
        N := RVal(P[1]);
        if (N < 1) or (N > 8) or (Length(P) < 1 + N) then Exit;
        S := '';
        for I := 0 to 4 do
          if I < N then S := S + P[2 + I] else S := S + GChar(0);
        Deliver(PLO_OTHERPLPROPS, GShort(Who) + GChar(PLPROP_COLORS) + S);
      end;
    'I': { left the level or took a link }
      Deliver(PLO_OTHERPLPROPS, GShort(Who) + GChar(PLPROP_JOINLEAVELVL) + GChar(0));
    'B': { x, y, w*8+h, tiles  ->  x, y, w, h, tiles }
      if Length(P) >= 3 then
      begin
        W := RVal(P[3]) div 8;
        H := RVal(P[3]) mod 8;
        if (W < 0) or (H < 0) then Exit;
        Deliver(PLO_BOARDMODIFY, Copy(P, 1, 2) + GChar(W) + GChar(H) + Copy(P, 4, MaxInt));
      end;
  else
    Deliver(RLO_UNHANDLED, Kind + P);
  end;
end;

procedure TAdventureClient.Handle(L: TRelayLink; const R: TRelayLine);
begin
  case R.Event of
    reId:
      begin
        Log(Format('%s: id %s', [L.Game, R.Id]));
        if L = FGame then Deliver(RLO_JOINED, R.Id);
      end;
    rePeerOut, reUnpaired:
      begin
        { a player left the game, or its pairing ended: the game drops it
          (on either link: the relay tells every link when a link closes) }
        if FRoomPeers.IndexOf(R.Id) >= 0 then FRoomPeers.Delete(FRoomPeers.IndexOf(R.Id));
        Deliver(RLO_PEERLEFT, R.Id);
      end;
    rePaired:
      begin
        if (L = FLevel) and (FRoomPeers.IndexOf(R.Id) < 0) then FRoomPeers.Add(R.Id);
        { the pair is made: the game pushes its whole state on that link }
        FPushTo := L;
        try
          Deliver(RLO_PARTNER, R.Id);
        finally
          FPushTo := nil;
        end;
      end;
    reData: HandleD(R.Data);
    { NR: the server's levels come from the web; NL: local levels }
    reLevelsRemote: if L = FGame then Deliver(RLO_LEVELSOURCE, 'R');
    reLevelsLocal: if L = FGame then Deliver(RLO_LEVELSOURCE, 'L');
  end;
end;

procedure TAdventureClient.FeedLine(Link: Integer; const Line: string);
var
  L: TRelayLink;
  R: TRelayLine;
  I: Integer;
begin
  if Link = 0 then L := FGame else L := FLevel;
  R := ParseRelayLine(Copy(Line, 1, RelayLineMax));
  Inc(L.LinesIn);
  { what TRelayLink.Poll keeps for a line from the socket }
  case R.Event of
    reId: L.MyId := R.Id;
    rePeerIn:
      if (R.Id <> L.MyId) and (L.Known.IndexOf(R.Id) < 0) and
        (L.Partners.IndexOf(R.Id) < 0) then
      begin
        L.Known.Add(R.Id);
        Send(L, 'P' + R.Id);
      end;
    rePeerOut, reUnpaired:
      begin
        I := L.Known.IndexOf(R.Id);
        if I >= 0 then L.Known.Delete(I);
        I := L.Partners.IndexOf(R.Id);
        if I >= 0 then L.Partners.Delete(I);
      end;
    rePaired:
      begin
        I := L.Known.IndexOf(R.Id);
        if I >= 0 then L.Known.Delete(I);
        if L.Partners.IndexOf(R.Id) < 0 then L.Partners.Add(R.Id);
      end;
    reLevelsRemote: L.GotNR := True;
    reLevelsLocal: L.GotNL := True;
  end;
  Handle(L, R);
end;

procedure TAdventureClient.PollLink(L: TRelayLink);
var
  Lines: TList;
  I: Integer;
begin
  Lines := TList.Create;
  try
    L.Poll(Lines);
    for I := 0 to Lines.Count - 1 do
      Handle(L, PRelayLine(Lines[I])^);
  finally
    for I := 0 to Lines.Count - 1 do Dispose(PRelayLine(Lines[I]));
    Lines.Free;
  end;
end;

procedure TAdventureClient.Poll;
begin
  PollLink(FGame);
  if not FGame.Connected then
  begin
    LastError := FGame.LastError;
    if LastError = '' then LastError := 'the game server closed the link';
    FLevel.Disconnect;
    Exit;
  end;
  if FLevel.Connected then
  begin
    PollLink(FLevel);
    if not FLevel.Connected then Log('level link closed: ' + FLevel.LastError);
  end;
  { the pairing answers GRelay made go out in the same tick }
  Flush;
end;

function TAdventureClient.GetMessagesIn: Integer;
begin
  Result := FGame.LinesIn + FLevel.LinesIn;
end;

function TAdventureClient.GetMessagesOut: Integer;
begin
  Result := FGame.LinesOut + FLevel.LinesOut;
end;

function TAdventureClient.GetBytesIn: Int64;
begin
  Result := FGame.BytesIn + FLevel.BytesIn;
end;

function TAdventureClient.GetBytesOut: Int64;
begin
  Result := FGame.BytesOut + FLevel.BytesOut;
end;

end.
