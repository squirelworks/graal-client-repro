{ GWindow: a plain window that shows a TGSurface and reports keys.

  Stands in for the DelphiX TDXForm of the originals. Back ends:
    Windows   GDI (StretchDIBits), the same API under Delphi and Free Pascal
    Unix      X11 through Free Pascal's xlib units (XPutImage)
    macOS     none yet: Ok is False, so the client runs headless or writes
              frames with --dump (a Cocoa back end is still to come)
  The window shows the surface 1:1 and keeps a held-key table that the game
  tick reads, which is how DelphiX's DXInput was used. }
unit GWindow;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF DARWIN}{$DEFINE GW_NONE}{$ENDIF}

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
{$ENDIF}
{$IFDEF GW_NONE}
{$ELSE}{$IFNDEF MSWINDOWS}
    FDisplay: Pointer;
    FWin: Cardinal;
    FGC: Pointer;
    FImage: Pointer;
    FImageBuf: Pointer;
    FWmDelete: Cardinal;
{$ENDIF}{$ENDIF}
    FWidth, FHeight: Integer;
    FPressed: array[TGKey] of Boolean; { pressed since the last tick }
    FClicked: Boolean;
    FClickX, FClickY: Integer;
    FRightClicked: Boolean;
    FRightX, FRightY: Integer;
    FWheel: Integer;
    FChars: string;
    { Alt+Enter fullscreen: on, the size and place the picture is shown
      at inside the window (FWidth x FHeight scaled), and the window's own
      size }
    FFull: Boolean;
    FOffX, FOffY, FShowW, FShowH, FWinW, FWinH: Integer;
{$IFDEF MSWINDOWS}
    FSavedStyle, FSavedExStyle: LongInt;
    FSavedL, FSavedT, FSavedR, FSavedB: Integer;
{$ENDIF}
{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}
    FBigImage: Pointer;
    FBigBuf: Pointer;
    FBigScale: Integer;
{$ENDIF}{$ENDIF}
    { window pixels to picture pixels (the same unless fullscreen) }
    procedure MapPoint(var X, Y: Integer);
    procedure AddClick(X, Y: Integer);
    procedure AddRightClick(X, Y: Integer);
{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}
    procedure SetArrow(Sym: Cardinal; Down: Boolean);
{$ENDIF}{$ENDIF}
  public
    MouseX, MouseY: Integer;
    { Mouse buttons held now, and the Ctrl / Shift keys (for the editor). }
    MouseLeft, MouseRight: Boolean;
    CtrlHeld, ShiftHeld: Boolean;
    { The arrow keys alone (up, left, down, right), without the I J K L
      letters that also walk, so the editor can scroll with them. }
    ArrowHeld: array[0..3] of Boolean;
    Held: array[TGKey] of Boolean;
    Closed: Boolean;
    { Alt+Enter switches between the window and fullscreen, as the
      DelphiX clients (2.31 and on) do; off unless a build sets it. In
      fullscreen the picture is scaled up to the screen, keeping its
      shape, with black bars. }
    AllowFullscreen: Boolean;
    procedure ToggleFullscreen;
    property Fullscreen: Boolean read FFull;
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
    procedure Reshape(const Title: string; AWidth, AHeight: Integer;
      Dialog: Boolean = False);
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

procedure TGWindow.MapPoint(var X, Y: Integer);
begin
  if not FFull or (FShowW <= 0) or (FShowH <= 0) then Exit;
  X := (X - FOffX) * FWidth div FShowW;
  Y := (Y - FOffY) * FHeight div FShowH;
end;

procedure TGWindow.AddClick(X, Y: Integer);
begin
  MapPoint(X, Y);
  FClicked := True;
  FClickX := X;
  FClickY := Y;
  MouseX := X;
  MouseY := Y;
end;

procedure TGWindow.AddRightClick(X, Y: Integer);
begin
  MapPoint(X, Y);
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

function TGWindow.WasPressed(K: TGKey): Boolean;
begin
  Result := FPressed[K];
  FPressed[K] := False;
end;

{$IFDEF MSWINDOWS}

var
  ActiveWindow: TGWindow;

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

function WndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
begin
  Result := 0;
  if ActiveWindow <> nil then
    case Msg of
      WM_KEYDOWN, WM_KEYUP:
        begin
          if WP = VK_CONTROL then ActiveWindow.CtrlHeld := Msg = WM_KEYDOWN;
          if WP = VK_SHIFT then ActiveWindow.ShiftHeld := Msg = WM_KEYDOWN;
          case WP of
            VK_UP: ActiveWindow.ArrowHeld[0] := Msg = WM_KEYDOWN;
            VK_LEFT: ActiveWindow.ArrowHeld[1] := Msg = WM_KEYDOWN;
            VK_DOWN: ActiveWindow.ArrowHeld[2] := Msg = WM_KEYDOWN;
            VK_RIGHT: ActiveWindow.ArrowHeld[3] := Msg = WM_KEYDOWN;
          end;
          ActiveWindow.SetKey(VKToKey(WP), Msg = WM_KEYDOWN);
          Exit;
        end;
      WM_CHAR: begin ActiveWindow.AddChar(Chr(WP and $FF)); Exit; end;
      WM_SYSKEYDOWN:
        if (WP = VK_RETURN) and ActiveWindow.AllowFullscreen then
        begin
          ActiveWindow.ToggleFullscreen;
          Exit;
        end;
      WM_SYSCHAR:
        { no beep for Alt+Enter }
        if (WP = 13) and ActiveWindow.AllowFullscreen then Exit;
      WM_LBUTTONDOWN:
        begin
          ActiveWindow.MouseLeft := True;
          ActiveWindow.AddClick(SmallInt(LP and $FFFF), SmallInt((LP shr 16) and $FFFF));
          SetCapture(Wnd);
          Exit;
        end;
      WM_LBUTTONUP:
        begin
          ActiveWindow.MouseLeft := False;
          if not ActiveWindow.MouseRight then ReleaseCapture;
          Exit;
        end;
      WM_RBUTTONDOWN:
        begin
          ActiveWindow.MouseRight := True;
          ActiveWindow.AddRightClick(SmallInt(LP and $FFFF), SmallInt((LP shr 16) and $FFFF));
          SetCapture(Wnd);
          Exit;
        end;
      WM_RBUTTONUP:
        begin
          ActiveWindow.MouseRight := False;
          if not ActiveWindow.MouseLeft then ReleaseCapture;
          Exit;
        end;
      WM_MOUSEWHEEL:
        begin
          if SmallInt((WP shr 16) and $FFFF) > 0 then Dec(ActiveWindow.FWheel)
          else Inc(ActiveWindow.FWheel);
          Exit;
        end;
      WM_MOUSEMOVE:
        begin
          ActiveWindow.MouseX := SmallInt(LP and $FFFF);
          ActiveWindow.MouseY := SmallInt((LP shr 16) and $FFFF);
          ActiveWindow.MapPoint(ActiveWindow.MouseX, ActiveWindow.MouseY);
          Exit;
        end;
      WM_CLOSE: begin ActiveWindow.Closed := True; Exit; end;
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
  WC.lpszClassName := 'TGraalWindow';
  Windows.RegisterClass(WC);
  R.Left := 0; R.Top := 0; R.Right := AWidth; R.Bottom := AHeight;
  AdjustWindowRect(R, WS_OVERLAPPEDWINDOW and not WS_THICKFRAME, False);
  FWnd := CreateWindow('TGraalWindow', PChar(Title),
    WS_OVERLAPPEDWINDOW and not WS_THICKFRAME, Integer(CW_USEDEFAULT), 0,
    R.Right - R.Left, R.Bottom - R.Top, 0, 0, HInstance, nil);
  ActiveWindow := Self;
  ShowWindow(FWnd, SW_SHOW);
end;

destructor TGWindow.Destroy;
begin
  if FWnd <> 0 then DestroyWindow(FWnd);
  ActiveWindow := nil;
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
  Dialog: Boolean);
var
  R: TRect;
  W, H: Integer;
  Style, ExStyle: DWORD;
begin
  if FFull then ToggleFullscreen;
  SetWindowText(FWnd, PChar(Title));
  FWidth := AWidth;
  FHeight := AHeight;
  if Dialog then
  begin
    { bsDialog: caption and close button only; the taskbar still shows
      the program }
    Style := WS_POPUP or WS_CAPTION or WS_SYSMENU or DS_MODALFRAME or WS_VISIBLE;
    ExStyle := WS_EX_DLGMODALFRAME or WS_EX_APPWINDOW;
  end
  else
  begin
    Style := (WS_OVERLAPPEDWINDOW and not WS_THICKFRAME) or WS_VISIBLE;
    ExStyle := WS_EX_APPWINDOW;
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
  SendMessage(FWnd, WM_SETICON, ICON_BIG, LPARAM(LoadIcon(HInstance, 'MAINICON')));
  SendMessage(FWnd, WM_SETICON, ICON_SMALL, LPARAM(LoadIcon(HInstance, 'MAINICON')));
end;

procedure TGWindow.ToggleFullscreen;
var
  W, H: Integer;
  R: TRect;
