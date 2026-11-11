{ Play6113: window world, login state, and the lab continuation.

  verified-from-evidence:
    the socket is TCP. The connect path does not open a datagram socket.
    The first client bytes are the clear hello GNP1905C. After that, if the
    caller did not ask for the lab fixture, further server bytes are counted
    and not decoded. Property strings are stored by the four tclient setters.
  provisional adapter:
    the picture is a software surface of solid colours, shown by the repo
    window. The original playfield is quattro_lib OpenGL, not this surface,
    and not a Torque SimObject. The camera follows the local box because no
    camera constant was recovered.
  lab-only fixture:
    collision, the step size, the colours, and every lab message. None of
    those are claimed as 6.1.1.3 movement or properties.

  Sources: protocol/v6113-hello.md, protocol/v6113-udp.md, manual section
  2.9.5, client-internals/unpacked-6113.md, manual section 10.1.12. }
unit Play6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, Frame6113, Props6113, Level6113, Connector6113;

const
  ViewW = 240;
  ViewH = 180;
  LabStep = 4;
  ColOutside = $FF101410;
  ColFloor = $FF2E6B3A;
  ColWall = $FF242424;
  ColPlayer = $FF3A7BD5;
  ColOther = $FFD08A2A;
  ColInk = $FFF2F2F2;
  ColBar = $FF101010;

type
  TPhase = (phIdle, phConnecting, phTcpUp, phHelloSent, phStoppedClear,
    phLabWorld, phError, phSeiPending);

  TLogFn = procedure(const S: string);

  TSession = class
  public
    Phase: TPhase;
    Err: string;
    Lab: Boolean;
    BytesAfterHello: Integer;
    UdpOpens: Integer;
    MyId, OtherId: Integer;
    MyX, MyY, OtherX, OtherY: Integer;
    HasOther: Boolean;
    CamX, CamY: Integer;
    MovesSent: Integer;
    { Connector path results. }
    ConnectorToken: string;
    ConnectorSteps: Integer;
    ConnectorIdle: TIdleProc;
    Proto: TProtocol;
    Props: TPropBag;
    Level: TLabLevel;
    constructor Create;
    destructor Destroy; override;
    function LoadLevelText(const Text: string): Boolean;
    function LoadLevelFile(const Path: string): Boolean;
    function ConnectTo(const Host: string; Port: Word): Boolean;
    { The 6.11 connector login: GET conf.gs from the connector, verify,
      decrypt, connect to the game port, run the connector script. Stops
      after the SEI00001 hello (not yet usable). }
    function ConnectViaConnector(ConnectorPort, GamePort: Word): Boolean;
    function WaitForLab(Ms: Integer): Boolean;
    procedure Pump;
    procedure MoveBy(DX, DY: Integer);
    procedure Render(Surf: TGSurface);
    function PhaseName: string;
    function EndToken: string;
    function SummaryJson: string;
  private
    FSock: TObject;
    FRx: string;
    FHelloSent: Boolean;
    FNeedReady: Boolean;
    procedure Fail(const Msg: string);
    function SendGame(const Wire: string): Boolean;
    procedure UpdateCamera;
    procedure SendLabMove;
    procedure OnLab(const Payload: string);
  end;

var
  SessionLog: TLogFn = nil;

procedure LogLine(const S: string);

implementation

uses
  SysUtils, GSocket, Lab6113;

procedure LogLine(const S: string);
begin
  if Assigned(SessionLog) then SessionLog(S)
  else
  begin
    WriteLn(ErrOutput, S);
    Flush(ErrOutput);
  end;
end;

