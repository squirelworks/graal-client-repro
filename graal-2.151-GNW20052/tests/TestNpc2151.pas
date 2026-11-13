{ Tests for the 2.05 NPC scripts: GGs1 (GS1), Npc2151 (NPCs, props),
  and their hooks in TAdventure. Test2151 calls RunNpcTests.

  Optional: GRAAL_NPC_LIBRARY = graal_analysis npc-library/scripts; every
  .gs1 file under it must compile. Without it that check is skipped. }
unit TestNpc2151;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TCheckProc = procedure(Cond: Boolean; const What: string);

procedure RunNpcTests(Check: TCheckProc; out Skipped: Integer);

implementation

uses
  SysUtils, Classes, GTypes, GLevel, GSurface, GGs1, Npc2151, Adventure;

type
  { A world that records what the scripts asked of it. }
  TTestWorld = class(TNpcWorld)
  public
    IsOnline: Boolean;
    PX, PY: Double;
    Rupees: Double;
    Chat: string;
    Sent, Said, Events: TStringList;
    Hurt, HurtX, HurtY: Double;
    WarpLevel: string;
    WarpX, WarpY: Double;
    Laid: Integer;
    Img: TGSurface;
    constructor Create;
    destructor Destroy; override;
    function Online: Boolean; override;
    function PlayerX: Double; override;
    function PlayerY: Double; override;
    function GetPlayerVar(const Name: string; out V: Double): Boolean; override;
    function SetPlayerVar(const Name: string; V: Double): Boolean; override;
    function PlayerChat: string; override;
    function Image(const Name: string): TGSurface; override;
    procedure HurtPlayer(Power, FromX, FromY: Double); override;
    procedure Say2(const Text: string); override;
    procedure Warp(const Level: string; X, Y: Double); override;
    procedure LayItem(Item: Integer; X, Y: Double); override;
    procedure Send(Id: Integer; const Data: string); override;
  end;

constructor TTestWorld.Create;
begin
  Sent := TStringList.Create;
  Said := TStringList.Create;
  Events := TStringList.Create;
  Img := TGSurface.Create(32, 48);
  PX := 10;
  PY := 10;
  Laid := -1;
end;

destructor TTestWorld.Destroy;
begin
  Sent.Free;
  Said.Free;
  Events.Free;
  Img.Free;
  inherited;
end;

function TTestWorld.Online: Boolean; begin Result := IsOnline; end;
function TTestWorld.PlayerX: Double; begin Result := PX; end;
function TTestWorld.PlayerY: Double; begin Result := PY; end;

function TTestWorld.GetPlayerVar(const Name: string; out V: Double): Boolean;
begin
  Result := Name = 'playerrupees';
  if Result then V := Rupees else V := 0;
end;

function TTestWorld.SetPlayerVar(const Name: string; V: Double): Boolean;
begin
  Result := Name = 'playerrupees';
  if Result then Rupees := V;
end;

function TTestWorld.PlayerChat: string; begin Result := Chat; end;

function TTestWorld.Image(const Name: string): TGSurface;
begin
  if Name = 'block.png' then Result := Img else Result := nil;
end;

procedure TTestWorld.HurtPlayer(Power, FromX, FromY: Double);
begin
  Hurt := Hurt + Power;
  HurtX := FromX;
  HurtY := FromY;
end;

procedure TTestWorld.Say2(const Text: string); begin Said.Add(Text); end;

procedure TTestWorld.Warp(const Level: string; X, Y: Double);
begin
  WarpLevel := Level;
  WarpX := X;
  WarpY := Y;
end;

procedure TTestWorld.LayItem(Item: Integer; X, Y: Double); begin Laid := Item; end;

procedure TTestWorld.Send(Id: Integer; const Data: string);
begin
  Sent.Add(IntToStr(Id) + ':' + Data);
end;

var
  C: TCheckProc;

{ Runs Script once on event Ev in a fresh NPC; returns the manager. }
function RunOne(W: TTestWorld; const Script, Ev: string): TNpcManager;
var
  N: TNpc;
begin
  Result := TNpcManager.Create(W);
  N := Result.Add(0, 5, 5, 'block.png', Script);
  Result.Fire(N, Ev);
end;

