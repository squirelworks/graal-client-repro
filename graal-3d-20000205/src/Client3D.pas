{ Client3D: the Graal3D link to its server (TCP 14901) and to the other
  players (UDP), and what each message does to the world.

  Each tick, as the original's frame timer: read TCP, read UDP, move,
  diff the local player's props and queue the changes as one props line,
  send changed positions to UDP peers, flush the TCP queue.
  Source: graal_analysis graal3d/protocol.md. }
unit Client3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSocket, Codec3D, Udp3D, World3D;

const
  SentProps: array[0..14] of Integer = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 17);

type
  TFindLevel = function(const Name: string): string of object;

  TClient3D = class
  private
    FSock: TGSocket;
    FUdp: TUdp3D;
    FRecv: string;
    FQueue: string;
    FSent: array[0..PropCount - 1] of string;
    FSentAny: Boolean;
    FLastPos: string;
    FRawNext: Boolean;
    procedure HandleMessage(Id: Integer; const Data: string);
    procedure LoadLevelText(const Text: string);
    procedure SendUdpToPeers(const Data: string);
  public
    World: TWorld3D;
    DataDir: string;
    FindLevel: TFindLevel;
    LevelName: string;
    LoggedIn: Boolean;
    Connected: Boolean;
    DiscMessage: string;
    AdminMessage: string;
    LastError: string;
    Leader: Boolean;
    LevelsLoaded: Integer;
    LinesIn, LinesOut, UdpIn, UdpOut: Integer;
    Log: procedure(const S: string) of object;
    constructor Create(AWorld: TWorld3D);
    destructor Destroy; override;
    { Connects, binds UDP (unless NoUdp), and queues the login line and the
      first props line, which go out in the same frame. }
    function Connect(const Host: string; Port: Integer; const Account, Password: string;
      NoUdp: Boolean; FixedUdpPort: Integer): Boolean;
    procedure Close;
    { Reads TCP and UDP and applies what came in. }
    procedure Receive;
    { Queues the props that changed since the last call. }
    procedure SendProps;
    { A chat line: to UDP peers at once, to the server in the next diff. }
    procedure Say(const Text: string);
    procedure Flush;
    function UdpPort: Integer;
    { Test hooks: feed received lines; take the queued lines. }
    procedure FeedLines(const Lines: string);
    function TakeQueue: string;
  end;

implementation

uses
  SysUtils, Classes, GTypes;

constructor TClient3D.Create(AWorld: TWorld3D);
begin
  inherited Create;
  World := AWorld;
  FSock := TGSocket.Create;
  FUdp := TUdp3D.Create;
end;

destructor TClient3D.Destroy;
begin
  FUdp.Free;
  FSock.Free;
  inherited Destroy;
end;

function TClient3D.UdpPort: Integer;
begin
  if FUdp.Active then Result := FUdp.Port else Result := 0;
end;

function TClient3D.Connect(const Host: string; Port: Integer; const Account, Password: string;
  NoUdp: Boolean; FixedUdpPort: Integer): Boolean;
begin
  Result := False;
  LoggedIn := False;
  DiscMessage := '';
  FQueue := '';
  FRecv := '';
  FSentAny := False;
  if not FSock.Connect(Host, Port) then
  begin
    LastError := FSock.LastError;
    Exit;
  end;
  Connected := True;
  if not NoUdp then FUdp.Open(FixedUdpPort);
  World.Me.UdpPort := UdpPort;
  FQueue := LoginLine(Account, Password);
  Inc(LinesOut);
  SendProps;
  Flush;
  Result := True;
end;

procedure TClient3D.Close;
begin
  FSock.Close;
  FUdp.Close;
  Connected := False;
end;

function TClient3D.TakeQueue: string;
begin
  Result := FQueue;
  FQueue := '';
end;

procedure TClient3D.SendProps;
var
  I: Integer;
  E, Line: string;
begin
  Line := '';
  for I := 0 to High(SentProps) do
  begin
    E := EncodeProp(World.Me, SentProps[I]);
    if not FSentAny or (E <> FSent[SentProps[I]]) then
    begin
      Line := Line + E;
      FSent[SentProps[I]] := E;
    end;
  end;
  FSentAny := True;
  if Line <> '' then
  begin
    FQueue := FQueue + MessageLine(CL_PROPS, Line);
    Inc(LinesOut);
  end;
  { positions to the UDP peers when props 1..5 changed }
  E := EncodePosBody(World.Me);
  if E <> FLastPos then
  begin
    FLastPos := E;
    SendUdpToPeers(GChar(UDP_POS) + E);
  end;
end;

procedure TClient3D.SendUdpToPeers(const Data: string);
var
  I: Integer;
begin
  if not FUdp.Active then Exit;
  for I := 0 to High(World.Others) do
    with World.Others[I].P do
      if InLevel and (UdpPort > 0) and (Ip <> 0) then
        if FUdp.SendTo(Ip, UdpPort, Data) then Inc(UdpOut);
end;

procedure TClient3D.Say(const Text: string);
var
  T: string;
begin
  T := Text;
  if Length(T) > 200 then T := Copy(T, 1, 197) + '...';
  World.Me.Chat := T;
  World.AddChat(World.Me.Nick + ': ' + T);
  SendUdpToPeers(GChar(UDP_CHAT) + T);
end;

procedure TClient3D.Flush;
var
  Lines, Frame: string;
begin
  if not Connected or (FQueue = '') then Exit;
  Lines := FQueue;
  FQueue := '';
  Frame := BuildFrame(Lines);
  if not FSock.Send(Frame) then
  begin
    Connected := False;
    LastError := FSock.LastError;
  end;
