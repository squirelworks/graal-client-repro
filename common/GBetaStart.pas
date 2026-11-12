{ GBetaStart: the start dialog of the 1998 and early 1999 clients, built
  from the client's own TConnectFrame form (GDfmObj, GVclForm), and what the
  player picked in it.

  The forms come in three shapes, recognised by their controls:
    radios     1st and 2nd Graal: One Player / Two Player / One Player
               Online radio buttons, server address and port fields
    online box 3rd Graal to 13th: One Player and Two Players radios, each
               with a character list, and a group with "Online At
               Cyberjoueur", nick name, server and port
    mode list  14th Graal to 1.1: a mode list (One Player, One Player
               Online, Two Players, and in 1.1.9 Three and Four Players),
               one character list per player, and a panel with nick name,
               server and port shown for the online mode

  The character lists are filled with the build's own names in its own
  order (Names), with the first and second player's defaults the real
  clients show; owner-drawn lists draw each character's head from the
  install's heads.gif. }
unit GBetaStart;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat,
  SysUtils, GSurface, GDfmObj, GVclForm;

type
  TBetaNames = array of string;
  TBetaMode = (bmOnePlayer, bmOnline, bmTwoPlayers, bmThreePlayers, bmFourPlayers);
  TBetaShape = (bsRadios, bsOnlineBox, bsModeList, bsUnknown);

  TBetaChoice = record
    Mode: TBetaMode;
    Chars: array[0..3] of Integer;
    Nick: string;
    Host: string;           { as typed; HostEdited False: the form's own text }
    HostEdited: Boolean;
    Port: Integer;
    Account, Password: string;  { 1.21 on: the account fields }
    LoadColors: Boolean;        { 1.21 on: "Load head/colors from last session" }
    Language: string;           { 1.28 beta 2: the language picked }
  end;

  TBetaStartInfo = record
    FormData: string;       { the TCONNECTFRAME form stream }
    AppTitle: string;       { the hidden TApplication window's title }
    Names: array of string; { character list, in the build's order }
    Heads: TGSurface;       { the install's heads.gif, or nil }
    Nick: string;           { pre-filled nick name, '' for none }
    { the dialog window as the build creates it: owned by the application
      window (1st to 5th Graal) or by none (its own taskbar button, from
      the 5th Graal alpha on), and stay-on-top (3rd to 5th Graal) }
    AppOwned: Boolean;
    StayOnTop: Boolean;
    { how the list shrinks a head: False ANDs each 2 x 2 block (GDI's
      default BLACKONWHITE, to the 13th Graal), True keeps one pixel of it
      (COLORONCOLOR, from the 14th Graal) }
    HeadPick: Boolean;
    { 1.21 on: one head sheet per entry (heads/headN.gif, named in
      headsconfig.txt), drawn instead of a column of Heads; nil entries
      are left blank }
    HeadSheets: array of TGSurface;
    { 1.21 on: graalconfig.txt, read for the last session's choices and
      written back on Start; '' for none }
    ConfigFile: string;
    { 1.28 beta 2: the folder with language<Name>.txt, '' for none; and the
      online panel showing only the nick name row in One Player mode }
    LanguageDir: string;
    NickRowAlone: Boolean;
    { the lists' ground: 0 for clSilver (to the 15th Graal); 1.1 on fill
      with heads' own transparent colour, $C6C6C6 }
    ItemFill: Cardinal;
    { where the head and name start in an entry, against the 1998 lists'
      4 and 24 px (1.21 on: one pixel further left) }
    ItemShift: Integer;
  end;

function BetaShape(F: TVclForm): TBetaShape;
{ Shows the dialog until Start (True) or close (False). }
function RunBetaStart(const Info: TBetaStartInfo; out Choice: TBetaChoice): Boolean;

{ The parts of the build's TAdventure form the game window copies. }
type
  TBetaGameForm = record
    Caption: string;
    Width, Height: Integer;   { outer }
    ViewW, ViewH: Integer;    { DXDraw }
    ChatH: Integer;           { Edit1 under it, 0 when hidden }
    MinBox, MaxBox: Boolean;
  end;

function BetaGameForm(const FormData: string; out G: TBetaGameForm): Boolean;

{ Draws character Index's head, front view, halved into the 16 x 16 cell at
  (X, Y) of Dest, the way the owner-drawn lists show it. }
procedure DrawHeadIcon(Heads, Dest: TGSurface; Index, X, Y: Integer;
  Pick: Boolean = False);

{ headsconfig.txt (1.21 on): the character list, "Name=headfile.gif,..."
  per line; Names and Files come back in the file's order. }
function ReadHeadsConfig(const FileName: string; out Names, Files: TBetaNames): Boolean;

implementation

uses
  GPaths,
  Classes;

type
  TBetaDialog = class
  public
    Info: TBetaStartInfo;
    Shape: TBetaShape;
    Started: Boolean;
    procedure Event(Form: TVclForm; Ctl: TVclCtl; Event: TVclEvent);
    procedure DrawItem(Form: TVclForm; Ctl: TVclCtl; Index: Integer;
      Selected: Boolean; Item: TGSurface);
    procedure ModeChanged(Form: TVclForm);
    procedure ApplyLanguage(Form: TVclForm; const Name: string);
  end;

function ReadHeadsConfig(const FileName: string; out Names, Files: TBetaNames): Boolean;
var
  L: TStringList;
  I, P, N: Integer;
  S, V: string;
begin
  SetLength(Names, 0);
  SetLength(Files, 0);
  Result := FileExists(FileName);
  if not Result then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    N := 0;
    for I := 0 to L.Count - 1 do
    begin
      S := Trim(L[I]);
      P := Pos('=', S);
      if P < 2 then Continue;
      V := Copy(S, P + 1, MaxInt);
      if Pos(',', V) > 0 then V := Copy(V, 1, Pos(',', V) - 1);
      SetLength(Names, N + 1);
      SetLength(Files, N + 1);
      Names[N] := Copy(S, 1, P - 1);
      Files[N] := Trim(V);
      Inc(N);
    end;
  finally
    L.Free;
  end;
  Result := N > 0;
end;

{ graalconfig.txt: key=value lines }
function ConfigValue(L: TStringList; const Key, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  if L = nil then Exit;
  I := L.IndexOfName(Key);
  if I >= 0 then Result := ValueAtIndex(L, I);
end;

procedure SetConfigValue(L: TStringList; const Key, Value: string);
var
  I: Integer;
begin
  I := L.IndexOfName(Key);
  if I >= 0 then L[I] := Key + '=' + Value else L.Add(Key + '=' + Value);
end;

function IndexOfText(F: TVclForm; const Ctl, Text: string): Integer;
var
  C: TVclCtl;
begin
  Result := -1;
  C := F.Ctl(Ctl);
  if C <> nil then
    for Result := 0 to C.Items.Count - 1 do
      if SameText(C.Items[Result], Text) then Exit;
  Result := -1;
end;

procedure TBetaDialog.ApplyLanguage(Form: TVclForm; const Name: string);
var
  L: TStringList;
  I, P, M: Integer;
  K, V, Ctl: string;
  Modes: array of string;
begin
  if Info.LanguageDir = '' then Exit;
  K := WithTrailingSep(Info.LanguageDir) + 'language' + Name + '.txt';
  if not FileExists(K) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(K);
    SetLength(Modes, 0);
    for I := 0 to L.Count - 1 do
    begin
      P := Pos('=', L[I]);
      if P < 2 then Continue;
      K := Copy(L[I], 1, P - 1);
      V := TrimRight(Copy(L[I], P + 1, MaxInt));
      if SameText(K, 'StartScreen') then Form.SetCaption(V)
      else if SameText(Copy(K, 1, 12), 'StartScreen-') then
      begin
        Ctl := Copy(K, 13, MaxInt);
        if SameText(Copy(Ctl, 1, 11), 'ModeSelect-') then
        begin
          M := StrToIntDef(Copy(Ctl, 12, MaxInt), -1);
          if M >= 0 then
          begin
            if M >= Length(Modes) then SetLength(Modes, M + 1);
            Modes[M] := V;
          end;
        end
        else if Form.Ctl(Ctl) <> nil then Form.SetText(Form.Ctl(Ctl).Name, V);
      end;
    end;
    if Length(Modes) > 0 then
    begin
      M := Form.GetItemIndex('ModeSelect');
      Form.SetItems('ModeSelect', Modes);
      Form.SetItemIndex('ModeSelect', M);
    end;
  finally
    L.Free;
  end;
end;

function BetaShape(F: TVclForm): TBetaShape;
begin
  if F.Ctl('ModeSelect') <> nil then Result := bsModeList
  else if (F.Ctl('CheckBox1') <> nil) and (F.Ctl('ComboBox1') <> nil) then Result := bsOnlineBox
  else if F.Ctl('RadioButton3') <> nil then Result := bsRadios
  else Result := bsUnknown;
end;

procedure DrawHeadIcon(Heads, Dest: TGSurface; Index, X, Y: Integer;
  Pick: Boolean);
var
  I, J: Integer;
  C: Cardinal;
  SX, SY: Integer;
begin
  if (Heads = nil) or (Index < 0) then Exit;
  SX := Index * 32;
  SY := 64; { the third row of a head's column faces the viewer }
  if SX + 32 > Heads.Width then Exit;
  { the 32 x 32 head shrunk to 16 x 16 by StretchBlt: in GDI's default
    mode (BLACKONWHITE) each pixel is the AND of a 2 x 2 block, which keeps
    the black outlines; drawn opaque (heads.gif's ground is silver) }
  for J := 0 to 15 do
    for I := 0 to 15 do
    begin
      if Pick then
        { COLORONCOLOR: the block's top right pixel, as GDI keeps it }
        C := Heads.GetPixel(SX + I * 2 + 1, SY + J * 2)
      else
        C := Heads.GetPixel(SX + I * 2, SY + J * 2) and
          Heads.GetPixel(SX + I * 2 + 1, SY + J * 2) and
          Heads.GetPixel(SX + I * 2, SY + J * 2 + 1) and
          Heads.GetPixel(SX + I * 2 + 1, SY + J * 2 + 1);
      { a transparent pixel (the 1.1 on head sheets) keeps the ground }
      if C shr 24 = 0 then
        if Pick then Continue;
      C := C or $FF000000;
      if (X + I >= 0) and (Y + J >= 0) and (X + I < Dest.Width) and (Y + J < Dest.Height) then
        Dest.Pixels[X + I + (Y + J) * Dest.Width] := C;
    end;
end;

procedure TBetaDialog.DrawItem(Form: TVclForm; Ctl: TVclCtl; Index: Integer;
  Selected: Boolean; Item: TGSurface);
begin
  { the head 4 px in, the name at 24 px (ComboBox1DrawItem) }
  if Length(Info.HeadSheets) > 0 then
  begin
    if (Index >= 0) and (Index <= High(Info.HeadSheets)) then
      DrawHeadIcon(Info.HeadSheets[Index], Item, 0, 4 + Info.ItemShift, 0, Info.HeadPick);
  end
  else
    DrawHeadIcon(Info.Heads, Item, Index, 4 + Info.ItemShift, 0, Info.HeadPick);
end;

procedure TBetaDialog.ModeChanged(Form: TVclForm);
var
  M: Integer;
begin
  M := Form.GetItemIndex('ModeSelect');
  { ModeSelectChange: the online panel for One Player Online, one more
    character list for each further player }
  if Info.NickRowAlone then
  begin
    { 1.28 beta 2: One Player keeps the panel, cut to its nick name row }
    Form.SetVisible('Panel1', M <= 1);
    if M = 0 then Form.SetHeight('Panel1', 37)
    else Form.SetHeight('Panel1', Form.Ctl('Panel1').Obj.Int('Height', 153));
  end
  else
    Form.SetVisible('Panel1', M = 1);
  Form.SetVisible('ComboBox2', M >= 2);
  Form.SetVisible('ComboBox3', M >= 3);
  Form.SetVisible('ComboBox4', M >= 4);
end;

procedure TBetaDialog.Event(Form: TVclForm; Ctl: TVclCtl; Event: TVclEvent);
begin
  if SameText(Ctl.Name, 'Button1') and (Event = veClick) then
  begin
    Started := True;
    Form.Close(1);
  end
  else if SameText(Ctl.Name, 'ModeSelect') and (Event = veChange) then
    ModeChanged(Form)
  else if SameText(Ctl.Name, 'ComboBox6') and (Event = veChange) then
    ApplyLanguage(Form, Form.GetText('ComboBox6'))
  else if (Event = veEnter) and (Ctl.Kind = vkEdit) then
  begin
    { Edit1/2/3KeyDown: Enter starts, as the Start button }
    Started := True;
    Form.Close(1);
  end;
end;

procedure FillChars(F: TVclForm; const Info: TBetaStartInfo; const Name: string;
  Default: Integer);
var
  C: TVclCtl;
  Fill: Cardinal;
begin
  C := F.Ctl(Name);
  if C = nil then Exit;
  F.SetItems(Name, Info.Names);
  if Default >= Length(Info.Names) then Default := Length(Info.Names) - 1;
  F.SetItemIndex(Name, Default);
  if C.OwnerDraw then
  begin
    { ComboBox1DrawItem fills with silver (the same on every colour
      scheme) and writes the name after the head }
    Fill := Info.ItemFill;
    if Fill = 0 then Fill := $C0C0C0;
    C.ItemFill := Fill;
    C.ItemTextX := 24 + Info.ItemShift;
  end;
end;

function RunBetaStart(const Info: TBetaStartInfo; out Choice: TBetaChoice): Boolean;
var
  Dfm: TDfmObj;
  F: TVclForm;
  D: TBetaDialog;
  HostCtl: TVclCtl;
  OrigHost, HostName, S: string;
  I, J: Integer;
  Cfg: TStringList;
  SR: TSearchRec;
  Langs: array of string;
begin
  Result := False;
  FillChar(Choice, SizeOf(Choice), 0);
  Choice.Nick := '';
  Choice.Host := '';
  Cfg := nil;
  if (Info.ConfigFile <> '') and FileExists(Info.ConfigFile) then
  begin
    Cfg := TStringList.Create;
    Cfg.LoadFromFile(Info.ConfigFile);
  end;
  Dfm := ParseDfm(Info.FormData);
  D := TBetaDialog.Create;
  F := TVclForm.Create(Dfm, Info.AppTitle);
  try
    D.Info := Info;
    D.Shape := BetaShape(F);
    F.AppOwned := Info.AppOwned;
    F.StayOnTop := Info.StayOnTop;
    F.OnEvent := D.Event;
    F.OnDrawItem := D.DrawItem;
    { FormCreate: the character lists and their defaults (the first
      player is the second entry before the mode list, the first after) }
    if D.Shape = bsOnlineBox then
    begin
      FillChars(F, Info, 'ComboBox1', 1);
      FillChars(F, Info, 'ComboBox2', 2);
    end
    else if D.Shape = bsModeList then
    begin
      FillChars(F, Info, 'ComboBox1', 0);
      FillChars(F, Info, 'ComboBox2', 1);
      FillChars(F, Info, 'ComboBox3', 2);
      FillChars(F, Info, 'ComboBox4', 3);
      F.SetItemIndex('ModeSelect', 0);
    end;
    if Info.Nick <> '' then F.SetText('Edit3', Info.Nick);
    { 1.21 on: the server is ComboBox5, the last session's choices come
      from graalconfig.txt }
    if F.Ctl('ComboBox5') <> nil then HostName := 'ComboBox5' else HostName := 'Edit1';
    if F.Ctl('Edit4') <> nil then
    begin
      S := ConfigValue(Cfg, 'serveraddr', '');
      if S = '' then S := 'listserver.graal.in';
      F.SetText('ComboBox5', S);
      F.SetText('Edit2', ConfigValue(Cfg, 'serverport', F.GetText('Edit2')));
      F.SetText('Edit4', ConfigValue(Cfg, 'accountname', F.GetText('Edit4')));
      F.SetText('Edit5', ConfigValue(Cfg, 'password', F.GetText('Edit5')));
      if Info.Nick = '' then F.SetText('Edit3', ConfigValue(Cfg, 'editnickname', ''));
      F.SetChecked('CheckBox1', SameText(ConfigValue(Cfg, 'loadcolorsfromserver', 'true'), 'true'));
      I := IndexOfText(F, 'ModeSelect', ConfigValue(Cfg, 'gamemode', ''));
      if I >= 0 then F.SetItemIndex('ModeSelect', I);
      for I := 1 to 4 do
        if IndexOfText(F, 'ComboBox' + IntToStr(I), ConfigValue(Cfg, 'head' + IntToStr(I), '')) >= 0 then
          F.SetItemIndex('ComboBox' + IntToStr(I), IndexOfText(F, 'ComboBox' + IntToStr(I),
            ConfigValue(Cfg, 'head' + IntToStr(I), '')));
    end;
    { 1.28 beta 2: the languages are the language*.txt files }
    if (Info.LanguageDir <> '') and (F.Ctl('ComboBox6') <> nil) then
    begin
      SetLength(Langs, 0);
      if FindFirst(WithTrailingSep(Info.LanguageDir) + 'language*.txt', faAnyFile, SR) = 0 then
      begin
        repeat
          S := ChangeFileExt(Copy(SR.Name, 9, MaxInt), '');
          SetLength(Langs, Length(Langs) + 1);
          Langs[High(Langs)] := S;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
      { sorted, as the list shows them }
      for I := 1 to High(Langs) do
        for J := I downto 1 do
          if CompareText(Langs[J - 1], Langs[J]) > 0 then
          begin
            S := Langs[J];
            Langs[J] := Langs[J - 1];
            Langs[J - 1] := S;
          end;
      F.SetItems('ComboBox6', Langs);
      I := IndexOfText(F, 'ComboBox6', ConfigValue(Cfg, 'language', 'English'));
      F.SetItemIndex('ComboBox6', I);
      if I >= 0 then D.ApplyLanguage(F, Langs[I]);
    end;
    if D.Shape = bsModeList then D.ModeChanged(F);
    HostCtl := F.Ctl(HostName);
    if HostCtl <> nil then OrigHost := HostCtl.Text else OrigHost := '';
    if F.ShowModal <> 1 then Exit;
    F.Hide;
    Choice.Nick := F.GetText('Edit3');
    Choice.Host := F.GetText(HostName);
    Choice.Account := F.GetText('Edit4');
    Choice.Password := F.GetText('Edit5');
    Choice.LoadColors := F.GetChecked('CheckBox1');
    Choice.Language := F.GetText('ComboBox6');
    Choice.HostEdited := Choice.Host <> OrigHost;
    Choice.Port := StrToIntDef(Trim(F.GetText('Edit2')), 0);
    for I := 0 to 3 do Choice.Chars[I] := I;
    case D.Shape of
      bsRadios:
        if F.GetChecked('RadioButton3') then Choice.Mode := bmOnline
        else if F.GetChecked('RadioButton2') then Choice.Mode := bmTwoPlayers
        else Choice.Mode := bmOnePlayer;
      bsOnlineBox:
        begin
          Choice.Chars[0] := F.GetItemIndex('ComboBox1');
          Choice.Chars[1] := F.GetItemIndex('ComboBox2');
          if F.GetChecked('RadioButton2') then Choice.Mode := bmTwoPlayers
          else if F.GetChecked('CheckBox1') then Choice.Mode := bmOnline
          else Choice.Mode := bmOnePlayer;
        end;
      bsModeList:
        begin
          for I := 0 to 3 do
            Choice.Chars[I] := F.GetItemIndex('ComboBox' + IntToStr(I + 1));
          case F.GetItemIndex('ModeSelect') of
            1: Choice.Mode := bmOnline;
            2: Choice.Mode := bmTwoPlayers;
            3: Choice.Mode := bmThreePlayers;
            4: Choice.Mode := bmFourPlayers;
          else
            Choice.Mode := bmOnePlayer;
          end;
        end;
    end;
    for I := 0 to 3 do
      if Choice.Chars[I] < 0 then Choice.Chars[I] := 0;
    Result := D.Started;
    if Result and (Info.ConfigFile <> '') and (F.Ctl('Edit4') <> nil) then
    begin
      { FormClose: the choices are kept for the next session }
      if Cfg = nil then Cfg := TStringList.Create;
      SetConfigValue(Cfg, 'gamemode', F.GetText('ModeSelect'));
      for I := 1 to 4 do
        SetConfigValue(Cfg, 'head' + IntToStr(I), F.GetText('ComboBox' + IntToStr(I)));
      SetConfigValue(Cfg, 'editnickname', Choice.Nick);
      if Choice.HostEdited then SetConfigValue(Cfg, 'serveraddr', Choice.Host);
      SetConfigValue(Cfg, 'serverport', IntToStr(Choice.Port));
      SetConfigValue(Cfg, 'accountname', Choice.Account);
      SetConfigValue(Cfg, 'password', Choice.Password);
      SetConfigValue(Cfg, 'loadcolorsfromserver', LowerCase(BoolText(Choice.LoadColors)));
      if Choice.Language <> '' then SetConfigValue(Cfg, 'language', Choice.Language);
      try
        Cfg.SaveToFile(Info.ConfigFile);
      except
        { a read-only folder: the choices are not kept }
      end;
    end;
  finally
    Cfg.Free;
    F.Free;
    D.Free;
    Dfm.Free;
  end;
end;

function BetaGameForm(const FormData: string; out G: TBetaGameForm): Boolean;
var
  O, DX, Ed: TDfmObj;
begin
  Result := False;
  G.Caption := 'Graal';
  G.Width := 648;
  G.Height := 516;
  G.ViewW := 640;
  G.ViewH := 448;
  G.ChatH := 24;
  G.MinBox := True;
  G.MaxBox := False;
  if FormData = '' then Exit;
  O := ParseDfm(FormData);
  try
    G.Caption := O.Str('Caption', G.Caption);
    G.Width := O.Int('Width', G.Width);
    G.Height := O.Int('Height', G.Height);
    if O.Has('BorderIcons') then
    begin
      G.MinBox := O.InSet('BorderIcons', 'biMinimize');
      G.MaxBox := O.InSet('BorderIcons', 'biMaximize');
    end
    else
    begin
      G.MinBox := True;
      G.MaxBox := True;
    end;
    DX := O.Find('DXDraw');
    if DX <> nil then
    begin
      G.ViewW := DX.Int('Width', G.ViewW);
      G.ViewH := DX.Int('Height', G.ViewH);
    end;
    Ed := O.Find('Edit1');
    if (Ed <> nil) and Ed.Bool('Visible', True) then G.ChatH := Ed.Int('Height', 24)
    else G.ChatH := 0;
    Result := True;
  finally
    O.Free;
  end;
end;

end.
