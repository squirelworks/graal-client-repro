{ Tests for the Graal3D rebuild. No framework: each check prints a line
  and the run exits 1 if any failed. Nothing here needs the original
  Graal3D files: the levels and models are the build's own stand-ins. }
program Test3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSurface in '../../common/GSurface.pas',
  Codec3D in '../src/Codec3D.pas',
  Math3D in '../src/Math3D.pas',
  XFile3D in '../src/XFile3D.pas',
  Builtin3D in '../src/Builtin3D.pas',
  Render3D in '../src/Render3D.pas',
  World3D in '../src/World3D.pas',
  Client3D in '../src/Client3D.pas',
  Config3D in '../src/Config3D.pas',
  Run3D in '../src/Run3D.pas',
  Overlay3D in '../src/Overlay3D.pas';

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

function Near(A, B, Eps: Double): Boolean;
begin
  Result := Abs(A - B) <= Eps;
end;

procedure TestCodec;
var
  P, Q: TProps3D;
  R: TGReader;
  S, Lines, Buf: string;
  Bits: Cardinal;
begin
  DefaultProps(P);
  Check(P.BodyX = 'body.x', 'default body mesh is body.x');
  Check(P.HeadTex = 'man.bmp', 'default head texture is man.bmp');
  Check(P.ArmColor = $FF0000, 'default arm colour FF0000');
  Check(P.ShoeColor = $800000, 'default shoe colour 800000');
  Check(P.HandColor = $FDCC47, 'default hand colour FDCC47');
  Check(P.Level = 'level1.x', 'the client''s default level is level1.x');
  { coordinates: (v - 8000) / 2 }
  S := EncodeCoord(0);
  R := TGReader.Create(S);
  Check(R.ReadGShort = 8000, 'x 0 goes out as 8000');
  R.Free;
  R := TGReader.Create(EncodeCoord(-4000));
  Check(DecodeCoord(R) = -4000, 'x -4000 round trip');
  R.Free;
  R := TGReader.Create(EncodeCoord(123.5));
  Check(DecodeCoord(R) = 123.5, 'half units round trip');
  R.Free;
  { colours: four 6-bit groups }
  S := EncodeColor($FDCC47);
  Check(Length(S) = 4, 'a colour is 4 bytes');
  R := TGReader.Create(S);
  Check(DecodeColor(R) = $FDCC47, 'colour FDCC47 round trip');
  R.Free;
  Check(EncodeColor($FFFFFF) = '____', 'white is four 63s');
  { the angle: degrees / 2 }
  Check(EncodeAngle(270) = GChar(135), 'angle 270 goes out as 135');
  Check(EncodeAngle(-90) = GChar(135), 'angle -90 is 270');
  { prop 16: the loopback address as an in_addr word }
  Check(IpWord('127.0.0.1') = $0100007F, 'loopback in_addr word');
  P.Ip := IpWord('127.0.0.1');
  Check(EncodeProp(P, PP_IP) = '0 (  '#$9F, 'prop 16 for the loopback address');
  Check(IpDotted($0100007F) = '127.0.0.1', 'in_addr word back to dotted');
  { the login line }
  Check(LoginLine('alice', 'pw1') = ' GR3DV002%alice#pw1'#10, 'login line');
  { a props run }
  P.X := 10;
  P.Y := 20.5;
  P.Z := -30;
  P.Angle := 90;
  P.Anim := 21;
  P.Nick := 'Bob (Admins)';
  P.Chat := 'hi';
  P.UdpPort := 50000;
  S := EncodeProp(P, PP_X) + EncodeProp(P, PP_Y) + EncodeProp(P, PP_Z) +
    EncodeProp(P, PP_ANGLE) + EncodeProp(P, PP_ANIM) + EncodeProp(P, PP_NICK) +
    EncodeProp(P, PP_CHAT) + EncodeProp(P, PP_UDPPORT) + EncodeProp(P, PP_ARMCOLOR);
  DefaultProps(Q);
  Q.ArmColor := 0;
  Bits := ApplyProps(Q, S);
  Check((Q.X = 10) and (Q.Y = 20.5) and (Q.Z = -30), 'position props round trip');
  Check((Q.Angle = 90) and (Q.Anim = 21), 'angle and animation round trip');
  Check((Q.Nick = 'Bob (Admins)') and (Q.Chat = 'hi'), 'nickname and chat round trip');
  Check(Q.UdpPort = 50000, 'UDP port round trip');
  Check(Q.ArmColor = $FF0000, 'arm colour round trip');
  Check(Bits and (1 shl PP_CHAT) <> 0, 'ApplyProps reports the chat prop');
  { an unknown id stops the run without reading past it }
  DefaultProps(Q);
  ApplyProps(Q, EncodeProp(P, PP_X) + GChar(30) + 'junk' + EncodeProp(P, PP_Y));
  Check((Q.X = 10) and (Q.Y = 0), 'an unknown prop id ends the run');
  { prop 51 marks a player gone }
  DefaultProps(Q);
  ApplyProps(Q, GChar(PP_LEFT));
  Check(Q.Left, 'prop 51 marks the player as gone');
  { the UDP position body: props 1..5, no ids, 9 bytes }
  S := EncodePosBody(P);
  Check(Length(S) = 9, 'UDP position body is 9 bytes');
  DefaultProps(Q);
  Check(ApplyPosBody(Q, S) and (Q.X = 10) and (Q.Anim = 21), 'UDP position body round trip');
  Check(not ApplyPosBody(Q, Copy(S, 1, 8)), '8 bytes or fewer are ignored');
  { frames }
  Lines := MessageLine(SV_LEVELNAME, 'startlevel.x') + MessageLine(SV_LEVEL, 'a'#10'b');
  Check(Pos(#$A7, Lines) > 0, 'a line break inside a message goes out as 0xA7');
  Buf := BuildFrame(Lines) + BuildFrame(MessageLine(SV_LEADER, ''));
  Check((Ord(Buf[1]) shl 8) or Ord(Buf[2]) = Length(BuildFrame(Lines)) - 2,
    'frame length is big-endian');
  Buf := Buf + #0; { one byte of the next frame }
  Check(TakeFrames(Buf, S) and (S = Lines + MessageLine(SV_LEADER, '')),
    'two frames inflate to their lines');
  Check(Buf = #0, 'a partial frame stays in the buffer');
  Buf := #0#5'xxxxx';
  Check(not TakeFrames(Buf, S), 'a frame that is not zlib is refused');
  Check(FromWire('a'#$A7'b') = 'a'#10'b', 'FromWire');
end;

const
  FramedX =
    'xof 0302txt 0064'#10 +
    'template Vector {'#10' <3D82AB5E-62DA-11cf-AB39-0020AF71E433>'#10' FLOAT x;'#10'}'#10 +
    'Material red {'#10' 1.0;0.0;0.0;1.0;;'#10' 5.0;'#10' 0.0;0.0;0.0;;'#10' 0.0;0.0;0.0;;'#10 +
    ' TextureFilename { "tex.bmp"; }'#10'}'#10 +
    'Frame f {'#10' FrameTransformMatrix {'#10 +
    '  1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,1.0,0.0,100.0,0.0,0.0,1.0;;'#10' }'#10 +
    ' Mesh m {'#10'  4;'#10'  0.0;0.0;0.0;,1.0;0.0;0.0;,1.0;0.0;1.0;,0.0;0.0;1.0;;'#10 +
    '  2;'#10'  3;0,3,2;,'#10'  3;0,2,1;;'#10 +
    '  MeshMaterialList { 1; 1; 0;; {red} }'#10 +
    '  MeshNormals { 1; 0.0;1.0;0.0;; 1; 3;0,0,0;; }'#10 +
    '  MeshTextureCoords { 4; 0.0;0.0;, 1.0;0.0;, 1.0;1.0;, 0.0;1.0;; }'#10 +
    ' }'#10'}'#10;

procedure TestXFile;
var
  S: TXScene;
  M: TMesh3D;
  T, Bad: string;
  I, J: Integer;
  N: TVec3;
begin
  S := TXScene.Create;
  try
    Check(S.LoadFromString(FramedX), 'a framed mesh with a material reference loads');
    Check(S.Count = 1, 'one mesh');
    M := S.Mesh(0);
    Check((M.VertexCount = 4) and (M.FaceCount = 2), '4 vertices, 2 faces');
    Check(M.Verts[1].X = 101, 'the frame matrix moves the mesh');
    Check((Length(M.Materials) = 1) and (M.Materials[0].Texture = 'tex.bmp') and
      (M.Materials[0].R = 1) and (M.Materials[0].Power = 5), 'the referenced material');
    Check((M.U[2] = 1) and (M.V[3] = 1), 'texture coordinates');
    N := M.FaceNormal(0);
    Check(Near(N.Y, 1, 1E-9), 'face 0,3,2 faces up (clockwise from above)');
    Check(not S.LoadFromString('xof 0302bin 0064'), 'binary .x is refused');
    Check(not S.LoadFromString('hello'), 'not a .x file');
    { hostile counts and truncations fail cleanly }
    Check(not S.LoadFromString('xof 0302txt 0064'#10'Mesh { 999999999; 1.0; }'),
      'a vertex count larger than the file is refused');
    Check(not S.LoadFromString('xof 0302txt 0064'#10'Mesh { 3; 0;0;0;,1;0;0;,0;0;1;; 1; 3;0,1,'),
      'a cut-off mesh is refused');
    Check(S.LoadFromString('xof 0302txt 0064'#10'Mesh { 3; 0;0;0;,1;0;0;,0;0;1;; 2; 3;0,1,7;, 3;0,1,2;; }') and
      (S.Mesh(0).FaceCount = 1), 'a face with an out of range index is dropped');
    { the stand-ins parse }
    Check(S.LoadFromString(BuiltinLevel) and (S.Mesh(0).FaceCount > 40), 'the stand-in level parses');
    T := 'body.x;head.x;armleft.x;armright.x;handleft.x;handright.x;footleft.x;footright.x';
    J := 0;
    while T <> '' do
    begin
      I := Pos(';', T);
      if I = 0 then I := Length(T) + 1;
      if S.LoadFromString(BuiltinModel(Copy(T, 1, I - 1))) and (S.Count = 1) then Inc(J);
      Delete(T, 1, I);
    end;
    Check(J = 8, 'the eight stand-in model parts parse');
    Check(BuiltinModel('other.x') = '', 'no stand-in for other names');
    { mutations of a good file never crash the reader }
    RandSeed := 1234;
    for I := 1 to 2000 do
    begin
      Bad := FramedX;
      for J := 1 to 1 + Random(4) do
        Bad[17 + Random(Length(Bad) - 17)] := Chr(Random(256));
      if Random(4) = 0 then SetLength(Bad, 17 + Random(Length(Bad) - 17));
      S.LoadFromString(Bad);
    end;
    Check(True, '2000 damaged files read without a crash');
  finally
    S.Free;
  end;
end;

procedure TestWorld;
var
  W: TWorld3D;
  I, J: Integer;
  Inp: TInput3D;
  Z0, Top, D, H: Double;
  Speeds: array[0..29] of Double;
begin
  W := TWorld3D.Create;
  try
    Check(W.Level.Load('builtin.x', BuiltinLevel), 'the stand-in level loads into the world');
    Check(W.Level.FloorAt(0, 0, 10, H) and Near(H, 0.5, 1E-6), 'the floor at the origin is the path');
    { walking: 8 a tick, then 12 after 25 ticks }
    W.Me.X := -1000;
    W.Me.Z := -1500;
    W.Me.Angle := 0;
    W.ResetCamera;
    FillChar(Inp, SizeOf(Inp), 0);
    Inp.Fwd := True;
    for I := 0 to 29 do
    begin
      Z0 := W.Me.Z;
      W.Step(Inp);
      Speeds[I] := W.Me.Z - Z0;
    end;
    Check(Near(Speeds[0], 8, 0.01) and Near(Speeds[24], 8, 0.01), 'walking is 8 units a tick');
    Check(Near(Speeds[25], 12, 0.01) and Near(Speeds[29], 12, 0.01), 'after 25 ticks it is x1.5');
    Inp.Fwd := False;
    W.Step(Inp);
    Inp.Fwd := True;
    Z0 := W.Me.Z;
    W.Step(Inp);
    Check(Near(W.Me.Z - Z0, 8, 0.01), 'stopping resets the run');
    { the camera trails a running player, then settles near 220 behind and
      80 above once the player stops }
    for I := 1 to 100 do W.Step(Inp);
    D := Sqrt(Sqr(W.Me.X - W.Cam.X) + Sqr(W.Me.Z - W.Cam.Z));
    Check((D > 220) and (D < 400), Format('camera trails a running player (%.0f)', [D]));
    Inp.Fwd := False;
    for I := 1 to 400 do W.Step(Inp);
    D := Sqrt(Sqr(W.Me.X - W.Cam.X) + Sqr(W.Me.Z - W.Cam.Z));
    Check((D > 220) and (D < 250), Format('and closes to about 220 when the player stops (%.0f)', [D]));
    Inp.Fwd := True;
    Check(Near(W.Cam.Y - W.Me.Y, 80, 5), 'camera sits about 80 above');
    Check(W.Me.Angle mod 2 = 0, 'the facing is in 2-degree steps');
    { jumping: 47 up at most, then back to the floor }
    FillChar(Inp, SizeOf(Inp), 0);
    W.Me.X := -1000;
    W.Me.Y := 0;
    W.Me.Z := -1000;
    W.ResetCamera;
    W.Step(Inp);
    Inp.Jump := True;
    Top := 0;
    for I := 1 to 30 do
    begin
      W.Step(Inp);
      if W.Me.Y > Top then Top := W.Me.Y;
    end;
    Check(Near(Top, 47, 0.01), Format('a held jump rises 47 (%.1f)', [Top]));
    Check(W.OnGround and Near(W.Me.Y, 0, 0.01), 'and lands again');
    { a tap gives a short hop; a new jump needs the key let go }
    W.Step(Inp);
    Check(W.OnGround, 'holding the key does not jump again');
    Inp.Jump := False;
    W.Step(Inp);
    Inp.Jump := True;
    W.Step(Inp);
    Inp.Jump := False;
    Top := 0;
    for I := 1 to 20 do
    begin
      W.Step(Inp);
      if W.Me.Y > Top then Top := W.Me.Y;
    end;
    Check(Top < 25, Format('a tap gives a short hop (%.1f)', [Top]));
    { the 20-high block can be stepped onto, the 60-high one cannot }
    FillChar(Inp, SizeOf(Inp), 0);
    W.Me.X := 250;
    W.Me.Y := 0;
    W.Me.Z := 100;
    W.Me.Angle := 0;
    W.Cam := V3(250, 80, -120);
    Inp.Fwd := True;
    for I := 1 to 15 do W.Step(Inp);
    Check(Near(W.Me.Y, 20, 0.01) and (W.Me.Z > 150), Format('walks up onto a 20-high step (y %.1f)', [W.Me.Y]));
    W.Me.X := -250;
    W.Me.Y := 0;
    W.Me.Z := 100;
    W.Cam := V3(-250, 80, -120);
    for I := 1 to 15 do W.Step(Inp);
    Check(Near(W.Me.Y, 0, 0.01) and (W.Me.Z < 150), Format('stopped by a 60-high wall (z %.1f)', [W.Me.Z]));
    Check(W.Me.Z > 135, Format('and stands right at it (z %.1f)', [W.Me.Z]));
    { walking off the edge falls to the field }
    W.Me.X := 250;
    W.Me.Y := 20;
    W.Me.Z := 340;
    W.Cam := V3(250, 100, 120);
    for I := 1 to 20 do W.Step(Inp);
    Check(Near(W.Me.Y, 0, 0.01) and W.OnGround, 'walks down off a step');
    { the world edge }
    W.Me.X := 3995;
    W.Me.Y := 0;
    W.Me.Z := 0;
    W.Cam := V3(3775, 80, 0);
    for I := 1 to 10 do W.Step(Inp);
    Check(W.Me.X <= 4000, 'the world stops at 4000');
    { the chat log keeps a line 200 ticks }
    W.AddChat('Alice: hi');
    FillChar(Inp, SizeOf(Inp), 0);
    for I := 1 to 199 do W.Step(Inp);
    Check(Length(W.Chat) = 1, 'a chat line is still there after 199 ticks');
    W.Step(Inp);
    Check(Length(W.Chat) = 0, 'and gone after 200');
    for J := 1 to 30 do W.AddChat('x');
    Check(Length(W.Chat) = 24, 'the log keeps the newest 24');
  finally
    W.Free;
  end;
end;

procedure TestClient;
var
  W: TWorld3D;
  C: TClient3D;
  P: TProps3D;
  Q, Lines: string;
begin
  W := TWorld3D.Create;
  C := TClient3D.Create(W);
  try
    { the first props line carries the full look and the UDP port }
    W.Me.Nick := 'Stefan';
    C.SendProps;
    Q := C.TakeQueue;
    Check(Copy(Q, 1, 1) = GChar(CL_PROPS), 'props go out as id 1');
    Check(Pos(EncodeProp(W.Me, PP_BODYX), Q) > 0, 'the first send carries the body mesh');
    Check(Pos(EncodeProp(W.Me, PP_NICK), Q) > 0, 'and the nickname');
    Check(Pos(EncodeProp(W.Me, PP_UDPPORT), Q) > 0, 'and the UDP port');
    DefaultProps(P);
    P.Level := 'unchanged';
    P.Ip := 7;
    ApplyProps(P, Copy(Q, 2, Length(Q) - 2));
    Check((P.Level = 'unchanged') and (P.Ip = 7), 'the client does not send props 14 and 16');
    C.SendProps;
    Check(C.TakeQueue = '', 'nothing changed, nothing sent');
    W.Me.X := 50;
    C.SendProps;
    Q := C.TakeQueue;
    Check(Q = GChar(CL_PROPS) + EncodeProp(W.Me, PP_X) + #10, 'only the changed prop goes out');
    { the login order from the server }
    DefaultProps(P);
    P.Id := 1;
    P.X := 10;
    Lines := MessageLine(SV_SESSION, GChar(0)) +
      MessageLine(SV_PLAYERPROPS, EncodeProp(P, PP_ID) + EncodeProp(P, PP_X));
    P.Id := 2;
    P.Nick := 'Bob';
    Lines := Lines + MessageLine(SV_OTHERPLPROPS, GChar(2) + EncodeProp(P, PP_NICK) +
      EncodeProp(P, PP_X));
    Lines := Lines + MessageLine(SV_LEVELNAME, 'test.x') + MessageLine(SV_LEVEL, BuiltinLevel) +
      MessageLine(SV_LEADER, '');
    P.InLevel := True;
    P.Chat := 'hello';
    Lines := Lines + MessageLine(SV_OTHERPLPROPS, GChar(2) + EncodeProp(P, PP_INLEVEL) +
      EncodeProp(P, PP_CHAT));
    C.FeedLines(Lines);
    Check(C.LoggedIn and (W.Me.Id = 1) and (W.Me.X = 10), 'own props: logged in as player 1 at x 10');
    Check((Length(W.Others) = 1) and (W.Others[0].P.Nick = 'Bob'), 'other player 2 is Bob');
    Check(W.Others[0].P.InLevel, 'prop 50 puts Bob in the level');
    Check((C.LevelName = 'test.x') and (C.LevelsLoaded = 1) and (Length(W.Level.Faces) > 40),
      'level name and text load the level');
    Check(C.Leader, 'packet 4 sets the leader flag');
    Check((Length(W.Chat) = 1) and (W.Chat[0].Text = 'Bob: hello'), 'chat goes to the log');
    { raw data: the line after 100 is dropped }
    C.FeedLines(MessageLine(SV_RAWDATA, GInt3(5)) + GChar(SV_DISCMESSAGE) + 'raw'#10);
    Check(C.DiscMessage = '', 'the raw line after packet 100 is dropped');
    C.FeedLines(MessageLine(SV_ADMINMESSAGE, 'Administrator alice:'#10'hi'));
    Check(C.AdminMessage = 'Administrator alice:'#10'hi', 'admin message with its line break');
    C.FeedLines(MessageLine(SV_OTHERPLPROPS, GChar(2) + GChar(PP_LEFT)));
    Check(Length(W.Others) = 0, 'prop 51 removes the player');
    C.FeedLines(MessageLine(SV_DISCMESSAGE, 'The account is already in use.'));
    Check(C.DiscMessage = 'The account is already in use.', 'disconnect message stored');
    { chat is cut at 200 }
    C.Say(StringOfChar('a', 250));
    Check((Length(W.Me.Chat) = 200) and (Copy(W.Me.Chat, 198, 3) = '...'), 'long chat is cut with ...');
    { hostile input does not crash }
    C.FeedLines(#255#0#10 + GChar(SV_OTHERPLPROPS) + #10 + GChar(SV_PLAYERPROPS) + GChar(PP_NICK) + #10);
    Check(True, 'short and odd lines are survived');
  finally
    C.Free;
    W.Free;
  end;
end;

procedure TestConfigScript;
var
  C: TConfig3D;
  K: TKeyScript;
begin
  DefaultConfig(C);
  Check(C.ServerAddr = 'listserver.graal.in', 'default host is the community list server');
  Check((C.ServerPort = 14901) and (C.FixedUdpPort = 14898), 'default ports 14901 and 14898');
  ParseConfig('serveraddr=example.org'#13#10'serverport=15000'#13#10'noudp=true'#13#10 +
    'armcolor=0x00FF00'#13#10'fixedport=true'#13#10'bogus'#13#10, C);
  Check((C.ServerAddr = 'example.org') and (C.ServerPort = 15000), 'host and port read');
  Check(C.NoUdp and C.FixedPort, 'booleans read');
  Check(C.ArmColor = $00FF00, 'hex colours read');
  Check(Pos('armcolor=0x00FF00', ConfigText(C)) > 0, 'colours written back as 0x');
  K := TKeyScript.Create;
  try
    Check(K.Parse('fwd*3,wait,fwd+left*2,say:hi there,jump'), 'key script parses');
    Check(K.Count = 8, 'eight steps');
    Check(K.At(3).Fwd = False, 'wait holds nothing');
    Check(K.At(4).Fwd and K.At(4).Left, 'two keys at once');
    Check(K.At(6).Say = 'hi there', 'a chat step');
    Check(not K.Parse('fly*2'), 'an unknown word is refused');
  finally
    K.Free;
  end;
end;

{ The nickname banner and the far plane }
procedure TestOverlay;
var
  O: TOverlay3D;
  S: TGSurface;
  R: TRenderer3D;
begin
  O := TOverlay3D.Create;
  S := TGSurface.Create(640, 456);
  R := TRenderer3D.Create(64, 48);
  try
    O.Load(nil);
    S.Fill($FFFFFFFF);
    O.Draw(S, 640, '');
    Check((S.GetPixel(639, 0) = $FF000000) and (S.GetPixel(639, BannerH - 1) = $FF000000) and
      (S.GetPixel(639, BannerH) = $FFFFFFFF), 'overlay: a black strip 48 high across the view');
    Check(R.Back >= 60000, 'render: the back plane reaches the cloud ceiling (40000 out)');
  finally
    R.Free;
    S.Free;
    O.Free;
  end;
end;

procedure TestRender;
var
  R: TRenderer3D;
  S: TXScene;
  I, Lit: Integer;
  SX, SY: Double;
begin
  R := TRenderer3D.Create(ViewW, ViewH);
  S := TXScene.Create;
  try
    S.LoadFromString(BuiltinLevel);
    R.CamPos := V3(0, 80, -300);
    R.LookAlong(V3(0, -0.3, 1));
    R.Clear;
    R.DrawMesh(S.Mesh(0), V3(0, 0, 0), 0, $FFFFFFFF, '');
    Lit := 0;
    for I := 0 to High(R.Surface.Pixels) do
      if R.Surface.Pixels[I] <> R.Background then Inc(Lit);
    Check(Lit > ViewW * ViewH div 3, 'the stand-in level fills the lower view');
    Check(R.FacesDrawn > 10, 'faces in front of the camera are drawn');
    { the field 0.5 viewport: 640 pixels per unit at distance 1 }
    R.CamPos := V3(0, 0, 0);
    R.LookAlong(V3(0, 0, 1));
    Check(R.Project(V3(0.25, 0, 1), SX, SY) and Near(SX, 320 + 160, 1E-6) and Near(SY, 228, 1E-6),
      'one scale from the longer side: x 0.25 at z 1 is 160 pixels off centre');
    Check(not R.Project(V3(0, 0, 0.5), SX, SY), 'nothing in front of the front plane');
  finally
    S.Free;
    R.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestCodec;
  TestXFile;
  TestWorld;
  TestClient;
  TestConfigScript;
  TestRender;
  TestOverlay;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