begin
  if FWnd = 0 then Exit;
  if not FFull then
  begin
    FSavedStyle := GetWindowLong(FWnd, GWL_STYLE);
    FSavedExStyle := GetWindowLong(FWnd, GWL_EXSTYLE);
    GetWindowRect(FWnd, R);
    FSavedL := R.Left;
    FSavedT := R.Top;
    FSavedR := R.Right;
    FSavedB := R.Bottom;
    W := GetSystemMetrics(SM_CXSCREEN);
    H := GetSystemMetrics(SM_CYSCREEN);
    SetWindowLong(FWnd, GWL_STYLE, LONG(WS_POPUP or WS_VISIBLE));
    SetWindowLong(FWnd, GWL_EXSTYLE, LONG(WS_EX_APPWINDOW));
    SetWindowPos(FWnd, HWND_TOP, 0, 0, W, H, SWP_FRAMECHANGED or SWP_SHOWWINDOW);
    FWinW := W;
    FWinH := H;
    FFull := True;
  end
  else
  begin
    FFull := False;
    SetWindowLong(FWnd, GWL_STYLE, FSavedStyle);
    SetWindowLong(FWnd, GWL_EXSTYLE, FSavedExStyle);
    SetWindowPos(FWnd, HWND_NOTOPMOST, FSavedL, FSavedT, FSavedR - FSavedL, FSavedB - FSavedT,
      SWP_FRAMECHANGED or SWP_SHOWWINDOW);
  end;
  InvalidateRect(FWnd, nil, True);
end;

procedure TGWindow.Present(Surface: TGSurface);
var
  BI: TBitmapInfo;
  DC: HDC;
  R: TRect;