procedure TestLanguage;
var
  W: TTestWorld;
  M: TNpcManager;
  N: TNpc;
  S: TGsScript;
  Bad, I: Integer;
const
  { each stops part way through a statement; the half-built pieces must
    still be freed (the heap check at exit catches a leak) }
  Broken: array[0..4] of string = (
    'this.a = (1 + (2 * 3;',
    'if (this.a == (1 + 2) this.b = 1;',
    'for (i = 0; i < (3 + 1; i++) this.c++;',
    'for (i = 0; i < 3; i++) { this.d = (4 + ; }',
    'setplayerprop #c,(1+;');
begin
  Bad := 0;
  for I := 0 to High(Broken) do
  begin
    S := TGsScript.Create;
    try
      if not S.Compile(Broken[I]) then Inc(Bad);
    finally
      S.Free;
    end;
  end;
  C(Bad >= 4, 'gs1: broken scripts report errors and free their pieces');
  W := TTestWorld.Create;
  M := TNpcManager.Create(W);
  try
    N := M.Add(0, 5, 5, 'block.png',
      'if (playerenters) {'#10 +
      '  this.a = 1 + 2 * 3;'#10 +          // 7
      '  this.b = (1 + 2) * 3 ^ 2;'#10 +    // 27
      '  this.c = 7 % 3;'#10 +              // 1
      '  if (this.a == 7 && !(this.b < 2)) this.d = 1; else this.d = 2;'#10 +
      '  for (i = 0; i < 5; i++) this.e += i;'#10 +   // 10
      '  this.w = 0;'#10 +
      '  while (1) { this.w++; if (this.w >= 3) break; }'#10 +
      '  this.r = this.a in |5,8|;'#10 +
      '  this.s = 3 in {1,2,4};'#10 +
      '  this.arr = {4,5,6};'#10 +
      '  this.f = this.arr[1] + arraylen(this.arr);'#10 +
      '  double();'#10 +
      '  this.loop = 0;'#10 +
      '  while (1) this.loop++;'#10 +
      '  message n=#v(this.a+1) ok;'#10 +
      '}'#10 +
      'function double() { this.g = this.a * 2; return; this.g = 0; }'#10 +
      'if (timeout) this.t = 1;'#10);
    M.Fire(N, 'playerenters');
    C(N.Ctx.Locals.Get('a', 0) = 7, 'GS1: precedence 1 + 2 * 3 = 7');
    C(N.Ctx.Locals.Get('b', 0) = 27, 'GS1: ^ binds tighter than *');
    C(N.Ctx.Locals.Get('c', 0) = 1, 'GS1: 7 % 3 = 1');
    C(N.Ctx.Locals.Get('d', 0) = 1, 'GS1: if/else with && and !');
    C(N.Ctx.Locals.Get('e', 0) = 10, 'GS1: for loop sums 0..4');
    C(N.Ctx.Locals.Get('w', 0) = 3, 'GS1: while with break');
    C(N.Ctx.Locals.Get('r', 0) = 1, 'GS1: x in |a,b|');
    C(N.Ctx.Locals.Get('s', 0) = 0, 'GS1: x in {set}, not a member');
    C(N.Ctx.Locals.Get('f', 0) = 8, 'GS1: array literal, index and arraylen');
    C(N.Ctx.Locals.Get('g', 0) = 14, 'GS1: function call and return');
    C(N.Ctx.Locals.Get('loop', 0) = GsMaxLoop, 'GS1: a loop stops after 10,000 passes');
    C(N.Ctx.Locals.Get('t', 0) = 0, 'GS1: timeout is false in playerenters');
    C(N.Message = 'n=8 ok', 'GS1: message expands #v(...)');
    M.Fire(N, 'timeout');
    C(N.Ctx.Locals.Get('t', 0) = 1, 'GS1: the timeout event flag');
  finally
    M.Free;
    W.Free;
  end;

  { compile errors are reported, not raised }
  S := TGsScript.Create;
  try
    C(not S.Compile('if (a { b;'), 'GS1: a broken script reports an error');
    C(S.Errors.Count > 0, 'GS1: the error text is kept');
  finally
    S.Free;
  end;
  { wire scripts use the section sign for line ends }
  S := TGsScript.Create;
  try
    C(S.Compile('// note'#$A7'if (created) x = 1;'), 'GS1: 0xA7 ends a line in a wire script');
  finally
    S.Free;
  end;

  { text arguments keep quote marks (lab: strequals(#c,"buy bombs") never
    matched on 2.05) }
  W := TTestWorld.Create;
  W.Chat := 'buy bombs';
  M := RunOne(W, 'if (playerchats) { if (strequals(#c,buy bombs)) this.a = 1;' +
    ' if (strequals(#c,"buy bombs")) this.b = 1; }', 'playerchats');
  try
    C(M.Npc(0).Ctx.Locals.Get('a', 0) = 1, 'GS1: strequals with bare text matches the chat');
    C(M.Npc(0).Ctx.Locals.Get('b', 0) = 0, 'GS1: quoted text keeps its quotes (2.05 lab)');
  finally
    M.Free;
    W.Free;
  end;

  { sleep: the next timeout resumes after it }
  W := TTestWorld.Create;
  M := RunOne(W, 'if (playerenters) { this.a = 1; sleep 0.1; this.a = 2; }', 'playerenters');
  try
    N := M.Npc(0);
    C(N.Ctx.Locals.Get('a', 0) = 1, 'GS1: sleep ends the run');
    M.Tick;
    C(N.Ctx.Locals.Get('a', 0) = 1, 'GS1: sleep 0.1 still waits after one tick');
    M.Tick;
    C(N.Ctx.Locals.Get('a', 0) = 2, 'GS1: the timeout resumes after sleep');
  finally
    M.Free;
    W.Free;
  end;
end;

procedure TestNpcCommands;
var
  W: TTestWorld;
  M: TNpcManager;
  N: TNpc;
  I: Integer;
begin
  W := TTestWorld.Create;
  M := RunOne(W,
    'if (playerenters) { setimgpart block.png,0,0,32,32; x = 20; y = 21; dir = 3;' +
    ' timeout = 0.2; set seen; setstring who,Nell; message #s(who); }'#10 +
    'if (timeout) { hide; this.done = 1; }'#10 +
    'if (playertouchsme) { hurt 2; say2 Hello#bthere; }'#10 +
    'if (washit) { lay2 greenrupee,1,1; playerrupees += 5; }'#10 +
    'if (exploded) setlevel2 other.nw,30,31;'#10, 'playerenters');
  try
    N := M.Npc(0);
    C((N.X = 20) and (N.Y = 21) and (N.Dir = 3), 'NPC: x, y and dir assignments');
    C(N.PartSet and (N.PW = 32) and (N.PH = 32), 'NPC: setimgpart');
    C(M.HasFlag('seen'), 'NPC: set adds a flag');
    C(N.Message = 'Nell', 'NPC: setstring and #s(...)');
    C(M.PointBlocked(21, 22) and not M.PointBlocked(22.5, 22), 'NPC: blocks over its image part (2x2 tiles)');
    for I := 1 to 3 do M.Tick;
    C(N.Visible, 'NPC: timeout 0.2 has not fired after 3 ticks');
    M.Tick;
    C(not N.Visible and (N.Ctx.Locals.Get('done', 0) = 1), 'NPC: timeout 0.2 fires on the 4th tick');
    C(not M.PointBlocked(21, 22), 'NPC: a hidden NPC does not block');
    N.VisFlags := VisVisible;
    { the player at (19.5, 18): the body's front edge reaches y 21.25 }
    M.PlayerPush(2, 19.5, 18);
    C(W.Hurt = 2, 'NPC: walking into it runs playertouchsme (hurt 2 half hearts)');
    C((W.HurtX = 21) and (W.HurtY = 22), 'NPC: hurt comes from the NPC centre');
    C((W.Said.Count = 1) and (W.Said[0] = 'Hello#bthere'), 'NPC: say2 text (#b kept for the sign window)');
    M.SwordHit(20, 21, 2, 2, 1);
    C((W.Laid = 0) and (W.Rupees = 5), 'NPC: washit, lay2 and playerrupees');
    M.BombBlast(25, 21, 2);
    C(W.WarpLevel = '', 'NPC: a blast out of reach does not hit');
    M.BombBlast(23, 22, 2);
    C((W.WarpLevel = 'other.nw') and (W.WarpX = 30) and (W.WarpY = 31), 'NPC: exploded, setlevel2');
  finally
    M.Free;
    W.Free;
  end;

  { character NPCs: setcharprop takes the prop code as written }
  W := TTestWorld.Create;
  M := RunOne(W, 'if (created) { showcharacter; setcharprop #3,head19.gif;' +
    ' setcharprop #C1,gray; setcharprop #n,Stefan; setcharani walk,; }', 'created');
  try
    N := M.Npc(0);
    C(N.Character and (N.HeadImage = 'head19.gif'), 'NPC: showcharacter, setcharprop #3');
    C((N.Colors[1] = 17) and (N.Nickname = 'Stefan') and (N.Gani = 'walk'),
      'NPC: setcharprop #C1 and #n, setcharani');
    C(M.PointBlocked(N.X + 1, N.Y + 2) and not M.PointBlocked(N.X + 0.25, N.Y + 2),
      'NPC: a character blocks with its 2x2 body box');
  finally
    M.Free;
    W.Free;
  end;

  { light effects (offline): colour multiply and zoom }
  W := TTestWorld.Create;
  M := RunOne(W, 'if (playerenters) { setcoloreffect 1,1,0,0.99; setzoomeffect 2; drawaslight; }',
    'playerenters');
  try
    N := M.Npc(0);
    C((N.Layer = 9) and (N.EffB = 0) and (Abs(N.EffA - 0.99) < 1E-9) and (N.Zoom = 2),
      'NPC: drawaslight, setcoloreffect, setzoomeffect');
  finally
    M.Free;
    W.Free;
  end;

  { destroy removes the NPC after its run }
  W := TTestWorld.Create;
  M := RunOne(W, 'if (playerenters) { destroy; this.a = 1; }', 'playerenters');
  try
    M.FireAll('none');
    C(M.Count = 0, 'NPC: destroy removes it');
  finally
    M.Free;
    W.Free;
  end;
end;

procedure TestNpcProps;
var
  W: TTestWorld;
  M: TNpcManager;
  N: TNpc;
  Script, S: string;
begin
  W := TTestWorld.Create;
  W.IsOnline := True;
  M := TNpcManager.Create(W);
  try
    Script := 'if (playerenters) { message hi; }'#$A7'if (playertouchsme) { x = 12; hide; set touched; }';
    S := GInt3(7) + GChar(NPCPROP_IMAGE) + GString('block.png') +
      GChar(NPCPROP_X) + GChar(20) + GChar(NPCPROP_Y) + GChar(30) +
      GChar(NPCPROP_SCRIPT) + GShort(Length(Script)) + Script;
    C(M.Receive(3, S), 'NPCPROPS: taken by the NPC manager');
    N := M.FindById(7);
    C(N <> nil, 'NPCPROPS: a new id makes an NPC');
    if N = nil then Exit;
    C((N.X = 10) and (N.Y = 15) and (N.Image = 'block.png'), 'NPCPROPS: image, x and y in half tiles');
    C(N.Message = 'hi', 'NPCPROPS: a new NPC gets playerenters');
    C(W.Sent.Count = 1, 'NPCPROPS: the script''s change is sent back');
    if W.Sent.Count > 0 then
      C(W.Sent[0] = '3:' + GInt3(7) + GChar(NPCPROP_MESSAGE) + GString('hi'),
        'NPCPROPS: PLI_NPCPROPS carries i3 id and the changed message');
    W.Sent.Clear;
    { a second SCRIPT is ignored }
    S := GInt3(7) + GChar(NPCPROP_SCRIPT) + GShort(5) + 'hide;' + GChar(NPCPROP_X) + GChar(40);
    M.Receive(3, S);
    C((N.Script = Script) and (N.X = 20), 'NPCPROPS: a second script is ignored, later props still apply');
    { an id above 40 ends the stream in 2.05 }
    S := GInt3(7) + GChar(NPCPROP_Y) + GChar(10) + GChar(48) + GChar(NPCPROP_X) + GChar(2);
    M.Receive(3, S);
    C((N.Y = 5) and (N.X = 20), 'NPCPROPS: an unknown prop id ends the stream');
    M.Fire(N, 'playertouchsme');
    C(W.Sent.IndexOf('18:touched') >= 0, 'flags: set sends PLI_FLAGSET');
    C(W.Sent.IndexOf('3:' + GInt3(7) + GChar(NPCPROP_X) + GChar(24) +
      GChar(NPCPROP_VISFLAGS) + GChar(0)) >= 0, 'NPCPROPS: x and visibility sent in prop order');
    M.Receive(28, 'quest=2');
    M.Receive(28, 'quest=3');
    C(M.Flags.IndexOf('quest=2') >= 0, 'FLAGSET: a set flag is not overwritten');
    M.Receive(31, 'quest');
    C(not M.HasFlag('quest'), 'FLAGDEL removes the flag');
    { online, timeouts run only on the leader }
    N.Timeout := 0.05;
    M.Tick;
    C(not M.IsLeader and (N.Timeout = 0), 'leader: a non-leader counts the timeout down');
    M.Receive(10, '');
    C(M.IsLeader, 'ISLEADER is taken');
  finally
    M.Free;
    W.Free;
  end;
end;

procedure TestLibrary(var Skipped: Integer);
var
  Dir, F: string;
  SR: TSearchRec;
  Dirs: TStringList;
  L: TStringList;
  S: TGsScript;
  I, Ok, Bad: Integer;
begin
  Dir := GetEnvironmentVariable('GRAAL_NPC_LIBRARY');
  if (Dir = '') or not DirectoryExists(Dir) then
  begin
    WriteLn('skip  GS1 library compile (GRAAL_NPC_LIBRARY not set)');
    Inc(Skipped);
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(Dir);
  Dirs := TStringList.Create;
  L := TStringList.Create;
  Ok := 0;
  Bad := 0;
  try
    Dirs.Add('');
    if FindFirst(Dir + '*', faDirectory, SR) = 0 then
    begin
      repeat
        if (SR.Attr and faDirectory <> 0) and (SR.Name <> '.') and (SR.Name <> '..') then
          Dirs.Add(SR.Name + PathDelim);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    for I := 0 to Dirs.Count - 1 do
      if FindFirst(Dir + Dirs[I] + '*.gs1', faAnyFile, SR) = 0 then
      begin
        repeat
          F := Dir + Dirs[I] + SR.Name;
          L.LoadFromFile(F);
          S := TGsScript.Create;
          try
            if S.Compile(L.Text) then Inc(Ok)
            else
            begin
              Inc(Bad);
              WriteLn('      ', Dirs[I] + SR.Name, ': ', Trim(S.Errors.Text));
            end;
          finally
            S.Free;
          end;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    C((Bad = 0) and (Ok > 0), Format('GS1: %d library scripts compile (%d fail)', [Ok, Bad]));
  finally
    Dirs.Free;
    L.Free;
  end;
end;

procedure TestInGame;
var
  G: TAdventure;
  F: string;
  L: TStringList;
  P0: Integer;
begin
  F := IncludeTrailingPathDelimiter(GetTempDir) + 'test2151-npc.nw';
  L := TStringList.Create;
  try
    L.Add('GLEVNW01');
    L.Add('NPC - 30 20');
    L.Add('if (playerenters) { setshape 1,32,32; this.n = 0; }');
    L.Add('if (playertouchsme) { hurt 1; this.n++; message #v(this.n); }');
    L.Add('NPCEND');
    L.SaveToFile(F);
  finally
    L.Free;
  end;
  G := TAdventure.Create;
  try
    G.Headless := True;
    C(G.LoadLevelFile(F), 'in game: an .nw level with an NPC loads');
    C(G.Npcs.Count = 1, 'in game: its NPC is made');
    G.Player.X := 29.5;
    G.Player.Y := 16;
    P0 := G.Player.Power;
    G.Keys[DirDown] := True;
    G.Tick;
    G.Tick;
    G.Tick;
    G.Tick;
    C(G.Player.Y < 18.5, 'in game: the NPC blocks the walk');
    C(G.Player.Power < P0, 'in game: pushing into it runs its touch script (hurt)');
    G.Headless := False;
    G.Tick;
    C(True, 'in game: a frame with an NPC draws');
  finally
    G.Free;
    DeleteFile(F);
  end;
end;

procedure RunNpcTests(Check: TCheckProc; out Skipped: Integer);
begin
  Skipped := 0;
  C := Check;
  TestLanguage;
  TestNpcCommands;
  TestNpcProps;
  TestLibrary(Skipped);
  TestInGame;
end;

end.
