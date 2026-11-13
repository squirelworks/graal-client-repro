{ Overlay3D: what Graal3D draws over its 3D view.

  Measured on the real client's first frames (Windows 10, software
  rendering, 2026-11-12 polishing run; the window was scaled 1.5x by the
  desktop, the figures here are the game's own pixels):

  - a black strip across the top of the view, 48 pixels high;
  - the nickname in it, white, in a large bold sans-serif font (Arial
    Bold, its ink from x 108, the letters' feet at y 43: the tops of the
    tall letters are cut off by the view's top edge);
  - logo.bmp from the install (100 x 100) at (10, 10), over the strip.

  How the original draws them (GDI on the DirectDraw surface, or the
  retained-mode device) was not read; the font here is Arial Bold from the
  install or Windows' Fonts folder, then Liberation Sans Bold (the same
  widths), then the built-in pixel font. }
unit Overlay3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GTrueType, Render3D;

const
  BannerH = 48;
  LogoX = 10;
  LogoY = 10;
  NickInkX = 108;
  NickFeetY = 43;
  { the em that gives the real banner's width ("realg3drealg3d", 375
    pixels of ink) }
  NickEm = 53;

type
  TOverlay3D = class
  private
    FLogo: TGSurface;
    FFont: TTrueTypeFont;
    FLoaded: Boolean;
  public
    destructor Destroy; override;
    { logo.bmp through Find, and the banner's font. }
    procedure Load(Find: TFindFile);
    procedure Draw(Dest: TGSurface; ViewW: Integer; const Nick: string);
    property Logo: TGSurface read FLogo;
  end;

implementation

uses
  SysUtils, GSysFont, GFont;

const
  FallbackFonts: array[0..2] of string = (
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
    '/usr/share/fonts/liberation/LiberationSans-Bold.ttf',
    '/Library/Fonts/Arial Bold.ttf');

destructor TOverlay3D.Destroy;
begin
  FLogo.Free;
  FFont.Free;
  inherited Destroy;
end;

procedure TOverlay3D.Load(Find: TFindFile);
var
  P: string;
  I: Integer;
begin
  if FLoaded then Exit;
  FLoaded := True;
  P := '';
  if Assigned(Find) then P := Find('logo.bmp');
  if P <> '' then
  begin
    FLogo := TGSurface.Create(0, 0);
    if not LoadImageFile(P, FLogo) then FreeAndNil(FLogo);
  end;
  P := FindFontFile('arialbd.ttf');
  I := 0;
  while (P = '') and (I <= High(FallbackFonts)) do
  begin
    if FileExists(FallbackFonts[I]) then P := FallbackFonts[I];
    Inc(I);
  end;
  if P <> '' then
  begin
    FFont := TTrueTypeFont.Create;
    if not FFont.LoadFromFile(P) then FreeAndNil(FFont);
  end;
end;

procedure TOverlay3D.Draw(Dest: TGSurface; ViewW: Integer; const Nick: string);
begin
  Dest.FillRect(0, 0, ViewW, BannerH, $FF000000);
  if Nick <> '' then
  begin
    if FFont <> nil then
      { the line's top so that the descenders end at NickFeetY; the left
        bearing of a bold r at this size is about 3 pixels }
      FFont.DrawText(Dest, NickInkX - 3,
        NickFeetY - FFont.LineHeight(NickEm), Nick, NickEm, $FFFFFFFF)
    else
      DrawText(Dest, NickInkX, NickFeetY - 7 * 4, Nick, $FFFFFFFF, 4);
  end;
  if FLogo <> nil then
    Dest.Blit(FLogo, 0, 0, FLogo.Width, FLogo.Height, LogoX, LogoY);
end;

end.
