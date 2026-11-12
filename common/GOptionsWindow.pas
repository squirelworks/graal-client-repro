{ GOptionsWindow: the window F1 opens in the game, built from the build's
  own form (TOptions), as the real clients show it.

  graal_analysis client-internals/gui-windows-fkeys.md:

  - 1st to 5th Graal: "Options", a "Save games" group (Load game (F2),
    Save game (F3)) and a "Level editing" group (the current level, Edit
    level (F4), Load level (F5)), Close. 5th Graal adds More options.
  - 6th Graal to 1.1.9: the same, and F6 also opens it (the key handler
    maps F6 to F10 onto F1 to F5). 15th Graal and 1.1 add More options and
    Controls.
  - 1.28 beta 2 to 1.39: the same groups, with & accelerators.
  - 1.41 rev 1: "Help", the same form as 1.39 with Debugger, Playerlist,
    Serverlist, General options and Controls added.
  - NewMain, 2.0 to 2.05 rev 2 and NewWorld beta 1: "Help", a painted form
    with the current level and Edit level, Load level, Debugger,
    Playerlist, ServerList, General options, Controls and Close
    (GRealStart20.RunHelp20 draws it).
  - 2.1 test2 and test3, NewWorld beta 2, 2.17, 2.22 and 2.31: "Help", a
    "Game windows" group with Edit Level, Load Level, Debugger, Player
    List, Server List and General Options, and Close. 2.31 hides Edit level
    and Debugger at run time (Hide below).

  The real window is stay-on-top and owned by the application window
  (captured on 1st Graal to 1.28 beta 2); the current level field holds
  the level's file name. Here it is modal: the game waits while it is
  open. A button that opens another window closes this one and hands its
  action back to the caller; actions the rebuild does not have yet do
  nothing.

  On Windows the form is a real dialog (GVclForm); elsewhere it is drawn
  with GVclForm.Render in a window of its own. }
unit GOptionsWindow;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat,
  SysUtils, GSurface, GDfmObj, GVclForm, GWindow;

type
  TOptionsAction = (oaNone, oaLoadGame, oaSaveGame, oaEditLevel, oaLoadLevel,
    oaDebugger, oaPlayerList, oaServerList, oaMoreOptions, oaControls, oaClose);

{ What a button of the form does, by its OnClick handler's name (the
  same names in every build): oaNone for a handler that is not a button
  of the window. }
function OptionsActionOf(const Handler: string): TOptionsAction;

{ Shows the TOptions form (FormData, a TPF0 stream) with LevelName in its
  current level field until a button or Esc closes it. The result is the
  button's action; oaNone for Close, the close box, or a form that
  cannot be read. Hide names controls (comma-separated) the build hides
  at run time. }
function RunOptionsWindow(const FormData, AppTitle, LevelName: string;
  const Hide: string = ''): TOptionsAction;

{ The same form drawn into Dest as the window shows it (for tests). }
function RenderOptionsWindow(const FormData, LevelName: string; Dest: TGSurface;
  const Hide: string = ''): Boolean;

implementation

function OptionsActionOf(const Handler: string): TOptionsAction;
var
  H: string;
begin
  H := LowerCase(Handler);
  if H = 'loadbuttonclick' then Result := oaLoadGame
  else if H = 'savebuttonclick' then Result := oaSaveGame
  else if H = 'editbuttonclick' then Result := oaEditLevel
  else if H = 'loadlevelbuttonclick' then Result := oaLoadLevel
  else if H = 'debuggerbuttonclick' then Result := oaDebugger
  else if H = 'playerlistbuttonclick' then Result := oaPlayerList
  else if H = 'serverlistbuttonclick' then Result := oaServerList
  { Button1 is More options (General options in 2.0x), Button2 Controls }
  else if H = 'button1click' then Result := oaMoreOptions
  else if H = 'button2click' then Result := oaControls
  else if H = 'closebuttonclick' then Result := oaClose
  else Result := oaNone;
end;

type
  TOptionsDialog = class
  public
    Action: TOptionsAction;
    procedure Event(Form: TVclForm; Ctl: TVclCtl; Event: TVclEvent);
  end;

procedure TOptionsDialog.Event(Form: TVclForm; Ctl: TVclCtl; Event: TVclEvent);
var
  A: TOptionsAction;
begin
  if (Event <> veClick) or (Ctl.Obj = nil) then Exit;
  A := OptionsActionOf(Ctl.Obj.Ident('OnClick', ''));
  if A = oaNone then Exit;
  if A = oaClose then A := oaNone;
  Action := A;
  Form.Close(1);
end;