end;

function ReadFileText(const FileName: string): string;
var
  F: TFileStream;
begin
  Result := '';
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  except
    Result := '';
  end;
end;

procedure TClient3D.LoadLevelText(const Text: string);
var
  Name, Path: string;
  F: TFileStream;
  OK: Boolean;
begin
  { the level is saved under its name in the program's own folder; only
    the bare file name is used, never a path the server sent }
  Name := ExtractFileName(StringReplace(LevelName, '\', '/', [rfReplaceAll]));
  if (Name = '') or (Name = '.') or (Name = '..') then Name := 'level.x';
  OK := False;
  if Text <> '' then
  begin
    if DataDir <> '' then
      try
        F := TFileStream.Create(IncludeTrailingPathDelimiter(DataDir) + Name, fmCreate);
        try
          F.WriteBuffer(Text[1], Length(Text));
        finally
          F.Free;
        end;
      except
        { a read-only folder: the level still loads from memory }
      end;
    OK := World.Level.Load(Name, Text);
  end
  else
  begin
    { "you already have it" }
    if Assigned(FindLevel) then Path := FindLevel(Name) else Path := '';
    if Path <> '' then
      OK := World.Level.Load(Name, ReadFileText(Path));
  end;
  if OK then Inc(LevelsLoaded)
  else if Assigned(Log) then Log('level ' + Name + ' did not load');
  World.ResetCamera;
end;

procedure TClient3D.HandleMessage(Id: Integer; const Data: string);
var
  P: TPlayer3D;
  Bits: Cardinal;
  R: TGReader;
  PlId: Integer;
  Rest: string;
begin
  case Id of
    SV_LEVELNAME: LevelName := Data;
    SV_LEVEL:
      begin
        LoadLevelText(FromWire(Data));
        Leader := False;
      end;
    SV_OTHERPLPROPS:
      begin
        if Data = '' then Exit;
        R := TGReader.Create(Data);
        try
          PlId := R.ReadGChar;
          Rest := R.ReadRest;
        finally
          R.Free;
        end;
        P := World.AddPlayer(PlId);
        Bits := ApplyProps(P.P, Rest);
        P.P.Id := PlId;
        if P.P.Left then
        begin
          World.RemovePlayer(PlId);
          Exit;
        end;
        if (Bits and (1 shl PP_CHAT) <> 0) and (P.P.Chat <> '') then
          World.AddChat(P.P.Nick + ': ' + P.P.Chat);
        if Assigned(Log) and (Bits and (1 shl PP_NICK) <> 0) then
          Log(Format('other player %d %s', [PlId, P.P.Nick]));
      end;
    SV_PLAYERPROPS:
      begin
        Bits := ApplyProps(World.Me, Data);
        if not LoggedIn and Assigned(Log) then
          Log(Format('logged in as player %d', [World.Me.Id]));
        LoggedIn := True;
        if Bits and ((1 shl PP_X) or (1 shl PP_Y) or (1 shl PP_Z)) <> 0 then
          World.ResetCamera;
        { what the server echoes back is what it has: no need to send it again }
        if Bits and (1 shl PP_NICK) <> 0 then FSent[PP_NICK] := EncodeProp(World.Me, PP_NICK);
      end;
    SV_LEADER: Leader := True;
    SV_DISCMESSAGE: DiscMessage := Data;
    SV_SESSION: ;
    SV_ADMINMESSAGE: AdminMessage := FromWire(Data);
    SV_RAWDATA: FRawNext := True;
  end;
end;

procedure TClient3D.FeedLines(const Lines: string);
var
  S, Line: string;
  P: Integer;
begin
  S := Lines;
  while S <> '' do
  begin
    P := Pos(#10, S);
    if P = 0 then P := Length(S) + 1;
    Line := Copy(S, 1, P - 1);
    Delete(S, 1, P);
    Inc(LinesIn);
    if FRawNext then
    begin
      { raw data: flagged, then dropped }
      FRawNext := False;
      Continue;
    end;
    if Line = '' then Continue;
    HandleMessage(Ord(Line[1]) - 32, Copy(Line, 2, MaxInt));
  end;
end;

procedure TClient3D.Receive;
var
  Lines, D: string;
  Addr: Cardinal;
  Port, I: Integer;
  P: TPlayer3D;
begin
  if Connected then
  begin
    if not FSock.Poll(FRecv) then
    begin
      Connected := False;
      LastError := FSock.LastError;
    end;
    if not TakeFrames(FRecv, Lines) then
    begin
      LastError := 'bad frame from the server';
      FSock.Close;
      Connected := False;
    end;
    if Lines <> '' then FeedLines(Lines);
  end;
  { UDP: only from a known player's address and port }
  while FUdp.Active and FUdp.Receive(D, Addr, Port) do
  begin
    P := nil;
    for I := 0 to High(World.Others) do
      if (World.Others[I].P.Ip = Addr) and (World.Others[I].P.UdpPort = Port) then
      begin
        P := World.Others[I];
        Break;
      end;
    if (P = nil) or (D = '') then Continue;
    Inc(UdpIn);
    case Ord(D[1]) - 32 of
      UDP_POS: ApplyPosBody(P.P, Copy(D, 2, MaxInt));
      UDP_CHAT:
        begin
          P.P.Chat := Copy(D, 2, 200);
          World.AddChat(P.P.Nick + ': ' + P.P.Chat);
        end;
    end;
  end;
end;

end.
