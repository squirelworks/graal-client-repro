{ Run3D: what a scripted or headless run needs and the original did not
  have: a microsecond clock, a stop request from SIGTERM / SIGINT
  (Ctrl+C on Windows), a key script, and JSON text. }
unit Run3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

function MonoUs: Int64;
procedure InstallStopHandlers;
function StopRequested: Boolean;
function JsonStr(const S: string): string;
function JsonNum(V: Double): string;

type
  { A key script: "fwd*20,wait*5,jump,left*3,say:hello,cam". Each step
    lasts one tick, or N with *N. }
  TStep3D = record
    Fwd, Back, Left, Right, Jump, Cam: Boolean;
    Say: string;
  end;

  TKeyScript = class
  private
    FSteps: array of TStep3D;
  public
    { False on a word it does not know. }
    function Parse(const S: string): Boolean;
    function Count: Integer;
    { The step for tick T (0-based); an empty step past the end. }
    function At(T: Integer): TStep3D;
  end;

implementation

uses
  SysUtils
{$IFDEF FPC}
  {$IFDEF UNIX}, BaseUnix, Unix {$ENDIF}
{$ENDIF}
{$IFDEF MSWINDOWS}, Windows {$ENDIF};

var
  Stop: Boolean = False;
{$IFDEF MSWINDOWS}
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
  Result := True;
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

function JsonStr(const S: string): string;
var
  I: Integer;
begin
  Result := '"';
  for I := 1 to Length(S) do
    case S[I] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #0..#31, #127..#255: Result := Result + '\u' + IntToHex(Ord(S[I]), 4);
    else
      Result := Result + S[I];
    end;
  Result := Result + '"';
end;

function JsonNum(V: Double): string;
begin
  Str(V:0:2, Result);
end;

{ TKeyScript }

procedure ClearStep(out St: TStep3D);
begin
  St.Fwd := False;
  St.Back := False;
  St.Left := False;
  St.Right := False;
  St.Jump := False;
  St.Cam := False;
  St.Say := '';
end;

function TKeyScript.Parse(const S: string): Boolean;
var
  Rest, Word, Name: string;
  P, N, I: Integer;
  St: TStep3D;
begin
  Result := True;
  SetLength(FSteps, 0);
  Rest := S;
  while Rest <> '' do
  begin
    P := Pos(',', Rest);
    if P = 0 then P := Length(Rest) + 1;
    Word := Trim(Copy(Rest, 1, P - 1));
    Delete(Rest, 1, P);
    if Word = '' then Continue;
    ClearStep(St);
    N := 1;
    if LowerCase(Copy(Word, 1, 4)) = 'say:' then
      St.Say := Copy(Word, 5, MaxInt)
    else
    begin
      P := Pos('*', Word);
      if P > 0 then
      begin
        N := StrToIntDef(Copy(Word, P + 1, MaxInt), -1);
        Name := LowerCase(Copy(Word, 1, P - 1));
      end
      else
        Name := LowerCase(Word);
      if (N < 0) or (N > 100000) then begin Result := False; Exit; end;
      P := 1;
      { several keys at once: "fwd+left" }
      while Name <> '' do
      begin
        P := Pos('+', Name);
        if P = 0 then P := Length(Name) + 1;
        Word := Copy(Name, 1, P - 1);
        Delete(Name, 1, P);
        if Word = 'fwd' then St.Fwd := True
        else if Word = 'back' then St.Back := True
        else if Word = 'left' then St.Left := True
        else if Word = 'right' then St.Right := True
        else if Word = 'jump' then St.Jump := True
        else if Word = 'cam' then St.Cam := True
        else if Word <> 'wait' then begin Result := False; Exit; end;
      end;
    end;
    for I := 1 to N do
    begin
      SetLength(FSteps, Length(FSteps) + 1);
      FSteps[High(FSteps)] := St;
    end;
  end;
end;

function TKeyScript.Count: Integer;
begin
  Result := Length(FSteps);
end;

function TKeyScript.At(T: Integer): TStep3D;
begin
  if (T >= 0) and (T < Length(FSteps)) then Result := FSteps[T]
  else
    ClearStep(Result);
end;

end.
