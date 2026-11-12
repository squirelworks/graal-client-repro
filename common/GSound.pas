{ GSound: sound effects (.wav) and music, the way 2.05 plays them.

  2.05 plays effects through DelphiX (TDXSound / TDXWaveList on
  DirectSound) and music through an invisible TMediaPlayer (MCI) or a
  remote-controlled Winamp (graal_analysis client-internals/
  sound-and-music.md). Neither builds under Free Pascal or outside Windows,
  so this unit mixes the effects itself and hands the mix to the system:

    Windows   waveOut (winmm.dll, always present)
    Linux     ALSA, loaded at run time (libasound.so.2); without it, or
              without a sound device, everything stays silent
    others    silent

  Music (.mid and anything else that is not .wav) goes to MCI on Windows,
  as 2.05's MCI path does, and loops a .mid when it ends. Elsewhere it is
  silent for now.

  What is kept from 2.05's one sound routine (its sound path, graal_analysis
  client-internals/sound-and-music.md):
  - the file is looked for under sounds/ (GAssetDirs: the data folder,
    beside the program, wins over graal-assets); a missing file is silent;
  - a leading '+' loops the effect; looped effects stop with
    StopLoopedSounds (2.05 does that on leaving a level);
  - the fifteen effects 2.05 knows by name (arrow, axe, bomb, crush,
    extra, fire, horse2, item, lift, lift2, put, steps, sword, thunder,
    water) start at most once per tick;
  - at most 8 effects play at once; a ninth is dropped;
  - pan = (sound x - listener x) * 150, clamped to +-10000, in
    DirectSound units (hundredths of a dB taken off the far side); the
    listener x here is the player's x without the 1.5 that the volume uses,
    as in 2.05, so a sound on the player pans slightly right;
  - volume = -((listener x + 1.5 - sound x)^2 + (listener y + 2 -
    sound y)^2), in hundredths of a dB, clamped at -10000.

  Nothing here is original Graal code or data. }
unit GSound;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { the mix: 22050 Hz, 16-bit stereo }
  MixRate = 22050;
  MaxVoices = 8;

type
  TSoundSamples = array of SmallInt; { interleaved left, right at MixRate }

  { One decoded .wav. }
  TSoundData = class
  public
    Name: string;
    Frames: Integer;
    Samples: TSoundSamples;
  end;

var
  { Effects and music play only when this is set; a stress run or a test
    leaves it off and no sound device is opened. }
  SoundEnabled: Boolean = False;
  MusicEnabled: Boolean = True;
  ReverseStereo: Boolean = False;

{ The player's position (tiles, the top-left of the 3x3 box), for pan and
  volume. }
procedure SetListener(X, Y: Double);
{ An effect at the player (x + 1.5, y + 2). }
procedure PlaySound(const FileName: string);
{ An effect at X, Y (tiles). A name that is not .wav goes to the music. }
procedure PlaySoundAt(const FileName: string; X, Y: Double);
procedure StopSound(const FileName: string);
procedure StopLoopedSounds;
procedure PlayMusic(const FileName: string);
procedure StopMusic;
{ Once per game tick: clears the once-per-tick names and feeds the device. }
procedure SoundTick;
{ Closes the device and frees the cached sounds. }
procedure SoundShutdown;

{ Decodes a PCM .wav (8 or 16 bit, mono or stereo, any rate) to the mix
  format; nil when it is not one. }
function DecodeWav(const Data: string): TSoundData;
{ Pan and volume as 2.05 works them out (DirectSound units). }
procedure SoundPanVolume(SX, SY, LX, LY: Double; out Pan, Volume: Integer);
{ The left and right gains (0..1) for a DirectSound pan and volume. }
procedure PanVolumeGains(Pan, Volume: Integer; out GL, GR: Single);
{ Mixes Frames frames of the playing voices into Buf (interleaved stereo)
  and moves them on. }
procedure MixVoices(var Buf: TSoundSamples; Frames: Integer);
{ The number of voices playing. }
function VoicesPlaying: Integer;
{ Starts a decoded sound directly (tests); False when 8 are playing. }
function StartVoice(S: TSoundData; Pan, Volume: Integer; Loop: Boolean): Boolean;

