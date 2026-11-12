{ GWindowCocoa.inc: TGWindow's macOS back end, included by GWindow.pas only
  when GW_COCOA is defined (Darwin without GW_HEADLESS).

  Plain Free Pascal: no Objective-C mode and no CocoaAll. AppKit is driven
  through the Objective-C runtime's C functions (objc_msgSend cast to one
  procedure type per method shape, as the arm64 ABI requires), and each
  frame goes to the content view's CALayer as a CGImage.

    window     an NSWindow subclass made at run time (GraalGWindow) that can
               be key while borderless (fullscreen) and answers NO to
               windowShouldClose:, so the close button only sets Closed, as
               WM_CLOSE and WM_DELETE_WINDOW do on the other back ends
    picture    the 32-bit surface (B G R X bytes) as a CGImage, 1:1 in
               points at the top left; fullscreen scales it to the screen
               keeping its aspect (nearest neighbour)
    input      events are taken from the queue in Pump: keys and characters
               are handled here, everything else goes on to [NSApp
               sendEvent:] (title bar drags, the close button)
    Alt+Enter  Option+Return: a borderless window over the whole screen with
               the menu bar and Dock hidden; Cmd+Q closes like the X }

{$linklib objc}
{$linkframework CoreFoundation}
{$linkframework CoreGraphics}
{$linkframework QuartzCore}
{$linkframework AppKit}

type
  GwId = Pointer;
  GwSel = Pointer;
  GwNSRect = record
    X, Y, W, H: Double;
  end;
  GwNSSize = record
    W, H: Double;
  end;
  GwNSPoint = record
    X, Y: Double;
  end;

  { objc_msgSend, one shape per kind of method used }
  TGwMsg = function(Self: GwId; Op: GwSel): GwId; cdecl;
  TGwMsgP = function(Self: GwId; Op: GwSel; A: Pointer): GwId; cdecl;
  TGwMsgU = function(Self: GwId; Op: GwSel; A: PtrUInt): GwId; cdecl;
  TGwMsgUP = function(Self: GwId; Op: GwSel; A: PtrUInt; B: Pointer): GwId; cdecl;
  TGwMsgUPPU = function(Self: GwId; Op: GwSel; A: PtrUInt; B, C: Pointer; D: PtrUInt): GwId; cdecl;
  TGwMsgRUUU = function(Self: GwId; Op: GwSel; R: GwNSRect; A, B, C: PtrUInt): GwId; cdecl;
  TGwMsgRU = function(Self: GwId; Op: GwSel; R: GwNSRect; A: PtrUInt): GwId; cdecl;
  TGwMsgS = function(Self: GwId; Op: GwSel; S: GwNSSize): GwId; cdecl;
  TGwMsgPU = function(Self: GwId; Op: GwSel; A: PChar; B: PtrUInt): GwId; cdecl;
  TGwMsgRetU = function(Self: GwId; Op: GwSel): PtrUInt; cdecl;
  TGwMsgRetD = function(Self: GwId; Op: GwSel): Double; cdecl;
  TGwMsgRetPt = function(Self: GwId; Op: GwSel): GwNSPoint; cdecl;
  TGwMsgRetRect = function(Self: GwId; Op: GwSel): GwNSRect; cdecl;

procedure objc_msgSend; cdecl; external 'objc';
{$IFDEF CPUX86_64}
{ x86-64 returns an NSRect (32 bytes) through memory: the _stret entry }
procedure objc_msgSend_stret; cdecl; external 'objc';
{$ENDIF}
function objc_getClass(Name: PChar): GwId; cdecl; external 'objc';
function sel_registerName(Name: PChar): GwSel; cdecl; external 'objc';
function objc_allocateClassPair(Super: GwId; Name: PChar; Extra: PtrUInt): GwId; cdecl; external 'objc';
procedure objc_registerClassPair(Cls: GwId); cdecl; external 'objc';
function class_addMethod(Cls: GwId; Name: GwSel; Imp: Pointer; Types: PChar): Byte; cdecl; external 'objc';
function objc_autoreleasePoolPush: Pointer; cdecl; external 'objc';
procedure objc_autoreleasePoolPop(Pool: Pointer); cdecl; external 'objc';

