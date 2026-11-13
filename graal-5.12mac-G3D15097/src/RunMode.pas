{ RunMode: what a stress run needs around the game loop, and nothing the
  original client had: a clock in microseconds, a stop request from
  SIGTERM / SIGINT (Ctrl+Break / Ctrl+C on Windows), the peak resident set,
  a histogram of tick times, a seeded walker, and JSON output. }
unit RunMode;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils, GLevel;

{ Microseconds from an arbitrary start, monotonic where the OS allows. }
function MonoUs: Int64;

{ Installs the handlers; StopRequested turns True when one fires. }
procedure InstallStopHandlers;
function StopRequested: Boolean;

{ Peak resident set in KiB, or -1 where it is not known. }
function PeakRssKiB: Int64;

type
  { Tick times in 10 us buckets up to 100 ms; longer ticks count in the
    last bucket and in Max. }
  TTickHistogram = class
  private
    FBuckets: array of Integer;
    FCount: Int64;
    FMaxUs: Int64;
  public
    constructor Create;
    procedure Add(Us: Int64);
    { The q-th quantile (0..1) in ms. }
    function QuantileMs(Q: Double): Double;
    function MaxMs: Double;
    property Count: Int64 read FCount;
  end;

  TWalkMode = (wmScript, wmIdle, wmRandom);

  { The stress-run walker: a new random direction every WalkTicks ticks,
    and every LinkEveryTicks it heads for the nearest link of the level
    until it has gone through or GiveUpTicks pass. }
  TWalker = class
  private
    FSeed: Cardinal;
    FDir: Integer;
    FSeekUntil: Integer;
    FSeekLevel: string;
    function Next(N: Integer): Integer;
  public
    Mode: TWalkMode;
    WalkTicks: Integer;
    LinkEveryTicks: Integer; { 0 = never }
    GiveUpTicks: Integer;
    constructor Create(Seed: Cardinal);
    { The direction to hold this tick, or -1. }
    function DirAt(Tick: Integer; Level: TAdventureLevel; PX, PY: Double): Integer;
  end;

{ A JSON string literal with the needed escapes. }
function JsonStr(const S: string): string;
{ A number with a dot and three decimals, whatever the locale. }
function JsonMs(V: Double): string;

implementation

uses
{$IFDEF FPC}
  {$IFDEF UNIX} BaseUnix, Unix, {$ENDIF}
{$ENDIF}
{$IFDEF MSWINDOWS} Windows, {$ENDIF}
  Classes;

var
  Stop: Boolean = False;

{$IFDEF MSWINDOWS}
var
  PerfFreq: Int64 = 0;
{$ENDIF}

function MonoUs: Int64;
{$IFDEF MSWINDOWS}
var
  C: Int64;
begin
  if PerfFreq = 0 then QueryPerformanceFrequency(PerfFreq);
  QueryPerformanceCounter(C);
  Result := Trunc(C / PerfFreq * 1000000.0);
end;
{$ELSE}
{$IFDEF FPC}
var
  TV: TTimeVal;
begin
  fpGetTimeOfDay(@TV, nil);
  Result := Int64(TV.tv_sec) * 1000000 + TV.tv_usec;
end;
{$ELSE}
begin
  Result := Trunc(Now * 86400000000.0);
end;
{$ENDIF}
{$ENDIF}

{$IFDEF MSWINDOWS}
function CtrlHandler(CtrlType: DWORD): BOOL; stdcall;
begin
  Stop := True;
  Result := True; { handled: the main loop logs out and exits }
end;
{$ENDIF}

{$IFDEF FPC}{$IFDEF UNIX}
procedure SigHandler(Sig: cint); cdecl;
begin
  Stop := True;
end;
{$ENDIF}{$ENDIF}

procedure InstallStopHandlers;
begin
{$IFDEF MSWINDOWS}
  SetConsoleCtrlHandler(@CtrlHandler, True);
{$ENDIF}
{$IFDEF FPC}{$IFDEF UNIX}
  fpSignal(SIGTERM, SignalHandler(@SigHandler));
  fpSignal(SIGINT, SignalHandler(@SigHandler));
{$ENDIF}{$ENDIF}
end;

function StopRequested: Boolean;
begin
  Result := Stop;
end;

function PeakRssKiB: Int64;
{$IFDEF LINUX}
var
  F: TextFile;
  Line: string;
  I: Integer;
begin
  Result := -1;
  if not FileExists('/proc/self/status') then Exit;
  AssignFile(F, '/proc/self/status');
  {$I-} Reset(F); {$I+}
  if IOResult <> 0 then Exit;
  try
    while not Eof(F) do
    begin
      ReadLn(F, Line);
      if Copy(Line, 1, 6) = 'VmHWM:' then
      begin
        Delete(Line, 1, 6);
        I := Pos('kB', Line);
        if I > 0 then Line := Copy(Line, 1, I - 1);
        Result := StrToInt64Def(Trim(Line), -1);
        Exit;
      end;
    end;
  finally
    CloseFile(F);
  end;
