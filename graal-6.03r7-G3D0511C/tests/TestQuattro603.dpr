{ Checks for the 6.037 scaffold in Quattro603. The Linux token is not
  changed. Opcode bodies and unlisted case numbers stay unknown. }
program TestQuattro603;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Protocol603 in '../src/Protocol603.pas',
  Quattro603 in '../src/Quattro603.pas',
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
  Check(UpperCase(WindowsStoredToken) = 'G3D0311C', 'Windows stored string upper-cases');
  Check(UpperCase(WindowsStoredToken) <> ClientVersionToken,
    'Windows string is not this folder''s token');
  Check(UsesGeneration5, '6.037 stays on the generation-5 framer');
  Check(not HasSetProtocol, 'no setprotocol');
  Check(not HasSendRaw, 'no sendraw');
  Check(not HasSendData, 'no senddata');
  Check(not HasTclientPropertyScripts, 'no tclient property-script names');
  Check(not LinksTorque, 'quattro_lib, not a Torque link');
end;

procedure TestGrescr;
begin
  Check(not GrescrAccepted(''), 'empty file rejected');
  Check(not GrescrAccepted('GRESCR0'), 'seven bytes rejected');
  Check(not GrescrAccepted('GRESCR00'), 'wrong magic rejected');
  Check(GrescrAccepted(GrescrMagic), 'eight-byte magic accepted');
  Check(GrescrAccepted(GrescrMagic + 'tail'), 'magic plus a body accepted');
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
begin
  Check(SendWantClassScript('abc') = 'onSendWantClassScript id=provisional len=3',
    'class-script send writes the name and the length');
  Check(SendWantWeaponScript('') = 'onSendWantWeaponScript id=provisional len=0',
    'weapon-script send allows an empty payload');
  Check(SendWantGaniScript('gani') = 'onSendWantGaniScript id=provisional len=4',
    'gani-script send writes the name and the length');
  Check(Pos('id=23', SendWantClassScript('abc')) = 0,
    'the outgoing table id is not invented');
end;

procedure TestCases;
var
  Op, Present, Unlisted: Integer;
begin
  Check(Gs2CaseTotal = 152, 'the note''s case count is 152');
  Check(Gs2CaseOf(10) = gscOutside, '10 is outside the span');
  Check(Gs2CaseOf(243) = gscOutside, '243 is outside the span');
  Check(Gs2CaseOf(48) = gscAbsent, '48 is absent');
  Check(Gs2CaseOf(49) = gscAbsent, '49 is absent');
  Check(Gs2CaseOf(200) = gscAbsent, '200 is absent');
  Check(Gs2CaseOf(54) = gscPresent, '54 is present');
  Check(Gs2CaseOf(121) = gscPresent, '121 is present');
  Check(Gs2CaseOf(201) = gscPresent, '201 is present');
  Check(Gs2CaseOf(242) = gscPresent, '242 is present');
  Check(Gs2CaseOf(12) = gscUnlisted, 'an unnamed number is not invented');
  Present := 0;
  Unlisted := 0;
  for Op := Gs2SpanLow to Gs2SpanHigh do
    case Gs2CaseOf(Op) of
      gscPresent: Inc(Present);
      gscUnlisted: Inc(Unlisted);
      gscAbsent, gscOutside: ;
    end;
  Check(Present = 44, 'only the named cases are marked present');
  Check(Present < Gs2CaseTotal, 'the full 152 are not filled in');
  Check(Unlisted > 0, 'unnamed numbers stay unlisted');
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
  TestCases;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