function CGColorSpaceCreateDeviceRGB: Pointer; cdecl; external name 'CGColorSpaceCreateDeviceRGB';
procedure CGColorSpaceRelease(CS: Pointer); cdecl; external name 'CGColorSpaceRelease';
function CGColorCreateGenericRGB(R, G, B, A: Double): Pointer; cdecl; external name 'CGColorCreateGenericRGB';
procedure CGColorRelease(C: Pointer); cdecl; external name 'CGColorRelease';
function CGDataProviderCreateWithCFData(Data: Pointer): Pointer; cdecl; external name 'CGDataProviderCreateWithCFData';
procedure CGDataProviderRelease(P: Pointer); cdecl; external name 'CGDataProviderRelease';
function CGImageCreate(W, H, BitsPerComponent, BitsPerPixel, BytesPerRow: PtrUInt;
  Space: Pointer; BitmapInfo: LongWord; Provider: Pointer; Decode: Pointer;
  Interpolate: LongInt; Intent: LongInt): Pointer; cdecl; external name 'CGImageCreate';
procedure CGImageRelease(I: Pointer); cdecl; external name 'CGImageRelease';
function CFDataCreate(Alloc: Pointer; Bytes: Pointer; Len: PtrInt): Pointer; cdecl; external name 'CFDataCreate';
procedure CFRelease(P: Pointer); cdecl; external name 'CFRelease';

const
  { NSWindowStyleMask }
  GwTitled = 1; GwClosable = 2; GwMiniaturizable = 4;
  { NSEventType }
  GwLeftDown = 1; GwLeftUp = 2; GwRightDown = 3; GwRightUp = 4; GwMoved = 5;
  GwLeftDragged = 6; GwRightDragged = 7; GwKeyDown = 10; GwKeyUp = 11;
  GwFlagsChanged = 12; GwScrollWheel = 22;
  { NSEventModifierFlags }
  GwShiftMask = 1 shl 17; GwControlMask = 1 shl 18; GwOptionMask = 1 shl 19;
  GwCommandMask = 1 shl 20;
  { kCGBitmapByteOrder32Little or kCGImageAlphaNoneSkipFirst: B G R X bytes }
  GwBitmapInfo = (2 shl 12) or 6;

var
  GwActive: TGWindow;
  GwWindowClass: GwId;
  GwRunMode: GwId;
  GwLaunched: Boolean;

function Sel(Name: PChar): GwSel;
begin
  Result := sel_registerName(Name);
end;

function Cls(Name: PChar): GwId;
begin
  Result := objc_getClass(Name);
end;

function Msg(Obj: GwId; Name: PChar): GwId;
begin
  Result := TGwMsg(@objc_msgSend)(Obj, Sel(Name));
end;

function MsgP(Obj: GwId; Name: PChar; A: Pointer): GwId;
begin
  Result := TGwMsgP(@objc_msgSend)(Obj, Sel(Name), A);
end;

function MsgU(Obj: GwId; Name: PChar; A: PtrUInt): GwId;
begin
  Result := TGwMsgU(@objc_msgSend)(Obj, Sel(Name), A);
end;

function MsgRetU(Obj: GwId; Name: PChar): PtrUInt;
begin
  Result := TGwMsgRetU(@objc_msgSend)(Obj, Sel(Name));
end;

function MsgRect(Obj: GwId; Name: PChar): GwNSRect;
begin
{$IFDEF CPUX86_64}
  Result := TGwMsgRetRect(@objc_msgSend_stret)(Obj, Sel(Name));
{$ELSE}
  Result := TGwMsgRetRect(@objc_msgSend)(Obj, Sel(Name));
{$ENDIF}
end;