begin
  if FFull then
  begin
    { the largest size of the picture's shape that fits the screen }
    if FWinW * FHeight <= FWinH * FWidth then
    begin
      FShowW := FWinW;
      FShowH := FWinW * FHeight div FWidth;
    end
    else
    begin
      FShowH := FWinH;
      FShowW := FWinH * FWidth div FHeight;
    end;
    FOffX := (FWinW - FShowW) div 2;
    FOffY := (FWinH - FShowH) div 2;
  end;
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := Surface.Width;
  BI.bmiHeader.biHeight := -Surface.Height; { top-down }
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  DC := GetDC(FWnd);
  if FFull then
  begin
    { black bars round the picture }
    R.Left := 0; R.Top := 0; R.Right := FWinW; R.Bottom := FOffY;
    FillRect(DC, R, HBRUSH(GetStockObject(BLACK_BRUSH)));
    R.Top := FOffY + FShowH; R.Bottom := FWinH;
    FillRect(DC, R, HBRUSH(GetStockObject(BLACK_BRUSH)));
    R.Top := 0; R.Right := FOffX;
    FillRect(DC, R, HBRUSH(GetStockObject(BLACK_BRUSH)));
    R.Left := FOffX + FShowW; R.Right := FWinW;
    FillRect(DC, R, HBRUSH(GetStockObject(BLACK_BRUSH)));
    SetStretchBltMode(DC, COLORONCOLOR);
    StretchDIBits(DC, FOffX, FOffY, FShowW, FShowH, 0, 0, Surface.Width, Surface.Height,
      @Surface.Pixels[0], BI, DIB_RGB_COLORS, SRCCOPY);
  end
  else
    StretchDIBits(DC, 0, 0, FWidth, FHeight, 0, 0, Surface.Width, Surface.Height,
      @Surface.Pixels[0], BI, DIB_RGB_COLORS, SRCCOPY);
  ReleaseDC(FWnd, DC);
end;

{$ENDIF}

{$IFDEF GW_NONE}

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

procedure TGWindow.Reshape(const Title: string; AWidth, AHeight: Integer;
  Dialog: Boolean);
begin
  FWidth := AWidth;
  FHeight := AHeight;
end;

procedure TGWindow.ToggleFullscreen;
begin
end;

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
    if FBigImage <> nil then
    begin
      PXImage(FBigImage)^.data := nil;
      XDestroyImage(FBigImage);
      FreeMem(FBigBuf);
    end;
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
          if ((Sym = XK_Return) or (Sym = XK_KP_Enter)) and
            (E.xkey.state and Mod1Mask <> 0) and AllowFullscreen then
          begin
            ToggleFullscreen;
            Continue;
          end;
          SetArrow(Sym, True);
          SetKey(KeySymToKey(Sym), True);
          if Sym = XK_BackSpace then AddChar(#8)
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
          1: begin MouseLeft := True; AddClick(E.xbutton.x, E.xbutton.y); end;
          3: begin MouseRight := True; AddRightClick(E.xbutton.x, E.xbutton.y); end;
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
          MouseX := E.xmotion.x;
          MouseY := E.xmotion.y;
          MapPoint(MouseX, MouseY);
        end;
      ConfigureNotify:
        begin
          FWinW := E.xconfigure.width;
          FWinH := E.xconfigure.height;
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

procedure TGWindow.Reshape(const Title: string; AWidth, AHeight: Integer;
  Dialog: Boolean);
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
  if FFull then ToggleFullscreen;
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
    Scr := DefaultScreen(D);
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
    FImage := XCreateImage(D, DefaultVisual(D, Scr), 24, ZPixmap, 0, FImageBuf,
      AWidth, AHeight, 32, AWidth * 4);
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

{ _NET_WM_STATE_FULLSCREEN through the window manager; the size limits
  are lifted while it is on }
procedure TGWindow.ToggleFullscreen;
var
  D: PDisplay;
  E: TXEvent;
  Hints: PXSizeHints;
  Scr: cint;
begin
  D := FDisplay;
  if D = nil then Exit;
  Scr := DefaultScreen(D);
  FFull := not FFull;
  Hints := XAllocSizeHints;
  if FFull then
    Hints^.flags := 0
  else
  begin
    Hints^.flags := PMinSize or PMaxSize;
    Hints^.min_width := FWidth;
    Hints^.max_width := FWidth;
    Hints^.min_height := FHeight;
    Hints^.max_height := FHeight;
  end;
  XSetWMNormalHints(D, FWin, Hints);
  XFree(Hints);
  FillChar(E, SizeOf(E), 0);
  E.xclient._type := ClientMessage;
  E.xclient.window := FWin;
  E.xclient.message_type := XInternAtom(D, '_NET_WM_STATE', False);
  E.xclient.format := 32;
  if FFull then E.xclient.data.l[0] := 1 else E.xclient.data.l[0] := 0;
  E.xclient.data.l[1] := clong(XInternAtom(D, '_NET_WM_STATE_FULLSCREEN', False));
  E.xclient.data.l[3] := 1;
  XSendEvent(D, RootWindow(D, Scr), False, SubstructureRedirectMask or
    SubstructureNotifyMask, @E);
  if FFull then
  begin
    FWinW := DisplayWidth(D, Scr);
    FWinH := DisplayHeight(D, Scr);
  end
  else
  begin
    FWinW := FWidth;
    FWinH := FHeight;
  end;
  XClearWindow(D, FWin);
  XFlush(D);
end;

procedure TGWindow.Present(Surface: TGSurface);
var
  D: PDisplay;
  N, K, X, Y, I: Integer;
  Src, Dst: PCardinal;
begin
  D := FDisplay;
  if (D = nil) or (FImage = nil) then Exit;
  if FFull and (FWinW > 0) and (FWinH > 0) then
  begin
    { a whole-number scale (nearest pixels), centred }
    K := FWinW div FWidth;
    if FWinH div FHeight < K then K := FWinH div FHeight;
    if K < 1 then K := 1;
    if (FBigImage = nil) or (K <> FBigScale) then
    begin
      if FBigImage <> nil then
      begin
        PXImage(FBigImage)^.data := nil;
        XDestroyImage(FBigImage);
        FreeMem(FBigBuf);
      end;
      FBigScale := K;
      GetMem(FBigBuf, FWidth * K * FHeight * K * 4);
      FBigImage := XCreateImage(D, DefaultVisual(D, DefaultScreen(D)), 24, ZPixmap, 0,
        FBigBuf, FWidth * K, FHeight * K, 32, FWidth * K * 4);
    end;
    FShowW := FWidth * K;
    FShowH := FHeight * K;
    FOffX := (FWinW - FShowW) div 2;
    FOffY := (FWinH - FShowH) div 2;
    if (Surface.Width = FWidth) and (Surface.Height >= FHeight) then
    begin
      Dst := FBigBuf;
      for Y := 0 to FShowH - 1 do
      begin
        Src := @Surface.Pixels[(Y div K) * FWidth];
        for X := 0 to FShowW - 1 do
        begin
          I := X div K;
          Dst^ := PCardinal(PAnsiChar(Src) + I * 4)^;
          Inc(Dst);
        end;
      end;
    end;
    XPutImage(D, FWin, FGC, FBigImage, 0, 0, FOffX, FOffY, FShowW, FShowH);
    XFlush(D);
    Exit;
  end;
  N := Surface.Width * Surface.Height;
  if N > FWidth * FHeight then N := FWidth * FHeight;
  if N > 0 then Move(Surface.Pixels[0], FImageBuf^, N * 4);
  XPutImage(D, FWin, FGC, FImage, 0, 0, 0, 0, FWidth, FHeight);
  XFlush(D);
end;

{$ENDIF}{$ENDIF}

end.
