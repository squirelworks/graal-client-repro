{ GWindow: a plain window that shows a TGSurface and reports keys.

  Stands in for the DelphiX TDXForm of the originals. Back ends:
    Windows   GDI (StretchDIBits), the same API under Delphi and Free Pascal
    Unix      X11 through Free Pascal's xlib units (XPutImage)
    macOS     Cocoa through the Objective-C runtime (a CALayer shows each
              frame as a CGImage); -dGW_HEADLESS builds the old windowless
              stub, where Ok is False and the client runs headless
  The window shows the surface 1:1 and keeps a held-key table that the game
  tick reads, which is how DelphiX's DXInput was used. }
unit GWindow;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF DARWIN}{$DEFINE GW_NONE}{$IFNDEF GW_HEADLESS}{$DEFINE GW_COCOA}{$ENDIF}{$ENDIF}

interface

uses
  GSurface;

type
  TGKey = (gkNone, gkUp, gkLeft, gkDown, gkRight, gkAction, gkAttack,
    gkItem, gkMap, gkChat, gkEscape, gkItemList,
    { the 2.05 built-in editor: F4 opens it, F5 is the load level dialog }
    gkEditor, gkLoadLevel, gkDelete, gkInsert);

  TGWindow = class
  private
{$IFDEF MSWINDOWS}
    FWnd: THandle;
    { Delphi's hidden TApplication window: it owns the taskbar button }
    FApp: THandle;
{$ENDIF}
    FDelphi: Boolean;
    { has been fullscreen: Delphi's form then has no WS_EX_ACCEPTFILES }
    FWasFull: Boolean;
    { the last frame shown, painted again on WM_PAINT }
    FLast: TGSurface;
{$IFDEF GW_NONE}
{$IFDEF GW_COCOA}
    { NSWindow, its content view's CALayer, a device RGB colour space }
    FWin, FLayer, FColorSpace: Pointer;
    { the content view's size in points, for the mouse }
    FViewW, FViewH: Double;
{$ENDIF}
{$ELSE}{$IFNDEF MSWINDOWS}
    FDisplay: Pointer;
    FWin: Cardinal;
    FGC: Pointer;
    FImage: Pointer;
    FImageBuf: Pointer;
    FWmDelete: Cardinal;
{$ENDIF}{$ENDIF}
    FWidth, FHeight: Integer;
    { the title and frame Reshape last set, put back when fullscreen ends }
    FTitle: string;
    FFullscreen: Boolean;
    FFullToggle: Boolean;
{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}
    { where the frame sits in a fullscreen window larger than the mode }
    FOffX, FOffY: Integer;
{$ENDIF}{$ENDIF}
    { ShowForm: a Delphi form's frame; the picture is drawn 1:1 at the
      scroll position, and what lies beyond it is the form's colour }
    FForm, FAutoScroll: Boolean;
    FDesignW, FDesignH: Integer;
    FFormColor: Cardinal;
    FPressed: array[TGKey] of Boolean; { pressed since the last tick }
    FClicked: Boolean;
    FClickX, FClickY: Integer;
    FRightClicked: Boolean;
    FRightX, FRightY: Integer;
    FWheel: Integer;
    FChars: string;
    procedure AddClick(X, Y: Integer);
    procedure AddRightClick(X, Y: Integer);
{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}
    procedure SetArrow(Sym: Cardinal; Down: Boolean);
    procedure NewImage(AWidth, AHeight: Integer);
{$ENDIF}{$ENDIF}
  public
    MouseX, MouseY: Integer;
    { the scroll position of a ShowForm window (0, 0 without scroll bars) }
    ScrollX, ScrollY: Integer;
    { Mouse buttons held now, and the Ctrl / Shift keys (for the editor). }
    MouseLeft, MouseRight: Boolean;
    CtrlHeld, ShiftHeld: Boolean;
    { The arrow keys alone (up, left, down, right), without the I J K L
      letters that also walk, so the editor can scroll with them. }
    ArrowHeld: array[0..3] of Boolean;
    Held: array[TGKey] of Boolean;
    Closed: Boolean;
    constructor Create(const Title: string; AWidth, AHeight: Integer);
    destructor Destroy; override;
    function Ok: Boolean;
    { Handles every waiting window event. }
    procedure Pump;
    procedure Present(Surface: TGSurface);
    { New title and client size (the start dialog is 577 x 416, the game
      640 x 480), kept centred on the screen. }
    { Dialog: a fixed dialog frame with only the close button (2.22's
      start window and server list, bsDialog); else the game's frame. }
    { MinBox (with Dialog False): a fixed frame with the minimise and close
      buttons and a greyed maximise button (the 1.x forms' BorderIcons
      [biSystemMenu, biMinimize]) }
    procedure Reshape(const Title: string; AWidth, AHeight: Integer;
      Dialog: Boolean = False; MinBox: Boolean = False);
    { Alt+Enter as 2.22: fullscreen in the given mode (graalconfig.txt's
      fullscreenmode) and back. Windows switches the display mode, as
      DirectDraw's SetDisplayMode did; X11 fills the screen with a frame-
      less window and centres the frame when the screen is larger. False
      when the mode cannot be set (the window stays as it was). }
    function EnterFullscreen(AWidth, AHeight: Integer): Boolean;
    { Back to the desktop mode and the framed AWidth x AHeight window. }
    procedure LeaveFullscreen(AWidth, AHeight: Integer);
    property Fullscreen: Boolean read FFullscreen;
    { The frames of a Delphi program, as 2.22's (the lab's GetWindowLong on
      the real windows): the taskbar button belongs to a hidden window
      titled AppTitle with the program's icon; Reshape's dialog is
      bsDialog (no caption icon, close button only) and the game window
      bsSizeable. Windows only. }
    procedure UseDelphiFrames(const AppTitle: string);
    { True once for each Alt+Enter since the last call. }
    function TakeFullscreenToggle: Boolean;
    { A Delphi form's own window, as TForm makes it: the outer size the
      form gives (Width, Height), so the client is what the frame leaves
      of it on this system; a sizable frame with the minimise box and a
      greyed maximise box ([biSystemMenu, biMinimize]); scroll bars over
      the controls' extent (DesignW x DesignH) when AutoScroll and it
      does not fit, as on Windows 10, where the 1.x start dialogs come up
      a little too small. The surfaces then given to Present are of the
      design size. Outside Windows the window is the design size. }
    procedure ShowForm(const Title: string; OuterW, OuterH, DesignW, DesignH: Integer;
      AutoScroll: Boolean; FormColor: Cardinal);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    { True once for each press since the last call (for one-shot keys). }
    function WasPressed(K: TGKey): Boolean;
    procedure SetKey(K: TGKey; Down: Boolean);
    { The last left click since the last call, in window pixels. }
    function TakeClick(out X, Y: Integer): Boolean;
    { The last right click since the last call. }
    function TakeRightClick(out X, Y: Integer): Boolean;
    { Mouse wheel steps since the last call: up is negative. }
    function TakeWheel: Integer;
    { Characters typed since the last call: printable ones, #8 backspace,
      #9 tab, #13 enter, #27 escape, and Ctrl+letter as #1..#26. }
    function TakeChars: string;
    procedure AddChar(C: Char);
  end;

implementation

uses
  SysUtils
{$IFDEF MSWINDOWS}
  , Windows, Messages
{$ENDIF}
{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}
  , xlib, x, xutil, keysym, xkblib, ctypes
{$ENDIF}{$ENDIF};

procedure TGWindow.SetKey(K: TGKey; Down: Boolean);
begin
  if K = gkNone then Exit;
  if Down and not Held[K] then FPressed[K] := True;
  Held[K] := Down;
end;

procedure TGWindow.AddClick(X, Y: Integer);
begin
  FClicked := True;
  FClickX := X;
  FClickY := Y;
  MouseX := X;
  MouseY := Y;
end;

procedure TGWindow.AddRightClick(X, Y: Integer);
begin
  FRightClicked := True;
  FRightX := X;
  FRightY := Y;
  MouseX := X;
  MouseY := Y;
end;

function TGWindow.TakeRightClick(out X, Y: Integer): Boolean;
begin
  Result := FRightClicked;
  X := FRightX;
  Y := FRightY;
  FRightClicked := False;
end;

function TGWindow.TakeWheel: Integer;
begin
  Result := FWheel;
  FWheel := 0;
end;

function TGWindow.TakeClick(out X, Y: Integer): Boolean;
begin
  Result := FClicked;
  X := FClickX;
  Y := FClickY;
  FClicked := False;
end;

procedure TGWindow.AddChar(C: Char);
begin
  if Length(FChars) < 256 then FChars := FChars + C;
end;

function TGWindow.TakeChars: string;
begin
  Result := FChars;
  FChars := '';
end;

function TGWindow.TakeFullscreenToggle: Boolean;
begin
  Result := FFullToggle;
  FFullToggle := False;
end;

function TGWindow.WasPressed(K: TGKey): Boolean;
begin
  Result := FPressed[K];
  FPressed[K] := False;
end;

{$IFDEF MSWINDOWS}

var
  ActiveWindow: TGWindow;
  LiveWindows: array of TGWindow;

{ declared here so that nil (back to the registry mode) can be passed }
function GwChangeDisplaySettings(DM: Pointer; Flags: DWORD): LongInt; stdcall;
  external 'user32.dll' name 'ChangeDisplaySettingsA';

function VKToKey(VK: WPARAM): TGKey;
begin
  case VK of
    VK_UP, Ord('I'): Result := gkUp;
    VK_LEFT, Ord('J'): Result := gkLeft;
    VK_DOWN, Ord('K'): Result := gkDown;
    VK_RIGHT, Ord('L'): Result := gkRight;
    Ord('A'): Result := gkAction;
    Ord('S'), VK_SPACE: Result := gkAttack;
    Ord('D'): Result := gkItem;
    Ord('M'): Result := gkMap;
    Ord('Q'): Result := gkItemList;
    VK_TAB: Result := gkChat;
    VK_ESCAPE: Result := gkEscape;
    VK_F4: Result := gkEditor;
    VK_F5: Result := gkLoadLevel;
    VK_DELETE: Result := gkDelete;
    VK_INSERT: Result := gkInsert;
  else
    Result := gkNone;
  end;
end;

procedure UpdateFormScroll(W: TGWindow; Wnd: HWND); forward;
procedure FormScroll(W: TGWindow; Wnd: HWND; Bar, Code: Integer); forward;

function WndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  W: TGWindow;
begin
  Result := 0;
  { each window answers for itself: a dialog over the start window must
    not take the start window's keys and clicks, nor leave it deaf once
    closed }
  W := TGWindow(GetWindowLongPtr(Wnd, GWLP_USERDATA));
  if W = nil then W := ActiveWindow;
  if W <> nil then
    case Msg of
      WM_KEYDOWN, WM_KEYUP:
        begin
          if WP = VK_CONTROL then W.CtrlHeld := Msg = WM_KEYDOWN;
          if WP = VK_SHIFT then W.ShiftHeld := Msg = WM_KEYDOWN;
          case WP of
            VK_UP: W.ArrowHeld[0] := Msg = WM_KEYDOWN;
            VK_LEFT: W.ArrowHeld[1] := Msg = WM_KEYDOWN;
            VK_DOWN: W.ArrowHeld[2] := Msg = WM_KEYDOWN;
            VK_RIGHT: W.ArrowHeld[3] := Msg = WM_KEYDOWN;
          end;
          W.SetKey(VKToKey(WP), Msg = WM_KEYDOWN);
          Exit;
        end;
      WM_SYSKEYDOWN:
        { Alt+Enter (bit 29: Alt held; bit 30: an auto-repeat) }
        if (WP = VK_RETURN) and ((LP and (1 shl 29)) <> 0) then
        begin
          if (LP and (1 shl 30)) = 0 then W.FFullToggle := True;
          Exit;
        end;
      WM_SYSCHAR:
        if WP = 13 then Exit; { no beep for Alt+Enter }
      WM_CHAR: begin W.AddChar(Chr(WP and $FF)); Exit; end;
      WM_LBUTTONDOWN:
        begin
          W.MouseLeft := True;
          W.AddClick(SmallInt(LP and $FFFF), SmallInt((LP shr 16) and $FFFF));
          SetCapture(Wnd);
          Exit;
        end;
      WM_LBUTTONUP:
        begin
          W.MouseLeft := False;
          if not W.MouseRight then ReleaseCapture;
          Exit;
        end;
      WM_RBUTTONDOWN:
        begin
          W.MouseRight := True;
          W.AddRightClick(SmallInt(LP and $FFFF), SmallInt((LP shr 16) and $FFFF));
          SetCapture(Wnd);
          Exit;
        end;
      WM_RBUTTONUP:
        begin
          W.MouseRight := False;
          if not W.MouseLeft then ReleaseCapture;
          Exit;
        end;
      WM_MOUSEWHEEL:
        begin
          if SmallInt((WP shr 16) and $FFFF) > 0 then Dec(W.FWheel)
          else Inc(W.FWheel);
          Exit;
        end;
      WM_MOUSEMOVE:
        begin
          W.MouseX := SmallInt(LP and $FFFF);
          W.MouseY := SmallInt((LP shr 16) and $FFFF);
          Exit;
        end;
      WM_CLOSE: begin W.Closed := True; Exit; end;
      { the frame covers the client: no erasing, and a paint (uncovering,
        restoring) shows the last frame again }
      WM_ERASEBKGND:
        if W.FLast <> nil then begin Result := 1; Exit; end;
      WM_PAINT:
        if W.FLast <> nil then
        begin
          ValidateRect(Wnd, nil);
          W.Present(W.FLast);
          Exit;
        end;
      WM_SYSCOMMAND:
        { minimising a form minimises the application, as Delphi's }
        if ((WP and $FFF0) = SC_MINIMIZE) and (W.FApp <> 0) then
        begin
          ShowWindow(W.FApp, SW_MINIMIZE);
          Exit;
        end;
      WM_SIZE:
        if ActiveWindow.FForm then UpdateFormScroll(ActiveWindow, Wnd);
      WM_HSCROLL, WM_VSCROLL:
        if ActiveWindow.FForm then
        begin
          if Msg = WM_HSCROLL then FormScroll(ActiveWindow, Wnd, SB_HORZ, WP and $FFFF)
          else FormScroll(ActiveWindow, Wnd, SB_VERT, WP and $FFFF);
          Exit;
        end;
    end;
  Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

constructor TGWindow.Create(const Title: string; AWidth, AHeight: Integer);
var
  WC: TWndClass;
  R: TRect;
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  { the program's MAINICON (its .rc), in the title bar and the taskbar;
    none: Windows' default }
  WC.hIcon := LoadIcon(HInstance, 'MAINICON');
  { what a larger (resized) window shows past the frame }
  WC.hbrBackground := GetStockObject(BLACK_BRUSH);
  WC.lpszClassName := 'TGraalWindow';
  Windows.RegisterClass(WC);
  R.Left := 0; R.Top := 0; R.Right := AWidth; R.Bottom := AHeight;
  AdjustWindowRect(R, WS_OVERLAPPEDWINDOW and not WS_THICKFRAME, False);
  FWnd := CreateWindow('TGraalWindow', PChar(Title),
    WS_OVERLAPPEDWINDOW and not WS_THICKFRAME, Integer(CW_USEDEFAULT), 0,
    R.Right - R.Left, R.Bottom - R.Top, 0, 0, HInstance, nil);
  SetWindowLongPtr(FWnd, GWLP_USERDATA, LONG_PTR(Self));
  SetLength(LiveWindows, Length(LiveWindows) + 1);
  LiveWindows[High(LiveWindows)] := Self;
  ActiveWindow := Self;
  ShowWindow(FWnd, SW_SHOW);
end;

destructor TGWindow.Destroy;
var
  I, J: Integer;
begin
  if FFullscreen then GwChangeDisplaySettings(nil, 0);
  { back to the newest window still open (a dialog's owner), if any }
  for I := High(LiveWindows) downto 0 do
    if LiveWindows[I] = Self then
    begin
      for J := I to High(LiveWindows) - 1 do LiveWindows[J] := LiveWindows[J + 1];
      SetLength(LiveWindows, Length(LiveWindows) - 1);
      Break;
    end;
  if ActiveWindow = Self then
    if Length(LiveWindows) > 0 then ActiveWindow := LiveWindows[High(LiveWindows)]
    else ActiveWindow := nil;
  FreeAndNil(FLast);
  if FWnd <> 0 then
  begin
    SetWindowLongPtr(FWnd, GWLP_USERDATA, 0);
    DestroyWindow(FWnd);
  end;
  if FApp <> 0 then DestroyWindow(FApp);
  inherited Destroy;
end;

function TGWindow.Ok: Boolean;
begin
  Result := FWnd <> 0;
end;

procedure TGWindow.Pump;
var
  M: TMsg;
begin
  while PeekMessage(M, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(M);
    DispatchMessage(M);
  end;
end;

procedure TGWindow.Reshape(const Title: string; AWidth, AHeight: Integer;
  Dialog: Boolean; MinBox: Boolean);
var
  R: TRect;
  W, H: Integer;
  Style, ExStyle: DWORD;
begin
  FTitle := Title;
  if FForm then
  begin
    FForm := False;
    FAutoScroll := False;
    ScrollX := 0;
    ScrollY := 0;
    UpdateFormScroll(Self, FWnd);
  end;
  SetWindowText(FWnd, PChar(Title));
  FWidth := AWidth;
  FHeight := AHeight;
  if FDelphi and Dialog then
  begin
    { bsDialog as Delphi 7 makes it: $96C80000 / $00000101 on the real
      2.22's start window and server list }
    Style := WS_POPUP or WS_VISIBLE or WS_CLIPSIBLINGS or WS_CLIPCHILDREN or
      WS_CAPTION or WS_SYSMENU;
    ExStyle := WS_EX_DLGMODALFRAME or WS_EX_WINDOWEDGE;
  end
  else if FDelphi then
  begin
    { bsSizeable: $16CF0000 / $00010110 on the real 2.22's game window,
      $00010100 once it has been fullscreen }
    Style := WS_VISIBLE or WS_CLIPSIBLINGS or WS_CLIPCHILDREN or WS_CAPTION or
      WS_SYSMENU or WS_THICKFRAME or WS_MINIMIZEBOX or WS_MAXIMIZEBOX;
    ExStyle := WS_EX_CONTROLPARENT or WS_EX_WINDOWEDGE;
    if not FWasFull then ExStyle := ExStyle or WS_EX_ACCEPTFILES;
    { the taskbar button (the application window) takes the game's title }
    if FApp <> 0 then SetWindowText(FApp, PChar(Title));
  end
  else if Dialog then
  begin
    { bsDialog: caption and close button only; the taskbar still shows
      the program }
    Style := WS_POPUP or WS_CAPTION or WS_SYSMENU or DS_MODALFRAME or WS_VISIBLE;
    ExStyle := WS_EX_DLGMODALFRAME or WS_EX_APPWINDOW;
  end
  else if MinBox then
  begin
    Style := WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX or WS_VISIBLE;
    ExStyle := WS_EX_APPWINDOW;
  end
  else
  begin
    Style := (WS_OVERLAPPEDWINDOW and not WS_THICKFRAME) or WS_VISIBLE;
    ExStyle := WS_EX_APPWINDOW;
  end;
  { a Delphi dialog's caption has no icon: drop the icons before the new
    frame is drawn, or Windows keeps a generic one in the caption }
  if FDelphi and Dialog then
  begin
    SendMessage(FWnd, WM_SETICON, ICON_BIG, 0);
    SendMessage(FWnd, WM_SETICON, ICON_SMALL, 0);
    SendMessage(FWnd, WM_SETICON, 2 { ICON_SMALL2 }, 0);
  end;
  SetWindowLong(FWnd, GWL_STYLE, LONG(Style));
  SetWindowLong(FWnd, GWL_EXSTYLE, LONG(ExStyle));
  R.Left := 0; R.Top := 0; R.Right := AWidth; R.Bottom := AHeight;
  AdjustWindowRectEx(R, Style, False, ExStyle);
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  SetWindowPos(FWnd, 0, (GetSystemMetrics(SM_CXSCREEN) - W) div 2,
    (GetSystemMetrics(SM_CYSCREEN) - H) div 2, W, H, SWP_NOZORDER or SWP_FRAMECHANGED);
  { the big icon for the taskbar and Alt+Tab, the small one for the
    caption }
  if Dialog then
  begin
    { a Delphi dialog's caption has no icon; redraw the frame without it }
    SendMessage(FWnd, WM_SETICON, ICON_BIG, 0);
    SendMessage(FWnd, WM_SETICON, ICON_SMALL, 0);
    SetWindowPos(FWnd, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_FRAMECHANGED);
  end
  else
  begin
    SendMessage(FWnd, WM_SETICON, ICON_BIG, LPARAM(LoadIcon(HInstance, 'MAINICON')));
    SendMessage(FWnd, WM_SETICON, ICON_SMALL, LPARAM(LoadIcon(HInstance, 'MAINICON')));
  end;
end;

function AppWndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
begin
  Result := 0;
  if ActiveWindow <> nil then
    case Msg of
      { the taskbar button brings the form forward, as TApplication }
      WM_ACTIVATE:
        if (LOWORD(WP) <> WA_INACTIVE) and (ActiveWindow.FWnd <> 0) and
          IsWindowEnabled(ActiveWindow.FWnd) then
        begin
          SetFocus(ActiveWindow.FWnd);
          Exit;
        end;
      WM_CLOSE: begin ActiveWindow.Closed := True; Exit; end;
    end;
  Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

procedure TGWindow.UseDelphiFrames(const AppTitle: string);
var
  WC: TWndClass;
begin
  if (FWnd = 0) or (FApp <> 0) then Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @AppWndProc;
  WC.hInstance := HInstance;
  WC.hIcon := LoadIcon(HInstance, 'MAINICON');
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.lpszClassName := 'TApplication';
  Windows.RegisterClass(WC);
  { TApplication.CreateHandle: a 0 x 0 window in the screen centre }
  FApp := CreateWindow('TApplication', PChar(AppTitle),
    WS_POPUP or WS_CAPTION or WS_CLIPSIBLINGS or WS_SYSMENU or WS_MINIMIZEBOX,
    GetSystemMetrics(SM_CXSCREEN) div 2, GetSystemMetrics(SM_CYSCREEN) div 2,
    0, 0, 0, 0, HInstance, nil);
  if FApp = 0 then Exit;
  SendMessage(FApp, WM_SETICON, ICON_BIG, LPARAM(WC.hIcon));
  SendMessage(FApp, WM_SETICON, ICON_SMALL, LPARAM(WC.hIcon));
  ShowWindow(FApp, SW_SHOWNORMAL);
  FDelphi := True;
  { the forms' class has no icon: a bsDialog caption shows none, the game
    window gets one with WM_SETICON (Reshape) }
  SetClassLong(FWnd, GCL_HICON, 0);
  SetClassLong(FWnd, -34 { GCL_HICONSM }, 0);
  { the form is owned by the application window: no button of its own }
  ShowWindow(FWnd, SW_HIDE);
  SetWindowLong(FWnd, GWL_HWNDPARENT, LONG(FApp));
  ShowWindow(FWnd, SW_SHOW);
end;

function TGWindow.EnterFullscreen(AWidth, AHeight: Integer): Boolean;
var
  DM: TDevMode;
begin
  Result := False;
  if (FWnd = 0) or FFullscreen then Exit;
  FillChar(DM, SizeOf(DM), 0);
  DM.dmSize := SizeOf(DM);
  DM.dmPelsWidth := AWidth;
  DM.dmPelsHeight := AHeight;
  DM.dmFields := DM_PELSWIDTH or DM_PELSHEIGHT;
  if GwChangeDisplaySettings(@DM, CDS_FULLSCREEN) <> DISP_CHANGE_SUCCESSFUL then Exit;
  FFullscreen := True;
  FWidth := AWidth;
  FHeight := AHeight;
  FWasFull := True;
  SetWindowLong(FWnd, GWL_STYLE, LONG(WS_POPUP or WS_VISIBLE));
  { $00010008 on the real 2.22 in fullscreen }
  if FDelphi then
    SetWindowLong(FWnd, GWL_EXSTYLE, LONG(WS_EX_CONTROLPARENT or WS_EX_TOPMOST))
  else
    SetWindowLong(FWnd, GWL_EXSTYLE, LONG(WS_EX_APPWINDOW or WS_EX_TOPMOST));
  SetWindowPos(FWnd, HWND_TOPMOST, 0, 0, AWidth, AHeight,
    SWP_FRAMECHANGED or SWP_SHOWWINDOW);
  SetForegroundWindow(FWnd);
  Result := True;
end;

procedure TGWindow.LeaveFullscreen(AWidth, AHeight: Integer);
begin
  if not FFullscreen then Exit;
  GwChangeDisplaySettings(nil, 0);
  FFullscreen := False;
  SetWindowPos(FWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
  Reshape(FTitle, AWidth, AHeight, False);
end;

procedure UpdateFormScroll(W: TGWindow; Wnd: HWND);
var
  SI: TScrollInfo;
  R: TRect;
  Bar: Integer;
begin
  { Delphi's AutoScroll: a bar for each way the design does not fit }
  GetClientRect(Wnd, R);
  W.FWidth := R.Right - R.Left;
  W.FHeight := R.Bottom - R.Top;
  for Bar := SB_HORZ to SB_VERT do
  begin
    FillChar(SI, SizeOf(SI), 0);
    SI.cbSize := SizeOf(SI);
    SI.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
    SI.nMin := 0;
    if W.FAutoScroll then
    begin
      if Bar = SB_HORZ then
      begin
        SI.nMax := W.FDesignW - 1;
        SI.nPage := W.FWidth;
        if W.ScrollX > W.FDesignW - W.FWidth then W.ScrollX := W.FDesignW - W.FWidth;
        if W.ScrollX < 0 then W.ScrollX := 0;
        SI.nPos := W.ScrollX;
      end
      else
      begin
        SI.nMax := W.FDesignH - 1;
        SI.nPage := W.FHeight;
        if W.ScrollY > W.FDesignH - W.FHeight then W.ScrollY := W.FDesignH - W.FHeight;
        if W.ScrollY < 0 then W.ScrollY := 0;
        SI.nPos := W.ScrollY;
      end;
    end;
    SetScrollInfo(Wnd, Bar, SI, True);
  end;
  GetClientRect(Wnd, R);
  W.FWidth := R.Right - R.Left;
  W.FHeight := R.Bottom - R.Top;
end;

procedure FormScroll(W: TGWindow; Wnd: HWND; Bar, Code: Integer);
var
  SI: TScrollInfo;
  P, Page, Max_: Integer;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_ALL;
  GetScrollInfo(Wnd, Bar, SI);
  P := SI.nPos;
  Page := Integer(SI.nPage);
  Max_ := SI.nMax - Page + 1;
  case Code of
    SB_LINEUP: Dec(P, 8);
    SB_LINEDOWN: Inc(P, 8);
    SB_PAGEUP: Dec(P, Page);
    SB_PAGEDOWN: Inc(P, Page);
    SB_THUMBTRACK, SB_THUMBPOSITION: P := SI.nTrackPos;
    SB_TOP: P := 0;
    SB_BOTTOM: P := Max_;
  end;
  if P > Max_ then P := Max_;
  if P < 0 then P := 0;
  if Bar = SB_HORZ then W.ScrollX := P else W.ScrollY := P;
  SI.fMask := SIF_POS;
  SI.nPos := P;
  SetScrollInfo(Wnd, Bar, SI, True);
end;

procedure TGWindow.ShowForm(const Title: string; OuterW, OuterH, DesignW, DesignH: Integer;
  AutoScroll: Boolean; FormColor: Cardinal);
var
  Style: DWORD;
begin
  { the game's last frame is not the form's: no repaint from it }
  FreeAndNil(FLast);
  FForm := True;
  FAutoScroll := AutoScroll;
  FDesignW := DesignW;
  FDesignH := DesignH;
  FFormColor := FormColor;
  ScrollX := 0;
  ScrollY := 0;
  SetWindowText(FWnd, PChar(Title));
  { TForm, bsSizeable, BorderIcons [biSystemMenu, biMinimize] }
  Style := WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_THICKFRAME or
    WS_MINIMIZEBOX or WS_VISIBLE;
  SetWindowLong(FWnd, GWL_STYLE, LONG(Style));
  SetWindowLong(FWnd, GWL_EXSTYLE, LONG(WS_EX_APPWINDOW));
  { poScreenCenter, at the outer size the form gives }
  SetWindowPos(FWnd, 0, (GetSystemMetrics(SM_CXSCREEN) - OuterW) div 2,
    (GetSystemMetrics(SM_CYSCREEN) - OuterH) div 2, OuterW, OuterH,
    SWP_NOZORDER or SWP_FRAMECHANGED);
  UpdateFormScroll(Self, FWnd);
  SendMessage(FWnd, WM_SETICON, ICON_BIG, LPARAM(LoadIcon(HInstance, 'MAINICON')));
  SendMessage(FWnd, WM_SETICON, ICON_SMALL, LPARAM(LoadIcon(HInstance, 'MAINICON')));
end;

procedure TGWindow.Present(Surface: TGSurface);
var
  BI: TBitmapInfo;
  DC: HDC;
  Br: HBRUSH;
  R: TRect;
  C: Cardinal;
begin
  if FForm then
  begin
    FillChar(BI, SizeOf(BI), 0);
    BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
    BI.bmiHeader.biWidth := Surface.Width;
    BI.bmiHeader.biHeight := -Surface.Height;
    BI.bmiHeader.biPlanes := 1;
    BI.bmiHeader.biBitCount := 32;
    BI.bmiHeader.biCompression := BI_RGB;
    DC := GetDC(FWnd);
    SetDIBitsToDevice(DC, -ScrollX, -ScrollY, Surface.Width, Surface.Height, 0, 0, 0,
      Surface.Height, @Surface.Pixels[0], BI, DIB_RGB_COLORS);
    { beyond the form's design: its colour (a larger window) }
    C := FFormColor;
    Br := CreateSolidBrush(((C shr 16) and $FF) or (C and $FF00) or ((C and $FF) shl 16));
    if Surface.Width - ScrollX < FWidth then
    begin
      R.Left := Surface.Width - ScrollX; R.Top := 0; R.Right := FWidth; R.Bottom := FHeight;
      Windows.FillRect(DC, R, Br);
    end;
    if Surface.Height - ScrollY < FHeight then
    begin
      R.Left := 0; R.Top := Surface.Height - ScrollY; R.Right := FWidth; R.Bottom := FHeight;
      Windows.FillRect(DC, R, Br);
    end;
    DeleteObject(Br);
    ReleaseDC(FWnd, DC);
    Exit;
  end;
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := Surface.Width;
  BI.bmiHeader.biHeight := -Surface.Height; { top-down }
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  { a copy of the frame for WM_PAINT (the game's own surface may be
    freed or resized before the next paint) }
  if Surface <> FLast then
  begin
    if FLast = nil then FLast := TGSurface.Create(Surface.Width, Surface.Height)
    else if (FLast.Width <> Surface.Width) or (FLast.Height <> Surface.Height) then
      FLast.SetSize(Surface.Width, Surface.Height);
    if Surface.Width * Surface.Height > 0 then
      Move(Surface.Pixels[0], FLast.Pixels[0], Surface.Width * Surface.Height * 4);
  end;
  if Surface.Width * Surface.Height = 0 then Exit;
  DC := GetDC(FWnd);
  StretchDIBits(DC, 0, 0, FWidth, FHeight, 0, 0, Surface.Width, Surface.Height,
    @Surface.Pixels[0], BI, DIB_RGB_COLORS, SRCCOPY);
  ReleaseDC(FWnd, DC);
end;

{$ENDIF}

{$IFDEF GW_NONE}{$IFNDEF GW_COCOA}

constructor TGWindow.Create(const Title: string; AWidth, AHeight: Integer);
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
end;

destructor TGWindow.Destroy;
begin
  inherited Destroy;
end;

function TGWindow.Ok: Boolean;
begin
  Result := False;
end;

procedure TGWindow.Pump;
begin
end;

procedure TGWindow.Present(Surface: TGSurface);
begin
end;

procedure TGWindow.UseDelphiFrames(const AppTitle: string);
begin
end;

function TGWindow.EnterFullscreen(AWidth, AHeight: Integer): Boolean;
begin
  Result := False;
end;

procedure TGWindow.LeaveFullscreen(AWidth, AHeight: Integer);
begin
end;


procedure TGWindow.ShowForm(const Title: string; OuterW, OuterH, DesignW, DesignH: Integer;
  AutoScroll: Boolean; FormColor: Cardinal);
begin
  FWidth := OuterW - 8;
  FHeight := OuterH - 34;
end;

procedure TGWindow.Reshape(const Title: string; AWidth, AHeight: Integer;
  Dialog: Boolean; MinBox: Boolean);
begin
  FWidth := AWidth;
  FHeight := AHeight;
end;

{$ENDIF}{$ENDIF}

{$IFDEF GW_COCOA}
{$I GWindowCocoa.inc}
{$ENDIF}

{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}

function KeySymToKey(K: TKeySym): TGKey;
begin
  case K of
    XK_Up, XK_i: Result := gkUp;
    XK_Left, XK_j: Result := gkLeft;
    XK_Down, XK_k: Result := gkDown;
    XK_Right, XK_l: Result := gkRight;
    XK_a: Result := gkAction;
    XK_s, XK_space: Result := gkAttack;
    XK_d: Result := gkItem;
    XK_m: Result := gkMap;
    XK_q: Result := gkItemList;
    XK_Tab: Result := gkChat;
    XK_Escape: Result := gkEscape;
    XK_F4: Result := gkEditor;
    XK_F5: Result := gkLoadLevel;
    XK_Delete, XK_KP_Delete: Result := gkDelete;
    XK_Insert, XK_KP_Insert: Result := gkInsert;
  else
    Result := gkNone;
  end;
end;

procedure TGWindow.SetArrow(Sym: Cardinal; Down: Boolean);
begin
  case Sym of
    XK_Up: ArrowHeld[0] := Down;
    XK_Left: ArrowHeld[1] := Down;
    XK_Down: ArrowHeld[2] := Down;
    XK_Right: ArrowHeld[3] := Down;
  end;
end;

constructor TGWindow.Create(const Title: string; AWidth, AHeight: Integer);
var
  D: PDisplay;
  Scr: cint;
  Hints: PXSizeHints;
  Supported: TBool;
  Atom: TAtom;
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  D := XOpenDisplay(nil);
  FDisplay := D;
  if D = nil then Exit;
  Scr := DefaultScreen(D);
  FWin := XCreateSimpleWindow(D, RootWindow(D, Scr), 0, 0, AWidth, AHeight, 0,
    BlackPixel(D, Scr), BlackPixel(D, Scr));
  XStoreName(D, FWin, PChar(Title));
  Hints := XAllocSizeHints;
  Hints^.flags := PMinSize or PMaxSize;
  Hints^.min_width := AWidth;
  Hints^.max_width := AWidth;
  Hints^.min_height := AHeight;
  Hints^.max_height := AHeight;
  XSetWMNormalHints(D, FWin, Hints);
  XFree(Hints);
  XSelectInput(D, FWin, KeyPressMask or KeyReleaseMask or ExposureMask or
    StructureNotifyMask or ButtonPressMask or ButtonReleaseMask or PointerMotionMask);
  Atom := XInternAtom(D, 'WM_DELETE_WINDOW', False);
  FWmDelete := Atom;
  XSetWMProtocols(D, FWin, @Atom, 1);
  { key repeat would send release/press pairs while a key is held }
  XkbSetDetectableAutoRepeat(D, True, @Supported);
  FGC := XCreateGC(D, FWin, 0, nil);
  GetMem(FImageBuf, AWidth * AHeight * 4);
  FImage := XCreateImage(D, DefaultVisual(D, Scr), 24, ZPixmap, 0, FImageBuf,
    AWidth, AHeight, 32, AWidth * 4);
  XMapWindow(D, FWin);
  XFlush(D);
end;

destructor TGWindow.Destroy;
var
  D: PDisplay;
begin
  D := FDisplay;
  if D <> nil then
  begin
    if FImage <> nil then
    begin
      PXImage(FImage)^.data := nil; { we free the buffer ourselves }
      XDestroyImage(FImage);
    end;
    if FImageBuf <> nil then FreeMem(FImageBuf);
    if FGC <> nil then XFreeGC(D, FGC);
    XDestroyWindow(D, FWin);
    XCloseDisplay(D);
  end;
  inherited Destroy;
end;

function TGWindow.Ok: Boolean;
begin
  Result := FDisplay <> nil;
end;

procedure TGWindow.Pump;
var
  D: PDisplay;
  E: TXEvent;
  Buf: array[0..15] of Char;
  N, I: Integer;
  Sym: TKeySym;
begin
  D := FDisplay;
  if D = nil then Exit;
  while XPending(D) > 0 do
  begin
    XNextEvent(D, @E);
    case E._type of
      KeyPress:
        begin
          Sym := XLookupKeysym(@E.xkey, 0);
          if (Sym = XK_Control_L) or (Sym = XK_Control_R) then CtrlHeld := True;
          if (Sym = XK_Shift_L) or (Sym = XK_Shift_R) then ShiftHeld := True;
          SetArrow(Sym, True);
          SetKey(KeySymToKey(Sym), True);
          if ((Sym = XK_Return) or (Sym = XK_KP_Enter)) and
            ((E.xkey.state and Mod1Mask) <> 0) then FFullToggle := True
          else if Sym = XK_BackSpace then AddChar(#8)
          else if (Sym = XK_Return) or (Sym = XK_KP_Enter) then AddChar(#13)
          else if Sym = XK_Tab then AddChar(#9)
          else if Sym = XK_Escape then AddChar(#27)
          else
          begin
            N := XLookupString(@E.xkey, @Buf[0], SizeOf(Buf), nil, nil);
            for I := 0 to N - 1 do
              if ((Buf[I] >= ' ') and (Buf[I] <= '~')) or
                ((Buf[I] >= #1) and (Buf[I] <= #26)) then AddChar(Buf[I]);
          end;
        end;
      ButtonPress:
        case E.xbutton.button of
          1: begin MouseLeft := True; AddClick(E.xbutton.x - FOffX, E.xbutton.y - FOffY); end;
          3: begin MouseRight := True; AddRightClick(E.xbutton.x - FOffX, E.xbutton.y - FOffY); end;
          4: Dec(FWheel);
          5: Inc(FWheel);
        end;
      ButtonRelease:
        case E.xbutton.button of
          1: MouseLeft := False;
          3: MouseRight := False;
        end;
      MotionNotify:
        begin
          MouseX := E.xmotion.x - FOffX;
          MouseY := E.xmotion.y - FOffY;
        end;
      KeyRelease:
        begin
          Sym := XLookupKeysym(@E.xkey, 0);
          if (Sym = XK_Control_L) or (Sym = XK_Control_R) then CtrlHeld := False;
          if (Sym = XK_Shift_L) or (Sym = XK_Shift_R) then ShiftHeld := False;
          SetArrow(Sym, False);
          SetKey(KeySymToKey(Sym), False);
        end;
      ClientMessage:
        if Cardinal(E.xclient.data.l[0]) = FWmDelete then Closed := True;
      DestroyNotify: Closed := True;
    end;
  end;
end;

procedure TGWindow.ShowForm(const Title: string; OuterW, OuterH, DesignW, DesignH: Integer;
  AutoScroll: Boolean; FormColor: Cardinal);
begin
  { the window managers here draw their own frames: the client is the
    form's design size (its outer size less a Windows 9x frame) }
  Reshape(Title, OuterW - 8, OuterH - 34, False, True);
end;

procedure TGWindow.Reshape(const Title: string; AWidth, AHeight: Integer;
  Dialog: Boolean; MinBox: Boolean);
type
  TMotifHints = record
    Flags, Functions, Decorations: culong;
    InputMode: clong;
    Status: culong;
  end;
var
  D: PDisplay;
  Hints: PXSizeHints;
  Scr: cint;
  MH: TMotifHints;
  A: TAtom;
begin
  D := FDisplay;
  if D = nil then Exit;
  FTitle := Title;
  XStoreName(D, FWin, PChar(Title));
  { _MOTIF_WM_HINTS: a dialog may only be moved and closed; the game may
    also be minimised }
  FillChar(MH, SizeOf(MH), 0);
  MH.Flags := 1 or 2; { functions, decorations }
  if Dialog then
  begin
    MH.Functions := 4 or 32;          { move, close }
    MH.Decorations := 2 or 8;         { border, title }
  end
  else
  begin
    MH.Functions := 4 or 8 or 32;     { move, minimise, close }
    MH.Decorations := 2 or 8 or 16 or 32;
  end;
  A := XInternAtom(D, '_MOTIF_WM_HINTS', False);
  XChangeProperty(D, FWin, A, A, 32, PropModeReplace, @MH, 5);
  if (AWidth <> FWidth) or (AHeight <> FHeight) then
  begin
    NewImage(AWidth, AHeight);
    Hints := XAllocSizeHints;
    Hints^.flags := PMinSize or PMaxSize;
    Hints^.min_width := AWidth;
    Hints^.max_width := AWidth;
    Hints^.min_height := AHeight;
    Hints^.max_height := AHeight;
    XSetWMNormalHints(D, FWin, Hints);
    XFree(Hints);
    XResizeWindow(D, FWin, AWidth, AHeight);
  end;
  { centred on the screen, as 2.22's forms (poScreenCenter) }
  Scr := DefaultScreen(D);
  XMoveWindow(D, FWin, (DisplayWidth(D, Scr) - AWidth) div 2,
    (DisplayHeight(D, Scr) - AHeight) div 2);
  XFlush(D);
end;

procedure TGWindow.UseDelphiFrames(const AppTitle: string);
begin
end;

procedure TGWindow.NewImage(AWidth, AHeight: Integer);
var
  D: PDisplay;
begin
  D := FDisplay;
  if FImage <> nil then
  begin
    PXImage(FImage)^.data := nil;
    XDestroyImage(FImage);
  end;
  if FImageBuf <> nil then FreeMem(FImageBuf);
  FWidth := AWidth;
  FHeight := AHeight;
  GetMem(FImageBuf, AWidth * AHeight * 4);
  FillChar(FImageBuf^, AWidth * AHeight * 4, 0);
  FImage := XCreateImage(D, DefaultVisual(D, DefaultScreen(D)), 24, ZPixmap, 0,
    FImageBuf, AWidth, AHeight, 32, AWidth * 4);
end;

{ _NET_WM_STATE_FULLSCREEN on or off, for a window manager that has it }
procedure SendFullscreenState(D: PDisplay; Win: TWindow; On: Boolean);
var
  E: TXEvent;
begin
  FillChar(E, SizeOf(E), 0);
  E.xclient._type := ClientMessage;
  E.xclient.window := Win;
  E.xclient.message_type := XInternAtom(D, '_NET_WM_STATE', False);
  E.xclient.format := 32;
  E.xclient.data.l[0] := Ord(On); { 1 add, 0 remove }
  E.xclient.data.l[1] := XInternAtom(D, '_NET_WM_STATE_FULLSCREEN', False);
  E.xclient.data.l[3] := 1;
  XSendEvent(D, RootWindow(D, DefaultScreen(D)), False,
    SubstructureRedirectMask or SubstructureNotifyMask, @E);
end;

function TGWindow.EnterFullscreen(AWidth, AHeight: Integer): Boolean;
type
  TMotifHints = record
    Flags, Functions, Decorations: culong;
    InputMode: clong;
    Status: culong;
  end;
var
  D: PDisplay;
  Scr: cint;
  DW, DH: Integer;
  Hints: PXSizeHints;
  MH: TMotifHints;
  A: TAtom;
begin
  Result := False;
  D := FDisplay;
  if (D = nil) or FFullscreen then Exit;
  Scr := DefaultScreen(D);
  DW := DisplayWidth(D, Scr);
  DH := DisplayHeight(D, Scr);
  if (DW < AWidth) or (DH < AHeight) then Exit;
  FFullscreen := True;
  NewImage(AWidth, AHeight);
  FOffX := (DW - AWidth) div 2;
  FOffY := (DH - AHeight) div 2;
  FillChar(MH, SizeOf(MH), 0);
  MH.Flags := 2; { decorations: none }
  A := XInternAtom(D, '_MOTIF_WM_HINTS', False);
  XChangeProperty(D, FWin, A, A, 32, PropModeReplace, @MH, 5);
  Hints := XAllocSizeHints;
  Hints^.flags := 0;
  XSetWMNormalHints(D, FWin, Hints);
  XFree(Hints);
  XMoveResizeWindow(D, FWin, 0, 0, DW, DH);
  SendFullscreenState(D, FWin, True);
  XRaiseWindow(D, FWin);
  XClearWindow(D, FWin);
  XFlush(D);
  Result := True;
end;

procedure TGWindow.LeaveFullscreen(AWidth, AHeight: Integer);
var
  D: PDisplay;
begin
  D := FDisplay;
  if (D = nil) or not FFullscreen then Exit;
  FFullscreen := False;
  FOffX := 0;
  FOffY := 0;
  SendFullscreenState(D, FWin, False);
  FWidth := -1; { Reshape makes a new image and sets the size again }
  Reshape(FTitle, AWidth, AHeight, False);
end;

procedure TGWindow.Present(Surface: TGSurface);
var
  D: PDisplay;
  N: Integer;
begin
  D := FDisplay;
  if (D = nil) or (FImage = nil) then Exit;
  N := Surface.Width * Surface.Height;
  if N > FWidth * FHeight then N := FWidth * FHeight;
  if N > 0 then Move(Surface.Pixels[0], FImageBuf^, N * 4);
  XPutImage(D, FWin, FGC, FImage, 0, 0, FOffX, FOffY, FWidth, FHeight);
  XFlush(D);
end;

{$ENDIF}{$ENDIF}

end.
