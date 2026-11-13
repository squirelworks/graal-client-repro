{ Tests for the 2.05 baddies (Baddy1391x). Test1391x calls RunBaddyTests. }
unit TestBaddy1391x;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  TestNpc1391x;

procedure RunBaddyTests(Check: TCheckProc);

implementation

uses
  SysUtils, Classes, GTypes, Baddy1391x;

type
  { An open field with the player where the test puts it. }
  TTestBaddyWorld = class(TBaddyWorld)
  public
    IsOnline, IsLeader: Boolean;
    PX, PY: Double;
    PDir: Integer;
    Hurts: Double;
    Shots, Died: Integer;
    Sent: TStringList;
    constructor Create;
    destructor Destroy; override;
    function Online: Boolean; override;
    function Leader: Boolean; override;
    function PlayerX: Double; override;
    function PlayerY: Double; override;
    function PlayerDir: Integer; override;
    procedure HurtPlayer(Hearts, FromX, FromY: Double); override;
    procedure Shoot(X, Y: Double; Dir, Sprite, Kind: Integer); override;
    procedure Send(Id: Integer; const Data: string); override;
    procedure AllDied; override;
  end;

constructor TTestBaddyWorld.Create;
begin
  inherited Create;
  Sent := TStringList.Create;
  PX := -100;
  PY := -100;
end;

destructor TTestBaddyWorld.Destroy;
begin
  Sent.Free;
  inherited;
end;

function TTestBaddyWorld.Online: Boolean; begin Result := IsOnline; end;
function TTestBaddyWorld.Leader: Boolean; begin Result := IsLeader; end;
function TTestBaddyWorld.PlayerX: Double; begin Result := PX; end;
function TTestBaddyWorld.PlayerY: Double; begin Result := PY; end;
function TTestBaddyWorld.PlayerDir: Integer; begin Result := PDir; end;

procedure TTestBaddyWorld.HurtPlayer(Hearts, FromX, FromY: Double);
begin
  Hurts := Hurts + Hearts;
end;

procedure TTestBaddyWorld.Shoot(X, Y: Double; Dir, Sprite, Kind: Integer);
begin
  Inc(Shots);
end;

procedure TTestBaddyWorld.Send(Id: Integer; const Data: string);
begin
  Sent.Add(IntToStr(Id) + ':' + Data);
end;

procedure TTestBaddyWorld.AllDied;
begin
  Inc(Died);
end;