implementation

uses
  GCompat, SysUtils, Classes, Math, GAssetDirs
{$IFDEF MSWINDOWS}
  , Windows
{$ENDIF}
{$IFDEF LINUX}
  , DynLibs
{$ENDIF};

type
  TVoice = record
    Sound: TSoundData;
    Pos: Integer;
    GL, GR: Single;
    Loop: Boolean;
  end;

const
  KnownEffects: array[0..14] of string = ('arrow.wav', 'axe.wav', 'bomb.wav',
    'crush.wav', 'extra.wav', 'fire.wav', 'horse2.wav', 'item.wav', 'lift.wav',
    'lift2.wav', 'put.wav', 'steps.wav', 'sword.wav', 'thunder.wav', 'water.wav');

var
  ListenerX: Double = 30;
  ListenerY: Double = 30;
  Voices: array[0..MaxVoices - 1] of TVoice;
  Cache: TStringList = nil;    { lower-case name -> TSoundData, or nil: not found }
  Looped: TStringList = nil;   { names of looped effects started }
  KnownUsed: array[0..14] of Boolean;
  DeviceTried: Boolean = False;
  MixBuf: TSoundSamples;
  TickCount: Integer = 0;
  MusicFile: string = '';
  MusicLoops: Boolean = False;

{ ---- .wav ---- }

function GetLE(const S: string; P, Bytes: Integer): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := Bytes - 1 downto 0 do
    Result := (Result shl 8) or Byte(S[P + I]);
end;

function DecodeWav(const Data: string): TSoundData;
var
  P, Len, Fmt, Chans, Rate, Bits, DataPos, DataLen, Align, N, I, C: Integer;
  ID: string;
  Src: array of Integer; { mono or stereo source samples, -32768..32767 }
  L, R, F: Double;
  A, B: Integer;
begin
  Result := nil;
  if (Length(Data) < 12) or (Copy(Data, 1, 4) <> 'RIFF') or (Copy(Data, 9, 4) <> 'WAVE') then
    Exit;
  Fmt := 0;
  Chans := 0;
  Rate := 0;
  Bits := 0;
  DataPos := 0;
  DataLen := 0;
  P := 13;
  while P + 8 <= Length(Data) + 1 do
  begin
    ID := Copy(Data, P, 4);
    Len := Integer(GetLE(Data, P + 4, 4));
    if Len < 0 then Exit;
    if (ID = 'fmt ') and (Len >= 16) and (P + 8 + 16 <= Length(Data) + 1) then
    begin
      Fmt := GetLE(Data, P + 8, 2);
      Chans := GetLE(Data, P + 10, 2);
      Rate := GetLE(Data, P + 12, 4);
      Bits := GetLE(Data, P + 22, 2);
    end
    else if ID = 'data' then
    begin
      DataPos := P + 8;
      DataLen := Min(Len, Length(Data) - DataPos + 1);
    end;
    P := P + 8 + Len + (Len and 1);
  end;
  if (Fmt <> 1) or not (Chans in [1, 2]) or not (Bits in [8, 16]) or
    (Rate < 1000) or (Rate > 192000) or (DataPos = 0) then Exit;
  Align := Chans * (Bits div 8);
  N := DataLen div Align;
  SetLength(Src, N * 2);
  for I := 0 to N - 1 do
    for C := 0 to 1 do
    begin
      P := DataPos + I * Align + (C mod Chans) * (Bits div 8);
      if Bits = 8 then
        Src[I * 2 + C] := (Byte(Data[P]) - 128) * 256
      else
        Src[I * 2 + C] := SmallInt(GetLE(Data, P, 2));
    end;
  Result := TSoundData.Create;
  { to MixRate by linear interpolation }
  if N = 0 then Result.Frames := 0
  else Result.Frames := Max(1, Round(Int64(N) * MixRate / Rate));
  SetLength(Result.Samples, Result.Frames * 2);
  for I := 0 to Result.Frames - 1 do
  begin
    F := I * Rate / MixRate;
    A := Trunc(F);
    if A >= N - 1 then
    begin
      A := N - 1;
      B := A;
    end
    else
      B := A + 1;
    F := F - Trunc(F);
    L := Src[A * 2] + (Src[B * 2] - Src[A * 2]) * F;
    R := Src[A * 2 + 1] + (Src[B * 2 + 1] - Src[A * 2 + 1]) * F;
    Result.Samples[I * 2] := Round(L);
    Result.Samples[I * 2 + 1] := Round(R);
  end;