end;
{$ELSE}
begin
  Result := -1;
end;
{$ENDIF}

{ TTickHistogram }

const
  BucketUs = 10;
  BucketCount = 10000; { 100 ms }

constructor TTickHistogram.Create;
begin
  inherited Create;
  SetLength(FBuckets, BucketCount);
end;

procedure TTickHistogram.Add(Us: Int64);
var
  B: Int64;
begin
  if Us < 0 then Us := 0;
  B := Us div BucketUs;
  if B >= BucketCount then B := BucketCount - 1;
  Inc(FBuckets[B]);
  Inc(FCount);
  if Us > FMaxUs then FMaxUs := Us;
end;

function TTickHistogram.QuantileMs(Q: Double): Double;
var
  Want, Seen: Int64;
  I: Integer;
begin
  Result := 0;
  if FCount = 0 then Exit;
  Want := Trunc(Q * FCount);
  if Want >= FCount then Want := FCount - 1;
  Seen := 0;
  for I := 0 to BucketCount - 1 do
  begin
    Inc(Seen, FBuckets[I]);
    if Seen > Want then
    begin
      { the bucket's upper edge, but never above the largest tick seen }
      Result := ((I + 1) * BucketUs) / 1000.0;
      if Result > MaxMs then Result := MaxMs;
      Exit;
    end;
  end;
  Result := MaxMs;
end;

function TTickHistogram.MaxMs: Double;
begin
  Result := FMaxUs / 1000.0;
end;

{ TWalker }

constructor TWalker.Create(Seed: Cardinal);
begin
  inherited Create;
  FSeed := Seed;
  FDir := -1;
  FSeekUntil := -1;
  WalkTicks := 2;
  GiveUpTicks := 200;
end;

{ A small LCG of its own, so the walk does not move the RTL's Random
  (which picks the gen-3 key). }
{$IFOPT Q+}{$DEFINE WQ}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE WR}{$R-}{$ENDIF}
function TWalker.Next(N: Integer): Integer;
begin
  FSeed := FSeed * 1103515245 + 12345;
  Result := Integer((FSeed shr 16) mod Cardinal(N));
end;
{$IFDEF WR}{$R+}{$ENDIF}
{$IFDEF WQ}{$Q+}{$ENDIF}

function TWalker.DirAt(Tick: Integer; Level: TAdventureLevel; PX, PY: Double): Integer;
var
  I, Best: Integer;
  CX, CY, D, BestD, DX, DY: Double;
begin
  Result := -1;
  if Mode = wmIdle then Exit;
  { the body's centre, as the link test uses }
  CX := PX + 1.5;
  CY := PY + 2;
  if (FSeekUntil >= 0) and ((Tick > FSeekUntil) or (Level.Name <> FSeekLevel)) then
    FSeekUntil := -1; { gone through, or given up }
  if (FSeekUntil < 0) and (LinkEveryTicks > 0) and (Tick > 0) and
    (Tick mod LinkEveryTicks = 0) and (Length(Level.Links) > 0) then
  begin
    FSeekUntil := Tick + GiveUpTicks;
    FSeekLevel := Level.Name;
  end;
  if FSeekUntil >= 0 then
  begin
    Best := -1;
    BestD := 0;
    for I := 0 to High(Level.Links) do
    begin
      DX := Level.Links[I].X + Level.Links[I].W / 2 - CX;
      DY := Level.Links[I].Y + Level.Links[I].H / 2 - CY;
      D := Abs(DX) + Abs(DY);
      if (Best < 0) or (D < BestD) then
      begin
        Best := I;
        BestD := D;
      end;
    end;
    if Best >= 0 then
    begin
      DX := Level.Links[Best].X + Level.Links[Best].W / 2 - CX;
      DY := Level.Links[Best].Y + Level.Links[Best].H / 2 - CY;
      if Abs(DX) >= Abs(DY) then
      begin
        if DX < 0 then Result := 1 else Result := 3; { left / right }
      end
      else if DY < 0 then Result := 0 else Result := 2; { up / down }
      Exit;
    end;
  end;
  if (WalkTicks <= 1) or (Tick mod WalkTicks = 0) or (FDir < 0) then
    FDir := Next(4);
  Result := FDir;
end;

function JsonStr(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #0..#31, #127..#255: Result := Result + '\u00' + IntToHex(Ord(C), 2);
    else
      Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

function JsonMs(V: Double): string;
var
  W: Int64;
  F: Integer;
begin
  if V < 0 then V := 0;
  W := Trunc(V);
  F := Round((V - W) * 1000);
  if F >= 1000 then
  begin
    Inc(W);
    Dec(F, 1000);
  end;
  Result := IntToStr(W) + '.' + Format('%.3d', [F]);
end;

end.