function Pattern(C: Char): string;
begin
  case UpCase(C) of
    '0': Result := '####.##.##.####';
    '1': Result := '.#..#..#..#..#.';
    '2': Result := '###..#####..###';
    '3': Result := '###..####..####';
    '4': Result := '#.##.####..#..#';
    '5': Result := '####..###..####';
    '6': Result := '####..####.####';
    '7': Result := '###..#..#..#..#';
    '8': Result := '####.#####.####';
    '9': Result := '####.####..####';
    'A': Result := '.#.#.#####.##.#';
    'B': Result := '##.#.###.#.###.';
    'C': Result := '####..#..#..###';
    'D': Result := '##.#.##.##.###.';
    'E': Result := '####..####..###';
    'G': Result := '####..#.##.####';
    'H': Result := '#.##.#####.##.#';
    'I': Result := '###.#..#..#.###';
    'L': Result := '#..#..#..#..###';
    'M': Result := '#.#####.##.##.#';
    'N': Result := '#.########.##.#';
    'O': Result := '####.##.##.####';
    'P': Result := '####.#####..#..';
    'R': Result := '####.######.#.#';
    'S': Result := '####..###..####';
    'T': Result := '###.#..#..#..#.';
    'W': Result := '#.##.##.#####.#';
    'X': Result := '#.##.#.#.#.##.#';
    'Y': Result := '#.##.#.#..#..#.';
    '-': Result := '......###......';
    ':': Result := '.#.....#.......';
    ' ': Result := '...............';

  else
    Result := '...............';
  end;
end;

procedure DrawText(Surf: TGSurface; X, Y: Integer; const S: string; Color: Cardinal);
var
  I, Row, Col: Integer;
  G: string;
begin
  for I := 1 to Length(S) do
  begin
    G := Pattern(S[I]);
    for Row := 0 to 4 do
      for Col := 0 to 2 do
        if G[Row * 3 + Col + 1] = '#' then
          Surf.FillRect(X + (I - 1) * 8 + Col * 2, Y + Row * 2, 2, 2, Color);
  end;
end;

constructor TSession.Create;
begin
  inherited Create;
  Phase := phIdle;
  Proto := TProtocol.Create;
  Props := TPropBag.Create;
  Level := TLabLevel.Create;
  FSock := TGSocket.Create;
  UdpOpens := 0;
end;

destructor TSession.Destroy;
begin
  TGSocket(FSock).Free;
  Level.Free;
  Props.Free;
  Proto.Free;
  inherited Destroy;
end;

procedure TSession.Fail(const Msg: string);
begin
  Phase := phError;
  Err := Msg;
  LogLine('error: ' + Msg);
end;

function TSession.LoadLevelText(const Text: string): Boolean;
begin
  Result := Level.LoadText(Text, Err);
  if not Result then
  begin
    Phase := phError;
    LogLine('error: ' + Err);
    Exit;
  end;
  MyX := Level.StartX;
  MyY := Level.StartY;
  HasOther := Level.HasOther;
  OtherX := Level.OtherX;
  OtherY := Level.OtherY;
  OtherId := 0;
  if HasOther then
  begin
    Props.SetOther(LabEncodeProps('name=marker'));
    LogLine('lab-only local marker placed');
  end;
  UpdateCamera;
  LogLine('lab level loaded');
end;

function TSession.LoadLevelFile(const Path: string): Boolean;
begin
  Result := Level.LoadFile(Path, Err);
  if not Result then
  begin
    Phase := phError;
    LogLine('error: ' + Err);
    Exit;
  end;
  MyX := Level.StartX;
  MyY := Level.StartY;
  HasOther := Level.HasOther;
  OtherX := Level.OtherX;
  OtherY := Level.OtherY;
  if HasOther then
    Props.SetOther(LabEncodeProps('name=marker'));
  UpdateCamera;
  LogLine('lab level loaded');
end;

procedure TSession.UpdateCamera;
var
  MaxX, MaxY, WorldW, WorldH: Integer;
begin
  if Level.W <= 0 then
  begin
    CamX := 0;
    CamY := 0;
    Exit;
  end;
  WorldW := Level.W * CellPx;
  WorldH := Level.H * CellPx;
  CamX := MyX + CellPx div 2 - ViewW div 2;
  CamY := MyY + CellPx div 2 - ViewH div 2;
  MaxX := WorldW - ViewW;
  MaxY := WorldH - ViewH;
  if MaxX < 0 then MaxX := 0;
  if MaxY < 0 then MaxY := 0;
  if CamX < 0 then CamX := 0;
  if CamY < 0 then CamY := 0;
  if CamX > MaxX then CamX := MaxX;
  if CamY > MaxY then CamY := MaxY;
end;

function TSession.ConnectTo(const Host: string; Port: Word): Boolean;
var
  Wire: string;
  Sock: TGSocket;