{ an autoreleased NSString; Latin-1 when the bytes are not UTF-8 }
function NSStr(const S: string): GwId;
begin
  Result := MsgP(Cls('NSString'), 'stringWithUTF8String:', PChar(S));
  if Result = nil then
    Result := TGwMsgPU(@objc_msgSend)(Cls('NSString'), Sel('stringWithCString:encoding:'),
      PChar(S), 5 { NSISOLatin1StringEncoding });
end;

function GwYes(Self: GwId; Op: GwSel): Byte; cdecl;
begin
  Result := 1;
end;

{ the close button: Closed is set and the window stays, as on Windows }
function GwShouldClose(Self: GwId; Op: GwSel; Sender: GwId): Byte; cdecl;
begin
  if GwActive <> nil then GwActive.Closed := True;
  Result := 0;
end;

function GwClass: GwId;
var
  C: GwId;
begin
  if GwWindowClass = nil then
  begin
    C := objc_allocateClassPair(Cls('NSWindow'), 'GraalGWindow', 0);
    if C = nil then C := Cls('GraalGWindow') { made already }
    else
    begin
      class_addMethod(C, Sel('canBecomeKeyWindow'), @GwYes, 'c@:');
      class_addMethod(C, Sel('canBecomeMainWindow'), @GwYes, 'c@:');
      class_addMethod(C, Sel('windowShouldClose:'), @GwShouldClose, 'c@:@');
      objc_registerClassPair(C);
    end;
    GwWindowClass := C;
  end;
  Result := GwWindowClass;
end;

{ the TGKey of a key: letters by the character they type (any layout),
  the rest by virtual key code }
function MacKeyToKey(Code: Word; Ch: Char): TGKey;
begin
  case Code of
    $7E: Result := gkUp;
    $7B: Result := gkLeft;
    $7D: Result := gkDown;
    $7C: Result := gkRight;
    $31: Result := gkAttack;   { space }
    $30: Result := gkChat;     { tab }
    $35: Result := gkEscape;
    $76: Result := gkEditor;   { F4 }
    $60: Result := gkLoadLevel; { F5 }
    $7A: Result := gkOptions;  { F1 }
    $61: Result := gkF6;       { F6 }
    $75: Result := gkDelete;   { forward delete }
    $72: Result := gkInsert;   { Help / Insert on PC keyboards }
  else
    case Ch of
      'i': Result := gkUp;
      'j': Result := gkLeft;
      'k': Result := gkDown;
      'l': Result := gkRight;
      'a': Result := gkAction;
      's': Result := gkAttack;
      'd': Result := gkItem;
      'm': Result := gkMap;
      'q': Result := gkItemList;
    else
      Result := gkNone;
    end;
  end;
end;

procedure SetMacArrow(W: TGWindow; Code: Word; Down: Boolean);
begin
  case Code of
    $7E: W.ArrowHeld[0] := Down;
    $7B: W.ArrowHeld[1] := Down;
    $7D: W.ArrowHeld[2] := Down;
    $7C: W.ArrowHeld[3] := Down;
  end;
end;

