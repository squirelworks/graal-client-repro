{ Dialogs231: 2.31's own small windows over the start window.

  "Open URL" (TOpenURL): asked before Get an account! (and the server
  list's Go button) open a web page: "Do you want to load the URL <url>
  with the default browser?", Open (with the form's own folder picture,
  compiled in from res/OPENGLYPH.bmp) and Cancel. 401 x 115, only a close
  button. The words are the program's own (2.31 does not take them from
  the language file).

  "More options" (TMoreOptions), behind the start window's Options
  button.

  Its own 434 x 354 window with only a close button, over the start
  window. The places are the form's own (TMOREOPTIONS in Graal_231.exe),
  checked against the real 2.31 under Wine (2026-11-05); the words come
  from the language file's MoreOptions- lines, as 2.31 reads them, falling
  back to the form's captions. Five pages: Video, Audio, Microphone,
  Controls and General.

  The settings live in graalconfig.txt in the Graal folder, under 2.31's
  own names (waitvertical, automapping, fullscreenmode, font, fontsize,
  midivolume ... dontconnectlevels). Close writes the file back with every
  line it did not change kept as it was, so 2.31 and the rebuild can share
  one folder. }
unit Dialogs231;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GWindow;

type
  { graalconfig.txt: name=value lines, kept in their order }
  TGraalConfig = class
  public
    Lines: TStringList;
    FileName: string;
    constructor Create;
    destructor Destroy; override;
    { 2.31's defaults, then the file's lines over them }
    procedure Load(const AFileName: string);
    function Save: Boolean;
    function Str(const Name: string): string;
    function Bool(const Name: string): Boolean;
    function Int(const Name: string; Default: Integer): Integer;
    procedure SetStr(const Name, Value: string);
    procedure SetBool(const Name: string; Value: Boolean);
  end;

  { Text(Key, Default): the language file's words for Key }
  TLangText = function(const Key, Default: string): string of object;

{ Shows the More options window until Close, Esc or its close button,
  then saves Config. }
procedure RunMoreOptions(Config: TGraalConfig; Lang: TLangText);

{ Asks before opening Url; True when the player chose Open (the page is
  then opened in the default browser, on Windows). }
function RunOpenUrl(const Url: string; Lang: TLangText): Boolean;

{ Esc in the game: "Do you really want to quit Graal?", OK and Cancel
  (Windows' own question box, titled Warning, as 2.31 shows it). True:
  OK. }
function AskQuit: Boolean;

{ An error, as 2.31 shows one (Windows' own box titled Error, with the
  warning sign and OK), e.g. "GraalEditor.exe has not been found in the
  Graal folder!" }
procedure ShowError(const Msg: string);

{ Opens Url in the default browser (Windows); False elsewhere. }
function OpenInBrowser(const Url: string): Boolean;

const
  OptW = 434;
  OptH = 354;
  { the Video page's lists }
  FullscreenModes: array[0..4] of string =
    ('640x480', '800x600', '1024x768', '1152x864', '1280x1024');
  ChatFonts: array[0..5] of string =
    ('Arial', 'Comic Sans MS', 'Courier New', 'Tempus Sans ITC',
     'Times New Roman', 'Verdana');

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, GUiFont, GSysUiFont, Res231;

{ ---- graalconfig.txt ---- }

const
  { what a fresh 2.31 writes (under Wine, 2026-11-05), in its order }
  Defaults: array[0..38] of string = (
    'waitvertical=false', 'microon=false', 'reversestereo=false',
    'saveimages=true', 'cachefilenames=true', 'dontsavepms=false',
    'compabilitydraw=false', 'nodecompressionerror=false',
    'joystickon=false', 'nodirectinput=false', 'language=English',
    'font=Tempus Sans ITC', 'fontsize=24', 'fixedport=false',
    'fixedudpport=14899', 'noudp=true', 'nomassmessages=false',
    'nohtmlinpms=false', 'limitnicknames=false', 'nicknamelimit=50',
    'dontconnectlevels=false', 'notoalls=false', 'nohtmlimages=true',
    'sortplayersbyname=false', 'dontloadlistheads=false',
    'dontsavepasswords=false', 'dontusedirectx7=false',
    'fullscreenmode=1024x768', 'startinfullscreen=false',
    'automapping=true', 'midivolume=0', 'mp3volume=100', 'radiovolume=20',
    'voicevolume=100', 'sfxvolume=0', 'microactivationlevel=50',
    'microactivatebyvolume=true', 'microactivatekey=T',
    'voicecodec=-1');

constructor TGraalConfig.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TGraalConfig.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

procedure TGraalConfig.Load(const AFileName: string);
var
  I: Integer;
begin
  FileName := AFileName;
  Lines.Clear;
  if (FileName <> '') and FileExists(FileName) then
    try
      Lines.LoadFromFile(FileName);
    except
      Lines.Clear;
    end;
  { the file's own lines in their order; 2.31's defaults for any it lacks }
  for I := 0 to High(Defaults) do
    if Lines.IndexOfName(Copy(Defaults[I], 1, Pos('=', Defaults[I]) - 1)) < 0 then
      Lines.Add(Defaults[I]);
end;

function TGraalConfig.Save: Boolean;
begin
  Result := False;
  if FileName = '' then Exit;
  try
    Lines.SaveToFile(FileName);
    Result := True;
  except
    Result := False;
  end;
end;

function TGraalConfig.Str(const Name: string): string;
var
  I: Integer;
begin
  I := Lines.IndexOfName(Name);
  if I >= 0 then Result := Lines.ValueFromIndex[I] else Result := '';
end;

function TGraalConfig.Bool(const Name: string): Boolean;
begin
  Result := LowerCase(Trim(Str(Name))) = 'true';
end;

function TGraalConfig.Int(const Name: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(Trim(Str(Name)), Default);
end;

procedure TGraalConfig.SetStr(const Name, Value: string);
var
  I: Integer;
begin
  I := Lines.IndexOfName(Name);
  if I >= 0 then Lines[I] := Name + '=' + Value
  else Lines.Add(Name + '=' + Value);
end;

procedure TGraalConfig.SetBool(const Name: string; Value: Boolean);
begin
  if Value then SetStr(Name, 'true') else SetStr(Name, 'false');
end;

{ ---- drawing, as Wine draws 2.31's controls ---- }

const
  ColFace = $FFF5F5F5;
  ColWhite = $FFFFFFFF;
  ColLight = $FFE3E3E3;
  ColShadow = $FFA6A6A6;
  ColDark = $FF6A6A6A;
  ColLine = $FFAEAEAE;
  ColText = $FF000000;
  { the page's sheets start here in the window }
  SheetX = 12;
  SheetY = 83;

type
  TPage = (pgVideo, pgAudio, pgMicro, pgControls, pgGeneral);

  TCheck = record
    Page: TPage;
    X, Y, W: Integer;
    Key, LangKey, Caption: string;
  end;

  TEditBox = record
    Page: TPage;
    X, Y, W: Integer;
    Key: string;
    Numeric: Boolean;
  end;

const
  Checks: array[0..19] of TCheck = (
    (Page: pgVideo; X: 16; Y: 14; W: 369; Key: 'waitvertical'; LangKey: 'Checkbox0'; Caption: 'Wait for vertical blank (slower but smoother)'),
    (Page: pgVideo; X: 16; Y: 36; W: 369; Key: 'compabilitydraw'; LangKey: 'Checkbox1'; Caption: 'Draw in compatibility mode (very slow)'),
    (Page: pgVideo; X: 16; Y: 58; W: 369; Key: 'dontusedirectx7'; LangKey: 'Checkbox20'; Caption: 'Don''t use Direct3D (lights)'),
    (Page: pgVideo; X: 16; Y: 80; W: 369; Key: 'automapping'; LangKey: 'Checkbox22'; Caption: 'Automapping'),
    (Page: pgVideo; X: 16; Y: 102; W: 369; Key: 'startinfullscreen'; LangKey: 'Checkbox21'; Caption: 'Start in fullscreen mode'),
    (Page: pgAudio; X: 16; Y: 14; W: 369; Key: 'reversestereo'; LangKey: 'Checkbox5'; Caption: 'Reverse stereo channels'),
    (Page: pgMicro; X: 16; Y: 14; W: 193; Key: 'microon'; LangKey: 'Checkbox3'; Caption: 'Microphone enabled'),
    (Page: pgControls; X: 16; Y: 14; W: 369; Key: 'joystickon'; LangKey: 'Checkbox2'; Caption: 'Joystick support'),
    (Page: pgControls; X: 16; Y: 36; W: 369; Key: 'nodirectinput'; LangKey: 'Checkbox12'; Caption: 'Don''t use DirectInput'),
    (Page: pgGeneral; X: 16; Y: 14; W: 369; Key: 'notoalls'; LangKey: 'Checkbox16'; Caption: 'Ignore toalls'),
    (Page: pgGeneral; X: 16; Y: 36; W: 369; Key: 'dontsavepasswords'; LangKey: 'Checkbox19'; Caption: 'Don''t save the passwords'),
    (Page: pgGeneral; X: 16; Y: 58; W: 369; Key: 'cachefilenames'; LangKey: ''; Caption: 'Use filename cache (don''t scan folders each startup)'),
    (Page: pgGeneral; X: 16; Y: 80; W: 369; Key: 'nodecompressionerror'; LangKey: 'Checkbox8'; Caption: 'Don''t show decompression errors'),
    (Page: pgGeneral; X: 16; Y: 102; W: 265; Key: 'fixedport'; LangKey: 'Checkbox9'; Caption: 'Use fixed port for data packages:'),
    (Page: pgGeneral; X: 16; Y: 124; W: 369; Key: 'noudp'; LangKey: 'Checkbox10'; Caption: 'Don''t use UDP for data packages'),
    (Page: pgGeneral; X: 16; Y: 146; W: 369; Key: 'dontloadlistheads'; LangKey: 'Checkbox17'; Caption: 'Don''t load heads for the playerlist / map'),
    (Page: pgGeneral; X: 16; Y: 168; W: 313; Key: 'limitnicknames'; LangKey: 'Checkbox14'; Caption: 'Limit the lenght of nicknames to'),
    (Page: pgGeneral; X: 16; Y: 190; W: 369; Key: 'dontconnectlevels'; LangKey: 'Checkbox15'; Caption: 'Don''t connect levels'),
    { not on any page in 2.31's form: kept so the list stays in step }
    (Page: pgGeneral; X: -1; Y: 0; W: 0; Key: 'saveimages'; LangKey: 'Checkbox6'; Caption: ''),
    (Page: pgGeneral; X: -1; Y: 0; W: 0; Key: 'dontsavepms'; LangKey: ''; Caption: ''));

  Edits: array[0..3] of TEditBox = (
    (Page: pgVideo; X: 296; Y: 168; W: 81; Key: 'fontsize'; Numeric: True),
    (Page: pgGeneral; X: 288; Y: 97; W: 89; Key: 'fixedudpport'; Numeric: True),
    (Page: pgGeneral; X: 328; Y: 162; W: 49; Key: 'nicknamelimit'; Numeric: True),
    (Page: pgAudio; X: 112; Y: 187; W: 217; Key: ''; Numeric: False));

  { the tabs, measured: left and right edge, unpicked }
  TabL: array[TPage] of Integer = (8, 69, 124, 216, 286);
  TabR: array[TPage] of Integer = (68, 122, 214, 284, 353);
  TabKeys: array[TPage] of string = ('Tab1', 'Tab2', 'Tab3', 'Tab4', 'Tab5');
  TabCaps: array[TPage] of string = ('&Video', '&Audio', '&Microphone', 'C&ontrols', '&General');

  VolKeys: array[0..4] of string = ('midivolume', 'mp3volume', 'radiovolume',
    'voicevolume', 'sfxvolume');
  VolX: array[0..4] of Integer = (105, 160, 215, 270, 325);

procedure Text(S: TGSurface; X, Y: Integer; const T: string);
begin
  { a pixel lower than the 16 px line's top, as Wine sets 2.31's text }
  UiDrawText(S, X, Y + 1, T, ColText, ufRegular);
end;

{ a caption with its & letter underlined }
procedure Mnemonic(S: TGSurface; X, Y: Integer; const T: string);
var
  P: Integer;
  Plain: string;
begin
  P := Pos('&', T);
  Plain := StringReplace(T, '&', '', []);
  Text(S, X, Y, Plain);
  if (P > 0) and (P <= Length(Plain)) then
    S.FillRect(X + UiTextWidth(Copy(Plain, 1, P - 1), ufRegular), Y + 14,
      UiTextWidth(Plain[P], ufRegular), 1, ColText);
end;

function Plain(const T: string): string;
begin
  Result := StringReplace(T, '&', '', []);
end;

procedure Sunken(S: TGSurface; X, Y, W, H: Integer; Fill: Cardinal);
begin
  S.FillRect(X, Y, W, H, Fill);
  S.FillRect(X, Y, W, 1, ColShadow);
  S.FillRect(X, Y, 1, H, ColShadow);
  S.FillRect(X + 1, Y + 1, W - 2, 1, ColDark);
  S.FillRect(X + 1, Y + 1, 1, H - 2, ColDark);
  S.FillRect(X, Y + H - 1, W, 1, ColWhite);
  S.FillRect(X + W - 1, Y, 1, H, ColWhite);
  S.FillRect(X + 1, Y + H - 2, W - 2, 1, ColLight);
  S.FillRect(X + W - 2, Y + 1, 1, H - 2, ColLight);
end;

procedure Raised(S: TGSurface; X, Y, W, H: Integer; Down: Boolean);
begin
  S.FillRect(X, Y, W, H, ColFace);
  if Down then
  begin
    S.FillRect(X, Y, W, 1, ColDark);
    S.FillRect(X, Y, 1, H, ColDark);
    S.FillRect(X, Y + H - 1, W, 1, ColWhite);
    S.FillRect(X + W - 1, Y, 1, H, ColWhite);
    Exit;
  end;
  S.FillRect(X, Y, W, 1, ColWhite);
  S.FillRect(X, Y, 1, H, ColWhite);
  S.FillRect(X + 1, Y + 1, W - 2, 1, ColLight);
  S.FillRect(X + 1, Y + 1, 1, H - 2, ColLight);
  S.FillRect(X, Y + H - 1, W, 1, ColDark);
  S.FillRect(X + W - 1, Y, 1, H, ColDark);
  S.FillRect(X + 1, Y + H - 2, W - 2, 1, ColShadow);
  S.FillRect(X + W - 2, Y + 1, 1, H - 2, ColShadow);
end;

procedure Button(S: TGSurface; X, Y, W, H: Integer; const Caption: string;
  Default, Down: Boolean);
var
  T: string;
  D: Integer;
begin
  if Default then
  begin
    S.FillRect(X, Y, W, H, ColText);
    Raised(S, X + 1, Y + 1, W - 2, H - 2, Down);
  end
  else
    Raised(S, X, Y, W, H, Down);
  T := Plain(Caption);
  if Down then D := 1 else D := 0;
  Mnemonic(S, X + (W - UiTextWidth(T, ufRegular)) div 2 + D,
    Y + (H - UiLineH) div 2 + D, Caption);
end;

procedure CheckBox(S: TGSurface; X, Y: Integer; const Caption: string; Checked: Boolean);
var
  I: Integer;
begin
  { the 13 x 13 box, 2 down in its 17 high row }
  Sunken(S, X, Y + 2, 13, 13, ColWhite);
  if Checked then
    for I := 0 to 6 do
    begin
      if I < 2 then S.FillRect(X + 3 + I, Y + 2 + 5 + I, 1, 3, ColText)
      else S.FillRect(X + 3 + I, Y + 2 + 7 - (I - 2), 1, 3, ColText);
    end;
  Text(S, X + 18, Y, Caption);
end;

procedure Radio(S: TGSurface; X, Y: Integer; const Caption: string; Checked: Boolean);
begin
  { a round 12 x 12 button, drawn as Wine draws it }
  S.FillRect(X + 4, Y + 2, 4, 1, ColShadow);
  S.FillRect(X + 2, Y + 3, 2, 1, ColShadow);
  S.FillRect(X + 8, Y + 3, 2, 1, ColShadow);
  S.FillRect(X + 1, Y + 4, 1, 2, ColShadow);
  S.FillRect(X, Y + 6, 1, 4, ColShadow);
  S.FillRect(X + 1, Y + 10, 1, 2, ColShadow);
  S.FillRect(X + 2, Y + 4, 8, 8, ColWhite);
  S.FillRect(X + 3, Y + 3, 6, 10, ColWhite);
  S.FillRect(X + 2, Y + 12, 2, 1, ColLight);
  S.FillRect(X + 8, Y + 12, 2, 1, ColLight);
  S.FillRect(X + 4, Y + 13, 4, 1, ColWhite);
  S.FillRect(X + 11, Y + 6, 1, 4, ColWhite);
  if Checked then
  begin
    S.FillRect(X + 5, Y + 6, 2, 4, ColText);
    S.FillRect(X + 4, Y + 7, 4, 2, ColText);
  end;
  Text(S, X + 17, Y, Caption);
end;

procedure Combo(S: TGSurface; X, Y, W: Integer; const Value: string);
var
  BX, I: Integer;
begin
  Sunken(S, X, Y, W, 24, ColWhite);
  BX := X + W - 2 - 16;
  Raised(S, BX, Y + 2, 16, 20, False);
  for I := 0 to 3 do S.FillRect(BX + 4 + I, Y + 10 + I, 7 - 2 * I, 1, ColText);
  Text(S, X + 4, Y + 4, Value);
end;

procedure EditBox(S: TGSurface; X, Y, W: Integer; const Value: string; Focused: Boolean);
begin
  Sunken(S, X, Y, W, 24, ColWhite);
  Text(S, X + 4, Y + 4, Value);
  if Focused and ((Trunc(Now * 86400000.0) div 500) mod 2 = 0) then
    S.FillRect(X + 4 + UiTextWidth(Value, ufRegular), Y + 4, 1, 15, ColText);
end;

{ a vertical track bar as Wine draws it: a white slot and a rounded thumb;
  Pos 0 is the top }
procedure TrackBar(S: TGSurface; X, Y, H, Pos, Max: Integer);
var
  SlotH, TY: Integer;
begin
  SlotH := H - 17;
  S.FillRect(X + 4, Y + 8, 14, SlotH, ColLine);
  S.FillRect(X + 5, Y + 9, 12, SlotH - 2, ColWhite);
  TY := Y + 8 + (SlotH - 10) * Pos div Max;
  S.FillRect(X + 2, TY, 19, 10, ColLine);
  S.FillRect(X + 3, TY + 1, 17, 8, ColWhite);
  S.FillRect(X + 2, TY, 1, 1, ColFace);
  S.FillRect(X + 20, TY, 1, 1, ColFace);
  S.FillRect(X + 2, TY + 9, 1, 1, ColFace);
  S.FillRect(X + 20, TY + 9, 1, 1, ColFace);
end;

{ Text broken at spaces to W pixels }
procedure Wrapped(S: TGSurface; X, Y, W: Integer; const T: string);
var
  Words: TStringList;
  I: Integer;
  Line, Cand: string;
begin
  Words := TStringList.Create;
  try
    { split at spaces only (ExtractStrings would treat ' as a quote) }
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := T;
    for I := Words.Count - 1 downto 0 do
      if Words[I] = '' then Words.Delete(I);
    Line := '';
    for I := 0 to Words.Count - 1 do
    begin
      if Line = '' then Cand := Words[I] else Cand := Line + ' ' + Words[I];
      if (UiTextWidth(Cand, ufRegular) > W) and (Line <> '') then
      begin
        Text(S, X, Y, Line);
        Inc(Y, UiLineH);
        Line := Words[I];
      end
      else
        Line := Cand;
    end;
    if Line <> '' then Text(S, X, Y, Line);
  finally
    Words.Free;
  end;
end;

{ ---- the window ---- }

procedure RunMoreOptions(Config: TGraalConfig; Lang: TLangText);
var
  Win: TGWindow;
  S: TGSurface;
  Page, P: TPage;
  I, CX, CY, Focus, Drag, Open, Row, PressBtn: Integer;
  Clicked: Boolean;
  Chars, V: string;
  Track: string;
  PressUntil: Int64;
  Items: array of string;
  OpenX, OpenY, OpenW: Integer;

  function L(const Key, Default: string): string;
  begin
    if not Assigned(Lang) then Result := Default
    else if Key = '' then Result := Lang('MoreOptions', Default)
    else Result := Lang('MoreOptions-' + Key, Default);
  end;

  function Inside(X, Y, W, H: Integer): Boolean;
  begin
    Result := (CX >= X) and (CY >= Y) and (CX < X + W) and (CY < Y + H);
  end;

  function NowMs: Int64;
  begin
    Result := Trunc(Now * 86400000.0);
  end;

  function CheckCaption(I: Integer): string;
  begin
    if Checks[I].LangKey = '' then Result := Checks[I].Caption
    else Result := L(Checks[I].LangKey, Checks[I].Caption);
  end;

  procedure ListOf(Which: Integer);
  var
    K: Integer;
  begin
    case Which of
      0: begin
           SetLength(Items, Length(FullscreenModes));
           for K := 0 to High(FullscreenModes) do Items[K] := FullscreenModes[K];
         end;
      1: begin
           SetLength(Items, Length(ChatFonts));
           for K := 0 to High(ChatFonts) do Items[K] := ChatFonts[K];
         end;
      2: begin
           SetLength(Items, 1);
           Items[0] := 'Default';
         end;
    else
      SetLength(Items, 4);
      Items[0] := L('CodecAuto', 'Auto-Select depending on listener count');
      Items[1] := 'GSM (13 kbit)';
      Items[2] := 'LPC (4.8 kbit)';
      Items[3] := 'LPC-10 (2.4 kbit)';
    end;
  end;

  procedure Pick(Which, Index: Integer);
  begin
    case Which of
      0: Config.SetStr('fullscreenmode', Items[Index]);
      1: Config.SetStr('font', Items[Index]);
      2: Config.SetStr('microinputdevice', '-1');
      3: Config.SetStr('voicecodec', IntToStr(Index - 1));
    end;
  end;

  procedure Vol(Index, Y: Integer);
  var
    Pos: Integer;
  begin
    { the slot runs 8 .. 91 in the 100 high bar; the thumb is 10 high }
    Pos := (Y - (SheetY + 32 + 8) - 5) * 100 div (100 - 17 - 10);
    if Pos < 0 then Pos := 0;
    if Pos > 100 then Pos := 100;
    if Index < 5 then Config.SetStr(VolKeys[Index], IntToStr(100 - Pos))
    else Config.SetStr('microactivationlevel', IntToStr(100 - Pos));
  end;

begin
  Win := TGWindow.Create(L('', 'More options'), OptW, OptH);
  S := TGSurface.Create(OptW, OptH);
  try
    if not Win.Ok then Exit;
    { 2.31 is poScreenCenter, a fixed dialog with only the close button }
    Win.Reshape(L('', 'More options'), OptW, OptH, True);
    Page := pgVideo;
    Track := '';
    Focus := -1;
    Drag := -1;
    Open := -1;
    PressBtn := 0;
    PressUntil := 0;
    OpenX := 0;
    OpenY := 0;
    OpenW := 0;
    while True do
    begin
      Win.Pump;
      if Win.Closed then Break;
      Clicked := Win.TakeClick(CX, CY);
      Chars := Win.TakeChars;
      if Pos(#27, Chars) > 0 then
      begin
        if Open >= 0 then Open := -1 else Break;
      end;
      { typing into the picked edit box }
      if (Focus >= 0) and (Chars <> '') then
      begin
        if Edits[Focus].Key <> '' then V := Config.Str(Edits[Focus].Key) else V := Track;
        for I := 1 to Length(Chars) do
          if Chars[I] = #8 then
          begin
            if V <> '' then Delete(V, Length(V), 1);
          end
          else if Edits[Focus].Numeric then
          begin
            if (Chars[I] >= '0') and (Chars[I] <= '9') and (Length(V) < 5) then V := V + Chars[I];
          end
          else if (Chars[I] >= ' ') and (Chars[I] <= '~') and (Length(V) < 60) then
            V := V + Chars[I];
        if Edits[Focus].Key <> '' then Config.SetStr(Edits[Focus].Key, V) else Track := V;
      end;
      { a held thumb follows the mouse }
      if Drag >= 0 then
      begin
        if Win.MouseLeft then Vol(Drag, Win.MouseY) else Drag := -1;
      end;
      if Clicked then
      begin
        if Open >= 0 then
        begin
          { a pick in the open list, or anywhere else closes it }
          Row := (CY - OpenY) div UiLineH;
          if (CX >= OpenX) and (CX < OpenX + OpenW) and (CY >= OpenY) and
            (Row >= 0) and (Row <= High(Items)) then
            Pick(Open, Row);
          Open := -1;
          Clicked := False;
        end;
      end;
      if Clicked then
      begin
        Focus := -1;
        for P := Low(TPage) to High(TPage) do
          if Inside(TabL[P], 57, TabR[P] - TabL[P], 22) then Page := P;
        if Inside(312, 320, 91, 28) then Break;
        for I := 0 to High(Checks) do
          if (Checks[I].X >= 0) and (Checks[I].Page = Page) and
            Inside(SheetX + Checks[I].X, SheetY + Checks[I].Y,
              18 + UiTextWidth(CheckCaption(I), ufRegular), 17) then
            Config.SetBool(Checks[I].Key, not Config.Bool(Checks[I].Key));
        for I := 0 to High(Edits) do
          if (Edits[I].Page = Page) and
            Inside(SheetX + Edits[I].X, SheetY + Edits[I].Y, Edits[I].W, 24) then
            Focus := I;
        case Page of
          pgVideo:
            begin
              if Inside(SheetX + 232, SheetY + 119, 145, 24) then
              begin
                Open := 0; OpenX := SheetX + 232; OpenY := SheetY + 143; OpenW := 145;
              end;
              if Inside(SheetX + 163, SheetY + 144, 214, 24) then
              begin
                Open := 1; OpenX := SheetX + 163; OpenY := SheetY + 168; OpenW := 214;
              end;
            end;
          pgAudio:
            begin
              for I := 0 to 4 do
                if Inside(SheetX + VolX[I], SheetY + 32, 24, 100) then
                begin
                  Drag := I;
                  Vol(I, CY);
                end;
              if Inside(SheetX + 329, SheetY + 187, 25, 25) then
              begin PressBtn := 1; PressUntil := NowMs + 150; end;
              if Inside(SheetX + 354, SheetY + 187, 25, 25) then
              begin PressBtn := 2; PressUntil := NowMs + 150; end;
            end;
          pgMicro:
            begin
              if Inside(SheetX + 190, SheetY + 66, 131, 17) then
                Config.SetBool('microactivatebyvolume', True);
              if Inside(SheetX + 190, SheetY + 117, 81, 17) then
                Config.SetBool('microactivatebyvolume', False);
              if Inside(SheetX + 329, SheetY + 38, 24, 73) then
              begin
                Drag := 5;
              end;
              if Inside(SheetX + 88, SheetY + 152, 281, 24) then
              begin
                Open := 2; OpenX := SheetX + 88; OpenY := SheetY + 176; OpenW := 281;
              end;
              if Inside(SheetX + 88, SheetY + 177, 281, 24) then
              begin
                Open := 3; OpenX := SheetX + 88; OpenY := SheetY + 201; OpenW := 281;
              end;
            end;
          pgControls:
            if Inside(SheetX + 16, SheetY + 64, 121, 28) then
            begin PressBtn := 3; PressUntil := NowMs + 150; end;
        end;
        if Open >= 0 then ListOf(Open);
      end;

      { drawing }
      S.Fill(ColFace);
      Wrapped(S, 16, 8, 393, L('Label1', 'Change these options if you''ve got problems ' +
        'with the game or if you want to speed up the game.'));
      { the page frame, then the tabs over its top edge }
      S.FillRect(8, 79, 401, 234, ColLine);
      S.FillRect(9, 80, 399, 232, ColWhite);
      S.FillRect(12, 83, 393, 226, ColFace);
      for P := Low(TPage) to High(TPage) do
        if P <> Page then
        begin
          S.FillRect(TabL[P], 59, TabR[P] - TabL[P], 20, ColLine);
          S.FillRect(TabL[P] + 1, 60, TabR[P] - TabL[P] - 2, 19, ColFace);
          Mnemonic(S, TabL[P] + (TabR[P] - TabL[P] -
            UiTextWidth(Plain(L(TabKeys[P], TabCaps[P])), ufRegular)) div 2, 61,
            L(TabKeys[P], TabCaps[P]));
        end;
      CX := TabL[Page] - 2;
      if Page = pgVideo then CX := 8;
      S.FillRect(CX, 57, TabR[Page] + 2 - CX, 23, ColLine);
      S.FillRect(CX + 1, 58, TabR[Page] + 2 - CX - 2, 22, ColWhite);
      Mnemonic(S, CX + (TabR[Page] + 2 - CX -
        UiTextWidth(Plain(L(TabKeys[Page], TabCaps[Page])), ufRegular)) div 2, 60,
        L(TabKeys[Page], TabCaps[Page]));
      for I := 0 to High(Checks) do
        if (Checks[I].X >= 0) and (Checks[I].Page = Page) then
          CheckBox(S, SheetX + Checks[I].X, SheetY + Checks[I].Y,
            CheckCaption(I), Config.Bool(Checks[I].Key));
      for I := 0 to High(Edits) do
        if Edits[I].Page = Page then
        begin
          if Edits[I].Key <> '' then V := Config.Str(Edits[I].Key) else V := Track;
          EditBox(S, SheetX + Edits[I].X, SheetY + Edits[I].Y, Edits[I].W, V, Focus = I);
        end;
      case Page of
        pgVideo:
          begin
            Text(S, SheetX + 16, SheetY + 124, L('Label4', 'Fullscreen mode:'));
            Text(S, SheetX + 16, SheetY + 148, L('Label2', 'Font:'));
            Text(S, SheetX + 16, SheetY + 172, L('Label3', 'Size:'));
            Combo(S, SheetX + 232, SheetY + 119, 145, Config.Str('fullscreenmode'));
            Combo(S, SheetX + 163, SheetY + 144, 214, Config.Str('font'));
          end;
        pgAudio:
          begin
            Text(S, SheetX + 16, SheetY + 40, L('Label10', 'Volume:'));
            for I := 0 to 4 do
              TrackBar(S, SheetX + VolX[I], SheetY + 32, 100,
                100 - Config.Int(VolKeys[I], 0), 100);
            V := L('Label5', 'midi');
            Text(S, SheetX + 96 + (44 - UiTextWidth(V, ufRegular)) div 2, SheetY + 132, V);
            V := L('Label6', 'mod, mp3');
            if Pos(', ', V) > 0 then
            begin
              Text(S, SheetX + 144 + (57 - UiTextWidth(Copy(V, 1, Pos(', ', V)), ufRegular)) div 2,
                SheetY + 132, Copy(V, 1, Pos(', ', V)));
              Text(S, SheetX + 144 + (57 - UiTextWidth(Copy(V, Pos(', ', V) + 2, MaxInt), ufRegular)) div 2,
                SheetY + 132 + UiLineH, Copy(V, Pos(', ', V) + 2, MaxInt));
            end
            else
              Text(S, SheetX + 144 + (57 - UiTextWidth(V, ufRegular)) div 2, SheetY + 132, V);
            V := L('Label7', 'radio');
            Text(S, SheetX + 200 + (56 - UiTextWidth(V, ufRegular)) div 2, SheetY + 132, V);
            V := L('Label8', 'voice');
            Text(S, SheetX + 256 + (57 - UiTextWidth(V, ufRegular)) div 2, SheetY + 132, V);
            V := L('Label9', 'sfx');
            Text(S, SheetX + 312 + (57 - UiTextWidth(V, ufRegular)) div 2, SheetY + 132, V);
            Text(S, SheetX + 16, SheetY + 192, L('Label16', 'Current track:'));
            { Play: a dark blue triangle; Stop: a dark blue square }
            Raised(S, SheetX + 329, SheetY + 187, 25, 25, (PressBtn = 1) and (NowMs < PressUntil));
            for I := 0 to 4 do
              S.FillRect(SheetX + 339 + I, SheetY + 194 + I, 1, 11 - 2 * I, $FF000080);
            Raised(S, SheetX + 354, SheetY + 187, 25, 25, (PressBtn = 2) and (NowMs < PressUntil));
            S.FillRect(SheetX + 362, SheetY + 195, 9, 9, $FF000080);
          end;
        pgMicro:
          begin
            S.FillRect(SheetX + 188, SheetY + 13, 20, 20, ColShadow);
            S.FillRect(SheetX + 189, SheetY + 14, 19, 19, ColWhite);
            S.FillRect(SheetX + 189, SheetY + 14, 18, 18, $FFFF0000);
            V := L('Label11', 'Micro activation by:');
            Text(S, SheetX + 214 + (129 - UiTextWidth(V, ufRegular)) div 2, SheetY + 14, V);
            Radio(S, SheetX + 190, SheetY + 66, L('RadioButton1', 'Volume'),
              Config.Bool('microactivatebyvolume'));
            Radio(S, SheetX + 190, SheetY + 117, L('RadioButton2', 'Key'),
              not Config.Bool('microactivatebyvolume'));
            V := L('Label12', 'loud');
            Text(S, SheetX + 323 - UiTextWidth(V, ufRegular), SheetY + 46, V);
            V := L('Label13', 'quiet');
            Text(S, SheetX + 323 - UiTextWidth(V, ufRegular), SheetY + 86, V);
            TrackBar(S, SheetX + 329, SheetY + 38, 73,
              100 - Config.Int('microactivationlevel', 50), 100);
            Sunken(S, SheetX + 358, SheetY + 48, 9, 55, ColFace);
            S.FillRect(SheetX + 296, SheetY + 114, 70, 23, ColLine);
            S.FillRect(SheetX + 297, SheetY + 115, 68, 21, ColFace);
            Text(S, SheetX + 300, SheetY + 117, Config.Str('microactivatekey'));
            Text(S, SheetX + 16, SheetY + 157, L('Label15', 'Input:'));
            Text(S, SheetX + 14, SheetY + 182, L('Label14', 'Codec:'));
            Combo(S, SheetX + 88, SheetY + 152, 281, 'Default');
            I := Config.Int('voicecodec', -1);
            ListOf(3);
            if (I + 1 >= 0) and (I + 1 <= High(Items)) then V := Items[I + 1] else V := Items[0];
            Combo(S, SheetX + 88, SheetY + 177, 281, V);
            if Open >= 0 then ListOf(Open);
          end;
        pgControls:
          Button(S, SheetX + 16, SheetY + 64, 121, 28,
            L('ControlsButton', 'Change &keys'), False, (PressBtn = 3) and (NowMs < PressUntil));
      end;
      Button(S, 312, 320, 91, 28, L('CloseButton', '&Close'), False, False);
      { an open list over everything }
      if Open >= 0 then
      begin
        S.FillRect(OpenX, OpenY, OpenW, Length(Items) * UiLineH + 2, ColText);
        S.FillRect(OpenX + 1, OpenY + 1, OpenW - 2, Length(Items) * UiLineH, ColWhite);
        for I := 0 to High(Items) do
        begin
          if (Win.MouseY >= OpenY + 1 + I * UiLineH) and (Win.MouseY < OpenY + 1 + (I + 1) * UiLineH) and
            (Win.MouseX >= OpenX) and (Win.MouseX < OpenX + OpenW) then
          begin
            S.FillRect(OpenX + 1, OpenY + 1 + I * UiLineH, OpenW - 2, UiLineH, $FF000080);
            UiDrawText(S, OpenX + 3, OpenY + 1 + I * UiLineH, Items[I], ColWhite, ufRegular);
          end
          else
            Text(S, OpenX + 3, OpenY + 1 + I * UiLineH, Items[I]);
        end;
      end;
      Win.Present(S);
      Sleep(20);
    end;
    { Close, Esc or the X: 2.31 keeps what was changed }
    Config.Save;
  finally
    S.Free;
    Win.Free;
  end;
end;

{ ---- Open URL ---- }

{$IFDEF MSWINDOWS}
function ShellExecuteA(Wnd: HWND; Op, FileName, Params, Dir: PAnsiChar;
  Show: Integer): HINST; stdcall; external 'shell32.dll';
{$ENDIF}

function OpenInBrowser(const Url: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := ShellExecuteA(0, 'open', PAnsiChar(AnsiString(Url)), nil, nil,
    SW_SHOWNORMAL) > 32;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function RunOpenUrl(const Url: string; Lang: TLangText): Boolean;
const
  W = 401;
  H = 115;
var
  Win: TGWindow;
  S, Glyph: TGSurface;
  CX, CY, X, Y: Integer;
  Clicked: Boolean;
  Chars, D, T: string;
  Key: Cardinal;
begin
  Result := False;
  Glyph := nil;
  if ResFile('OPENGLYPH', D) then
  begin
    Glyph := TGSurface.Create(0, 0);
    if LoadImageData(D, 'OPENGLYPH.bmp', Glyph, False) and (Glyph.Width > 0) then
    begin
      { a BitBtn's see-through colour is its picture's bottom left pixel }
      Key := Glyph.Pixels[(Glyph.Height - 1) * Glyph.Width];
      for X := 0 to Glyph.Width * Glyph.Height - 1 do
        if Glyph.Pixels[X] = Key then Glyph.Pixels[X] := 0;
    end
    else
      FreeAndNil(Glyph);
  end;
  T := 'Open URL';
  if Assigned(Lang) then T := Lang('OpenURL', T);
  Win := TGWindow.Create(T, W, H);
  S := TGSurface.Create(W, H);
  try
    if not Win.Ok then Exit;
    Win.Reshape(T, W, H, True);
    while True do
    begin
      Win.Pump;
      if Win.Closed then Exit;
      Clicked := Win.TakeClick(CX, CY);
      Chars := Win.TakeChars;
      if Pos(#27, Chars) > 0 then Exit;
      if (Pos(#13, Chars) > 0) or (Clicked and (CX >= 216) and (CX < 305) and
        (CY >= 80) and (CY < 108)) then
      begin
        Result := True;
        OpenInBrowser(Url);
        Exit;
      end;
      if Clicked and (CX >= 312) and (CX < 393) and (CY >= 80) and (CY < 108) then Exit;
      S.Fill(ColFace);
      Wrapped(S, 8, 16, 385, 'Do you want to load the URL ' + Url +
        '  with the default browser?');
      { Open: the default button, its picture left of the words }
      S.FillRect(216, 80, 89, 28, ColText);
      Raised(S, 217, 81, 87, 26, False);
      T := '&Open';
      if Assigned(Lang) then T := Lang('OpenURL-OpenButton', T);
      X := 216 + (89 - 15 - 4 - UiTextWidth(Plain(T), ufRegular)) div 2;
      Y := 80 + (28 - 14) div 2;
      if Glyph <> nil then S.Blit(Glyph, 0, 0, Glyph.Width, Glyph.Height, X, Y);
      Mnemonic(S, X + 19, 80 + (28 - UiLineH) div 2, T);
      T := '&Cancel';
      if Assigned(Lang) then T := Lang('OpenURL-CancelButton', T);
      Button(S, 312, 80, 81, 28, T, False, False);
      Win.Present(S);
      Sleep(20);
    end;
  finally
    S.Free;
    Win.Free;
    Glyph.Free;
  end;
end;

{ ---- quit ---- }

function AskQuit: Boolean;
{$IFDEF MSWINDOWS}
begin
  Result := MessageBox(GetActiveWindow, 'Do you really want to quit Graal?', 'Warning',
    MB_OKCANCEL or MB_ICONQUESTION) = IDOK;
end;
{$ELSE}
const
  W = 236;
  H = 82;
var
  Win: TGWindow;
  S: TGSurface;
  CX, CY, I: Integer;
  Chars: string;
begin
  Result := False;
  Win := TGWindow.Create('Warning', W, H);
  S := TGSurface.Create(W, H);
  try
    if not Win.Ok then
    begin
      Result := True;
      Exit;
    end;
    Win.Reshape('Warning', W, H, True);
    while True do
    begin
      Win.Pump;
      if Win.Closed then Exit;
      Chars := Win.TakeChars;
      if Pos(#27, Chars) > 0 then Exit;
      if Pos(#13, Chars) > 0 then
      begin
        Result := True;
        Exit;
      end;
      if Win.TakeClick(CX, CY) then
      begin
        if (CX >= 40) and (CX < 115) and (CY >= 48) and (CY < 71) then
        begin
          Result := True;
          Exit;
        end;
        if (CX >= 122) and (CX < 197) and (CY >= 48) and (CY < 71) then Exit;
      end;
      S.Fill(ColWhite);
      S.FillRect(0, 40, W, H - 40, ColFace);
      { the question mark in a blue circle }
      for I := 0 to 23 do
        S.FillRect(12 + 12 - Round(Sqrt(Sqr(12.0) - Sqr(I - 11.5))), 10 + I,
          2 * Round(Sqrt(Sqr(12.0) - Sqr(I - 11.5))), 1, $FF2A5CAA);
      UiDrawText(S, 20, 14, '?', ColWhite, ufBold);
      Text(S, 48, 14, 'Do you really want to quit Graal?');
      Button(S, 40, 48, 75, 23, 'OK', True, False);
      Button(S, 122, 48, 75, 23, 'Cancel', False, False);
      Win.Present(S);
      Sleep(20);
    end;
  finally
    S.Free;
    Win.Free;
  end;
end;
{$ENDIF}

procedure ShowError(const Msg: string);
{$IFDEF MSWINDOWS}
begin
  MessageBox(GetActiveWindow, PChar(Msg), 'Error', MB_OK or MB_ICONWARNING);
end;
{$ELSE}
var
  Win: TGWindow;
  S: TGSurface;
  W, H, CX, CY, I, BX: Integer;
  Chars: string;
begin
  W := UiTextWidth(Msg, ufRegular) + 90;
  if W < 200 then W := 200;
  H := 82;
  BX := W - 75 - 12;
  Win := TGWindow.Create('Error', W, H);
  S := TGSurface.Create(W, H);
  try
    if not Win.Ok then Exit;
    Win.Reshape('Error', W, H, True);
    while True do
    begin
      Win.Pump;
      if Win.Closed then Exit;
      Chars := Win.TakeChars;
      if (Pos(#27, Chars) > 0) or (Pos(#13, Chars) > 0) then Exit;
      if Win.TakeClick(CX, CY) and (CX >= BX) and (CX < BX + 75) and
        (CY >= 48) and (CY < 71) then Exit;
      S.Fill(ColWhite);
      S.FillRect(0, 40, W, H - 40, ColFace);
      { the warning sign: a yellow triangle with a black ! }
      for I := 0 to 21 do
        S.FillRect(24 - I div 2, 9 + I, I + 1, 1, $FFF2C200);
      S.FillRect(23, 14, 3, 9, $FF000000);
      S.FillRect(23, 25, 3, 3, $FF000000);
      Text(S, 54, 14, Msg);
      Button(S, BX, 48, 75, 23, 'OK', True, False);
      Win.Present(S);
      Sleep(20);
    end;
  finally
    S.Free;
    Win.Free;
  end;
end;
{$ENDIF}

end.
