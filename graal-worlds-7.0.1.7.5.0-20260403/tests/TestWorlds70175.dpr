{ Checks for the Worlds 7.0.1.7.5.0 scaffold. No token is invented. }
program TestWorlds70175;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Worlds70175 in '../src/Worlds70175.pas';

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
  Check(BuildLabel = '7.0.1.7.5.0', 'build label');
  Check(BundleVersion = '701750', 'bundleVersion');
  Check(UnityVersion = '6000.0.63f1', 'Unity version');
  Check(PluginFileVersion = '', 'plugin has no version resource');
  Check(BuildDate = '2026-04-03', 'GameAssembly date');
  Check(MainExe = 'Worlds.exe', 'main exe');
  Check(HasGameAssembly, 'IL2CPP GameAssembly');
  Check(not LinksTorque, 'Torque is not linked');
  Check(not StoresEightCharToken, 'no stored eight-character token');
  Check(TokenLiteral = '', 'token literal stays empty');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
