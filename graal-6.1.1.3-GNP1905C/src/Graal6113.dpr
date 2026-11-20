{ Graal 6.1.1.3 (GNP1905C). The clear hello is the documented login.
  Anything after it is either refused or the lab-only fixture.

  Graal6113 --level FILE [--window] [--frames N] [--keys SCRIPT]
             [--dump FRAME.bmp]
  Graal6113 --server 127.0.0.1:PORT [--lab] [--level FILE] [--window]
             [--frames N] [--keys SCRIPT] [--dump FRAME.bmp]
  Graal6113 --lab-serve PORT [--seconds N]
  Graal6113 --server 127.0.0.1:PORT --connector 127.0.0.1:PORT [--frames N]
  Graal6113 --connector-serve PORT --conf FILE [--seconds N]

  --connector runs the 6.11 connector login: GET conf.gs, check the
  project-key signature, run the connector script (setProtocol EILLLT,
  sendRaw, setEncryptionOut). The project script sends the placeholder
  token SEI00001, which is not yet usable: the client stops after it
  until seihai-gserver-v2 handles SEI00001.
  --lab continues after the clear hello on the lab fixture. Without it the
  client sends GNP1905C and stops. The cipher is not applied.
  --password-env is accepted and never sent or logged.
  This rebuild connects only to 127.0.0.1. }
program Graal6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal6113.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal6113.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils, Classes,
  GSurface in '../../common/GSurface.pas',
  GWindow in '../../common/GWindow.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  GTypes in '../../common/GTypes.pas',
  GSocket in '../../common/GSocket.pas',
  GSecLogin in '../../common/GSecLogin.pas',
  Lab6113 in 'Lab6113.pas',
  Connector6113 in 'Connector6113.pas',
  Secure6113 in 'Secure6113.pas',
  SecureNet6113 in 'SecureNet6113.pas',
  Play6113 in 'Play6113.pas',
  Controls6113 in 'Controls6113.pas';

function ArgCount: Integer;
begin
  Result := ParamCount;
end;

function ArgAt(I: Integer): string;
begin
  Result := ParamStr(I);
end;