end;

{ ---- mixing ---- }

procedure SoundPanVolume(SX, SY, LX, LY: Double; out Pan, Volume: Integer);
var
  V: Double;
begin
  V := (SX - LX) * 150;
  if V < -10000 then V := -10000;
  if V > 10000 then V := 10000;
  Pan := Round(V);
  V := -(Sqr(LX + 1.5 - SX) + Sqr(LY + 2 - SY));
  if V < -10000 then V := -10000;
  Volume := Round(V);
end;

procedure PanVolumeGains(Pan, Volume: Integer; out GL, GR: Single);
var
  G: Double;
begin
  { hundredths of a dB: gain = 10 ^ (v / 2000) }
  G := Power(10, Volume / 2000);
  GL := G;
  GR := G;
  if Pan > 0 then GL := G * Power(10, -Pan / 2000)
  else if Pan < 0 then GR := G * Power(10, Pan / 2000);
end;

function VoicesPlaying: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to MaxVoices - 1 do
    if Voices[I].Sound <> nil then Inc(Result);
end;

function StartVoice(S: TSoundData; Pan, Volume: Integer; Loop: Boolean): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (S = nil) or (S.Frames = 0) then Exit;
  if ReverseStereo then Pan := -Pan;
  for I := 0 to MaxVoices - 1 do
    if Voices[I].Sound = nil then
    begin
      Voices[I].Sound := S;
      Voices[I].Pos := 0;
      Voices[I].Loop := Loop;
      PanVolumeGains(Pan, Volume, Voices[I].GL, Voices[I].GR);
      Result := True;
      Exit;
    end;
end;

procedure MixVoices(var Buf: TSoundSamples; Frames: Integer);
var
  Acc: array of Integer;
  I, V, K: Integer;
  S: TSoundData;
begin
  if Length(Buf) < Frames * 2 then SetLength(Buf, Frames * 2);
  SetLength(Acc, Frames * 2);
  for I := 0 to Frames * 2 - 1 do Acc[I] := 0;
  for V := 0 to MaxVoices - 1 do
  begin
    S := Voices[V].Sound;
    if S = nil then Continue;
    for I := 0 to Frames - 1 do
    begin
      if Voices[V].Pos >= S.Frames then
      begin
        if Voices[V].Loop then Voices[V].Pos := 0
        else
        begin
          Voices[V].Sound := nil;
          Break;
        end;
      end;
      K := Voices[V].Pos * 2;
      Inc(Acc[I * 2], Round(S.Samples[K] * Voices[V].GL));
      Inc(Acc[I * 2 + 1], Round(S.Samples[K + 1] * Voices[V].GR));
      Inc(Voices[V].Pos);
    end;
    if (Voices[V].Sound <> nil) and not Voices[V].Loop and (Voices[V].Pos >= S.Frames) then
      Voices[V].Sound := nil;
  end;
  for I := 0 to Frames * 2 - 1 do
    Buf[I] := Max(-32768, Min(32767, Acc[I]));
end;

{ ---- devices ---- }

{$IFDEF MSWINDOWS}
type
  TWaveFormatEx = packed record
    wFormatTag, nChannels: Word;
    nSamplesPerSec, nAvgBytesPerSec: DWORD;
    nBlockAlign, wBitsPerSample, cbSize: Word;
  end;
  PWaveHdr = ^TWaveHdr;
  TWaveHdr = record
    lpData: PChar;
    dwBufferLength, dwBytesRecorded: DWORD;
    dwUser: PtrUInt;
    dwFlags, dwLoops: DWORD;
    lpNext: PWaveHdr;
    reserved: PtrUInt;
  end;

