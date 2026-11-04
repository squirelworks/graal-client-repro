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
  GLevelWrite in '../../common/GLevelWrite.pas';

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
  TestTutorials;
  WriteLn(Format('%d passed, %d failed, %d skipped', [Passed, Failed, Skipped]));
  if Failed > 0 then Halt(1);
end.