begin
  Result := False;
  Sock := TGSocket(FSock);
  UdpOpens := 0;
  if Host <> '127.0.0.1' then
  begin
    Fail('this rebuild only connects to 127.0.0.1');
    Exit;
  end;
  Phase := phConnecting;
  LogLine('connecting');
  if not Sock.Connect(Host, Port) then
  begin
    Fail(Sock.LastError);
    Exit;
  end;
  Sock.SetNoDelay(True);
  Phase := phTcpUp;
  LogLine('tcp up; datagram sockets opened: 0');
  if not Proto.SendRaw(ClearHello, Wire) then
  begin
    Fail('clear hello was not built');
    Exit;
  end;
  if Wire <> ClearHello then
  begin
    Fail('clear hello gained a header');
    Exit;
  end;
  if not Sock.Send(Wire) then
  begin
    Fail(Sock.LastError);
    Exit;
  end;
  FHelloSent := True;
  Phase := phHelloSent;
  LogLine('clear hello sent');
  FNeedReady := Lab;
  if not Lab then
  begin
    Phase := phStoppedClear;
    LogLine('stopped at clear hello; cipher not identified');
  end;
  Result := True;
end;

function TSession.SendGame(const Wire: string): Boolean;
begin
  Result := TGSocket(FSock).Send(Wire);
end;

function TSession.ConnectViaConnector(ConnectorPort, GamePort: Word): Boolean;
var
  Reply, Sig, Payload, Script, Err: string;
  Steps: TConnectorSteps;
  Sock: TGSocket;
begin
  Result := False;
  Sock := TGSocket(FSock);
  UdpOpens := 0;
  Phase := phConnecting;
  LogLine('connector: GET ' + ConfPath);
  if not FetchConfReply(ConnectorPort, 3000, ConnectorIdle, Reply, Err) then
  begin
    Fail(Err);
    Exit;
  end;
  if not ParseConfReply(Reply, Sig, Payload, Err) then
  begin
    Fail(Err);
    Exit;
  end;
  { The signature is checked before anything is decrypted or run. }
  if not VerifyConfReply(Sig, Payload, Err) then
  begin
    Fail('connector reply refused: ' + Err);
    Exit;
  end;
  LogLine('connector: signature verified (project key)');
  if not DecryptConfPayload(Payload, Script, Err) then
  begin
    Fail(Err);
    Exit;
  end;
  if PayloadCipherPending then
    LogLine('connector: payload cipher pending; payload read as clear');
  if not ParseConnectorScript(Script, Steps, Err) then
  begin
    Fail(Err);
    Exit;
  end;
  ConnectorSteps := Length(Steps);
  if not Sock.Connect('127.0.0.1', GamePort) then
  begin
    Fail(Sock.LastError);
    Exit;
  end;
  Sock.SetNoDelay(True);
  Phase := phTcpUp;
  LogLine('tcp up; datagram sockets opened: 0');
  if not RunConnectorSteps(Steps, Proto, SendGame, ConnectorToken, Err) then
  begin
    Fail(Err);
    Exit;
  end;
  if ConnectorToken = '' then
  begin
    Fail('connector script sent no token');
    Exit;
  end;
  FHelloSent := True;
  Phase := phHelloSent;
  LogLine('connector: header template ' + ConnectorTemplate + ' set');
  LogLine('connector hello sent: ' + ConnectorToken);
  if (ConnectorToken = SeiToken) and not SeiTokenUsable then
  begin
    Phase := phSeiPending;
    LogLine('stopped after SEI00001 hello; ' + SeiPendingNote);
  end
  else
    Phase := phStoppedClear;
  Result := True;
end;

function TSession.WaitForLab(Ms: Integer): Boolean;
var
  Start: QWord;
begin
  Start := GetTickCount64;
  while (Phase <> phLabWorld) and (Phase <> phError) and
    (GetTickCount64 - Start < QWord(Ms)) do
  begin
    Pump;
    Sleep(10);
  end;
  Result := Phase = phLabWorld;
  if not Result and (Phase <> phError) then
    Fail('lab fixture did not answer');
end;

procedure TSession.OnLab(const Payload: string);
var
  Id, Kind, X, Y, PLen: Integer;
  Raw, Body: string;
