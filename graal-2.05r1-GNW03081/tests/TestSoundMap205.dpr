{ Tests of the 2.05 rev 1 sound and map units (GSound, Sound205, Map205).
  No sound device is opened: SoundEnabled stays off, and the mixer is
  driven directly. }
program TestSoundMap205;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils, Classes,
  GClamp in '../../common/GClamp.pas',
  GNumText in '../../common/GNumText.pas',
  GTypes in '../../common/GTypes.pas',
  GSurface in '../../common/GSurface.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GAni in '../../common/GAni.pas',
  GSound in '../../common/GSound.pas',
  Adventure in '../src/Adventure.pas',
  Sound205 in '../src/Sound205.pas',
  Map205 in '../src/Map205.pas';

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then Inc(Passed)
  else
  begin
    Inc(Failed);
    WriteLn('FAIL: ', What);
  end;
end;

function LE(V: Cardinal; Bytes: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Bytes - 1 do
    Result := Result + Chr((V shr (8 * I)) and $FF);
end;

{ A PCM .wav in memory. }
function MakeWav(Rate, Chans, Bits: Integer; const Pcm: string): string;
var
  Fmt: string;
begin
  Fmt := LE(1, 2) + LE(Chans, 2) + LE(Rate, 4) + LE(Rate * Chans * Bits div 8, 4) +
    LE(Chans * Bits div 8, 2) + LE(Bits, 2);
  Result := 'RIFF' + LE(4 + 8 + Length(Fmt) + 8 + Length(Pcm), 4) + 'WAVE' +
    'fmt ' + LE(Length(Fmt), 4) + Fmt + 'LIST' + LE(3, 4) + 'abc' + #0 +
    'data' + LE(Length(Pcm), 4) + Pcm;
end;

procedure TestWav;
var
  S: TSoundData;
  Pcm: string;
  I: Integer;
begin
  { 8-bit mono at 11025: every frame doubles; 255 is the top }
  Pcm := '';
  for I := 0 to 99 do Pcm := Pcm + Chr(255);
  S := DecodeWav(MakeWav(11025, 1, 8, Pcm));
  Check(S <> nil, 'wav: 8-bit mono decodes (with an odd-sized chunk before data)');
  if S <> nil then
  begin
    Check(S.Frames = 200, 'wav: 11025 Hz becomes 22050 Hz');
    Check((S.Samples[0] = 127 * 256) and (S.Samples[1] = 127 * 256), 'wav: mono goes to both sides');
    S.Free;
  end;
  { 16-bit stereo at 22050: kept as is }
  S := DecodeWav(MakeWav(22050, 2, 16, LE($1000, 2) + LE($FF00, 2) + LE(5, 2) + LE(6, 2)));
  Check((S <> nil) and (S.Frames = 2), 'wav: 16-bit stereo decodes');
  if S <> nil then
  begin
    Check((S.Samples[0] = 4096) and (S.Samples[1] = -256) and (S.Samples[3] = 6),
      'wav: 16-bit samples are signed, left then right');
    S.Free;
  end;
  Check(DecodeWav('RIFF....WAVE') = nil, 'wav: no fmt or data chunk');
  Check(DecodeWav(MakeWav(22050, 1, 24, 'abcdef')) = nil, 'wav: 24-bit is not read');
  Check(DecodeWav('not a wave at all') = nil, 'wav: garbage');
  Check(DecodeWav(Copy(MakeWav(22050, 1, 16, 'abcdef'), 1, 30)) = nil, 'wav: cut short');
end;

procedure TestPanVolume;
var
  Pan, Vol: Integer;
  GL, GR: Single;
begin
  { a sound on the player: 2.05 pans against x without the 1.5 }
  SoundPanVolume(31.5, 32, 30, 30, Pan, Vol);
  Check((Pan = 225) and (Vol = 0), 'sound: on the player, pan 225, full volume');
  SoundPanVolume(30 + 1.5 + 3, 30 + 2 + 4, 30, 30, Pan, Vol);
  Check(Vol = -25, 'sound: volume falls with the squared distance');
  SoundPanVolume(200, 30, 30, 30, Pan, Vol);
  Check((Pan = 10000) and (Vol = -10000), 'sound: pan and volume are clamped');
  SoundPanVolume(-200, 30, 30, 30, Pan, Vol);
  Check(Pan = -10000, 'sound: pan is clamped on the left');
  PanVolumeGains(0, 0, GL, GR);
  Check((Abs(GL - 1) < 1e-6) and (Abs(GR - 1) < 1e-6), 'sound: centre, full gain');
  PanVolumeGains(2000, 0, GL, GR);
  Check((Abs(GL - 0.1) < 1e-4) and (Abs(GR - 1) < 1e-6), 'sound: pan right takes 20 dB off the left');
  PanVolumeGains(0, -2000, GL, GR);
  Check((Abs(GL - 0.1) < 1e-4) and (Abs(GR - 0.1) < 1e-4), 'sound: volume -2000 is 20 dB down');
end;

procedure TestMixer;
var
  S: TSoundData;
  Buf: TSoundSamples;
  I: Integer;
begin
  S := TSoundData.Create;
  try
    S.Name := 'test.wav';
    S.Frames := 10;
    SetLength(S.Samples, 20);
    for I := 0 to 19 do S.Samples[I] := 10000;
    for I := 1 to MaxVoices do
      Check(StartVoice(S, 0, 0, False), 'mixer: voice ' + IntToStr(I) + ' starts');
    Check(not StartVoice(S, 0, 0, False), 'mixer: a ninth sound is dropped');
    Check(VoicesPlaying = MaxVoices, 'mixer: eight playing');
    MixVoices(Buf, 4);
    Check(Buf[0] = 32767, 'mixer: the sum is clipped');
    MixVoices(Buf, 10);
    Check(VoicesPlaying = 0, 'mixer: one-shot voices end');
    Check(Buf[2 * 9] = 0, 'mixer: silence after the end');
    Check(StartVoice(S, 0, 0, True), 'mixer: a looped voice starts');
    MixVoices(Buf, 25);
    Check((VoicesPlaying = 1) and (Buf[2 * 24] = 10000), 'mixer: a looped voice keeps going');
    StopSound('+TEST.WAV');
    Check(VoicesPlaying = 0, 'mixer: stopsound stops it by name, any case');
  finally
    S.Free;
  end;
  { with sound off nothing starts and nothing is opened }
  SoundEnabled := False;
  PlaySound('sword.wav');
  Check(VoicesPlaying = 0, 'sound: off, PlaySound does nothing');
  SoundTick;
end;

procedure TestMapFile;
var
  M: TGraalMap;
  PX, PY: Integer;
begin
  M := TGraalMap.Create;
  try
    M.LoadText('"a-1.graal","b-1.graal","c-1.graal"'#13#10 +
      '"a-2.graal","","C-2.GRAAL"'#10'"x","levels/b-3.graal","c-3.graal"'#10);
    Check((M.Cols = 3) and (M.Rows = 3), 'map: columns from the first line, rows from the count');
    Check(M.IndexOf('c-2.graal') = 5, 'map: names are matched in lower case');
    Check(M.IndexOf('B-3.graal') = 7, 'map: a folder in the file is dropped');
    Check((M.IndexOf('') = -1) and (M.IndexOf('x') = -1), 'map: empty cells are not levels');
    Check(M.IndexOf('nowhere.graal') = -1, 'map: an unknown level');
    Check(M.Place('b-1.graal', 10, 20, PX, PY) and (PX = 128 + 20) and (PY = 40),
      'map: place in half tiles, column * 128 + 2x');
    { Delphi's Round, as 2.05: half to even }
    Check(M.Place('c-3.graal', 63.5, 0.25, PX, PY) and (PX = 256 + 127) and (PY = 256),
      'map: place rounds half to even');
    Check(not M.Place('nowhere.graal', 1, 1, PX, PY) and (PX = -1), 'map: off the map');
  finally
    M.Free;
  end;
end;

procedure TestBigMap;
var
  G: TAdventure;
  Root: string;
  L: TStringList;
begin
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'soundmap-' + IntToStr(Random(1000000)) + PathDelim;
  ForceDirectories(Root);
  L := TStringList.Create;
  try
    { 18 x 17 levels: 1008 x 952 px, bigger than the view }
    L.Text := '';
    L.Add('"l0.graal","l1.graal","l2.graal","l3.graal","l4.graal","l5.graal",' +
      '"l6.graal","l7.graal","l8.graal","l9.graal","l10.graal","l11.graal","l12.graal",' +
      '"l13.graal","l14.graal","l15.graal","l16.graal","l17.graal"');
    while L.Count < 17 do L.Add(L[0]);
    L.SaveToFile(Root + 'bigmap.txt');
    L.Text := '"tiny.graal","l1.graal"';
    L.SaveToFile(Root + 'tutorialmap.txt');
  finally
    L.Free;
  end;
  SetAssetRootsFor('', Root, '2.05r1');
  G := TAdventure.Create;
  try
    G.Headless := True;
    G.Level.Name := 'l17.graal';
    G.Player.X := 60;
    G.Player.Y := 30;
    UseDefaultMaps;
    G.MapKey := True;
    MapTick(G);
    Check(MapOpen, 'big map: the map key opens it');
    Check((BigMap.Cols = 18) and (BigMap.Rows = 17), 'big map: bigmap.txt read');
    { head at column 17: (17 * 128 + 120) * 56 / 128 = 1057, past the right
      edge, so the scroll stops at 1008 - 640 }
    Check(MapScrollX = 18 * 56 - ScreenW, 'big map: centred on the player, kept inside the map');
    { the first row: (2 * 30) * 56 / 128 = 26 px down, above the middle }
    Check(MapScrollY = 0, 'big map: the top edge holds the scroll at 0');
    G.Keys[DirLeft] := True;
    G.ActionKey := True;
    MapTick(G);
    Check(MapScrollX = 18 * 56 - ScreenW - 8, 'big map: a held arrow scrolls 8 px a tick');
    Check(not G.Keys[DirLeft] and not G.ActionKey, 'big map: the game does not get the keys');
    G.Draw;
    Check(G.Screen.GetPixel(5, 5) = $FF000000, 'big map: no picture, the view is black');
    G.MapKey := True;
    MapTick(G);
    Check(not MapOpen, 'big map: the map key closes it');
    { a map smaller than the view is centred; a level not on it centres the
      whole map }
    UseTutorialMaps;
    G.Level.Name := 'tiny.graal';
    OpenBigMap(G);
    Check((MapScrollX = (2 * 56 - ScreenW) div 2) and (MapScrollY = (56 - ScreenH) div 2),
      'big map: a small map is centred');
    G.Level.Name := 'elsewhere.graal';
    OpenBigMap(G);
    Check(MapScrollX = (2 * 56 - ScreenW) div 2, 'big map: off the map, the whole map centred');
    MapOpen := False;
    UseDefaultMaps;
  finally
    G.Free;
    SetAssetRootsFor('', '', '');
    DeleteFile(Root + 'bigmap.txt');
    DeleteFile(Root + 'tutorialmap.txt');
    RemoveDir(Root);
  end;
end;

begin
  Randomize;
  TestWav;
  TestPanVolume;
  TestMixer;
  TestMapFile;
  TestBigMap;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