function waveOutOpen(lphWaveOut: PHandle; uDeviceID: UINT; lpFormat: Pointer;
  dwCallback, dwInstance: PtrUInt; fdwOpen: DWORD): UINT; stdcall; external 'winmm.dll';
function waveOutPrepareHeader(h: THandle; pwh: PWaveHdr; cbwh: UINT): UINT; stdcall; external 'winmm.dll';
function waveOutUnprepareHeader(h: THandle; pwh: PWaveHdr; cbwh: UINT): UINT; stdcall; external 'winmm.dll';
function waveOutWrite(h: THandle; pwh: PWaveHdr; cbwh: UINT): UINT; stdcall; external 'winmm.dll';
function waveOutReset(h: THandle): UINT; stdcall; external 'winmm.dll';
function waveOutClose(h: THandle): UINT; stdcall; external 'winmm.dll';
function mciSendStringA(lpstrCommand, lpstrReturnString: PChar; uReturnLength: UINT;
  hwndCallback: THandle): DWORD; stdcall; external 'winmm.dll';

const
  WAVE_MAPPER = UINT(-1);
  WHDR_DONE = 1;
  BufFrames = 441;   { 20 ms }
  BufCount = 8;
  QueueTarget = 5;   { 100 ms queued }

var
  WaveOut: THandle = 0;
  Hdrs: array[0..BufCount - 1] of TWaveHdr;
  HdrData: array[0..BufCount - 1] of array[0..BufFrames * 2 - 1] of SmallInt;
  HdrBusy: array[0..BufCount - 1] of Boolean;

function OpenDevice: Boolean;
var
  F: TWaveFormatEx;
  I: Integer;
begin
  F.wFormatTag := 1;
  F.nChannels := 2;
  F.nSamplesPerSec := MixRate;
  F.wBitsPerSample := 16;
  F.nBlockAlign := 4;
  F.nAvgBytesPerSec := MixRate * 4;
  F.cbSize := 0;
  Result := waveOutOpen(@WaveOut, WAVE_MAPPER, @F, 0, 0, 0) = 0;
  if not Result then
  begin
    WaveOut := 0;
    Exit;
  end;
  for I := 0 to BufCount - 1 do
  begin
    FillChar(Hdrs[I], SizeOf(TWaveHdr), 0);
    Hdrs[I].lpData := @HdrData[I][0];
    Hdrs[I].dwBufferLength := BufFrames * 4;
    waveOutPrepareHeader(WaveOut, @Hdrs[I], SizeOf(TWaveHdr));
    HdrBusy[I] := False;
  end;
end;

procedure FeedDevice;
var
  I, Queued: Integer;
begin
  if WaveOut = 0 then Exit;
  Queued := 0;
  for I := 0 to BufCount - 1 do
  begin
    if HdrBusy[I] and (Hdrs[I].dwFlags and WHDR_DONE <> 0) then HdrBusy[I] := False;
    if HdrBusy[I] then Inc(Queued);
  end;
  for I := 0 to BufCount - 1 do
  begin
    if Queued >= QueueTarget then Break;
    if HdrBusy[I] then Continue;
    MixVoices(MixBuf, BufFrames);
    Move(MixBuf[0], HdrData[I][0], BufFrames * 4);
    Hdrs[I].dwFlags := Hdrs[I].dwFlags and not WHDR_DONE;
    if waveOutWrite(WaveOut, @Hdrs[I], SizeOf(TWaveHdr)) = 0 then
    begin
      HdrBusy[I] := True;
      Inc(Queued);
    end;
  end;
end;

procedure CloseDevice;
var
  I: Integer;
begin
  if WaveOut = 0 then Exit;
  waveOutReset(WaveOut);
  for I := 0 to BufCount - 1 do
    waveOutUnprepareHeader(WaveOut, @Hdrs[I], SizeOf(TWaveHdr));
  waveOutClose(WaveOut);
  WaveOut := 0;
end;

function Mci(const Cmd: string): string;
var
  Ret: array[0..127] of Char;
begin
  Ret[0] := #0;
  if mciSendStringA(PChar(Cmd), @Ret[0], SizeOf(Ret), 0) = 0 then Result := Ret
  else Result := '';
end;

procedure MusicPlay(const Path: string);
var
  Kind: string;
