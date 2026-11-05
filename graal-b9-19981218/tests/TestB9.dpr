{ Tests for the 9th Graal (beta9) rebuild. No framework: each check prints a line and
  the run exits 1 if any failed.

  Wire checks use lines from the 1.1.9 captures written up in graal_analysis
  client-internals/live-trace-early.md. The live check against a relay is
  scripts/loopback-relay.sh. }
program TestB9;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GBetaHud in '../../common/GBetaHud.pas',
  GArrays in '../../common/GArrays.pas',
  GAni in '../../common/GAni.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GRelay in '../../common/GRelay.pas',
  ProtocolB9 in '../src/ProtocolB9.pas',
  Adventure in '../src/Adventure.pas',
  GDfm in '../../common/GDfm.pas',
  GVclForm in '../../common/GVclForm.pas',
  GBetaStart in '../../common/GBetaStart.pas',
  RealResB9 in '../src/RealResB9.pas';

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

procedure TestProfile;
begin
  Check(ClientGeneration = 1, 'profile: generation 1 (no token, no compression)');
  Check(ClientVersionToken = '', 'profile: no version token');
  Check((RelayGame = 'Zelda2') or (Copy(RelayGame, 1, 5) = 'Graal'),
    'profile: the fixed game is ' + RelayGame);
  Check(RelayZeldaRooms or (Copy(RelayRoomPrefix, 1, 1) = 'G'),
    'profile: level games start with ' + RelayRoomPrefix);
  Check(DialogHost = 'listserver.graal.in', 'profile: connect dialog host is the project listserver host');
  Check((DialogPort = 14801) or (DialogPort = 14802), 'profile: connect port 14801 or 14802');
  Check(ColourCount in [4, 5], 'profile: 4 or 5 colours');
  Check(SendsType('P') and SendsType('N') and SendsType('L'), 'profile: sends P, N and L');
end;

procedure TestSid;
begin
  Check(EncodeSid('00000000') = '  ', 'sid: id 0 is two spaces');
  Check(EncodeSid('00000001') = ' !', 'sid: id 1 is " !" (capture)');
  Check(DecodeSid(' !') = '00000001', 'sid: " !" back to 00000001');
  Check(DecodeSid(EncodeSid('00000300')) = '00000300', 'sid: 300 round trip (two digits base 128)');
  Check(DecodeSid('x') = '', 'sid: one character is not an id');
end;

procedure TestLines;
var
  R: TRelayLine;
begin
  R := ParseRelayLine('I00000002');
  Check((R.Event = reId) and (R.Id = '00000002'), 'line: I gives the id');
  R := ParseRelayLine('+00000003def');
  Check((R.Event = rePeerIn) and (R.Id = '00000003') and (R.Name = 'def'),
    'line: +id plus name (1.1.9 capture form)');
  R := ParseRelayLine('-00000003');
  Check((R.Event = rePeerOut) and (R.Id = '00000003'), 'line: - a player left');
  R := ParseRelayLine('P00000003');
  Check(R.Event = rePaired, 'line: P pairing confirmed');
  R := ParseRelayLine('C00000003');
  Check(R.Event = reUnpaired, 'line: C partner left the party');
  R := ParseRelayLine('D !P^\3');
  Check((R.Event = reData) and (R.Data = ' !P^\3'), 'line: D keeps the payload');
  Check(ParseRelayLine('NR').Event = reLevelsRemote, 'line: NR');
  Check(ParseRelayLine('NL').Event = reLevelsLocal, 'line: NL');
  Check(ParseRelayLine('Q').Event = reUnknown, 'line: an unknown command is ignored');
  Check(ParseRelayLine('').Event = reUnknown, 'line: an empty line is ignored');
end;

procedure TestTime;
var
  V: Int64;
begin
  V := 123456789012;
  Check(Length(EncodeTime128(V)) = 10, 'T: 10 characters');
  Check(DecodeTime128(EncodeTime128(V)) = V, 'T: round trip, little end first');
  Check(EncodeTime128(1)[1] = '!', 'T: the low digit comes first');
end;

procedure TestRooms;
var
  G: TAdventure;
begin
  G := TAdventure.Create;
  try
    if RelayZeldaRooms then
    begin
      Check(G.RoomFor('house1.graal') = 'Zhouse12', 'room: Z + level base + 2 (1st Graal live run)');
      Check(G.RoomFor('') = RelayGame, 'room: the fixed game with no level');
    end
    else
    begin
      Check(G.RoomFor('level13.graal') = RelayRoomPrefix + 'level13.graal',
        'room: ' + RelayRoomPrefix + ' + level file (live runs)');
      Check(G.RoomFor('') = RelayRoomPrefix, 'room: bare prefix with no level');
    end;
  finally
    G.Free;
  end;
end;

procedure TestPeerData;
var
  G: TAdventure;
  P: TPeer;
