program TestQuattroSecure;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses
  SysUtils, Classes{$IFDEF LINUX}, Process{$ENDIF},
  GSecLogin in '../../common/GSecLogin.pas',
  GQuattroPlay in '../../common/GQuattroPlay.pas';

{$IFDEF LINUX}
procedure Check(OK: Boolean; const What: string);
begin
  if not OK then raise Exception.Create(What);
  WriteLn('ok ', What);
end;

procedure TestRouting;
var
  Dir, Exe, Mode: string;
  I, RouteCount: Integer;
  F: TStringList;

  procedure Route(const EnvMode, ExplicitMode: string; Online, WantQuattro: Boolean;
    const What: string; Display: Boolean = True; PascalGame: Boolean = False);
  var
    P: TProcess;
    J: Integer;
    E, HeapLog: string;
    Heap: TStringList;
  begin
    Inc(RouteCount);
    HeapLog := Dir + 'route-' + IntToStr(RouteCount) + '.heap';
    P := TProcess.Create(nil);
    Heap := TStringList.Create;
    try
      { A fresh process tests the actual startup environment, as when the
        player launches the GUI. It only selects a program, never runs it. }
      P.Executable := ExpandFileName(ParamStr(0));
      P.Parameters.Add('--route');
      P.Parameters.Add(Dir);
      { TProcess may omit empty arguments. Keep every child slot explicit. }
      if ExplicitMode = '' then P.Parameters.Add('configured')
      else P.Parameters.Add(ExplicitMode);
      P.Parameters.Add(BoolToStr(Online, True));
      P.Parameters.Add(BoolToStr(WantQuattro, True));
      for J := 1 to GetEnvironmentVariableCount do
      begin
        E := GetEnvironmentString(J);
        if (Pos('DISPLAY=', E) <> 1) and (Pos('GRAAL_PASCAL_GAME=', E) <> 1) and
          (Pos('GRAAL_SECURE_LOGIN=', E) <> 1) and (Pos('HEAPTRC=', E) <> 1) then
          P.Environment.Add(E);
      end;
      { Each child owns its tracer log; the parent's report stays intact. }
      P.Environment.Add('HEAPTRC=log=' + HeapLog);
      if Display then P.Environment.Add('DISPLAY=:123');
      if PascalGame then P.Environment.Add('GRAAL_PASCAL_GAME=1');
      if EnvMode <> '' then P.Environment.Add('GRAAL_SECURE_LOGIN=' + EnvMode);
      P.Options := [poWaitOnExit];
      P.Execute;
      Check(P.ExitStatus = 0, What);
      Check(FileExists(HeapLog), What + ': child heap report exists');
      Heap.LoadFromFile(HeapLog);
      Check(Heap.IndexOf('0 unfreed memory blocks : 0') >= 0, What + ': child has no unfreed blocks');
    finally
      Heap.Free;
      P.Free;
      DeleteFile(HeapLog);
    end;
  end;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'quattro-secure-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  Dir := IncludeTrailingPathDelimiter(Dir);
  Exe := Dir + 'quattro-play';
  F := TStringList.Create;
  RouteCount := 0;
  try
    { A fake installed player plus DISPLAY makes the insecure route
      available. No X server or executable game is needed. }
    F.SaveToFile(Exe);
    Route('', '', True, True, 'default off selects Quattro online');
    for I := 0 to 1 do
    begin
      if I = 0 then Mode := 'auto' else Mode := 'required';
      Route(Mode, '', True, False, Mode + ' environment keeps online login in Pascal');
      Route(Mode, '', False, True, Mode + ' environment allows offline Training');
      F.Clear;
      F.Add(Mode);
      F.SaveToFile(Dir + 'secure_login.txt');
      Route('', '', True, False, Mode + ' settings keep online login in Pascal');
      Route('', '', False, True, Mode + ' settings allow offline Training');
      DeleteFile(Dir + 'secure_login.txt');
    end;
    Route('off', 'required', True, False, 'explicit required and server key override environment off');
    Route('required', 'off', True, True, 'explicit off preserves original-login route');
    Route('', '', False, False, 'Pascal override keeps Training in Pascal', True, True);
    Route('', '', True, False, 'headless game stays in Pascal', False);
  finally
    F.Free;
    DeleteFile(Dir + 'secure_login.txt');
    DeleteFile(Exe);
    RemoveDir(Dir);
  end;
end;

procedure ChildRoute;
var
  Mode: TSecMode;
  GotQuattro, Online, WantQuattro: Boolean;
begin
  if (ParamCount <> 5) or not TryStrToBool(ParamStr(4), Online) or
    not TryStrToBool(ParamStr(5), WantQuattro) then
  begin
    WriteLn(ErrOutput, 'invalid route test arguments');
    Halt(2);
  end;
  PinDirOverride := ParamStr(2);
  if ParamStr(3) <> 'configured' then
  begin
    if not ParseSecMode(ParamStr(3), Mode) then Halt(2);
    SetSecure(Mode, 'given-key');
  end;
  GotQuattro := QuattroProgram(ParamStr(2), Online) <> '';
  if GotQuattro <> WantQuattro then Halt(1);
end;
{$ENDIF}

begin
{$IFDEF LINUX}
  if ParamStr(1) = '--route' then ChildRoute else TestRouting;
{$ELSE}
  if QuattroProgram('.', True) <> '' then Halt(1);
  WriteLn('ok non-Linux games stay in Pascal');
{$ENDIF}
end.