begin
  Mci('close graalmusic');
  if LowerCase(ExtractFileExt(Path)) = '.mid' then Kind := ' type sequencer' else Kind := '';
  Mci('open "' + Path + '"' + Kind + ' alias graalmusic');
  Mci('play graalmusic');
end;

procedure MusicStop;
begin
  Mci('close graalmusic');
end;

function MusicStopped: Boolean;
begin
  Result := Mci('status graalmusic mode') = 'stopped';
end;

procedure MusicRewind;
begin
  Mci('play graalmusic from 0');
end;
{$ENDIF}

{$IFDEF LINUX}
const
  SND_PCM_STREAM_PLAYBACK = 0;
  SND_PCM_NONBLOCK = 1;
  SND_PCM_FORMAT_S16_LE = 2;
  SND_PCM_ACCESS_RW_INTERLEAVED = 3;
  SND_PCM_STATE_PREPARED = 2;
  TargetFrames = MixRate div 10;  { 100 ms queued }

type
  Tsnd_pcm_open = function(pcm: PPointer; name: PChar; stream, mode: Integer): Integer; cdecl;
  Tsnd_pcm_set_params = function(pcm: Pointer; format, access: Integer;
    channels, rate: Cardinal; soft_resample: Integer; latency: Cardinal): Integer; cdecl;
  Tsnd_pcm_get_params = function(pcm: Pointer; buffer_size, period_size: PPtrUInt): Integer; cdecl;
  Tsnd_pcm_avail_update = function(pcm: Pointer): PtrInt; cdecl;
  Tsnd_pcm_writei = function(pcm: Pointer; buffer: Pointer; size: PtrUInt): PtrInt; cdecl;
  Tsnd_pcm_recover = function(pcm: Pointer; err, silent: Integer): Integer; cdecl;
  Tsnd_pcm_state = function(pcm: Pointer): Integer; cdecl;
  Tsnd_pcm_start = function(pcm: Pointer): Integer; cdecl;
  Tsnd_pcm_close = function(pcm: Pointer): Integer; cdecl;

var
  Lib: TLibHandle = NilHandle;
  Pcm: Pointer = nil;
  BufferFrames: PtrUInt = 0;
  snd_pcm_open: Tsnd_pcm_open;
  snd_pcm_set_params: Tsnd_pcm_set_params;
  snd_pcm_get_params: Tsnd_pcm_get_params;
  snd_pcm_avail_update: Tsnd_pcm_avail_update;
  snd_pcm_writei: Tsnd_pcm_writei;
  snd_pcm_recover: Tsnd_pcm_recover;
  snd_pcm_state: Tsnd_pcm_state;
  snd_pcm_start: Tsnd_pcm_start;
  snd_pcm_close: Tsnd_pcm_close;

function OpenDevice: Boolean;
var
  Period: PtrUInt;
begin
  Result := False;
  Lib := LoadLibrary('libasound.so.2');
  if Lib = NilHandle then Exit;
  snd_pcm_open := Tsnd_pcm_open(GetProcedureAddress(Lib, 'snd_pcm_open'));
  snd_pcm_set_params := Tsnd_pcm_set_params(GetProcedureAddress(Lib, 'snd_pcm_set_params'));
  snd_pcm_get_params := Tsnd_pcm_get_params(GetProcedureAddress(Lib, 'snd_pcm_get_params'));
  snd_pcm_avail_update := Tsnd_pcm_avail_update(GetProcedureAddress(Lib, 'snd_pcm_avail_update'));
  snd_pcm_writei := Tsnd_pcm_writei(GetProcedureAddress(Lib, 'snd_pcm_writei'));
  snd_pcm_recover := Tsnd_pcm_recover(GetProcedureAddress(Lib, 'snd_pcm_recover'));
  snd_pcm_state := Tsnd_pcm_state(GetProcedureAddress(Lib, 'snd_pcm_state'));
  snd_pcm_start := Tsnd_pcm_start(GetProcedureAddress(Lib, 'snd_pcm_start'));
  snd_pcm_close := Tsnd_pcm_close(GetProcedureAddress(Lib, 'snd_pcm_close'));
  if not Assigned(snd_pcm_open) or not Assigned(snd_pcm_set_params) or
    not Assigned(snd_pcm_get_params) or not Assigned(snd_pcm_avail_update) or
    not Assigned(snd_pcm_writei) or not Assigned(snd_pcm_recover) or
    not Assigned(snd_pcm_state) or not Assigned(snd_pcm_start) or
    not Assigned(snd_pcm_close) then
  begin
    UnloadLibrary(Lib);
    Lib := NilHandle;
    Exit;
  end;
  if snd_pcm_open(@Pcm, 'default', SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK) < 0 then
  begin
    Pcm := nil;
    Exit;
  end;
  if (snd_pcm_set_params(Pcm, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
    2, MixRate, 1, 250000) < 0) or (snd_pcm_get_params(Pcm, @BufferFrames, @Period) < 0) then
  begin
    snd_pcm_close(Pcm);
    Pcm := nil;
    Exit;
  end;
  Result := True;
