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
    gkItem, gkMap, gkChat, gkEscape, gkItemList);

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
    FChars: string;
    procedure AddClick(X, Y: Integer);
  public
    MouseX, MouseY: Integer;
    Held: array[TGKey] of Boolean;
    Closed: Boolean;
    constructor Create(const Title: string; AWidth, AHeight: Integer);
    destructor Destroy; override;
    function Ok: Boolean;
    { Handles every waiting window event. }
    procedure Pump;
    procedure Present(Surface: TGSurface);
    { True once for each press since the last call (for one-shot keys). }
    function WasPressed(K: TGKey): Boolean;
    procedure SetKey(K: TGKey; Down: Boolean);
    { The last left click since the last call, in window pixels. }
    function TakeClick(out X, Y: Integer): Boolean;
    { Characters typed since the last call: printable ones, #8 backspace,
      #9 tab, #13 enter, #27 escape. }
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
  else
    Result := gkNone;
  end;
end;

function WndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
begin
  Result := 0;
  if ActiveWindow <> nil then
    case Msg of
      WM_KEYDOWN: begin ActiveWindow.SetKey(VKToKey(WP), True); Exit; end;
      WM_KEYUP: begin ActiveWindow.SetKey(VKToKey(WP), False); Exit; end;
      WM_CHAR: begin ActiveWindow.AddChar(Chr(WP and $FF)); Exit; end;
      WM_LBUTTONDOWN:
        begin
          ActiveWindow.AddClick(SmallInt(LP and $FFFF), SmallInt((LP shr 16) and $FFFF));
          Exit;
        end;
      WM_MOUSEMOVE:
        begin
          ActiveWindow.MouseX := SmallInt(LP and $FFFF);
          ActiveWindow.MouseY := SmallInt((LP shr 16) and $FFFF);
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

procedure TGWindow.Present(Surface: TGSurface);
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
  else
    Result := gkNone;
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
    StructureNotifyMask or ButtonPressMask or PointerMotionMask);
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
          SetKey(KeySymToKey(Sym), True);
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
      ButtonPress:
        if E.xbutton.button = 1 then AddClick(E.xbutton.x, E.xbutton.y);
      MotionNotify:
        begin
          MouseX := E.xmotion.x;
          MouseY := E.xmotion.y;
        end;
      KeyRelease: SetKey(KeySymToKey(XLookupKeysym(@E.xkey, 0)), False);
      ClientMessage:
        if Cardinal(E.xclient.data.l[0]) = FWmDelete then Closed := True;
      DestroyNotify: Closed := True;
    end;
  end;
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
  XPutImage(D, FWin, FGC, FImage, 0, 0, 0, 0, FWidth, FHeight);
  XFlush(D);
end;

{$ENDIF}{$ENDIF}

end.
