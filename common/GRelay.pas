{ GRelay: the 1998 relay link (gen 1), shared by every build from 1st Graal
  to 1.1.

  The 1998 clients have no login, token, compression or cipher. They open
  TCP connections to a lobby server, join a named game with one text line
  and then trade text lines with the other players in that game. Every
  line ends in LF and its first character is the command. The lobby knows
  nothing about the game: it hands out ids, pairs players and forwards D
  lines. Sources (graal_analysis): protocol/relay-1998.md,
  client-internals/live-trace-early.md (1.1.9 captures),
  client-internals/version-profiles/v1998-v11.toml.

  Client to server:  N<game>#<name>  join (the clients always send "def")
                     P<id8>          pair with a player / accept
                     C               leave the party
                     -               leave (sent on a clean disconnect)
                     D<data>         relay data to the partners
  Server to client:  I<id8>          your id
                     +<id8>[name]    a player in the same game
                     -<id8>          a player left
                     P<id8>          pairing confirmed
                     C<id8>          a partner left the party
                     D<data>         relayed data
                     NR / NL         15th Graal on: server level choice

  A D payload is: sender id as two base-128 characters, a type character,
  then the type's fields. Numbers are single characters +32 (as GCHAR
  later); coordinates are half tiles.

  What is the same in every gen-1 build lives here; which types a build
  sends and how it names its game stay in the build's own units. }
unit GRelay;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSocket;

const
  { the read buffer of the 1998 clients; a longer line is cut there }
  RelayLineMax = 1024;