end;

procedure FeedDevice;
var
  Avail, Want, Done: PtrInt;
begin
  if Pcm = nil then Exit;
  Avail := snd_pcm_avail_update(Pcm);
  if Avail < 0 then
  begin
    snd_pcm_recover(Pcm, Avail, 1);
    Avail := snd_pcm_avail_update(Pcm);
    if Avail < 0 then Exit;
  end;
  { keep about TargetFrames queued: what is in the device is the buffer
    less what is free }
  Want := TargetFrames - (PtrInt(BufferFrames) - Avail);
  if Want > Avail then Want := Avail;
  if Want <= 0 then Exit;
  MixVoices(MixBuf, Want);
  Done := snd_pcm_writei(Pcm, @MixBuf[0], Want);
  if Done < 0 then snd_pcm_recover(Pcm, Done, 1);
  if snd_pcm_state(Pcm) = SND_PCM_STATE_PREPARED then snd_pcm_start(Pcm);
end;

procedure CloseDevice;
begin
  if Pcm <> nil then snd_pcm_close(Pcm);
  Pcm := nil;
  if Lib <> NilHandle then UnloadLibrary(Lib);
  Lib := NilHandle;
end;
{$ENDIF}

{$IFNDEF MSWINDOWS}
{$IFNDEF LINUX}
function OpenDevice: Boolean;
begin
  Result := False;
end;

procedure FeedDevice;
begin
end;

procedure CloseDevice;
begin
end;
{$ENDIF}

{ TODO: music outside Windows (2.05 had MCI and Winamp only). }
procedure MusicPlay(const Path: string);
begin
end;

procedure MusicStop;
begin
end;

function MusicStopped: Boolean;
begin
  Result := False;
end;

procedure MusicRewind;
begin
end;
{$ENDIF}

{ ---- the sound routine ---- }

{ The file name without a path, lower case. }
function SoundKey(const FileName: string): string;
var
  I: Integer;