procedure Ticks(M: TBaddyManager; N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do M.Tick;
end;

procedure RunBaddyTests(Check: TCheckProc);
var
  W: TTestBaddyWorld;
  M: TBaddyManager;
  B: TBaddy;
  Y0: Double;
  I, J, K, Raised: Integer;
  Found: Boolean;
  Data: string;
begin
  { a new baddy, walking: a quarter tile every second tick }
  W := TTestBaddyWorld.Create;
  M := TBaddyManager.Create(W);
  try
    M.Seed(1);
    B := M.Add(2, 30, 30, 'I see you\Ouch\Take that');
    Check((B.Power = 4) and (B.Image = 'baddyred.gif') and (B.Mode = BdWalk),
      'baddy: type 2 has power 4 and baddyred.gif, and walks');
    Check((B.Verses[0] = 'I see you') and (B.Verses[1] = 'Ouch') and (B.Verses[2] = 'Take that'),
      'baddy: the level''s verses split at \');
    Check(B.Dir = 0, 'baddy: far from the player, it faces up toward it');
    Ticks(M, 4);
    Check(Abs(B.Y - 29.5) < 1E-9, Format('baddy: two steps up a quarter tile each (y %.2f)', [B.Y]));

    { sight: the player 7 tiles ahead, in the cone, starts the hunt }
    B.Y := 30;
    B.Dir := 0;
    B.Head := 0;
    W.PX := 29.5;
    W.PY := 22;
    Ticks(M, 2);
    Check(B.Mode = BdHunt, 'baddy: the player in sight starts the hunt');
    Check((B.Verse = 'I see you') and (B.VerseTime >= 0), 'baddy: the sight verse shows');
    Ticks(M, 22);
    Check(B.Y < 30, Format('baddy: hunting moves toward the player (y %.2f)', [B.Y]));

    { touch: the middles within a tile hurt the player half a heart }
    W.PX := B.X - 0.5;
    W.PY := B.Y - 1;
    W.Hurts := 0;
    Ticks(M, 2);
    Check(Abs(W.Hurts - 0.5) < 1E-9, Format('baddy: touching hurts half a heart (%.2f)', [W.Hurts]));
  finally
    M.Free;
  end;

  { the sword: a hit takes power and knocks back; a shield blocks }
  W := TTestBaddyWorld.Create;
  M := TBaddyManager.Create(W);
  try
    M.Seed(2);
    B := M.Add(2, 30, 30, '');
    B.Dir := 2;
    B.Head := 2;
    W.PX := 29.5;
    W.PY := 27;
    W.PDir := 2;
    M.SwordHit(1);
    Check((B.Mode = BdHurt) and (B.Power = 3) and B.Hurt, 'sword: a hit takes 1 power, mode 3');
    Y0 := B.Y;
    Ticks(M, 2);
    Check(B.Y > Y0 + 1.9, Format('sword: knocked 2 tiles away (y %.2f)', [B.Y]));

    B.Mode := BdWalk;
    B.X := 30;
    B.Y := 30;
    B.Dir := 0;
    B.Head := 0;
    W.PY := 26.5;
    M.SwordHit(1);
    Check((B.Mode = BdBumped) and (B.Power = 3), 'sword: facing the swing, type 2 blocks with its shield');

    { a last hit: dying, then gone, and compusdied }
    B.Mode := BdWalk;
    B.Power := 1;
    B.X := 30;
    B.Y := 30;
    B.Dir := 2;
    B.Head := 2;
    W.PY := 27;
    M.SwordHit(1);
    Ticks(M, 80);
    Check((M.Count = 0) and (W.Died = 1), 'sword: at no power the baddy dies and goes');
  finally
    M.Free;
  end;

  { type 4 comes out of the ground and shoots on count 25 }
  W := TTestBaddyWorld.Create;
  M := TBaddyManager.Create(W);
  try
    B := M.Add(4, 30, 30, '');
    Check((B.Mode = BdRise) and (B.Ani = 2), 'type 4: rises from the ground');
    Ticks(M, 50);
    Check(W.Shots = 1, Format('type 4: one arrow by count 25 (%d)', [W.Shots]));
  finally
    M.Free;
  end;

  { online: props from the server, the leader's updates, a hit sent }
  W := TTestBaddyWorld.Create;
  M := TBaddyManager.Create(W);
  try
    W.IsOnline := True;
    Check(M.Receive(PLO_BADDYPROPS_ID, GChar(5) + GChar(1) + GChar(20) + GChar(2) + GChar(22) +
      GChar(3) + GChar(7) + GChar(4) + GChar(6) + GChar(0) + GChar(8) + GChar(2) + 'Hi'),
      'props: BADDYPROPS taken');
    B := M.Find(5);
    Check((B <> nil) and (Abs(B.X - 10) < 1E-9) and (Abs(B.Y - 11) < 1E-9) and (B.Kind = 7) and
      (B.Power = 6) and (B.Image = 'baddygold.gif') and (B.Verses[0] = 'Hi'),
      'props: a new baddy 5, type 7, at 10,11, power 6, verse Hi');
    B := M.Find(5);
    Check((B <> nil) and (M.Prop(B, 4) = GChar(6) + GChar(0)) and (M.Prop(B, 8) = GChar(2) + 'Hi'),
      'props: written back the same way');
    { a non-leader does not run the AI and sends its hits }
    B.X := 30;
    B.Y := 30;
    B.Dir := 2;
    B.Head := 2;
    W.PX := 29.5;
    W.PY := 27;
    W.PDir := 2;
    Y0 := B.Y;
    Ticks(M, 4);
    Check(B.Y = Y0, 'online: no AI without the leader');
    M.SwordHit(2);
    Check((W.Sent.Count = 1) and (Copy(W.Sent[0], 1, 3) = '16:') and (W.Sent[0][4] = GChar(5)) and
      (B.Power = 4), 'online: the hit goes to the server as BADDYHURT');
    { the leader runs the AI and sends what changed }
    W.Sent.Clear;
    W.IsLeader := True;
    W.PX := -100;
    B.Mode := BdWalk;
    B.Counter := 30;
    Ticks(M, 6);
    Found := False;
    for I := 0 to W.Sent.Count - 1 do
      if Copy(W.Sent[I], 1, 4) = '15:' + GChar(5) then Found := True;
    Check(Found, 'online: the leader sends BADDYPROPS for its baddy');
    Check(M.Receive(PLO_BADDYPROPS_ID, GChar(5) + GChar(5) + GChar(BdDead)) and (M.Find(5) = nil),
      'props: mode 9 removes the baddy');
    { random bytes: never an exception, and every prop still writes }
    RandSeed := 19;
    Raised := 0;
    for I := 1 to 20000 do
    begin
      Data := '';
      for J := 1 to Random(40) do Data := Data + Chr(Random(256));
      try
        if Random(2) = 0 then M.Receive(PLO_BADDYPROPS_ID, Data)
        else M.Receive(PLO_BADDYHURT_ID, Data);
        for J := 0 to M.Count - 1 do
          for K := 0 to 10 do M.Prop(M.Baddy(J), K);
      except
        Inc(Raised);
      end;
    end;
    Check(Raised = 0, Format('props: 20000 random messages, %d raised', [Raised]));
  finally
    M.Free;
  end;
end;

end.
