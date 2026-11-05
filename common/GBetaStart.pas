{ GBetaStart: the start dialog of the 1998 and early 1999 clients, built
  from the client's own TConnectFrame form (GDfm, GVclForm), and what the
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
  SysUtils, GSurface, GDfm, GVclForm;

type
  TBetaMode = (bmOnePlayer, bmOnline, bmTwoPlayers, bmThreePlayers, bmFourPlayers);
  TBetaShape = (bsRadios, bsOnlineBox, bsModeList, bsUnknown);

  TBetaChoice = record
    Mode: TBetaMode;
    Chars: array[0..3] of Integer;
    Nick: string;
    Host: string;           { as typed; HostEdited False: the form's own text }
    HostEdited: Boolean;
    Port: Integer;
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

implementation

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
      C := C or $FF000000;
      if (X + I >= 0) and (Y + J >= 0) and (X + I < Dest.Width) and (Y + J < Dest.Height) then
        Dest.Pixels[X + I + (Y + J) * Dest.Width] := C;
    end;
end;

procedure TBetaDialog.DrawItem(Form: TVclForm; Ctl: TVclCtl; Index: Integer;
  Selected: Boolean; Item: TGSurface);
begin
  { the head 4 px in, the name at 24 px (ComboBox1DrawItem) }
  DrawHeadIcon(Info.Heads, Item, Index, 4, 0, Info.HeadPick);
end;

procedure TBetaDialog.ModeChanged(Form: TVclForm);
var
  M: Integer;
begin
  M := Form.GetItemIndex('ModeSelect');
  { ModeSelectChange: the online panel for One Player Online, one more
    character list for each further player }
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
    C.ItemFill := $C0C0C0;
    C.ItemTextX := 24;
  end;
end;

function RunBetaStart(const Info: TBetaStartInfo; out Choice: TBetaChoice): Boolean;
var
  Dfm: TDfmObj;
  F: TVclForm;
  D: TBetaDialog;
  HostCtl: TVclCtl;
  OrigHost: string;
  I: Integer;
begin
  Result := False;
  FillChar(Choice, SizeOf(Choice), 0);
  Choice.Nick := '';
  Choice.Host := '';
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
    HostCtl := F.Ctl('Edit1');
    if HostCtl <> nil then OrigHost := HostCtl.Text else OrigHost := '';
    if F.ShowModal <> 1 then Exit;
    F.Hide;
    Choice.Nick := F.GetText('Edit3');
    Choice.Host := F.GetText('Edit1');
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
  finally
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