begin
  if Payload = '' then
  begin
    Fail('empty lab message');
    Exit;
  end;
  if FNeedReady then
  begin
    if (Ord(Payload[1]) <> ltReady) or
      (Copy(Payload, 2, Length(LabReadyText)) <> LabReadyText) then
    begin
      Fail('lab fixture rejected: first server payload is not the lab marker');
      Exit;
    end;
    FNeedReady := False;
    Phase := phLabWorld;
    LogLine('lab-only: cipher not identified, continuing on the lab fixture');
    Exit;
  end;
  case Ord(Payload[1]) of
    ltYourId:
      if Length(Payload) >= 3 then MyId := Ord(Payload[2]) shl 8 + Ord(Payload[3]);
    ltSpawn:
      begin
        if Length(Payload) < 10 then
        begin
          Fail('short lab spawn');
          Exit;
        end;
        Id := Ord(Payload[2]) shl 8 + Ord(Payload[3]);
        Kind := Ord(Payload[4]);
        X := Ord(Payload[5]) shl 8 + Ord(Payload[6]);
        Y := Ord(Payload[7]) shl 8 + Ord(Payload[8]);
        PLen := Ord(Payload[9]) shl 8 + Ord(Payload[10]);
        if Length(Payload) < 10 + PLen then
        begin
          Fail('lab spawn truncated');
          Exit;
        end;
        Raw := Copy(Payload, 11, PLen);
        if Kind = 2 then
        begin
          OtherId := Id;
          OtherX := X;
          OtherY := Y;
          HasOther := True;
          Props.SetOther(Raw);
          if LabDecodeProps(Raw, Body) then
            LogLine('other entity ' + IntToStr(Id) + ' props ' + Body)
          else
            LogLine('other entity ' + IntToStr(Id) + ' stored');
        end
        else if Kind = 1 then
          Props.SetPlayer(Raw);
      end;
    ltMove:
      begin
        if Length(Payload) < 7 then Exit;
        Id := Ord(Payload[2]) shl 8 + Ord(Payload[3]);
        X := Ord(Payload[4]) shl 8 + Ord(Payload[5]);
        Y := Ord(Payload[6]) shl 8 + Ord(Payload[7]);
        if Id = OtherId then
        begin
          OtherX := X;
          OtherY := Y;
        end
        else if Id = MyId then
        begin
          MyX := X;
          MyY := Y;
          UpdateCamera;
        end;
      end;
    ltProps:
      begin
        if Length(Payload) < 5 then Exit;
        Id := Ord(Payload[2]) shl 8 + Ord(Payload[3]);
        PLen := Ord(Payload[4]) shl 8 + Ord(Payload[5]);
        if Length(Payload) < 5 + PLen then Exit;
        Raw := Copy(Payload, 6, PLen);
        if Id = MyId then Props.SetPlayer(Raw)
        else
        begin
          OtherId := Id;
          HasOther := True;
          Props.SetOther(Raw);
          if LabDecodeProps(Raw, Body) then
            LogLine('other entity ' + IntToStr(Id) + ' props ' + Body);
        end;
      end;
  else
    Fail('unknown lab message');
  end;
end;

procedure TSession.Pump;
var
  Sock: TGSocket;
  Old: Integer;
  Payload: string;
begin
  if Phase = phError then Exit;
  if not FHelloSent then Exit;
  Sock := TGSocket(FSock);
  Old := Length(FRx);
  if not Sock.Poll(FRx) then
  begin
    if Phase = phStoppedClear then
    begin
      LogLine('link closed after the clear hello');
      Exit;
    end;
    if Phase = phSeiPending then
    begin
      LogLine('link closed after the SEI00001 hello');
      Exit;
    end;
    Fail(Sock.LastError);
    Exit;
  end;
  if Phase = phSeiPending then
  begin
    Inc(BytesAfterHello, Length(FRx) - Old);
    if Length(FRx) > Old then
      LogLine('received ' + IntToStr(Length(FRx) - Old) +
        ' bytes after the SEI00001 hello; not decoded');
    FRx := '';
    Exit;
  end;
  if not Lab then
  begin
    Inc(BytesAfterHello, Length(FRx) - Old);
    if Length(FRx) > Old then
      LogLine('received ' + IntToStr(Length(FRx) - Old) +
        ' bytes after the clear hello; cipher not identified; not decoded');
    FRx := '';
    Exit;
  end;
  if Phase = phStoppedClear then Exit;
  while (Phase <> phError) and LabTryPop(FRx, Payload) do
    OnLab(Payload);
