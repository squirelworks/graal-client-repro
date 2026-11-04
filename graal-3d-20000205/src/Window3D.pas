{ Window3D: the Graal3D window, keys and mouse.

  Graal3D walks with the numeric keypad (8 / 2 forward and back, 4 / 6
  step sideways, 5 jump, 0 camera follow), which the 2D builds' common
  GWindow does not read, so this build keeps its own copy of that unit
  with Graal3D's key table. The drawing side is the same: GDI on Windows,
  X11 elsewhere, nothing on macOS (the client then runs headless or with
  --dump). The arrow keys walk as well: they are what the keypad sends
  with Num Lock off. }
unit Window3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF DARWIN}{$DEFINE GW_NONE}{$ENDIF}

interface

uses
  GSurface;

type
  TKey3D = (k3None, k3Fwd, k3Back, k3Left, k3Right, k3Jump, k3Camera,
    k3Enter, k3Escape, k3F1, k3F2);

  TWindow3D = class
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
    FPressed: array[TKey3D] of Boolean;
    FClicked: Boolean;
    FClickX, FClickY: Integer;
    FChars: string;
  public
    Held: array[TKey3D] of Boolean;
    CtrlHeld: Boolean;
    Closed: Boolean;
    constructor Create(const Title: string; AWidth, AHeight: Integer);
    destructor Destroy; override;
    function Ok: Boolean;
    procedure Pump;
    procedure Present(Surface: TGSurface);
    procedure SetKey(K: TKey3D; Down: Boolean);
    { True once for each press since the last call. }
    function WasPressed(K: TKey3D): Boolean;
    procedure AddClick(X, Y: Integer);
    function TakeClick(out X, Y: Integer): Boolean;
    { Typed characters: printable ones, #8 backspace, #9 tab, #13 enter,
      #27 escape. }
    procedure AddChar(C: Char);
    function TakeChars: string;
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

procedure TWindow3D.SetKey(K: TKey3D; Down: Boolean);
begin
  if K = k3None then Exit;
  if Down and not Held[K] then FPressed[K] := True;
  Held[K] := Down;
end;

function TWindow3D.WasPressed(K: TKey3D): Boolean;
begin
  Result := FPressed[K];
  FPressed[K] := False;
end;

procedure TWindow3D.AddClick(X, Y: Integer);
begin
  FClicked := True;
  FClickX := X;
  FClickY := Y;
end;

function TWindow3D.TakeClick(out X, Y: Integer): Boolean;
begin
  Result := FClicked;
  X := FClickX;
  Y := FClickY;
  FClicked := False;
end;

procedure TWindow3D.AddChar(C: Char);
begin
  if Length(FChars) < 256 then FChars := FChars + C;
end;

function TWindow3D.TakeChars: string;
begin
  Result := FChars;
  FChars := '';
end;

{$IFDEF MSWINDOWS}

var
  ActiveWindow: TWindow3D;

function VKToKey(VK: WPARAM): TKey3D;
begin
  case VK of
    VK_NUMPAD8, VK_UP: Result := k3Fwd;
    VK_NUMPAD2, VK_DOWN: Result := k3Back;
    VK_NUMPAD4, VK_LEFT: Result := k3Left;
    VK_NUMPAD6, VK_RIGHT: Result := k3Right;
    VK_NUMPAD5, VK_CLEAR: Result := k3Jump;
    VK_NUMPAD0, VK_INSERT: Result := k3Camera;
    VK_RETURN: Result := k3Enter;
    VK_ESCAPE: Result := k3Escape;
    VK_F1: Result := k3F1;
    VK_F2: Result := k3F2;
  else
    Result := k3None;
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
          ActiveWindow.SetKey(VKToKey(WP), Msg = WM_KEYDOWN);
          Exit;
        end;
      WM_CHAR: begin ActiveWindow.AddChar(Chr(WP and $FF)); Exit; end;
      WM_LBUTTONDOWN:
        begin
          ActiveWindow.AddClick(SmallInt(LP and $FFFF), SmallInt((LP shr 16) and $FFFF));
          Exit;
        end;
      WM_CLOSE: begin ActiveWindow.Closed := True; Exit; end;
    end;
  Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

constructor TWindow3D.Create(const Title: string; AWidth, AHeight: Integer);
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
  WC.lpszClassName := 'TGraal3DWindow';
  Windows.RegisterClass(WC);
  R.Left := 0; R.Top := 0; R.Right := AWidth; R.Bottom := AHeight;
  AdjustWindowRect(R, WS_OVERLAPPEDWINDOW and not WS_THICKFRAME, False);
  FWnd := CreateWindow('TGraal3DWindow', PChar(Title),
    WS_OVERLAPPEDWINDOW and not WS_THICKFRAME, Integer(CW_USEDEFAULT), 0,
    R.Right - R.Left, R.Bottom - R.Top, 0, 0, HInstance, nil);
  ActiveWindow := Self;
  ShowWindow(FWnd, SW_SHOW);
end;

destructor TWindow3D.Destroy;
begin
  if FWnd <> 0 then DestroyWindow(FWnd);
  ActiveWindow := nil;
  inherited Destroy;
end;

function TWindow3D.Ok: Boolean;
begin
  Result := FWnd <> 0;
end;

procedure TWindow3D.Pump;
var
  M: TMsg;
begin
  while PeekMessage(M, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(M);
    DispatchMessage(M);
  end;
end;

procedure TWindow3D.Present(Surface: TGSurface);
var
  BI: TBitmapInfo;
  DC: HDC;
begin
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := Surface.Width;
  BI.bmiHeader.biHeight := -Surface.Height; { top-down }
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  DC := GetDC(FWnd);
  StretchDIBits(DC, 0, 0, FWidth, FHeight, 0, 0, Surface.Width, Surface.Height,
    @Surface.Pixels[0], BI, DIB_RGB_COLORS, SRCCOPY);
  ReleaseDC(FWnd, DC);
end;

{$ENDIF}

{$IFDEF GW_NONE}

constructor TWindow3D.Create(const Title: string; AWidth, AHeight: Integer);
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
end;

destructor TWindow3D.Destroy;
begin
  inherited Destroy;
end;

function TWindow3D.Ok: Boolean;
begin
  Result := False;
end;

procedure TWindow3D.Pump;
begin
end;

procedure TWindow3D.Present(Surface: TGSurface);
begin
end;

{$ENDIF}

{$IFNDEF MSWINDOWS}{$IFNDEF GW_NONE}

function KeySymToKey(K: TKeySym): TKey3D;
begin
  case K of
    XK_KP_8, XK_KP_Up, XK_Up: Result := k3Fwd;
    XK_KP_2, XK_KP_Down, XK_Down: Result := k3Back;
    XK_KP_4, XK_KP_Left, XK_Left: Result := k3Left;
    XK_KP_6, XK_KP_Right, XK_Right: Result := k3Right;
    XK_KP_5, XK_KP_Begin: Result := k3Jump;
    XK_KP_0, XK_KP_Insert: Result := k3Camera;
    XK_Return, XK_KP_Enter: Result := k3Enter;
    XK_Escape: Result := k3Escape;
    XK_F1: Result := k3F1;
    XK_F2: Result := k3F2;
  else
    Result := k3None;
  end;
end;

constructor TWindow3D.Create(const Title: string; AWidth, AHeight: Integer);
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
    StructureNotifyMask or ButtonPressMask);
  Atom := XInternAtom(D, 'WM_DELETE_WINDOW', False);
  FWmDelete := Atom;
  XSetWMProtocols(D, FWin, @Atom, 1);
  XkbSetDetectableAutoRepeat(D, True, @Supported);
  FGC := XCreateGC(D, FWin, 0, nil);
  GetMem(FImageBuf, AWidth * AHeight * 4);
  FImage := XCreateImage(D, DefaultVisual(D, Scr), 24, ZPixmap, 0, FImageBuf,
    AWidth, AHeight, 32, AWidth * 4);
  XMapWindow(D, FWin);
  XFlush(D);
end;

destructor TWindow3D.Destroy;
var
  D: PDisplay;
begin
  D := FDisplay;
  if D <> nil then
  begin
    if FImage <> nil then
    begin
      PXImage(FImage)^.data := nil;
      XDestroyImage(FImage);
    end;
    if FImageBuf <> nil then FreeMem(FImageBuf);
    if FGC <> nil then XFreeGC(D, FGC);
    XDestroyWindow(D, FWin);
    XCloseDisplay(D);
  end;
  inherited Destroy;
end;

function TWindow3D.Ok: Boolean;
begin
  Result := FDisplay <> nil;
end;

procedure TWindow3D.Pump;
var
  D: PDisplay;
  E: TXEvent;
  Buf: array[0..15] of Char;
  N, I: Integer;
  Sym, Sym1: TKeySym;
begin
  D := FDisplay;
  if D = nil then Exit;
  while XPending(D) > 0 do
  begin
    XNextEvent(D, @E);
    case E._type of
      KeyPress, KeyRelease:
        begin
          Sym := XLookupKeysym(@E.xkey, 0);
          { the keypad's second level holds KP_0..KP_9 }
          Sym1 := XLookupKeysym(@E.xkey, 1);
          if (Sym = XK_Control_L) or (Sym = XK_Control_R) then
            CtrlHeld := E._type = KeyPress;
          if KeySymToKey(Sym) <> k3None then
            SetKey(KeySymToKey(Sym), E._type = KeyPress)
          else
            SetKey(KeySymToKey(Sym1), E._type = KeyPress);
          if E._type = KeyPress then
          begin
            if Sym = XK_BackSpace then AddChar(#8)
            else if (Sym = XK_Return) or (Sym = XK_KP_Enter) then AddChar(#13)
            else if Sym = XK_Tab then AddChar(#9)
            else if Sym = XK_Escape then AddChar(#27)
            else
            begin
              N := XLookupString(@E.xkey, @Buf[0], SizeOf(Buf), nil, nil);
              for I := 0 to N - 1 do
                if (Buf[I] >= ' ') and (Buf[I] <= '~') then AddChar(Buf[I]);
            end;
          end;
        end;
      ButtonPress:
        if E.xbutton.button = 1 then AddClick(E.xbutton.x, E.xbutton.y);
      ClientMessage:
        if Cardinal(E.xclient.data.l[0]) = FWmDelete then Closed := True;
      DestroyNotify: Closed := True;
    end;
  end;
end;

procedure TWindow3D.Present(Surface: TGSurface);
var
  D: PDisplay;
  N: Integer;
begin
  D := FDisplay;
  if (D = nil) or (FImage = nil) then Exit;
  N := Surface.Width * Surface.Height;
  if N > FWidth * FHeight then N := FWidth * FHeight;
  if N > 0 then Move(Surface.Pixels[0], FImageBuf^, N * 4);
  XPutImage(D, FWin, FGC, FImage, 0, 0, 0, 0, FWidth, FHeight);
  XFlush(D);
end;

{$ENDIF}{$ENDIF}

end.
