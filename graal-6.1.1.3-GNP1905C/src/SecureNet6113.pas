{ SecureNet6113: the socket transport for the 6.1.1.3 SEI00001 secure login.

  The handshake and its pinning are the shared common/GSecLogin
  (TSecSession); this unit carries its three lines over the game socket in
  the plain zlib login frames the Seihai gserver reads, the same framing the
  6.0x folders use:

    frame = FrameLen(len(Z)) + Z,  Z = ZCompress(line + #10)

  where FrameLen is a 16-bit big-endian length, or the long form
  0xFFFF then a 32-bit big-endian length. C1 goes out, S1 comes back in one
  such frame, C2 goes out, and the session then continues in the inner
  build's coding (which this slice does not decode).

  SEI00001 is Seihai's own login, not part of any Graal build. }
unit SecureNet6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSocket, GSecLogin;

const
  { The 6.x client type byte (generation 5), as the gserver reads it from
    the login prefix. The key byte only seeds the post-login cipher. }
  Sei6113ClientType = 5;
  LongFrameMark = $FFFF;

{ A handshake line wrapped in one plain zlib login frame. }
function SeiFrameEncode(const Line: string): string;

{ Pop one whole frame from Buf (removing its bytes) and inflate it into
  Line. False (Buf unchanged) when Buf does not yet hold a whole frame;
  sets Bad when a frame is malformed or does not inflate. }
function SeiFramePop(var Buf: string; out Line: string; out Bad: Boolean): Boolean;

{ Run the SEI00001 login over an already-connected socket. Prefix is the
  type and key bytes; Inner the inner token; Tail the sealed login tail.
  Server is "host:port" (the pin name); GivenKey, when set, is the only
  server key trusted. Note receives the trust-on-first-use line. On success
  the result is ssDone and C2 has been sent. }
function SeiSocketLogin(Sock: TGSocket; Mode: TSecMode;
  const Prefix, Inner, Suffix, Tail, Server, GivenKey: string;
  Note: TNoteProc; out Why: string): TSecState;

implementation

uses
  SysUtils, GZlib;

function FrameLen(Len: Integer): string;
begin
  if Len >= LongFrameMark then
    Result := Chr($FF) + Chr($FF) + Chr((Len shr 24) and $FF) +
      Chr((Len shr 16) and $FF) + Chr((Len shr 8) and $FF) + Chr(Len and $FF)
  else
    Result := Chr((Len shr 8) and $FF) + Chr(Len and $FF);
end;

function SeiFrameEncode(const Line: string): string;
var
  Z: string;
begin
  Z := ZCompress(Line + #10);
  Result := FrameLen(Length(Z)) + Z;
end;

function SeiFramePop(var Buf: string; out Line: string; out Bad: Boolean): Boolean;
var
  Len, Head: Integer;
  Z: string;
begin
  Result := False;
  Bad := False;
  Line := '';
  if Length(Buf) < 2 then Exit;
  Len := (Ord(Buf[1]) shl 8) or Ord(Buf[2]);
  Head := 2;
  if Len = LongFrameMark then
  begin
    if Length(Buf) < 6 then Exit;
    Len := (Ord(Buf[3]) shl 24) or (Ord(Buf[4]) shl 16) or
      (Ord(Buf[5]) shl 8) or Ord(Buf[6]);
    Head := 6;
  end;
  if Length(Buf) < Head + Len then Exit;
  Z := Copy(Buf, Head + 1, Len);
  Delete(Buf, 1, Head + Len);
  if not ZDecompress(Z, Line) then
  begin
    Bad := True;
    Exit;
  end;
  { the line is one message, the trailing #10 optional for Answer }
  if (Line <> '') and (Line[Length(Line)] = #10) then
    SetLength(Line, Length(Line) - 1);
  Result := True;
end;

function SeiSocketLogin(Sock: TGSocket; Mode: TSecMode;
  const Prefix, Inner, Suffix, Tail, Server, GivenKey: string;
  Note: TNoteProc; out Why: string): TSecState;
var
  Sess: TSecSession;
  C1, C2, Buf, Line: string;
  Deadline: Int64;
  Bad: Boolean;
begin
  Why := '';
  Result := ssFailed;
  Sess := TSecSession.Create;
  try
    Sess.Mode := Mode;
    Sess.ServerKey := GivenKey;
    Sess.OnNote := Note;
    Sess.Reset(Server);
    if not Sess.Want then
    begin
      Why := 'secure login not wanted for this server in this mode';
      Result := ssNone;
      Exit;
    end;
    if not Sess.Start(Prefix, Inner, Suffix, Tail, C1) then
    begin
      Why := Sess.Why;
      Result := ssFailed;
      Exit;
    end;
    if not Sock.Send(SeiFrameEncode(C1)) then
    begin
      Why := Sock.LastError;
      Result := ssFailed;
      Exit;
    end;
    Buf := '';
    Deadline := GetTickCount64 + QWord(SeiWaitMs);
    while True do
    begin
      if not Sock.Poll(Buf) then
      begin
        { the server closed while we waited: a refusal }
        if Sess.Check(False) then ;
        Why := Sess.Why;
        if Sess.State = ssNone then Result := ssRefused else Result := Sess.State;
        if Result = ssNone then Result := ssRefused;
        Exit;
      end;
      if SeiFramePop(Buf, Line, Bad) then
      begin
        if Bad then
        begin
          Why := 'the server frame did not inflate';
          Result := ssFailed;
          Exit;
        end;
        if Sess.Answer(Line, C2) then
        begin
          if not Sock.Send(SeiFrameEncode(C2)) then
          begin
            Why := Sock.LastError;
            Result := ssFailed;
            Exit;
          end;
          Why := '';
          Result := ssDone;
          Exit;
        end
        else
        begin
          Why := Sess.Why;
          Result := Sess.State;
          Exit;
        end;
      end;
      if GetTickCount64 >= Deadline then
      begin
        if Sess.Check(Sock.Connected) then ;
        Why := Sess.Why;
        Result := ssNoAnswer;
        Exit;
      end;
      Sleep(10);
    end;
  finally
    Sess.Free;
  end;
end;

end.