type
  TRelayEvent = (reId, rePeerIn, rePeerOut, rePaired, reUnpaired, reData,
    reLevelsRemote, reLevelsLocal, reUnknown);

  { One line from the server, split. }
  TRelayLine = record
    Event: TRelayEvent;
    Id: string;    { I, +, -, P, C: the 8-character id }
    Name: string;  { +: the name after the id, if any }
    Data: string;  { D: everything after the D }
  end;

  { One relay connection: one game (room) on one server. }
  TRelayLink = class
  private
    FSocket: TGSocket;
    FIn: string;
    FOut: string;
    FLastError: string;
    FGame: string;
  public
    MyId: string;
    { ids of the paired partners, and of the players announced but not
      paired yet }
    Partners, Known: TStringList;
    LinesIn, LinesOut, BytesIn, BytesOut: Integer;
    { the server's level choice (15th Graal on): seen NR, seen NL }
    GotNR, GotNL: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Connect(const Host: string; Port: Word): Boolean;
    { N<game>#def; leaves the old game first when there was one }
    procedure Join(const Game: string);
    procedure SendLine(const Line: string);
    { D + sid + type + payload, to every partner (the server fans out) }
    procedure SendData(const TypeAndPayload: string);
    { sends what is queued }
    procedure Flush;
    { reads the socket; returns the complete lines in Lines (parsed);
      answers + with P and keeps Partners / Known up to date }
    procedure Poll(Lines: TList);
    { "-" then close }
    procedure Disconnect;
    function Connected: Boolean;
    property Game: string read FGame;
    property LastError: string read FLastError;
    property Socket: TGSocket read FSocket;
  end;

  PRelayLine = ^TRelayLine;

{ The sender id as the two base-128 characters of a D line: the number in
  the last four digits of an id8, (c0-32)*128 + (c1-32). }
function EncodeSid(const Id8: string): string;
{ Back to an id8: '0000' plus four zero-padded digits. }
function DecodeSid(const S: string): string;
{ One server line (without its LF) parsed. }
function ParseRelayLine(const Line: string): TRelayLine;
{ A number as one character, +32, clipped to 0..223. }
function RChar(V: Integer): Char;
{ The number in a +32 character. }
function RVal(C: Char): Integer;
{ T payload: a time as 10 characters base 128, little end first. }
function EncodeTime128(V: Int64): string;
function DecodeTime128(const S: string): Int64;

implementation

uses
  SysUtils;

function RChar(V: Integer): Char;
begin
  if V < 0 then V := 0;
  if V > 223 then V := 223;
  Result := Chr(V + 32);
end;

function RVal(C: Char): Integer;
begin
  Result := Ord(C) - 32;
end;

function EncodeSid(const Id8: string): string;
var
  N: Integer;
begin
  N := StrToIntDef(Copy(Id8, Length(Id8) - 3, 4), 0);
  if N < 0 then N := 0;
  if N > 16383 then N := 16383;
  Result := Chr(N div 128 + 32) + Chr(N mod 128 + 32);
end;

function DecodeSid(const S: string): string;
var
  N: Integer;
begin
  Result := '';
  if Length(S) < 2 then Exit;
  N := (Ord(S[1]) - 32) * 128 + (Ord(S[2]) - 32);
  if N < 0 then N := 0;
  Result := '0000' + Format('%.4d', [N mod 10000]);
end;

function EncodeTime128(V: Int64): string;
var
  I: Integer;
begin
  Result := '';
  if V < 0 then V := 0;
  for I := 1 to 10 do
  begin
    Result := Result + Chr(V mod 128 + 32);
    V := V div 128;
  end;
end;

function DecodeTime128(const S: string): Int64;
var
  I: Integer;
  C: Integer;
begin
  Result := 0;
  for I := Length(S) downto 1 do
  begin
    C := Ord(S[I]) - 32;
    if (C < 0) or (C > 127) then C := 0;
    Result := Result * 128 + C;
    if Result > (High(Int64) div 256) then Exit;
  end;
end;

function ParseRelayLine(const Line: string): TRelayLine;
begin
  Result.Event := reUnknown;
  Result.Id := '';
  Result.Name := '';
  Result.Data := '';
  if Line = '' then Exit;
  case Line[1] of
    'I': begin Result.Event := reId; Result.Id := Copy(Line, 2, 8); end;
    '+':
      begin
        Result.Event := rePeerIn;
        Result.Id := Copy(Line, 2, 8);
        Result.Name := Copy(Line, 10, MaxInt);
      end;
    '-': begin Result.Event := rePeerOut; Result.Id := Copy(Line, 2, 8); end;
    'P': begin Result.Event := rePaired; Result.Id := Copy(Line, 2, 8); end;
    'C': begin Result.Event := reUnpaired; Result.Id := Copy(Line, 2, 8); end;
    'D': begin Result.Event := reData; Result.Data := Copy(Line, 2, MaxInt); end;
    'N':
      if Line = 'NR' then Result.Event := reLevelsRemote
      else if Line = 'NL' then Result.Event := reLevelsLocal;
  end;
end;

{ TRelayLink }

constructor TRelayLink.Create;
begin
  inherited Create;
  FSocket := TGSocket.Create;
  Partners := TStringList.Create;
  Known := TStringList.Create;
end;

destructor TRelayLink.Destroy;
begin
  FSocket.Free;
  Partners.Free;
  Known.Free;
  inherited Destroy;
end;

function TRelayLink.Connect(const Host: string; Port: Word): Boolean;
begin
  Result := FSocket.Connect(Host, Port);
  if not Result then FLastError := FSocket.LastError;
end;

function TRelayLink.Connected: Boolean;
begin
  Result := FSocket.Connected;
end;

procedure TRelayLink.SendLine(const Line: string);
var
  L: string;
begin
  { a LF inside would break the framing: the line is cut there }
  L := Line;
  if Pos(#10, L) > 0 then SetLength(L, Pos(#10, L) - 1);
  FOut := FOut + L + #10;
  Inc(LinesOut);
end;

procedure TRelayLink.Join(const Game: string);
begin
  if FGame <> '' then
  begin
    { as captured from 1.1.9 when the level room changes: leave the
      available list and the party, then join the new game }
    SendLine('-');
    SendLine('C');
    Partners.Clear;
    Known.Clear;
  end;
  FGame := Game;
  SendLine('N' + Game + '#def');
end;

procedure TRelayLink.SendData(const TypeAndPayload: string);
begin
  if MyId = '' then Exit;
  SendLine('D' + EncodeSid(MyId) + TypeAndPayload);
end;

procedure TRelayLink.Flush;
begin
  if (FOut = '') or not FSocket.Connected then Exit;
  Inc(BytesOut, Length(FOut));
  if not FSocket.Send(FOut) then FLastError := FSocket.LastError;
  FOut := '';
end;

procedure TRelayLink.Poll(Lines: TList);
var
  P, I: Integer;
  Line: string;
  R: PRelayLine;
begin
  if not FSocket.Connected then Exit;
  I := Length(FIn);
  if not FSocket.Poll(FIn) then FLastError := FSocket.LastError;
  Inc(BytesIn, Length(FIn) - I);
  repeat
    P := Pos(#10, FIn);
    if P = 0 then
    begin
      { no LF within the 1 KB read buffer: the line is dropped there }
      if Length(FIn) > RelayLineMax then FIn := '';
      Break;
    end;
    Line := Copy(FIn, 1, P - 1);
    Delete(FIn, 1, P);
    if (Line <> '') and (Line[Length(Line)] = #13) then SetLength(Line, Length(Line) - 1);
    if Length(Line) > RelayLineMax then SetLength(Line, RelayLineMax);
    Inc(LinesIn);
    New(R);
    R^ := ParseRelayLine(Line);
    case R^.Event of
      reId: MyId := R^.Id;
      rePeerIn:
        if (R^.Id <> MyId) and (Known.IndexOf(R^.Id) < 0) and
          (Partners.IndexOf(R^.Id) < 0) then
        begin
          Known.Add(R^.Id);
          { the client asks every announced player to pair (a relay game
            is a full mesh of pairs in the 1.1.9 captures) }
          SendLine('P' + R^.Id);
        end;
      rePeerOut:
        begin
          I := Known.IndexOf(R^.Id);
          if I >= 0 then Known.Delete(I);
          I := Partners.IndexOf(R^.Id);
          if I >= 0 then Partners.Delete(I);
        end;
      rePaired:
        begin
          I := Known.IndexOf(R^.Id);
          if I >= 0 then Known.Delete(I);
          if Partners.IndexOf(R^.Id) < 0 then Partners.Add(R^.Id);
        end;
      reUnpaired:
        begin
          I := Partners.IndexOf(R^.Id);
          if I >= 0 then Partners.Delete(I);
        end;
      reLevelsRemote: GotNR := True;
      reLevelsLocal: GotNL := True;
    end;
    if Lines <> nil then Lines.Add(R) else Dispose(R);
  until False;
end;

procedure TRelayLink.Disconnect;
begin
  if FSocket.Connected then
  begin
    SendLine('-');
    Flush;
  end;
  FSocket.Close;
end;

end.
