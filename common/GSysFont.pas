{ GSysFont: the Windows fonts the original clients ask GDI for, read with
  GTrueType from the install or from Windows' own Fonts folder, so the
  rebuild draws the same text the original drew without carrying a font.

  2.0x draws the names under characters and the sword and glove powers
  in graalconfig.txt's font (font=Tempus Sans ITC, fontsize=24): GDI
  text in that font, bold, with a cell 24 pixels high (traced under Wine,
  WINEDEBUG=+font). }
unit GSysFont;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GTrueType;

{ The file of a font face: TEMPSITC.TTF for "Tempus Sans ITC", else the
  face name with .ttf. }
function FontFileName(const Face: string): string;
{ FileName in the asset roots, else in Windows' Fonts folder; '' when
  neither has it. }
function FindFontFile(const FileName: string): string;
{ The em, in pixels, whose line (ascent + descent) is Cell pixels: GDI's
  font of a positive height. }
function EmForCell(F: TTrueTypeFont; Cell: Integer): Integer;
{ The font face and cell height graalconfig.txt in Dir names (font=,
  fontsize=), Tempus Sans ITC and 24 when it does not. }
procedure ConfigFont(const Dir: string; out Face: string; out Cell: Integer);

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Classes, SysUtils, GAssetDirs;

function FontFileName(const Face: string): string;
begin
  if SameText(Face, 'Tempus Sans ITC') then Result := 'TEMPSITC.TTF'
  else Result := Face + '.ttf';
end;

function FindFontFile(const FileName: string): string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..MAX_PATH] of Char;
{$ENDIF}
begin
  Result := AssetPath(FileName);
  if Result <> '' then Exit;
  Result := AssetPath(LowerCase(FileName));
  if Result <> '' then Exit;
{$IFDEF MSWINDOWS}
  if GetWindowsDirectory(Buf, MAX_PATH) > 0 then
  begin
    Result := IncludeTrailingPathDelimiter(Buf) + 'Fonts' + PathDelim + FileName;
    if FileExists(Result) then Exit;
  end;
{$ENDIF}
  Result := '';
end;

function EmForCell(F: TTrueTypeFont; Cell: Integer): Integer;
begin
  Result := Cell;
  while (Result > 1) and (F.LineHeight(Result) > Cell) do Dec(Result);
end;

procedure ConfigFont(const Dir: string; out Face: string; out Cell: Integer);
var
  L: TStringList;
begin
  Face := 'Tempus Sans ITC';
  Cell := 24;
  if (Dir = '') or not FileExists(IncludeTrailingPathDelimiter(Dir) + 'graalconfig.txt') then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + 'graalconfig.txt');
    except
      Exit;
    end;
    if Trim(L.Values['font']) <> '' then Face := Trim(L.Values['font']);
    Cell := StrToIntDef(Trim(L.Values['fontsize']), 24);
    if (Cell < 6) or (Cell > 72) then Cell := 24;
  finally
    L.Free;
  end;
end;

end.