end;

procedure TSession.SendLabMove;
var
  Sock: TGSocket;
  Wire: string;
begin
  if Phase <> phLabWorld then Exit;
  Sock := TGSocket(FSock);
  Wire := LabClientMove(MyX, MyY);
  if not Sock.Send(Wire) then
  begin
    Fail(Sock.LastError);
    Exit;
  end;
  Inc(MovesSent);
end;

procedure TSession.MoveBy(DX, DY: Integer);
var
  Moved: Boolean;
begin
  if Level.W <= 0 then Exit;
  Moved := False;
  if (DX <> 0) and Level.Fits(MyX + DX, MyY, CellPx) then
  begin
    Inc(MyX, DX);
    Moved := True;
  end;
  if (DY <> 0) and Level.Fits(MyX, MyY + DY, CellPx) then
  begin
    Inc(MyY, DY);
    Moved := True;
  end;
  if Moved then
  begin
    UpdateCamera;
    SendLabMove;
  end;
end;

procedure TSession.Render(Surf: TGSurface);
var
  X0, Y0, X1, Y1, CX, CY, SX, SY: Integer;
  Bar: string;
begin
  Surf.Fill(ColOutside);
  if Level.W > 0 then
  begin
    X0 := CamX div CellPx;
    Y0 := CamY div CellPx;
    X1 := (CamX + ViewW - 1) div CellPx;
    Y1 := (CamY + ViewH - 1) div CellPx;
    if X0 < 0 then X0 := 0;
    if Y0 < 0 then Y0 := 0;
    if X1 >= Level.W then X1 := Level.W - 1;
    if Y1 >= Level.H then Y1 := Level.H - 1;
    for CY := Y0 to Y1 do
      for CX := X0 to X1 do
      begin
        SX := CX * CellPx - CamX;
        SY := CY * CellPx - CamY;
        if Level.SolidCell(CX, CY) then
          Surf.FillRect(SX, SY, CellPx, CellPx, ColWall)
        else
          Surf.FillRect(SX, SY, CellPx, CellPx, ColFloor);
      end;
  end;
  if HasOther then
    Surf.FillRect(OtherX - CamX, OtherY - CamY, CellPx, CellPx, ColOther);
  Surf.FillRect(MyX - CamX, MyY - CamY, CellPx, CellPx, ColPlayer);
  Surf.FillRect(0, ViewH - 16, ViewW, 16, ColBar);
  Bar := PhaseName;
  if Phase = phError then Bar := 'ERROR';
  DrawText(Surf, 4, ViewH - 14, Bar, ColInk);
end;

function TSession.PhaseName: string;
begin
  case Phase of
    phIdle: Result := 'LOCAL';
    phConnecting: Result := 'CONNECTING';
    phTcpUp: Result := 'TCP';
    phHelloSent: Result := 'HELLO';
    phStoppedClear: Result := 'STOP';
    phLabWorld: Result := 'LAB';
    phError: Result := 'ERROR';
    phSeiPending: Result := 'SEI PENDING';
  else
    Result := 'ERROR';
  end;
end;

function TSession.EndToken: string;
begin
  if Phase = phError then Result := 'error'
  else if Phase = phStoppedClear then Result := 'clear-hello'
  else if Phase = phSeiPending then Result := 'sei-pending'
  else Result := 'clean';
end;

function TSession.SummaryJson: string;
var
  OtherBit: string;
begin
  if HasOther then OtherBit := 'true' else OtherBit := 'false';
  Result := '{"kind":"summary","end":"' + EndToken + '","phase":"' + PhaseName +
    '","udp":' + IntToStr(UdpOpens) + ',"moves":' + IntToStr(MovesSent) +
    ',"bytesAfterHello":' + IntToStr(BytesAfterHello) + ',"other":' + OtherBit + '}';
end;

end.