begin
  G := TAdventure.Create;
  try
    { walking right in the 1.1.9 capture: ^\3 = x 31, y 30, frame 4 right }
    G.HandleData(' !P^\3');
    P := G.FindOther('00000001', False);
    Check(P <> nil, 'D: a partner is made from its first D line');
    if P <> nil then
    begin
      Check((P.X = 31) and (P.Y = 30), 'D P: x and y in half tiles (capture)');
      Check((P.Sprite = 19) and (P.Dir = DirRight), 'D P: frame*4 + direction (capture)');
    end;
    G.HandleData(' !Nloop1');
    Check((P <> nil) and (P.Nickname = 'loop1'), 'D N: nickname');
    G.HandleData(' !S%"!*$2');
    Check((P <> nil) and (P.Colors[0] = 2) and (P.Colors[1] = 1) and (P.Colors[4] = 18),
      'D S: count then colour indices');
    G.HandleData(' !T' + EncodeTime128(4242));
    Check((P <> nil) and (P.LoginTime = 4242), 'D T: login time');
    G.HandleData(' !I');
    Check((P <> nil) and P.Away, 'D I: the partner left the level');
    G.HandleData(' !P' + #32#32#32);
    Check((P <> nil) and not P.Away, 'D P: back on the level');
    G.RemoveOther('00000001');
    Check(G.OtherCount = 0, 'partner removed');
  finally
    G.Free;
  end;
end;

procedure TestLevels;
var
  G: TAdventure;
  F, D: string;
  S: TFileStream;
begin
  G := TAdventure.Create;
  try
    Check(G.LoadLevelFile('start.nw'), 'level: the built-in starter level loads');
    Check(G.SheetBuiltin and (G.Sheet.Width > 0), 'level: built-in tile sheet');
    Check(AcceptsLevel('Z3-V1.04') and AcceptsLevel(Copy(LevelFormats, 1, 8)),
      'level: reads ' + LevelFormats);
    Check(not AcceptsLevel('GLEVNW01'), 'level: no .nw (the text format came later)');
    { a .nw file on disk is refused, as the build had no reader for it }
    F := GetTempDir + 'test119.nw';
    D := 'GLEVNW01'#10;
    S := TFileStream.Create(F, fmCreate);
    try
      S.WriteBuffer(D[1], Length(D));
    finally
      S.Free;
    end;
    Check(not G.LoadLevelFile(F), 'level: a GLEVNW01 file is refused');
    DeleteFile(F);
  finally
    G.Free;
  end;
end;

procedure TestWalking;
var
  G: TAdventure;
  I: Integer;
  X0: Double;
begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    G.LoadLevelFile('start.nw');
    G.Player.X := 30;
    G.Player.Y := 30;
    X0 := G.Player.X;
    for I := 1 to 4 do
    begin
      G.Keys[DirRight] := True;
      G.Tick;
    end;
    Check(G.Player.X > X0, 'walk: right moves the player');
    Check((G.Player.Sprite and 3) = DirRight, 'walk: sprite carries the direction');
    Check(G.Player.Sprite div 4 > 0, 'walk: a walking frame while moving');
    G.Keys[DirRight] := False;
    G.Tick;
    Check(G.Player.Sprite = DirRight, 'walk: idle frame on stop');
  finally
    G.Free;
  end;
end;

procedure TestFuzz;
var
  G: TAdventure;
  I, J, N: Integer;
  S: string;
  Ok: Boolean;
begin
  RandSeed := 119;
  G := TAdventure.Create;
  Ok := True;
  try
    G.Headless := True;
    try
      for I := 1 to 20000 do
      begin
        N := Random(40);
        SetLength(S, N);
        for J := 1 to N do S[J] := Chr(Random(256));
        G.HandleData(S);
        ParseRelayLine(S);
        DecodeTime128(S);
      end;
      G.Draw;
    except
      Ok := False;
    end;
  finally
    G.Free;
  end;
  Check(Ok, 'fuzz: 20000 random D payloads and lines, no crash');
end;

{ The start dialog and the game window come from the real client's own
  forms (src/RealResB9.pas, extracted from its exe). }
procedure TestStartForm;
var
  Data: string;
  O: TDfmObj;
  F: TVclForm;
  Img: TGSurface;
  G: TBetaGameForm;
begin
  Check(RealResource('TCONNECTFRAME', Data) and (Copy(Data, 1, 4) = 'TPF0'),
    'forms: TCONNECTFRAME is in the program');
  O := ParseDfm(Data);
  F := TVclForm.Create(O, 'Graal');
  Img := TGSurface.Create(F.ClientWidth, F.ClientHeight);
  try
    Check(SameText(O.ClassName_, 'TConnectFrame'), 'forms: the start dialog is TConnectFrame');
    Check(F.Caption = 'Graal - The Adventure', 'forms: the dialog''s caption');
    Check(BetaShape(F) = bsOnlineBox, 'forms: the dialog''s shape is bsOnlineBox');
    Check(F.Ctl('Button1') <> nil, 'forms: the Start button');
    F.Render(Img);
    Check(Img.Pixels[0] <> 0, 'forms: the dialog draws without Win32');
  finally
    Img.Free;
    F.Free;
    O.Free;
  end;
  Check(RealResource('TADVENTURE', Data), 'forms: TADVENTURE is in the program');
  Check(BetaGameForm(Data, G) and (G.ViewW = 640) and (G.ViewH = 448),
    'forms: the game view is 640 x 448');
  Check(G.MinBox and not G.MaxBox, 'forms: the game window has a minimise box, no maximise box');
  Check((Length(CharacterNames) = 1) = (CharacterNames[0] = ''),
    'forms: the character list is the build''s own');
end;

begin
  TestProfile;
  TestStartForm;
  TestSid;
  TestLines;
  TestTime;
  TestRooms;
  TestPeerData;
  TestLevels;
  TestWalking;
  TestFuzz;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
