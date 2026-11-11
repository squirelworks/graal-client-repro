{ Checks for the Worlds 548 scaffold. No token is invented. }
program TestWorlds548;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Worlds548 in '../src/Worlds548.pas';

var
  Passed, Failed: Integer;

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

begin
  Passed := 0;
  Failed := 0;
  Check(ScaffoldOnly, 'no wire client');
  Check(BuildLabel = '548', 'build label');
  Check(BundleVersion = '548', 'bundleVersion');
  Check(UnityVersion = '2021.3.8f1', 'Unity version');
  Check(PluginFileVersion = '6.114', 'plugin FileVersion 6.114');
  Check(BuildDate = '2022-12-17', 'GameAssembly date');
  Check(MainExe = 'Worlds.exe', 'main exe');
  Check(HasGameAssembly, 'IL2CPP GameAssembly');
  Check(not LinksTorque, 'Torque is not linked');
  Check(not StoresEightCharToken, 'no stored eight-character token');
  Check(TokenLiteral = '', 'token literal stays empty');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
