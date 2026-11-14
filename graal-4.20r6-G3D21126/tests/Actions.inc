{ The player's actions (Adventure: sword and spin, lift and throw, the
  weapon key with the built-in Bomb and Bow, the item list, the lay mode),
  offline and on the wire. Included by the build's test program, which
  gives Check, MsgId, ServerReadAll and LoggedInGame. }

{ An offline game on an empty board, the player facing down at 30, 30. }
function ActionsGame: TAdventure;
var
  I: Integer;
begin
  Result := TAdventure.Create;
  Result.UseWallClock := False;
  Result.Headless := True;
  for I := 0 to BoardSize - 1 do Result.Level.Tiles[I] := 0;
  Result.Player.X := 30;
  Result.Player.Y := 30;
  Result.Player.Dir := DirDown;
  { what offline play starts with (LoadLevelFile) }
  Result.AddDefaultWeapon(8);
end;

{ Puts lift entry E of arrays.dat (list 11) under the probe point below the
  player (x + 1.5, y + 4). }
procedure PutBush(G: TAdventure; E: Integer);
var
  C, R, TX, TY: Integer;
begin
  TX := Trunc(G.Player.X + 1.5);
  TY := Trunc(G.Player.Y + 4);
  for C := 0 to 1 do
    for R := 0 to 1 do
      G.Level.Tiles[TX + C + (TY + R) * BoardW] := G.Arrays.ObjectTile(11, E, C, R);
end;

{ One frame, then the keys let go, as the frame loop does. }
procedure Step(G: TAdventure);
var
  D: Integer;
begin
  G.Tick;
  for D := 0 to 3 do G.Keys[D] := False;
  G.AttackHeld := False;
end;

