{ Checks for the Worlds 613 scaffold. No token is invented. }
program TestWorlds613;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Worlds613 in '../src/Worlds613.pas';

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
  Check(BuildLabel = '613', 'build label');
  Check(BundleVersion = '613', 'bundleVersion');
  Check(UnityVersion = '2023.2.13f1', 'Unity version');
  Check(PluginFileVersion = '6.114', 'plugin FileVersion 6.114');
  Check(BuildDate = '2024-04-15', 'GameAssembly date');
  Check(MainExe = 'Worlds.exe', 'main exe');
  Check(HasGameAssembly, 'IL2CPP GameAssembly');
  Check(not LinksTorque, 'Torque is not linked');
  Check(not StoresEightCharToken, 'no stored eight-character token');
  Check(TokenLiteral = '', 'token literal stays empty');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
