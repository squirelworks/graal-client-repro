{ The 5.12 launcher's tray icon (Windows).

  The lab's 5.12 (2026-11-13): the icon's tip reads "<server>: N online";
  its right-click menu is Show Game (checked), Show Player List (checked),
  a separator, then Quit. The two toggles hide or show their window and
  make no engine call.

  The icon is the program's own (MAINICON). Clicks come back through
  TrayTake, read once per launcher tick; the launcher's window pump
  (TGWindow.Pump) also delivers the tray window's messages. Other systems
  have no tray here: TrayStart returns False. }
unit Tray512;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TTrayCommand = (tcNone, tcShowGame, tcShowPlayers, tcQuit);

{ Puts the icon in the tray with its tip. False where there is no tray. }
function TrayStart(const Tip: string): Boolean;
procedure TraySetTip(const Tip: string);
{ The check marks the menu shows next to its two toggles. }
procedure TraySetChecks(Game, Players: Boolean);
{ The next menu item picked, tcNone when there is none. }
function TrayTake: TTrayCommand;
procedure TrayStop;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows, Messages, ShellAPI;

const
  WM_TRAY = WM_USER + 1;
  IdGame = 1;
  IdPlayers = 2;
  IdQuit = 3;

var
  Wnd: HWND = 0;
  Data: TNotifyIconDataW;
  CheckGame: Boolean = True;
  CheckPlayers: Boolean = True;
  Queued: TTrayCommand = tcNone;

procedure ShowMenu;
var
  Menu: HMENU;
  P: TPoint;
  Cmd: Integer;
  function Flags(Checked: Boolean): UINT;
  begin
    if Checked then Result := MF_STRING or MF_CHECKED else Result := MF_STRING;
  end;
begin
  Menu := CreatePopupMenu;
  AppendMenuW(Menu, Flags(CheckGame), IdGame, 'Show Game');
  AppendMenuW(Menu, Flags(CheckPlayers), IdPlayers, 'Show Player List');
  AppendMenuW(Menu, MF_SEPARATOR, 0, nil);
  AppendMenuW(Menu, MF_STRING, IdQuit, 'Quit');
  GetCursorPos(P);
  { so the menu closes when the user clicks elsewhere }
  SetForegroundWindow(Wnd);
  Cmd := Integer(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_RIGHTBUTTON, P.X, P.Y, 0, Wnd, nil));
  PostMessage(Wnd, WM_NULL, 0, 0);
  DestroyMenu(Menu);
  case Cmd of
    IdGame: Queued := tcShowGame;
    IdPlayers: Queued := tcShowPlayers;
    IdQuit: Queued := tcQuit;
  end;
end;

function TrayProc(W: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
begin
  if (Msg = WM_TRAY) and ((LP = WM_RBUTTONUP) or (LP = WM_CONTEXTMENU)) then
  begin
    ShowMenu;
    Result := 0;
    Exit;
  end;
  Result := DefWindowProcW(W, Msg, WP, LP);
end;

procedure PutTip(const Tip: string);
var
  T: WideString;
  I: Integer;
begin
  T := WideString(Tip);
  FillChar(Data.szTip, SizeOf(Data.szTip), 0);
  for I := 1 to Length(T) do
    if I <= High(Data.szTip) then Data.szTip[I - 1] := T[I];
end;

function TrayStart(const Tip: string): Boolean;
var
  WC: TWndClassW;
begin
  Result := Wnd <> 0;
  if Result then Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @TrayProc;
  WC.hInstance := HInstance;
  WC.lpszClassName := 'TGraal512Tray';
  RegisterClassW(WC);
  Wnd := CreateWindowExW(0, 'TGraal512Tray', '', 0, 0, 0, 0, 0, 0, 0, HInstance, nil);
  if Wnd = 0 then Exit;
  FillChar(Data, SizeOf(Data), 0);
  Data.cbSize := SizeOf(Data);
  Data.hWnd := Wnd;
  Data.uID := 1;
  Data.uFlags := NIF_ICON or NIF_MESSAGE or NIF_TIP;
  Data.uCallbackMessage := WM_TRAY;
  Data.hIcon := LoadIcon(HInstance, 'MAINICON');
  PutTip(Tip);
  Result := Shell_NotifyIconW(NIM_ADD, @Data);
end;

procedure TraySetTip(const Tip: string);
begin
  if Wnd = 0 then Exit;
  PutTip(Tip);
  Shell_NotifyIconW(NIM_MODIFY, @Data);
end;

procedure TraySetChecks(Game, Players: Boolean);
begin
  CheckGame := Game;
  CheckPlayers := Players;
end;

function TrayTake: TTrayCommand;
begin
  Result := Queued;
  Queued := tcNone;
end;

procedure TrayStop;
begin
  if Wnd = 0 then Exit;
  Shell_NotifyIconW(NIM_DELETE, @Data);
  DestroyWindow(Wnd);
  Wnd := 0;
end;

{$ELSE}

function TrayStart(const Tip: string): Boolean;
begin
  Result := False;
end;

procedure TraySetTip(const Tip: string);
begin
end;

procedure TraySetChecks(Game, Players: Boolean);
begin
end;

function TrayTake: TTrayCommand;
begin
  Result := tcNone;
end;

procedure TrayStop;
begin
end;

{$ENDIF}

end.