procedure RunTicks(G: TAdventure; N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do Step(G);
end;

procedure TestActionsOffline;
var
  G: TAdventure;
  N: Integer;
begin
  G := ActionsGame;
  try
    Check((CarryWireCode(-1) = -1) and (CarryWireCode(261) = 1) and (CarryWireCode(239) = 201) and
      (CarryWireCode(65) = 0) and (CarryWireCode(66) = 200),
      'actions: CARRYSPRITE codes (-1 none, bush 1, black stone 201, bombs 0 and 200)');
    Check((CarrySpriteFromWire(-1) = -1) and (CarrySpriteFromWire(223) = -1) and
      (CarrySpriteFromWire(7) = 267) and (CarrySpriteFromWire(201) = 239) and
      (CarrySpriteFromWire(50) = 261),
      'actions: CARRYSPRITE read back; 223 is empty hands, an unknown sprite the bush');
    Check((Length(G.Weapons) = 1) and (G.Weapons[0].Name = 'Bomb') and (G.Selected = 0),
      'actions: offline the player has the client''s own Bomb, selected');

    { the sword; S again during the swing is the spin only with STATUS 0x40 }
    G.AttackKey := True;
    Step(G);
    Check((G.Mode = ModeSword) and (G.Player.AniName = 'sword'), 'actions: S swings the sword');
    G.AttackKey := True;
    Step(G);
    Check(G.Mode = ModeSword, 'actions: no spin without the has-spin bit');
    RunTicks(G, 20);
    Check((G.Mode = ModeFree) and (G.Player.AniName = 'idle'), 'actions: the swing ends in idle');
    G.Player.Status := StatusHasSpin;
    G.AttackKey := True;
    Step(G);
    G.AttackKey := True;
    Step(G);
    Check((G.Mode = ModeSpin) and (G.Player.AniName = 'spin'), 'actions: S twice with 0x40 spins');
    RunTicks(G, 20);
    Check(G.Mode = ModeFree, 'actions: the spin ends');

    { lift and throw }
    PutBush(G, 0);
    G.ActionKey := True;
    Step(G);
    Check((G.Mode = ModeLift) and (G.CarryKind = 0) and (G.Player.CarrySprite = 261) and
      (G.Player.AniName = 'lift'), 'actions: A lifts the bush ahead (carry sprite 261)');
    Check(G.Level.Tile(Trunc(G.Player.X + 1.5), Trunc(G.Player.Y + 4)) = G.Arrays.ObjectTile(12, 0, 0, 0),
      'actions: the lifted bush leaves its lifted tiles');
    RunTicks(G, 20);
    Check((G.Mode = ModeCarry) and (G.Player.AniName = 'carrystill'), 'actions: then it is carried');
    G.Keys[DirLeft] := True;
    Step(G);
    Check(G.Player.AniName = 'carry', 'actions: walking with it is the carry gani');
    G.AttackKey := True;
    Step(G);
    Check((G.Mode = ModeFree) and (Length(G.Thrown) = 1) and (G.Player.CarrySprite = -1),
      'actions: S while carrying throws');
    RunTicks(G, 10);
    Check(Length(G.Thrown) = 0, 'actions: the thrown bush breaks after its flight');

    { D: the Bomb, then the Bow from DEFAULTWEAPON's item }
    N := G.Player.Bombs;
    G.ItemKey := True;
    Step(G);
    Check((Length(G.Bombs) = 1) and (G.Player.Bombs = N - 1), 'actions: D puts a bomb');
    RunTicks(G, 60);
    Check((Length(G.Bombs) = 0) and (Length(G.Blasts) = 1), 'actions: the bomb goes off after its fuse');
    RunTicks(G, 12);
    Check(Length(G.Blasts) = 0, 'actions: the blast dies');
    G.AddDefaultWeapon(7);
    Check((Length(G.Weapons) = 2) and (G.Weapons[1].Name = 'Bow') and (G.Selected = 1),
      'actions: a new weapon is added and selected');
    N := G.Player.Arrows;
    G.ItemKey := True;
    Step(G);
    Check((Length(G.Shots) = 1) and (G.Player.Arrows = N - 1), 'actions: D with the Bow shoots');
    RunTicks(G, 70);
    Check(Length(G.Shots) = 0, 'actions: the arrow leaves the board');

    { the item list: Q opens it, an arrow moves the selection, Q closes it }
    G.ItemListKey := True;
    Step(G);
    Check(G.ItemListOpen, 'actions: Q opens the item list');
    G.Headless := False;
    Step(G);
    G.Headless := True;
    N := Round(G.Player.X * 2);
    G.Keys[DirLeft] := True;
    Step(G);
    Check(G.ItemListOpen and (G.Selected = 0) and (Round(G.Player.X * 2) = N),
      'actions: left in the list picks the Bomb, and the player does not walk');
    Step(G);
    G.ItemListKey := True;
    Step(G);
    Check(not G.ItemListOpen, 'actions: Q again closes it');

    { the lay mode }
    G.Player.Rupees := 40;
    G.Player.Dir := DirDown;
    G.Player.Bombs := 0;
    G.Player.Arrows := 0;
    G.AttackHeld := True;
    G.ActionKey := True;
    Step(G);
    Check((G.Mode = ModeLay) and (G.LayingItem = 0), 'actions: A with S held picks the green rupee');
    G.AttackHeld := True;
    G.ActionKey := True;
    Step(G);
    Check(G.LayingItem = 1, 'actions: A with S held again, the blue rupee');
    N := Length(G.Items);
    G.ActionKey := True;
    Step(G);
    Check((G.Mode = ModeFree) and (G.Player.Rupees = 35) and (Length(G.Items) = N + 1) and
      (G.Items[N].Item = 1) and (G.Items[N].Y = G.Player.Y + 3),
      'actions: A lays it two tiles ahead, and it is paid');
    G.AttackHeld := True;
    G.ActionKey := True;
    Step(G);
    N := Round(G.Player.X * 2);
    G.Keys[DirRight] := True;
    Step(G);
    Check((G.Mode = ModeFree) and (Round(G.Player.X * 2) = N), 'actions: an arrow leaves the lay mode without a step');
    G.Headless := False;
    Step(G);

    { a hit: hurt mode, then death and a respawn on an arrow }
    G.Player.Power := 1;
    G.HurtPlayer(1, 0, 1);
    Check((G.Mode = ModeDead) and (G.Player.AniName = 'dead'), 'actions: the last half heart kills');
    G.Keys[DirUp] := True;
    Step(G);
    Check((G.Mode = ModeFree) and (G.Player.Power = G.Player.MaxPower * 2),
      'actions: an arrow after a death respawns with full hearts');
  finally
    G.Free;
  end;
end;

{ The actions on the wire: GANI sword, CARRYSPRITE and THROWCARRIED, BOMBADD
  with the new count, ITEMADD for a lay, and the server's DEFAULTWEAPON,
  ITEMADD and another player's CARRYSPRITE. }
procedure TestActionsOnline;
var
  G: TAdventure;
  Codec: TGen5;
  Msgs: TStringList;
  I: Integer;
  All: string;
  OP: TServerPlayer;
begin
  G := LoggedInGame(Codec);
  Msgs := TStringList.Create;
  try
    G.Headless := True;
    Step(G); { the login frame }
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    G.Client.Sent := '';
    Msgs.Clear;
    Check((Length(G.Weapons) = 3) and (G.Weapons[0].Name = 'Bomb') and (G.Weapons[1].Name = 'Bow') and
      (G.Weapons[2].Name = '-gr_movement') and (G.Weapons[2].Item = -1) and (G.Selected = 0),
      'actions online: the burst''s DEFAULTWEAPON 8 and 7 and NPCWEAPONADD; a system weapon is not selected');
    G.Receive(PLO_NPCWEAPONDEL, '-gr_movement');
    Check(Length(G.Weapons) = 2, 'actions online: NPCWEAPONDEL takes it out');
    G.Receive(PLO_ITEMADD, GChar(20) + GChar(22) + GChar(2));
    Check((Length(G.Items) = 1) and (G.Items[0].X = 10) and (G.Items[0].Item = 2),
      'actions online: ITEMADD lays a red rupee');
    G.Receive(PLO_OTHERPLPROPS, GShort(7) + GChar(PLPROP_CARRYSPRITE) + GChar(5));
    OP := G.FindOther(7, False);
    Check((OP <> nil) and (OP.CarrySprite = 265), 'actions online: another player''s CARRYSPRITE 5 is the pot');
    G.Receive(PLO_OTHERPLPROPS, GShort(7) + GChar(PLPROP_CARRYSPRITE) + Chr(31));
    Check(OP.CarrySprite = -1, 'actions online: CARRYSPRITE -1 empties the hands');

    G.Player.SwordPower := 1;
    G.Player.GlovePower := 1;
    G.Player.Bombs := 10;
    G.Player.X := 30;
    G.Player.Y := 30;
    G.Player.Dir := DirDown;
    G.AttackKey := True;
    Step(G);
    RunTicks(G, 20);
    PutBush(G, 0);
    G.ActionKey := True;
    Step(G);
    RunTicks(G, 20);
    G.ActionKey := True;
    Step(G);
    G.ItemKey := True;
    Step(G);
    G.Player.Rupees := 10;
    G.Player.Bombs := 0;
    G.Player.Arrows := 0;
    G.Player.Power := 0;
    G.AttackHeld := True;
    G.ActionKey := True;
    Step(G);
    G.ActionKey := True;
    Step(G);
    Check(ServerReadAll(Codec, G.Client.Sent, Msgs), 'actions online: frames decode');
    All := '';
    for I := 0 to Msgs.Count - 1 do All := All + '|' + Msgs[I];
    Check(Pos(GChar(PLPROP_GANI) + GString('sword'), All) > 0, 'actions online: the swing goes out as GANI sword');
    Check(Pos(GChar(PLPROP_CARRYSPRITE) + GChar(1), All) > 0, 'actions online: a lifted bush goes out as CARRYSPRITE 1');
    Check(Pos('|' + GChar(PLI_THROWCARRIED) + '|', All + '|') > 0, 'actions online: the throw is PLI_THROWCARRIED');
    Check(Pos(GChar(PLPROP_CARRYSPRITE) + Chr(31), All) > 0, 'actions online: then CARRYSPRITE -1');
    Check(Pos(GChar(PLI_BOMBADD), All) > 0, 'actions online: D with the Bomb is PLI_BOMBADD');
    Check(Pos(GChar(PLI_PLAYERPROPS) + GChar(PLPROP_BOMBSCOUNT) + GChar(9), All) > 0,
      'actions online: then BOMBSCOUNT 9');
    Check(Pos(GChar(PLI_ITEMADD) + GChar(61) + GChar(66) + GChar(0), All) > 0,
      'actions online: a laid green rupee is PLI_ITEMADD (30.5, 33)');
    Check(Pos(GChar(PLPROP_RUPEESCOUNT) + GInt3(9), All) > 0, 'actions online: then RUPEESCOUNT 9');
  finally
    Msgs.Free;
    Codec.Free;
    G.Free;
  end;
end;
