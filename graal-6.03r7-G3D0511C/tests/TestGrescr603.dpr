{ Checks the 6.037 GRESCR01 accept path and the want-script stubs.
  The Linux token is not changed. No numeric packet id is invented. }
program TestGrescr603;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Protocol603 in '../src/Protocol603.pas',
  Grescr603 in '../src/Grescr603.pas',
  Controls603 in '../src/Controls603.pas';

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

procedure TestToken;
begin
  Check(ClientVersionToken = 'G3D0511C', 'Linux folder keeps G3D0511C');
  Check(not LinksTorque, 'quattro_lib, not a Torque link');
end;

procedure TestGrescr;
begin
  Check(not GrescrAccepted(''), 'empty file rejected');
  Check(not GrescrAccepted('GRESCR0'), 'seven bytes rejected');
  Check(not GrescrAccepted('GRESCR00'), 'wrong magic rejected');
  Check(GrescrLog = '', 'a wrong magic does not log a payload');
  Check(GrescrAccepted(GrescrMagic), 'eight-byte magic accepted');
  Check(GrescrPayloadLen = 0, 'magic alone has an empty payload');
  Check(GrescrAccepted(GrescrMagic + 'tail'), 'magic plus a body accepted');
  WriteLn(GrescrLog);
  Check(GrescrPayloadLen = 4, 'payload length is the bytes after the magic');
  Check(GrescrLog = 'GRESCR01 payload 4', 'accept path logs the payload length');
  Check(not GrescrAccepted('short'), 'a short buffer is still rejected');
  Check(GrescrPayloadLen = -1, 'a reject clears the payload length');
  Check(GrescrLog = '', 'a reject does not log a payload');
  Check(GrescrCrcStart = 9, 'CRC covers the bytes after the magic');
  Check(Copy(GrescrMagic + 'tail', GrescrCrcStart, MaxInt) = 'tail',
    'covered bytes are the tail');
end;

procedure TestSend;
var
  Line: string;
begin
  Line := SendWantClassScript('abc');
  WriteLn(Line);
  Check(Line = 'onSendWantClassScript id=provisional len=3',
    'class-script send writes the name and the length');
  Check(SendWantWeaponScript('') = 'onSendWantWeaponScript id=provisional len=0',
    'weapon-script send allows an empty payload');
  Check(SendWantGaniScript('gani') = 'onSendWantGaniScript id=provisional len=4',
    'gani-script send writes the name and the length');
  Check(Pos('id=23', SendWantClassScript('abc')) = 0,
    'the outgoing table id is not invented');
end;

procedure TestControls;
var
  I: Integer;
  SawLevel, SawTiles, SawDrawable, SawAbsent: Boolean;
  Log: string;
begin
  Check(ControlCount = 71, 'seventy-one 6.037 controls');
  SawLevel := False;
  SawTiles := False;
  SawDrawable := False;
  SawAbsent := False;
  for I := 0 to ControlCount - 1 do
  begin
    if ControlName(I) = 'GuiGraalCtrl' then SawLevel := True;
    if ControlName(I) = 'GuiTilesCtrl' then SawTiles := True;
    if ControlName(I) = 'TDrawableObject' then SawDrawable := True;
    if (ControlName(I) = 'GuiBrowserCtrl') or (ControlName(I) = 'GuiTSCtrl') or
      (ControlName(I) = 'TFontData') then
      SawAbsent := True;
  end;
  Check(SawLevel, 'GuiGraalCtrl is registered');
  Check(SawTiles, 'GuiTilesCtrl is registered');
  Check(SawDrawable, 'TDrawableObject stays on 6.037');
  Check(not SawAbsent, 'browser, Torque scene view and TFontData are absent');
  Check(not LinksTorque, 'controls stay off Torque');
  Log := LevelViewLog;
  Check(Pos('level view opened: GraalControl (GuiGraalCtrl)', Log) > 0,
    'the level view opens');
  Check(Pos('script-bound action attack', Log) > 0, 'attack stays script-bound');
end;

begin
  Passed := 0;
  Failed := 0;
  TestToken;
  TestControls;
  TestGrescr;
  TestSend;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