function HasArg(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ArgCount do
    if ArgAt(I) = Name then Result := True;
end;

function Arg(const Name, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  for I := 1 to ArgCount - 1 do
    if ArgAt(I) = Name then
    begin
      Result := ArgAt(I + 1);
      Exit;
    end;
end;

procedure Usage;
begin
  WriteLn('Graal 6.1.1.3 (GNP1905C)');
  WriteLn('  --level FILE [--window] [--frames N] [--keys SCRIPT] [--dump FILE]');
  WriteLn('  --server 127.0.0.1:PORT [--lab] [--window] [--frames N] [--keys SCRIPT]');
  WriteLn('  --lab-serve PORT [--seconds N]');
  WriteLn('  --server 127.0.0.1:PORT --connector 127.0.0.1:PORT   connector login (SEI00001, not yet usable)');
  WriteLn('  --connector-serve PORT --conf FILE [--seconds N]     lab conf.gs responder');
  WriteLn('  --connector-key FILE    trust this operator modulus (hex) instead of the open lab key');
  WriteLn('  --password-env VAR   accepted, never sent or logged');
end;

function ParseKeys(const S: string; out Dirs: array of Integer; out N: Integer): Boolean;
var
  Items: TStringList;
  I, J, Count, Star, D: Integer;
  Name: string;
begin
  Result := True;
  N := 0;
  Items := TStringList.Create;
  try
    Items.Delimiter := ',';
    Items.StrictDelimiter := True;
    Items.DelimitedText := S;
    for I := 0 to Items.Count - 1 do
    begin
      Star := Pos('*', Items[I]);
      if Star > 0 then
      begin
        Name := LowerCase(Copy(Items[I], 1, Star - 1));
        Count := StrToIntDef(Copy(Items[I], Star + 1, MaxInt), 1);
      end
      else
      begin
        Name := LowerCase(Items[I]);
        Count := 1;
      end;
      if Name = 'right' then D := 0
      else if Name = 'left' then D := 1
      else if Name = 'up' then D := 2
      else if Name = 'down' then D := 3
      else if Name = 'wait' then D := -1
      else
      begin
        Result := False;
        Exit;
      end;
      for J := 1 to Count do
      begin
        if N > High(Dirs) then Break;
        Dirs[N] := D;
        Inc(N);
      end;
    end;
  finally
    Items.Free;
  end;
end;

function Serve(Port: Word; Seconds: Integer): Integer;
var
  Srv: TLabServer;
  Start: QWord;
begin
  Result := 1;
  Srv := TLabServer.Create;
  try
    if not Srv.Listen(Port) then
    begin
      LogLine('error: ' + Srv.LastError);
      Exit;
    end;
    LogLine('lab-only fixture listening on 127.0.0.1:' + IntToStr(Srv.Port));
    Start := GetTickCount64;
    while GetTickCount64 - Start < QWord(Seconds) * 1000 do
    begin
      Srv.Pump;
      Sleep(10);
    end;
    LogLine('lab server closed; hellos ' + IntToStr(Srv.HelloCount) +
      ' moves ' + IntToStr(Srv.Moves));
    Result := 0;
  finally
    Srv.Free;
  end;
end;

function ReadFileBytes(const Path: string; out Data: string): Boolean;
var
  F: TFileStream;
begin
  Data := '';
  Result := False;
  if not FileExists(Path) then Exit;
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then F.ReadBuffer(Data[1], F.Size);
    Result := True;
  finally
    F.Free;
  end;
end;

function ServeConnector(Port: Word; const ConfFile: string; Seconds: Integer): Integer;
var
  Con: TLabConnector;
  Start: QWord;
  Body: string;
begin
  Result := 1;
  if not ReadFileBytes(ConfFile, Body) or (Body = '') then
  begin
    LogLine('error: cannot read --conf ' + ConfFile);
    Exit;
  end;
  Con := TLabConnector.Create;
  try
    Con.Reply := Body;
    if not Con.Listen(Port) then
    begin
      LogLine('error: ' + Con.LastError);
      Exit;
    end;
    LogLine('lab connector listening on 127.0.0.1:' + IntToStr(Con.Port));
    Start := GetTickCount64;
    while GetTickCount64 - Start < QWord(Seconds) * 1000 do
    begin
      Con.Pump;
      Sleep(10);
    end;
    LogLine('lab connector closed; requests ' + IntToStr(Con.Requests));
    Result := 0;
  finally
    Con.Free;
  end;
end;

function LoopPort(const Spec: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  I := Pos(':', Spec);
  if (I < 2) or (Copy(Spec, 1, I - 1) <> '127.0.0.1') then Exit;
  Result := StrToIntDef(Copy(Spec, I + 1, MaxInt), -1);
  if (Result < 1) or (Result > 65535) then Result := -1;
end;

type
  { Carries the handshake's trust-on-first-use line to the log. }
  TNoteSink = class
    procedure Note(const Line: string);
  end;

procedure TNoteSink.Note(const Line: string);
begin
  LogLine('secure login: ' + Line);
end;

{ --secure-login 127.0.0.1:PORT [--account A] [--password-env VAR]
  [--inner TOKEN] [--server-key KEY] [--secure-mode auto|required]
  [--secure-name HOST:PORT]. Runs the SEI00001 login over the game socket
  against a Seihai gserver and reports the handshake verdict. }
function RunSecureLogin: Integer;
var
  Sock: TGSocket;
  Sink: TNoteSink;
  Mode: TSecMode;
  Spec, Inner, Acct, PwName, Pw, Key, Name, Why, Prefix, Tail: string;
  I, Port: Integer;
  State: TSecState;
begin
  Result := 1;
  Spec := Arg('--secure-login', '');
  I := Pos(':', Spec);
  if (I < 2) or (Copy(Spec, 1, I - 1) <> '127.0.0.1') then
  begin
    LogLine('error: --secure-login must be 127.0.0.1:PORT');
    Result := 64; Exit;
  end;
  Port := StrToIntDef(Copy(Spec, I + 1, MaxInt), -1);
  if (Port < 1) or (Port > 65535) then
  begin
    LogLine('error: bad port'); Result := 64; Exit;
  end;
  Inner := Arg('--inner', Sei6113Inner);
  if Length(Inner) <> 8 then
  begin
    LogLine('error: --inner must be eight bytes'); Result := 64; Exit;
  end;
  Acct := Arg('--account', '');
  if Acct = '' then
  begin
    LogLine('error: --secure-login needs --account'); Result := 64; Exit;
  end;
  PwName := Arg('--password-env', '');
  Pw := '';
  if PwName <> '' then Pw := GetEnvironmentVariable(PwName);
  Key := '';
  if HasArg('--server-key') and not DecodeKey(Arg('--server-key', ''), Key) then
  begin
    LogLine('error: bad --server-key'); Result := 64; Exit;
  end;
  Mode := smRequired;
  if HasArg('--secure-mode') and not ParseSecMode(Arg('--secure-mode', 'required'), Mode) then
  begin
    LogLine('error: --secure-mode is off, auto or required'); Result := 64; Exit;
  end;
  Name := Arg('--secure-name', Spec);
  { The 6.x type byte and a key byte. The key byte only seeds the post-login
    cipher, which this login does not reach, so a fixed lab byte is used. }
  Prefix := GChar(Sei6113ClientType) + GChar(Ord('a'));
  Tail := Sei6113Tail(Acct, Pw, '');
  Sink := TNoteSink.Create;
  Sock := TGSocket.Create;
  try
    if not Sock.Connect('127.0.0.1', Word(Port)) then
    begin
      LogLine('error: ' + Sock.LastError); Exit;
    end;
    Sock.SetNoDelay(True);
    LogLine('secure login: ' + Spec + ' inner ' + Inner + ' mode ' + SecModeName(Mode));
    State := SeiSocketLogin(Sock, Mode, Prefix, Inner, '', Tail, Name, Key, Sink.Note, Why);
    case State of
      ssDone:
        begin LogLine('secure login: C1/S1/C2 complete; sealed login sent'); Result := 0; end;
      ssRefused:
        begin LogLine('secure login: the server refused the token (' + Why + ')'); Result := 2; end;
      ssNoAnswer:
        begin LogLine('secure login: no S1 from the server (' + Why + ')'); Result := 3; end;
      ssNone:
        begin LogLine('secure login: not attempted (' + Why + ')'); Result := 4; end;
    else
      LogLine('secure login: failed (' + Why + ')'); Result := 1;
    end;
  finally
    Pw := '';
    Tail := '';
    Sock.Free;
    Sink.Free;
  end;
end;

var
  Session: TSession;
  Surf: TGSurface;
  Win: TGWindow;
  LevelPath, Keys, DumpPath, Server, PwName, Pw, CtrlText, CtrlLine, KeyErr: string;
  Port, ConnPort: Integer;
  Frames, I, KeyN, Dir, Seconds, CtrlAt: Integer;
  Dirs: array[0..4095] of Integer;
  WantWindow, Shown, Lab: Boolean;
  Code: Integer;
begin
  { A windowed program on Windows has no standard output open; started by
    double-click (no arguments) the usage text crashed it with "File not
    open". Attach to the parent console, or carry on without output. }
  OpenConsoleIO;
  if HasArg('--help') or (ParamCount = 0) then
  begin
    if TextRec(Output).Mode <> fmClosed then Usage;
    Halt(0);
  end;
  if HasArg('--password-env') then
  begin
    PwName := Arg('--password-env', '');
    Pw := GetEnvironmentVariable(PwName);
    if Pw <> '' then
      LogLine('password not sent')
    else
      LogLine('password variable empty; nothing sent');
    Pw := '';
    PwName := '';
  end;
  if HasArg('--account') then
    LogLine('account not sent; the clear hello has no account field');

  if HasArg('--lab-serve') then
  begin
    Port := StrToIntDef(Arg('--lab-serve', '14900'), -1);
    Seconds := StrToIntDef(Arg('--seconds', '20'), 20);
    if (Port < 0) or (Port > 65535) then
    begin
      LogLine('error: bad port');
      Halt(64);
    end;
    Halt(Serve(Word(Port), Seconds));
  end;

  if HasArg('--connector-key') then
    if not LoadConnectorKey(Arg('--connector-key', ''), KeyErr) then
    begin
      LogLine('error: ' + KeyErr);
      Halt(64);
    end;

  { Headless unless --window. The loopback and stress scripts do not pass
    --window. A failed --window is reported and is not treated as a run. }
  if HasArg('--connector-serve') then
  begin
    Port := StrToIntDef(Arg('--connector-serve', '14901'), -1);
    Seconds := StrToIntDef(Arg('--seconds', '20'), 20);
    if (Port < 0) or (Port > 65535) then
    begin
      LogLine('error: bad port');
      Halt(64);
    end;
    Halt(ServeConnector(Word(Port), Arg('--conf', ''), Seconds));
  end;

  if HasArg('--secure-login') then
    Halt(RunSecureLogin);

  WantWindow := HasArg('--window');
  Lab := HasArg('--lab');
  Frames := StrToIntDef(Arg('--frames', '30'), 30);
  if Frames < 1 then Frames := 1;
  Keys := Arg('--keys', '');
  KeyN := 0;
  if (Keys <> '') and not ParseKeys(Keys, Dirs, KeyN) then
  begin
    LogLine('error: bad --keys');
    Halt(64);
  end;
  DumpPath := Arg('--dump', '');
  LevelPath := Arg('--level', '');

  Session := TSession.Create;
  Surf := TGSurface.Create(ViewW, ViewH);
  Win := nil;
  Code := 0;
  try
    Session.Lab := Lab;
    if LevelPath <> '' then
    begin
      if not Session.LoadLevelFile(LevelPath) then
      begin
        Code := 1;
        Exit;
      end;
    end
    else if not HasArg('--server') then
    begin
      LogLine('error: need --level or --server');
      Code := 64;
      Exit;
    end;

    if HasArg('--server') then
    begin
      Server := Arg('--server', '');
      I := Pos(':', Server);
      if (I < 2) or (Copy(Server, 1, I - 1) <> '127.0.0.1') then
      begin
        LogLine('error: --server must be 127.0.0.1:PORT');
        Code := 64;
        Exit;
      end;
      Port := StrToIntDef(Copy(Server, I + 1, MaxInt), -1);
      if (Port < 1) or (Port > 65535) then
      begin
        LogLine('error: bad port');
        Code := 64;
        Exit;
      end;
      if HasArg('--connector') then
      begin
        if Lab then
        begin
          LogLine('error: --lab continues the GNP1905C clear hello, not the connector login');
          Code := 64;
          Exit;
        end;
        ConnPort := LoopPort(Arg('--connector', ''));
        if ConnPort < 0 then
        begin
          LogLine('error: --connector must be 127.0.0.1:PORT');
          Code := 64;
          Exit;
        end;
        if not Session.ConnectViaConnector(Word(ConnPort), Word(Port)) then
        begin
          Code := 1;
          Exit;
        end;
      end
      else if not Session.ConnectTo('127.0.0.1', Word(Port)) then
      begin
        Code := 1;
        Exit;
      end;
    end;

    if HasArg('--server') and Lab then
      if not Session.WaitForLab(2000) then Code := 1;

    if Code = 0 then
    begin
      LogLine('engine quattro_lib');
      if Session.ConnectorToken <> '' then
        LogLine('token ' + Session.ConnectorToken + ' (from the connector script)')
      else
        LogLine('token GNP1905C');
      for I := 0 to ControlCount - 1 do
        LogLine('registered control ' + ControlName(I));
      CtrlText := LevelViewLog;
      while CtrlText <> '' do
      begin
        CtrlAt := Pos(#10, CtrlText);
        if CtrlAt = 0 then
        begin
          LogLine(CtrlText);
          Break;
        end;
        CtrlLine := Copy(CtrlText, 1, CtrlAt - 1);
        Delete(CtrlText, 1, CtrlAt);
        if CtrlLine <> '' then LogLine(CtrlLine);
      end;
    end;

    Shown := False;
    if (Code = 0) and WantWindow then
    begin
      Win := TGWindow.Create('Graal 6.1.1.3', ViewW, ViewH);
      Shown := Win.Ok;
      if not Shown then
      begin
        LogLine('the client was not shown');
        Code := 1;
        Exit;
      end;
      LogLine('window shown');
    end
    else
      LogLine('headless');

    for I := 1 to Frames do
    begin
      if Session.Phase = phError then Break;
      Session.Pump;
      if KeyN > 0 then
      begin
        if I - 1 < KeyN then Dir := Dirs[I - 1] else Dir := -1;
        if Dir = 0 then Session.MoveBy(LabStep, 0)
        else if Dir = 1 then Session.MoveBy(-LabStep, 0)
        else if Dir = 2 then Session.MoveBy(0, -LabStep)
        else if Dir = 3 then Session.MoveBy(0, LabStep);
      end
      else if Shown then
      begin
        Win.Pump;
        if Win.Closed or Win.WasPressed(gkEscape) then Break;
        if Win.Held[gkRight] then Session.MoveBy(LabStep, 0);
        if Win.Held[gkLeft] then Session.MoveBy(-LabStep, 0);
        if Win.Held[gkUp] then Session.MoveBy(0, -LabStep);
        if Win.Held[gkDown] then Session.MoveBy(0, LabStep);
      end;
      if Lab and (Session.Phase = phLabWorld) then Sleep(20);
      Session.Render(Surf);
      if Shown then
      begin
        Win.Present(Surf);
        Win.Pump;
        Sleep(30);
      end;
    end;
    if DumpPath <> '' then
      Surf.SaveBMP(DumpPath);
    if Session.Phase = phError then Code := 1;
    WriteLn(Session.SummaryJson);
  finally
    Win.Free;
    Surf.Free;
    Session.Free;
  end;
  Halt(Code);
end.