{ the first character of an NSString, lower case (#0 for none or non-ASCII) }
function FirstChar(Str: GwId): Char;
var
  P: PChar;
begin
  Result := #0;
  if Str = nil then Exit;
  P := PChar(Msg(Str, 'UTF8String'));
  if (P <> nil) and (P^ >= ' ') and (P^ <= '~') then
  begin
    Result := P^;
    if (Result >= 'A') and (Result <= 'Z') then Inc(Result, 32);
  end;
end;

constructor TGWindow.Create(const Title: string; AWidth, AHeight: Integer);
var
  Pool, App, View, Color: Pointer;
  R: GwNSRect;
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  { AppKit and Core Graphics compute with NaNs and denormals and expect the
    C default, all floating-point exceptions masked. FPC unmasks invalid
    operation, divide by zero and overflow, and AppKit's start-up
    (_NSGetCGFloatAppConfig) then stopped the program with EInvalidOp.
    Mask them all before AppKit runs, as a Cocoa program has them. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  Pool := objc_autoreleasePoolPush;
  try
    App := Msg(Cls('NSApplication'), 'sharedApplication');
    if App = nil then Exit;
    { a regular app: a Dock icon and the keyboard, though the program is
      not in a bundle }
    MsgU(App, 'setActivationPolicy:', 0);
    R.X := 0; R.Y := 0; R.W := AWidth; R.H := AHeight;
    FWin := TGwMsgRUUU(@objc_msgSend)(Msg(GwClass, 'alloc'),
      Sel('initWithContentRect:styleMask:backing:defer:'), R,
      GwTitled or GwClosable or GwMiniaturizable, 2 { buffered }, 0);
    if FWin = nil then Exit;
    MsgU(FWin, 'setReleasedWhenClosed:', 0);
    MsgU(FWin, 'setAcceptsMouseMovedEvents:', 1);
    FTitle := Title;
    MsgP(FWin, 'setTitle:', NSStr(Title));
    { a layer-hosting content view: the layer is ours to fill }
    View := Msg(FWin, 'contentView');
    FLayer := Msg(Msg(Cls('CALayer'), 'layer'), 'retain');
    MsgP(View, 'setLayer:', FLayer);
    MsgU(View, 'setWantsLayer:', 1);
    MsgP(FLayer, 'setContentsGravity:', NSStr('topLeft'));
    MsgP(FLayer, 'setMagnificationFilter:', NSStr('nearest'));
    Color := CGColorCreateGenericRGB(0, 0, 0, 1);
    MsgP(FLayer, 'setBackgroundColor:', Color);
    CGColorRelease(Color);
    FColorSpace := CGColorSpaceCreateDeviceRGB;
    FViewW := AWidth;
    FViewH := AHeight;
    Msg(FWin, 'center');
    MsgP(FWin, 'makeKeyAndOrderFront:', nil);
    if not GwLaunched then
    begin
      Msg(App, 'finishLaunching');
      GwRunMode := Msg(NSStr('kCFRunLoopDefaultMode'), 'retain');
      GwLaunched := True;
    end;
    MsgU(App, 'activateIgnoringOtherApps:', 1);
    GwActive := Self;
  finally
    objc_autoreleasePoolPop(Pool);
  end;
end;

destructor TGWindow.Destroy;
var
  Pool: Pointer;
begin
  Pool := objc_autoreleasePoolPush;
  if FFullscreen then
    MsgU(Msg(Cls('NSApplication'), 'sharedApplication'), 'setPresentationOptions:', 0);
  if GwActive = Self then GwActive := nil;
  if FWin <> nil then
  begin
    MsgP(FWin, 'orderOut:', nil);
    Msg(FWin, 'release');
  end;
  if FLayer <> nil then Msg(FLayer, 'release');
  if FColorSpace <> nil then CGColorSpaceRelease(FColorSpace);
  objc_autoreleasePoolPop(Pool);
  FreeAndNil(FLast);
  inherited Destroy;
end;

function TGWindow.Ok: Boolean;
begin
  Result := FWin <> nil;
end;

procedure TGWindow.Pump;
var
  Pool, App, E: Pointer;
  T, Flags: PtrUInt;
  Code: Word;
  Pt: GwNSPoint;
  S, X, Y: Double;
  P: PChar;
  Fwd: Boolean;
begin
  if FWin = nil then Exit;
  Pool := objc_autoreleasePoolPush;
  App := Msg(Cls('NSApplication'), 'sharedApplication');
  repeat
    E := TGwMsgUPPU(@objc_msgSend)(App,
      Sel('nextEventMatchingMask:untilDate:inMode:dequeue:'), High(PtrUInt), nil,
      GwRunMode, 1);
    if E = nil then Break;
    T := MsgRetU(E, 'type');
    Fwd := True;
    case T of
      GwKeyDown, GwKeyUp:
        begin
          Fwd := False;
          Code := Word(MsgRetU(E, 'keyCode'));
          Flags := MsgRetU(E, 'modifierFlags');
          if (Flags and GwCommandMask) <> 0 then
          begin
            { Cmd+Q quits as the close box does; other Cmd keys are the
              system's }
            if (T = GwKeyDown) and (FirstChar(Msg(E, 'charactersIgnoringModifiers')) = 'q') then
              Closed := True;
            Continue;
          end;
          SetMacArrow(Self, Code, T = GwKeyDown);
          SetKey(MacKeyToKey(Code, FirstChar(Msg(E, 'charactersIgnoringModifiers'))),
            T = GwKeyDown);
          if T = GwKeyDown then
          begin
            if ((Code = $24) or (Code = $4C)) and ((Flags and GwOptionMask) <> 0) then
            begin
              if MsgRetU(E, 'isARepeat') and $FF = 0 then FFullToggle := True;
            end
            else if Code = $33 then AddChar(#8)
            else if (Code = $24) or (Code = $4C) then AddChar(#13)
            else if Code = $30 then AddChar(#9)
            else if Code = $35 then AddChar(#27)
            else
            begin
              P := PChar(Msg(Msg(E, 'characters'), 'UTF8String'));
              if P <> nil then
                while P^ <> #0 do
                begin
                  if ((P^ >= ' ') and (P^ <= '~')) or ((P^ >= #1) and (P^ <= #26)) then
                    AddChar(P^);
                  Inc(P);
                end;
            end;
          end;
        end;
      GwFlagsChanged:
        begin
          Flags := MsgRetU(E, 'modifierFlags');
          CtrlHeld := (Flags and GwControlMask) <> 0;
          ShiftHeld := (Flags and GwShiftMask) <> 0;
        end;
      GwLeftDown, GwLeftUp, GwRightDown, GwRightUp, GwMoved, GwLeftDragged,
      GwRightDragged, GwScrollWheel:
        if Msg(E, 'window') = FWin then
        begin
          Pt := TGwMsgRetPt(@objc_msgSend)(E, Sel('locationInWindow'));
          { window points, y up from the content's bottom, to frame pixels }
          S := 1;
          X := 0;
          Y := 0;
          if FFullscreen and (FWidth > 0) and (FHeight > 0) then
          begin
            S := FViewW / FWidth;
            if FViewH / FHeight < S then S := FViewH / FHeight;
            X := (FViewW - FWidth * S) / 2;
            Y := (FViewH - FHeight * S) / 2;
          end;
          MouseX := Trunc((Pt.X - X) / S);
          MouseY := Trunc((FViewH - Pt.Y - Y) / S);
          case T of
            GwLeftDown:
              if Pt.Y < FViewH then
              begin
                MouseLeft := True;
                AddClick(MouseX, MouseY);
              end;
            GwLeftUp: MouseLeft := False;
            GwRightDown:
              if Pt.Y < FViewH then
              begin
                MouseRight := True;
                AddRightClick(MouseX, MouseY);
              end;
            GwRightUp: MouseRight := False;
            GwScrollWheel:
              begin
                S := TGwMsgRetD(@objc_msgSend)(E, Sel('deltaY'));
                { up is negative, as WM_MOUSEWHEEL }
                if S > 0 then Dec(FWheel)
                else if S < 0 then Inc(FWheel);
              end;
          end;
        end;
    end;
    if Fwd then MsgP(App, 'sendEvent:', E);
  until False;
  objc_autoreleasePoolPop(Pool);
end;

procedure TGWindow.Present(Surface: TGSurface);
var
  Pool, Data, Prov, Img, CAT: Pointer;
  N: Integer;
begin
  if (FWin = nil) or (Surface = nil) then Exit;
  N := Surface.Width * Surface.Height;
  if N <= 0 then Exit;
  Pool := objc_autoreleasePoolPush;
  { a copy: the layer keeps the image while the game draws the next frame }
  Data := CFDataCreate(nil, @Surface.Pixels[0], PtrInt(N) * 4);
  Prov := CGDataProviderCreateWithCFData(Data);
  Img := CGImageCreate(Surface.Width, Surface.Height, 8, 32, Surface.Width * 4,
    FColorSpace, GwBitmapInfo, Prov, nil, 0, 0);
  if Img <> nil then
  begin
    CAT := Cls('CATransaction');
    Msg(CAT, 'begin');
    MsgU(CAT, 'setDisableActions:', 1); { no cross-fade between frames }
    MsgP(FLayer, 'setContents:', Img);
    Msg(CAT, 'commit');
    Msg(CAT, 'flush');
    CGImageRelease(Img);
  end;
  CGDataProviderRelease(Prov);
  CFRelease(Data);
  objc_autoreleasePoolPop(Pool);
end;

procedure TGWindow.UseDelphiFrames(const AppTitle: string);
begin
end;

procedure TGWindow.Reshape(const Title: string; AWidth, AHeight: Integer;
  Dialog: Boolean; MinBox: Boolean);
var
  Pool: Pointer;
  Sz: GwNSSize;
begin
  if FWin = nil then Exit;
  Pool := objc_autoreleasePoolPush;
  FTitle := Title;
  MsgP(FWin, 'setTitle:', NSStr(Title));
  { a dialog may only be moved and closed; the game may also be minimised }
  if Dialog then MsgU(FWin, 'setStyleMask:', GwTitled or GwClosable)
  else MsgU(FWin, 'setStyleMask:', GwTitled or GwClosable or GwMiniaturizable);
  FWidth := AWidth;
  FHeight := AHeight;
  Sz.W := AWidth;
  Sz.H := AHeight;
  TGwMsgS(@objc_msgSend)(FWin, Sel('setContentSize:'), Sz);
  FViewW := AWidth;
  FViewH := AHeight;
  { centred on the screen, as 2.22's forms (poScreenCenter) }
  Msg(FWin, 'center');
  objc_autoreleasePoolPop(Pool);
end;

procedure TGWindow.ShowForm(const Title: string; OuterW, OuterH, DesignW, DesignH: Integer;
  AutoScroll: Boolean; FormColor: Cardinal);
begin
  { macOS draws its own frame: the client is the form's design size (its
    outer size less a Windows 9x frame), as on X11 }
  Reshape(Title, OuterW - 8, OuterH - 34, False, True);
end;

function TGWindow.EnterFullscreen(AWidth, AHeight: Integer): Boolean;
var
  Pool, Scr: Pointer;
  F: GwNSRect;
begin
  Result := False;
  if (FWin = nil) or FFullscreen then Exit;
  Pool := objc_autoreleasePoolPush;
  try
    Scr := Msg(FWin, 'screen');
    if Scr = nil then Scr := Msg(Cls('NSScreen'), 'mainScreen');
    if Scr = nil then Exit;
    F := MsgRect(Scr, 'frame');
    if (F.W < AWidth) or (F.H < AHeight) then Exit;
    FFullscreen := True;
    FWidth := AWidth;
    FHeight := AHeight;
    FViewW := F.W;
    FViewH := F.H;
    { borderless over the whole screen, the menu bar and Dock hidden }
    MsgU(Msg(Cls('NSApplication'), 'sharedApplication'), 'setPresentationOptions:',
      2 or 8 { NSApplicationPresentationHideDock, HideMenuBar });
    MsgU(FWin, 'setStyleMask:', 0);
    TGwMsgRU(@objc_msgSend)(FWin, Sel('setFrame:display:'), F, 1);
    MsgP(FLayer, 'setContentsGravity:', NSStr('resizeAspect'));
    MsgP(FWin, 'makeKeyAndOrderFront:', nil);
    Result := True;
  finally
    objc_autoreleasePoolPop(Pool);
  end;
end;

procedure TGWindow.LeaveFullscreen(AWidth, AHeight: Integer);
var
  Pool: Pointer;
begin
  if (FWin = nil) or not FFullscreen then Exit;
  Pool := objc_autoreleasePoolPush;
  FFullscreen := False;
  MsgU(Msg(Cls('NSApplication'), 'sharedApplication'), 'setPresentationOptions:', 0);
  MsgP(FLayer, 'setContentsGravity:', NSStr('topLeft'));
  objc_autoreleasePoolPop(Pool);
  Reshape(FTitle, AWidth, AHeight, False);
end;
