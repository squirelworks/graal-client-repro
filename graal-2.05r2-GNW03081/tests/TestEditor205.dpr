{ Tests for the 2.05 rev 2 built-in level editor: the level writers and
  (later) the editor document. Same style as Test205: each check prints a
  line and the run exits 1 if any failed.

  Optional: GRAAL205_TUTORIALS = a folder with the 13 tutorial_*.graal
  files from the 2.05 exe (graal_analysis tools/file-formats/
  extract_tutorials.py). They were saved by the 2.05 editor, so writing
  them back must give the same bytes. Skipped when the folder is missing. }
program TestEditor205;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GLevel in '../../common/GLevel.pas',
  GLevelWrite in '../../common/GLevelWrite.pas',
  EditorDoc in '../src/editor/EditorDoc.pas';

var
  Passed, Failed, Skipped: Integer;

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

procedure Skip(const What: string);
begin
  Inc(Skipped);
  WriteLn('skip  ', What);
end;

procedure WriteText(const FileName, Text: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Text <> '' then F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
end;

function ReadFileStr(const FileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

{ A level with something in every section. }
function SampleLevel: TAdventureLevel;
var
  I: Integer;
begin
  Result := TAdventureLevel.Create;
  for I := 0 to BoardSize - 1 do
    Result.Tiles[I] := (I * 7 + I div 64) mod 4096;
  { runs: a single run and an ABAB double run }
  for I := 0 to 63 do Result.Tiles[10 * 64 + I] := 511;
  for I := 0 to 31 do
  begin
    Result.Tiles[11 * 64 + I * 2] := 100;
    Result.Tiles[11 * 64 + I * 2 + 1] := 101;
  end;
  SetLength(Result.Links, 2);
  with Result.Links[0] do
  begin
    Dest := 'house one.graal'; X := 0; Y := 30; W := 1; H := 4; NewX := '62'; NewY := 'playery';
  end;
  with Result.Links[1] do
  begin
    Dest := 'b.nw'; X := 20; Y := 0; W := 4; H := 1; NewX := 'playerx'; NewY := 'playery+60';
  end;
  SetLength(Result.Baddies, 3);
  with Result.Baddies[0] do begin X := 0; Y := 5; Kind := 0; Verses := 'Stop!\Ouch!\Ha ha'; end;
  with Result.Baddies[1] do begin X := 40; Y := 41; Kind := 5; Verses := ''; end;
  with Result.Baddies[2] do begin X := 63; Y := 63; Kind := 9; Verses := 'Grr\\'; end;
  SetLength(Result.NPCs, 2);
  with Result.NPCs[0] do
  begin
    X := 12; Y := 13; Image := 'door.png'; Script := 'if (playertouchsme) {'#10'  say 1;'#10'}';
  end;
  with Result.NPCs[1] do
  begin
    X := 3; Y := 4; Image := ''; Script := 'hide;';
  end;
  SetLength(Result.Chests, 2);
  with Result.Chests[0] do begin X := 30; Y := 31; Item := 1; Sign := -1; end;
  with Result.Chests[1] do begin X := 33; Y := 31; Item := 24; Sign := 2; end;
  SetLength(Result.Signs, 3);
  with Result.Signs[0] do begin X := 10; Y := 20; Text := 'Welcome!'#10'Press #A to read #l#r'; end;
  with Result.Signs[1] do begin X := 0; Y := 0; Text := 'Got #h it, 100% sure #4'; end;
  with Result.Signs[2] do begin X := 1; Y := 2; Text := 'a#b'; end;
end;

function SameObjects(A, B: TAdventureLevel; out Why: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  Why := '';
  for I := 0 to BoardSize - 1 do
    if A.Tiles[I] <> B.Tiles[I] then begin Why := 'tile ' + IntToStr(I); Exit; end;
  if Length(A.Links) <> Length(B.Links) then begin Why := 'link count'; Exit; end;
  for I := 0 to High(A.Links) do
    if (A.Links[I].Dest <> B.Links[I].Dest) or (A.Links[I].X <> B.Links[I].X) or
      (A.Links[I].Y <> B.Links[I].Y) or (A.Links[I].W <> B.Links[I].W) or
      (A.Links[I].H <> B.Links[I].H) or (A.Links[I].NewX <> B.Links[I].NewX) or
      (A.Links[I].NewY <> B.Links[I].NewY) then begin Why := 'link ' + IntToStr(I); Exit; end;
  if Length(A.Chests) <> Length(B.Chests) then begin Why := 'chest count'; Exit; end;
  for I := 0 to High(A.Chests) do
    if (A.Chests[I].X <> B.Chests[I].X) or (A.Chests[I].Y <> B.Chests[I].Y) or
      (A.Chests[I].Item <> B.Chests[I].Item) or (A.Chests[I].Sign <> B.Chests[I].Sign) then
      begin Why := 'chest ' + IntToStr(I); Exit; end;
  if Length(A.NPCs) <> Length(B.NPCs) then begin Why := 'npc count'; Exit; end;
  for I := 0 to High(A.NPCs) do
    if (A.NPCs[I].X <> B.NPCs[I].X) or (A.NPCs[I].Y <> B.NPCs[I].Y) or
      (A.NPCs[I].Image <> B.NPCs[I].Image) then begin Why := 'npc ' + IntToStr(I); Exit; end;
  if Length(A.Baddies) <> Length(B.Baddies) then begin Why := 'baddy count'; Exit; end;
  for I := 0 to High(A.Baddies) do
    if (A.Baddies[I].X <> B.Baddies[I].X) or (A.Baddies[I].Y <> B.Baddies[I].Y) or
      (A.Baddies[I].Kind <> B.Baddies[I].Kind) then begin Why := 'baddy ' + IntToStr(I); Exit; end;
  if Length(A.Signs) <> Length(B.Signs) then begin Why := 'sign count'; Exit; end;
  for I := 0 to High(A.Signs) do
    if (A.Signs[I].X <> B.Signs[I].X) or (A.Signs[I].Y <> B.Signs[I].Y) then
      begin Why := 'sign ' + IntToStr(I); Exit; end;
  Result := True;
end;

{ Sign text as the editor shows it: the CR escape dropped. }
function PlainSign(const S: string): string;
begin
  Result := StringReplace(S, '#K(13)', '', [rfReplaceAll]);
end;

procedure TestSignText;
var
  E: string;
begin
  E := EncodeSignText('Hello');
  Check(E = Chr(7 + 32) + Chr(30 + 32) + Chr(37 + 32) + Chr(37 + 32) + Chr(40 + 32),
    'sign text: letters are alphabet index + 32');
  Check(EncodeSignText(' ') = Chr(89 + 32), 'sign text: space is code 89');
  Check(EncodeSignText('a'#10'b') = EncodeSignText('a') + EncodeSignText('#K(13)') +
    Chr(96 + 32) + EncodeSignText('b'), 'sign text: a line break is #K(13) then the newline code');
  Check(Copy(EncodeSignText('#K(13)'), 1, 1) = Chr(86 + 32), 'sign text: #K starts with the literal # code');
  Check(EncodeSignText('#h') = Chr(74 + 32) + Chr(75 + 32), 'sign text: #h is two codes');
  Check(EncodeSignText('#A') = Chr(91 + 32), 'sign text: #A is one code');
  Check(DecodeSignText(EncodeSignText('Press #A, go #u #d #l #r! (#h #4 #x #y #z #.)')) =
    'Press #A, go #u #d #l #r! (#h #4 #x #y #z #.)', 'sign text: every glyph round trips');
  Check(PlainSign(DecodeSignText(EncodeSignText('line1'#10'line2'))) = 'line1'#10'line2',
    'sign text: line breaks round trip');
  Check(PlainSign(DecodeSignText(EncodeSignText('100%'))) = '100#K(37)',
    'sign text: % is outside the alphabet and becomes #K(37)');
  Check(EncodeSignText('x#K(13)'#10'y') = EncodeSignText('x'#10'y'),
    'sign text: a decoded CRLF is not doubled');
end;

procedure TestVerses;
var
  A, B, C: string;
begin
  SplitVerses('Stop!\Ouch!\Ha', A, B, C);
  Check((A = 'Stop!') and (B = 'Ouch!') and (C = 'Ha'), 'verses: three parts');
  SplitVerses('one\two\three\', A, B, C);
  Check((A = 'one') and (C = 'three'), 'verses: the .nw form with a trailing \');
  SplitVerses('', A, B, C);
  Check((A = '') and (B = '') and (C = ''), 'verses: empty');
  Check(BaddyTalks(0) and not BaddyTalks(4) and not BaddyTalks(6) and BaddyTalks(7),
    'verses: swamp soldier, frog and spider do not talk');
end;

procedure TestGRV;
var
  A, B: TAdventureLevel;
  S, Why: string;
  V1, V2, V3: string;
begin
  A := SampleLevel;
  B := TAdventureLevel.Create;
  try
    S := WriteGRV103(A);
    Check(Copy(S, 1, 8) = 'GR-V1.03', 'GR-V1.03: magic');
    Check(Pos(#$FF#$FF#$FF#10, S) > 0, 'GR-V1.03: baddy section ends FF FF FF 0A');
    Check(B.LoadFromString(S), 'GR-V1.03: loads back');
    Check(SameObjects(A, B, Why), 'GR-V1.03: board and objects round trip');
    if Why <> '' then WriteLn('      first difference: ', Why);
    Check(B.Links[0].Dest = 'house one.graal', 'GR-V1.03: a link name with a space');
    Check(B.Links[1].NewY = 'playery+60', 'GR-V1.03: a link expression');
    SplitVerses(B.Baddies[0].Verses, V1, V2, V3);
    Check((V1 = 'Stop!') and (V2 = 'Ouch!') and (V3 = 'Ha ha'), 'GR-V1.03: baddy verses');
    Check(B.Baddies[0].X = 0, 'GR-V1.03: a baddy at x 0 is kept');
    Check(B.Baddies[1].Verses = '\\', 'GR-V1.03: a frog saves empty verses');
    Check(B.NPCs[0].Script = A.NPCs[0].Script, 'GR-V1.03: NPC script newlines as A7');
    Check(B.NPCs[1].Image = '', 'GR-V1.03: NPC with no image');
    Check(B.Chests[0].Sign = -1, 'GR-V1.03: chest with no sign (-1)');
    Check(PlainSign(B.Signs[0].Text) = A.Signs[0].Text, 'GR-V1.03: sign text');
    Check(PlainSign(B.Signs[2].Text) = 'a#b', 'GR-V1.03: a lone # in a sign');
    Check(WriteGRV103(B) = S, 'GR-V1.03: writing the loaded level gives the same bytes');
    Check(Copy(LevelToString(A, 'x.graal'), 1, 8) = 'GR-V1.03', 'save: .graal is GR-V1.03');
    Check(Copy(LevelToString(A, 'x.zelda'), 1, 8) = 'GR-V1.03', 'save: any other extension is GR-V1.03');
    Check(Copy(LevelToString(A, 'X.NW'), 1, 8) = 'GLEVNW01', 'save: .nw is GLEVNW01');
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TestNWWrite;
var
  A, B: TAdventureLevel;
  S, Why: string;
  V1, V2, V3: string;
begin
  A := SampleLevel;
  B := TAdventureLevel.Create;
  try
    A.Links[0].Dest := 'house_one.graal'; { .nw tokens have no spaces }
    A.NPCs[0].X := 12.5;
    S := WriteNW(A);
    Check(Copy(S, 1, 9) = 'GLEVNW01'#10, 'GLEVNW01: magic line');
    Check(Pos('BOARD 0 63 64 0 ', S) > 0, 'GLEVNW01: 64 board rows');
    Check(Pos('NPC - 3 4', S) > 0, 'GLEVNW01: no image is -');
    Check(Pos('CHEST 30 31 bluerupee -1', S) > 0, 'GLEVNW01: chest item by name');
    Check(B.LoadFromString(S), 'GLEVNW01: loads back');
    if B.Chests[0].Item = -1 then
    begin
      { main's loader reads CHEST items as numbers; names resolve once
        GLevel has ItemIndex (graal-delphi PR #11) }
      Skip('GLEVNW01: chest item names load back (needs GLevel.ItemIndex)');
      B.Chests[0].Item := A.Chests[0].Item;
      B.Chests[1].Item := A.Chests[1].Item;
    end
    else
      Check(B.Chests[1].Item = 24, 'GLEVNW01: chest item names load back');
    Check(SameObjects(A, B, Why), 'GLEVNW01: board and objects round trip');
    if Why <> '' then WriteLn('      first difference: ', Why);
    Check(B.NPCs[0].X = 12.5, 'GLEVNW01: fractional NPC x');
    Check(B.NPCs[1].Image = '', 'GLEVNW01: no image loads back empty');
    Check(B.NPCs[0].Script = A.NPCs[0].Script + #10, 'GLEVNW01: NPC script lines');
    Check(B.Signs[0].Text = A.Signs[0].Text, 'GLEVNW01: sign text is plain');
    SplitVerses(B.Baddies[0].Verses, V1, V2, V3);
    Check((V1 = 'Stop!') and (V2 = 'Ouch!') and (V3 = 'Ha ha'), 'GLEVNW01: baddy verses');
    Check(WriteNW(B) = S, 'GLEVNW01: writing the loaded level gives the same text');
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TestSaveFile;
var
  A, B: TAdventureLevel;
  F: string;
begin
  A := SampleLevel;
  B := TAdventureLevel.Create;
  F := GetTempDir + 'testeditor205.graal';
  try
    Check(SaveLevelToFile(A, F), 'save: writes a file');
    Check(B.LoadFromFile(F) and (B.Magic = 'GR-V1.03') and (Length(B.Signs) = 3),
      'save: the file loads');
  finally
    DeleteFile(F);
    B.Free;
    A.Free;
  end;
end;

procedure TestEditorBoard;
var
  E: TEditor;
  D: TEditorDoc;
  I: Integer;
  B: TTileBlock;
begin
  E := TEditor.Create;
  try
    E.Background := 7;
    D := E.NewDoc;
    Check((D.Title = '(new)') and (D.Level.Tiles[0] = 7) and (D.Level.Tiles[BoardSize - 1] = 7),
      'editor: a new level is (new), filled with the background tile');
    D.SetTile(3, 4, 100);
    Check((D.Level.Tile(3, 4) = 100) and D.Modified and (D.UndoCount = 1), 'editor: set a tile');
    Check(D.Undo and (D.Level.Tile(3, 4) = 7), 'editor: undo restores the tile');
    Check(D.HasSel and (D.SelX = 3) and (D.SelY = 4) and (D.SelW = 1), 'editor: undo selects the rectangle');
    Check(not D.Undo, 'editor: nothing more to undo');
    for I := 1 to 130 do D.SetTile(I mod 64, 0, I);
    Check(D.UndoCount = 128, 'editor: the undo stack holds 128 records');
    for I := 1 to 128 do D.Undo;
    { records 1 and 2 (x 1 and 2 from the background) were dropped }
    Check((D.Level.Tile(1, 0) = 1) and (D.Level.Tile(2, 0) = 2) and (D.Level.Tile(3, 0) = 7),
      'editor: the oldest records were dropped');

    D.Select(10, 12, 8, 9);
    Check((D.SelX = 8) and (D.SelY = 9) and (D.SelW = 3) and (D.SelH = 4), 'editor: selection is normalised');
    D.Select(60, 60, 70, -3);
    Check((D.SelX = 60) and (D.SelY = 0) and (D.SelW = 4) and (D.SelH = 61), 'editor: selection is clipped to the board');

    { copy floats a copy; drop writes it }
    D.Select(0, 0, 1, 1);
    D.FillSelection(50);
    E.Copy;
    Check(D.Floating and (D.Float.W = 2) and (D.Level.Tile(0, 0) = 50), 'editor: copy floats the selection, board unchanged');
    D.MoveFloat(20, 20);
    D.DropFloat;
    Check(not D.Floating and (D.Level.Tile(21, 21) = 50) and (D.Level.Tile(0, 0) = 50),
      'editor: dropping writes the floating block');
    Check(D.HasSel and (D.SelX = 20) and (D.SelW = 2), 'editor: the drop is selected');
    { cut lifts and clears }
    E.Cut;
    Check(D.Floating and (D.Level.Tile(20, 20) = 7), 'editor: cut fills the hole with the background');
    D.MoveFloat(62, 63);
    D.DropFloat;
    Check((D.Level.Tile(62, 63) = 50) and (D.Level.Tile(63, 63) = 50), 'editor: a drop at the edge is clipped');
    Check(D.Undo and (D.Level.Tile(62, 63) = 7), 'editor: undo a clipped drop');
    E.Paste(30, 31);
    Check(D.FloatContains(31, 32) and not D.FloatContains(32, 32), 'editor: paste floats the clipboard');
    E.Delete;
    Check(not D.Floating, 'editor: delete drops a floating paste');
    D.Select(0, 0, 1, 1);
    E.Delete;
    Check(D.Level.Tile(0, 0) = 7, 'editor: delete fills the selection with the background');

    { flood fill }
    D.Select(0, 0, 63, 63);
    D.FillSelection(7);
    for I := 0 to 63 do D.SetTile(I, 10, 1); { a wall across the board }
    D.FloodFill(5, 5, TileBlock(1, 1, 3));
    Check((D.Level.Tile(0, 0) = 3) and (D.Level.Tile(63, 9) = 3) and (D.Level.Tile(5, 10) = 1) and
      (D.Level.Tile(5, 11) = 7), 'editor: flood fill stops at other tiles');
    B := TileBlock(2, 1, 4);
    B.Tiles[1] := 5;
    D.FloodFill(0, 20, B);
    Check((D.Level.Tile(0, 20) = 4) and (D.Level.Tile(1, 20) = 5) and (D.Level.Tile(2, 30) = 4),
      'editor: flood fill repeats a block');
    Check(D.Undo and (D.Level.Tile(0, 20) = 7) and (D.Level.Tile(0, 0) = 3), 'editor: flood fill is one undo');
  finally
    E.Free;
  end;
end;

procedure TestEditorObjects;
var
  E: TEditor;
  D: TEditorDoc;
  K: TEditorObjKind;
  N, I: Integer;
  L: TLevelLink;
  F: string;
begin
  E := TEditor.Create;
  try
    D := E.NewDoc;
    N := D.AddChest(10, 10);
    Check((D.Level.Chests[N].Item = 1) and (D.Level.Chests[N].Sign = -1), 'objects: new chest is bluerupee, no sign');
    N := D.AddBaddy(20, 20, 0);
    Check(D.Level.Baddies[N].Verses = 'Stop!\Ouch!\', 'objects: new baddy says Stop! and Ouch!');
    N := D.AddBaddy(22, 20, 5);
    Check(D.Level.Baddies[N].Verses = '\\', 'objects: a frog has no verses');
    D.AddNPC(30.5, 30, 'x.png');
    Check(D.ObjectAt(11, 11, K, I) and (K = okChest) and (I = 0), 'objects: chest under the cursor');
    Check(D.ObjectAt(31, 31, K, I) and (K = okNPC), 'objects: NPC under the cursor');
    Check(not D.ObjectAt(12, 12, K, I) and (K = okNone), 'objects: nothing there');
    N := D.CloneObject(okBaddy, 0, 40, 41);
    Check((N = 2) and (D.Level.Baddies[2].X = 40) and (D.Level.Baddies[2].Verses = 'Stop!\Ouch!\'),
      'objects: right button clones a baddy');
    D.DeleteObject(okBaddy, 1);
    Check((Length(D.Level.Baddies) = 2) and (D.Level.Baddies[1].X = 40), 'objects: delete a baddy');
    D.MoveObject(okNPC, 0, 1.5, 2);
    Check(D.Level.NPCs[0].X = 1.5, 'objects: move an NPC');

    L := LinkWarpDefaults(63, 10, 1, 4);
    Check((L.NewX = '0') and (L.NewY = 'playery'), 'warp: east edge arrives at x 0');
    L := LinkWarpDefaults(10, 63, 4, 1);
    Check((L.NewX = 'playerx') and (L.NewY = '0'), 'warp: south edge arrives at y 0');
    L := LinkWarpDefaults(0, 10, 1, 4);
    Check(L.NewX = '61', 'warp: one-wide west edge arrives at x 61');
    L := LinkWarpDefaults(10, 0, 4, 1);
    Check(L.NewY = '61', 'warp: one-high north edge arrives at y 61');
    L := LinkWarpDefaults(0, 10, 2, 4);
    Check((L.NewX = 'playerx') and (L.NewY = 'playery'), 'warp: elsewhere both follow the player');
    D.Select(63, 30, 63, 33);
    N := D.MakeWarpLink;
    Check((N = 0) and (D.Level.Links[0].H = 4) and (D.Level.Links[0].NewX = '0'), 'warp: from the selection');

    Check(not D.Save and D.NeedsName, 'save: a new level needs a name');
    F := GetTempDir + 'testeditor205-doc.nw';
    D.Level.Links[0].Dest := 'next.nw';
    Check(D.SaveAs(F) and not D.Modified and (D.Title = 'testeditor205-doc.nw'), 'save: save as .nw');
    E.CloseDoc(0);
    Check(E.DocCount = 0, 'tabs: closed');
    D := E.OpenDoc(F);
    Check((D <> nil) and (Length(D.Level.Chests) = 1) and (Length(D.Level.NPCs) = 1) and
      (D.Level.NPCs[0].X = 1.5) and (D.Level.Links[0].Dest = 'next.nw'), 'tabs: reopen the saved level');
    Check(E.OpenDoc(F) = D, 'tabs: opening an open file switches to its tab');
    E.NewDoc;
    Check((E.DocCount = 2) and (E.Current = 1), 'tabs: a second tab');
    DeleteFile(F);
    F := GetTempDir + 'testeditor205-bad.graal';
    WriteText(F, 'not a level');
    Check((E.OpenDoc(F) = nil) and (E.LastError = 'Unsupported file type!'), 'open: Unsupported file type!');
    DeleteFile(F);
  finally
    E.Free;
  end;
end;

procedure TestTutorials;
const
  Names: array[0..12] of string = ('a-1', 'a-2', 'a-3', 'a-4', 'b-1', 'b-2',
    'b-2_house', 'b-3', 'b-4', 'c-1', 'c-2', 'c-3', 'c-4');
var
  Dir, Orig, Again: string;
  I, Same: Integer;
  L: TAdventureLevel;
begin
  Dir := GetEnvironmentVariable('GRAAL205_TUTORIALS');
  if (Dir = '') or not FileExists(IncludeTrailingPathDelimiter(Dir) + 'tutorial_a-1.graal') then
  begin
    Skip('tutorials: set GRAAL205_TUTORIALS to check the writer against the 2.05 files');
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(Dir);
  Same := 0;
  L := TAdventureLevel.Create;
  try
    for I := 0 to High(Names) do
    begin
      Orig := ReadFileStr(Dir + 'tutorial_' + Names[I] + '.graal');
      if not L.LoadFromString(Orig) then
      begin
        Check(False, 'tutorials: ' + Names[I] + ' loads');
        Continue;
      end;
      Again := WriteGRV103(L);
      if Again = Orig then Inc(Same)
      else WriteLn('      ', Names[I], ': ', Length(Orig), ' bytes, rewritten ', Length(Again));
    end;
  finally
    L.Free;
  end;
  Check(Same = Length(Names), Format('tutorials: %d of %d rewrite byte for byte', [Same, Length(Names)]));
end;

begin
  TestSignText;
  TestVerses;
  TestGRV;
  TestNWWrite;
  TestSaveFile;
  TestEditorBoard;
  TestEditorObjects;
  TestTutorials;
  WriteLn(Format('%d passed, %d failed, %d skipped', [Passed, Failed, Skipped]));
  if Failed > 0 then Halt(1);
end.