function MakeForm(const FormData, LevelName, Hide: string; out Dfm: TDfmObj): TVclForm;
var
  Rest, Name: string;
  P: Integer;
begin
  Result := nil;
  Dfm := nil;
  if Copy(FormData, 1, 4) <> 'TPF0' then Exit;
  try
    Dfm := ParseDfm(FormData);
  except
    on EDfmError do
    begin
      Dfm := nil;
      Exit;
    end;
  end;
  Result := TVclForm.Create(Dfm, 'Graal');
  if Result.Ctl('LevelEdit') <> nil then Result.SetText('LevelEdit', LevelName);
  Rest := Hide;
  while Rest <> '' do
  begin
    P := Pos(',', Rest);
    if P = 0 then P := Length(Rest) + 1;
    Name := Trim(Copy(Rest, 1, P - 1));
    Delete(Rest, 1, P);
    if (Name <> '') and (Result.Ctl(Name) <> nil) then Result.SetVisible(Name, False);
  end;
end;

function RenderOptionsWindow(const FormData, LevelName: string; Dest: TGSurface;
  const Hide: string): Boolean;
var
  Dfm: TDfmObj;
  F: TVclForm;
begin
  F := MakeForm(FormData, LevelName, Hide, Dfm);
  Result := F <> nil;
  try
    if Result then F.Render(Dest);
  finally
    F.Free;
    Dfm.Free;
  end;
end;

{ The control under (X, Y) of the client area, the deepest one. }
function HitCtl(F: TVclForm; X, Y: Integer): TVclCtl;
var
  I, AX, AY: Integer;
  C, P: TVclCtl;
  Shown: Boolean;
begin
  Result := nil;
  for I := 0 to F.CtlCount - 1 do
  begin
    C := F.CtlAt(I);
    if (C.Kind <> vkButton) or not C.Enabled then Continue;
    AX := C.X;
    AY := C.Y;
    Shown := C.Visible;
    P := C.Parent;
    while (P <> nil) and (P.Kind <> vkForm) do
    begin
      Inc(AX, P.X);
      Inc(AY, P.Y);
      Shown := Shown and P.Visible;
      P := P.Parent;
    end;
    if Shown and (X >= AX) and (Y >= AY) and (X < AX + C.W) and (Y < AY + C.H) then
      Result := C;
  end;
end;

{ No Win32 dialog: the form drawn into a window of its own. }
function RunDrawn(F: TVclForm; D: TOptionsDialog): TOptionsAction;
var
  Win: TGWindow;
  S: TGSurface;
  CX, CY: Integer;
  C: TVclCtl;
  Chars: string;
begin
  Result := oaNone;
  Win := TGWindow.Create(F.Caption, F.ClientWidth, F.ClientHeight);
  S := TGSurface.Create(F.ClientWidth, F.ClientHeight);
  try
    if not Win.Ok then Exit;
    Win.Reshape(F.Caption, F.ClientWidth, F.ClientHeight, True);
    while True do
    begin
      Win.Pump;
      if Win.Closed then Exit;
      Chars := Win.TakeChars;
      { Esc closes the drawn window, as its close box does }
      if Pos(#27, Chars) > 0 then Exit;
      if Win.TakeClick(CX, CY) then
      begin
        C := HitCtl(F, CX, CY);
        if C <> nil then
        begin
          D.Event(F, C, veClick);
          if D.Action <> oaNone then
          begin
            Result := D.Action;
            Exit;
          end;
          if (C.Obj <> nil) and (OptionsActionOf(C.Obj.Ident('OnClick', '')) = oaClose) then Exit;
        end;
      end;
      F.Render(S);
      Win.Present(S);
      Sleep(20);
    end;
  finally
    S.Free;
    Win.Free;
  end;
end;

function RunOptionsWindow(const FormData, AppTitle, LevelName: string;
  const Hide: string): TOptionsAction;
var
  Dfm: TDfmObj;
  F: TVclForm;
  D: TOptionsDialog;
begin
  Result := oaNone;
  F := MakeForm(FormData, LevelName, Hide, Dfm);
  if F = nil then Exit;
  D := TOptionsDialog.Create;
  try
    F.AppTitle := AppTitle;
    F.AppOwned := True;
    F.OnEvent := D.Event;
{$IFDEF MSWINDOWS}
    { Close and the close box end ShowModal; the form's own key handler
      (KeyPreview, FormKeyDown) is not read yet, so keys do nothing }
    F.ShowModal;
    F.Hide;
    Result := D.Action;
{$ELSE}
    Result := RunDrawn(F, D);
{$ENDIF}
  finally
    D.Free;
    F.Free;
    Dfm.Free;
  end;
end;

end.
