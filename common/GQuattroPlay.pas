unit GQuattroPlay;

{ Hands a game from a 6.x start screen to the Quattro program.

  The real 6.01r1 and 6.03r7 clients are one native C++ program
  (quattro_lib; Graal_analysis client-internals/engine-600r2.md). The
  rebuild of that program is common/cpp/quattro, and scripts/build.sh
  puts its player (quattro-play) beside these folders' start screens.
  The start screen still picks the server (or Training); the game then
  runs in quattro-play: GS2 weapons, bombs and arrows, being hurt, the
  item list. On Linux it needs an X display; on Windows a Win32 window;
  on macOS an AppKit window.
  Without the program, with GRAAL_PASCAL_GAME=1, or (Linux) with no
  DISPLAY, the start screen plays in its own Pascal game as before.

  The Seihai secure login (GSecLogin; not in any original client) goes
  with the game: quattro-play speaks SEI00001 itself, with the same pins
  and refused-server list, and is told the mode and any given server key
  on its command line. }

interface

type
  TQuattroArgs = array of string;

{ The quattro-play beside the program in Dir, when the game should go to
  it; '' otherwise. Online is accepted in every secure-login mode, since
  quattro-play implements SEI00001; it stays as a parameter for callers. }
function QuattroProgram(const Dir: string; Online: Boolean = False): string;

{ Runs it and waits. Build is the profile label ('6.03r7', '6.03r7 Windows');
  Args are the game's arguments; a Password is handed over in the environment
  (GRAAL_QUATTRO_PW), never on the command line. Returns the exit code,
  or -1 when it could not be started. }
function RunQuattro(const Exe, Build: string; const Args: array of string;
  const Password: string): Integer;

{ The arguments for one game. Online: Host:Port, Account, ServerName and
  Nickname; offline (Level <> ''): the level and its start. Roots are the
  install folders searched after Dir. }
function QuattroArgs(const Dir: string; const Roots: array of string; const Level, X, Y,
  HostPort, Account, ServerName, Nickname: string): TQuattroArgs;

implementation

uses
  SysUtils, GSecLogin{$IF DEFINED(LINUX) OR DEFINED(MSWINDOWS) OR DEFINED(DARWIN)}, Classes, Process{$ENDIF};

const
  PasswordVar = 'GRAAL_QUATTRO_PW';

function QuattroProgram(const Dir: string; Online: Boolean): string;
var
  Base, Candidate: string;
begin
  Result := '';
{$IF DEFINED(LINUX) OR DEFINED(MSWINDOWS) OR DEFINED(DARWIN)}
  if GetEnvironmentVariable('GRAAL_PASCAL_GAME') = '1' then Exit;
{$IFDEF LINUX}
  if GetEnvironmentVariable('DISPLAY') = '' then Exit;
{$ENDIF}
  Base := IncludeTrailingPathDelimiter(Dir);
{$IFDEF MSWINDOWS}
  Candidate := Base + 'quattro-play.exe';
  if FileExists(Candidate) then
  begin
    Result := Candidate;
    Exit;
  end;
{$ENDIF}
  Candidate := Base + 'quattro-play';
  if FileExists(Candidate) then Result := Candidate;
{$ENDIF}
end;

function QuattroArgs(const Dir: string; const Roots: array of string; const Level, X, Y,
  HostPort, Account, ServerName, Nickname: string): TQuattroArgs;
var
  N: Integer;

  procedure Add(const S: string);
  begin
    if N >= Length(Result) then SetLength(Result, N + 8);
    Result[N] := S;
    Inc(N);
  end;

var
  I: Integer;
begin
  N := 0;
  SetLength(Result, 0);
  if Level <> '' then
  begin
    Add('--offline'); Add(Level);
    Add('--x'); Add(X);
    Add('--y'); Add(Y);
  end
  else
  begin
    Add('--connect'); Add(HostPort);
    Add('--account'); Add(Account);
    Add('--password-env'); Add(PasswordVar);
    Add('--server-name'); Add(ServerName);
    { the player's secure-login setting, or the start screen's
      --secure-login / --server-key, as GSecLogin resolved it }
    Add('--secure-login'); Add(SecModeName(ConfiguredSecMode));
    if ConfiguredServerKey <> '' then
    begin
      Add('--server-key'); Add(ConfiguredServerKey);
    end;
    if Nickname <> '' then
    begin
      Add('--nickname'); Add(Nickname);
    end;
    Add('--download-files');
  end;
  Add('--assets'); Add(ExcludeTrailingPathDelimiter(Dir));
  for I := 0 to High(Roots) do
    if (Roots[I] <> '') and (ExcludeTrailingPathDelimiter(Roots[I]) <> ExcludeTrailingPathDelimiter(Dir)) then
    begin
      Add('--asset-root'); Add(ExcludeTrailingPathDelimiter(Roots[I]));
    end;
  SetLength(Result, N);
end;

function RunQuattro(const Exe, Build: string; const Args: array of string;
  const Password: string): Integer;
{$IF DEFINED(LINUX) OR DEFINED(MSWINDOWS) OR DEFINED(DARWIN)}
var
  P: TProcess;
  I: Integer;
{$ENDIF}
begin
  Result := -1;
{$IF DEFINED(LINUX) OR DEFINED(MSWINDOWS) OR DEFINED(DARWIN)}
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Parameters.Add('--build');
    P.Parameters.Add(Build);
    for I := 0 to High(Args) do P.Parameters.Add(Args[I]);
    { the program's own environment, plus the password for this game only }
    for I := 1 to GetEnvironmentVariableCount do
      if Pos(PasswordVar + '=', GetEnvironmentString(I)) <> 1 then
        P.Environment.Add(GetEnvironmentString(I));
    P.Environment.Add(PasswordVar + '=' + Password);
    P.Options := [poWaitOnExit];
    try
      P.Execute;
      Result := P.ExitStatus;
    except
      Result := -1;
    end;
  finally
    P.Free;
  end;
{$ENDIF}
end;

end.