begin
  Result := FileName;
  for I := Length(Result) downto 1 do
    if (Result[I] = '/') or (Result[I] = '\') then
    begin
      Delete(Result, 1, I);
      Break;
    end;
  Result := LowerCase(Result);
end;

function ReadAll(const Path: string): string;
var
  F: TFileStream;
begin
  Result := '';
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  except
    Result := '';
  end;
end;

{ The sound by name, loaded once; nil when there is no such file. }
function GetSound(const Key: string): TSoundData;
var
  I: Integer;
  Path: string;
begin
  if Cache = nil then
  begin
    Cache := TStringList.Create;
    Cache.Sorted := True;
  end;
  I := Cache.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TSoundData(Cache.Objects[I]);
    Exit;
  end;
  Result := nil;
  Path := AssetPath('sounds/' + Key);
  if Path = '' then Path := AssetPath(Key);
  if Path <> '' then
  begin
    Result := DecodeWav(ReadAll(Path));
    if Result <> nil then Result.Name := Key;
  end;
  Cache.AddObject(Key, Result);
end;

function EnsureDevice: Boolean;
begin
  if not DeviceTried then
  begin
    DeviceTried := True;
    OpenDevice;
  end;
{$IFDEF MSWINDOWS}
  Result := WaveOut <> 0;
{$ELSE}{$IFDEF LINUX}
  Result := Pcm <> nil;
{$ELSE}
  Result := False;
{$ENDIF}{$ENDIF}
end;

procedure SetListener(X, Y: Double);
begin
  ListenerX := X;
  ListenerY := Y;
end;

procedure PlaySound(const FileName: string);
begin
  PlaySoundAt(FileName, ListenerX + 1.5, ListenerY + 2);
end;

procedure PlaySoundAt(const FileName: string; X, Y: Double);
var
  Name, Key: string;
  Loop: Boolean;
  I, Pan, Vol: Integer;
  S: TSoundData;
begin
  if not SoundEnabled then Exit;
  Name := Trim(FileName);
  Loop := (Name <> '') and (Name[1] = '+');
  if Loop then Delete(Name, 1, 1);
  Key := SoundKey(Name);
  if Key = '' then Exit;
  if ExtractFileExt(Key) <> '.wav' then
  begin
    PlayMusic(Name);
    Exit;
  end;
  for I := 0 to High(KnownEffects) do
    if KnownEffects[I] = Key then
    begin
      if KnownUsed[I] then Exit;
      KnownUsed[I] := True;
      Break;
    end;
  if VoicesPlaying >= MaxVoices then Exit;
  if not EnsureDevice then Exit;
  S := GetSound(Key);
  if S = nil then Exit;
  SoundPanVolume(X, Y, ListenerX, ListenerY, Pan, Vol);
  if StartVoice(S, Pan, Vol, Loop) and Loop then
  begin
    if Looped = nil then Looped := TStringList.Create;
    if Looped.IndexOf(Key) < 0 then Looped.Add(Key);
  end;
end;

procedure StopSound(const FileName: string);
var
  Key: string;
  I: Integer;
begin
  Key := SoundKey(Trim(FileName));
  if (Key <> '') and (Key[1] = '+') then Delete(Key, 1, 1);
  for I := 0 to MaxVoices - 1 do
    if (Voices[I].Sound <> nil) and (Voices[I].Sound.Name = Key) then
      Voices[I].Sound := nil;
end;

procedure StopLoopedSounds;
var
  I: Integer;
begin
  if Looped = nil then Exit;
  for I := 0 to Looped.Count - 1 do StopSound(Looped[I]);
  Looped.Clear;
end;

procedure PlayMusic(const FileName: string);
var
  Path, Key: string;
begin
  if not SoundEnabled or not MusicEnabled then Exit;
  Key := SoundKey(FileName);
  if Key = '' then Exit;
  { 2.05 starts the track only when it is not the one playing }
  if (Key = MusicFile) and not MusicStopped then Exit;
  Path := AssetPath('levels/midis/' + Key);
  if Path = '' then Path := AssetPath('midis/' + Key);
  if Path = '' then Path := AssetPath(Key);
  if Path = '' then Exit;
  MusicFile := Key;
  MusicLoops := ExtractFileExt(Key) = '.mid';
  MusicPlay(Path);
end;

procedure StopMusic;
begin
  if MusicFile = '' then Exit;
  MusicStop;
  MusicFile := '';
end;

procedure SoundTick;
var
  I: Integer;
begin
  for I := 0 to High(KnownUsed) do KnownUsed[I] := False;
  if not SoundEnabled then Exit;
  Inc(TickCount);
  { a .mid loops for ever: checked once a second }
  if (MusicFile <> '') and MusicLoops and (TickCount mod 20 = 0) and MusicStopped then
    MusicRewind;
  if DeviceTried then FeedDevice;
end;

procedure SoundShutdown;
var
  I: Integer;
begin
  for I := 0 to MaxVoices - 1 do Voices[I].Sound := nil;
  StopMusic;
  CloseDevice;
  DeviceTried := False;
  if Cache <> nil then
  begin
    for I := 0 to Cache.Count - 1 do Cache.Objects[I].Free;
    FreeAndNil(Cache);
  end;
  FreeAndNil(Looped);
  SetLength(MixBuf, 0);
end;

initialization

finalization
  SoundShutdown;

end.
