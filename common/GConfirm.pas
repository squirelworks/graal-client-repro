{ GConfirm: a modal OK / Cancel question, as the classic clients ask it
  with a Windows message box (Esc in offline play: "Warning", "Do you
  really want to quit Graal?", OK and Cancel; lab, 2.01, 2.05r2 and GraalX
  on Windows XP, 2026-11-13).

  On Windows it is the real message box (question icon, as the real
  clients show it; lab on Windows 10, 2026-11-13), owned by the
  window in front. Elsewhere it is drawn in a small window of its own:
  Enter or OK says yes, Esc, Cancel or the close box says no. }
unit GConfirm;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat;

{ True when the player picks OK. }
function AskOkCancel(const Title, Text: string): Boolean;

{ The drawn box's layout, for tests: its client size and the two buttons
  (X, Y, W, H) for a given text. }
procedure ConfirmLayout(const Text: string; out W, H: Integer;
  out OkRect, CancelRect: array of Integer);

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, GSurface, GWindow, GUiFont;

const
  BtnW = 75;
  BtnH = 23;
  Gap = 6;

procedure ConfirmLayout(const Text: string; out W, H: Integer;
  out OkRect, CancelRect: array of Integer);
var
  TW: Integer;
begin
  TW := UiTextWidth(Text, ufRegular);
  W := TW + 2 * 24;
  if W < 2 * BtnW + Gap + 2 * 24 then W := 2 * BtnW + Gap + 2 * 24;
  H := 24 + UiLineH + 24 + BtnH + 12;
  OkRect[0] := (W - (2 * BtnW + Gap)) div 2;
  OkRect[1] := H - 12 - BtnH;
  OkRect[2] := BtnW;
  OkRect[3] := BtnH;
  CancelRect[0] := OkRect[0] + BtnW + Gap;
  CancelRect[1] := OkRect[1];
  CancelRect[2] := BtnW;
  CancelRect[3] := BtnH;
end;

{$IFDEF MSWINDOWS}
function AskOkCancel(const Title, Text: string): Boolean;
begin
  Result := MessageBoxA(GetActiveWindow, PChar(Text), PChar(Title),
    MB_OKCANCEL or MB_ICONQUESTION or MB_DEFBUTTON1) = IDOK;
end;
{$ELSE}
function AskOkCancel(const Title, Text: string): Boolean;
const
  Face = $FFD4D0C8;
  ColBlack = $FF000000;
  ColWhite = $FFFFFFFF;
  ColShadow = $FF808080;
var
  Win: TGWindow;
  S: TGSurface;
  W, H, CX, CY: Integer;
  Ok, Cancel: array[0..3] of Integer;
  Chars: string;

  procedure Button(const R: array of Integer; const Caption: string);
  begin
    S.FillRect(R[0], R[1], R[2], R[3], ColBlack);
    S.FillRect(R[0], R[1], R[2] - 1, R[3] - 1, ColWhite);
    S.FillRect(R[0] + 1, R[1] + 1, R[2] - 2, R[3] - 2, ColShadow);
    S.FillRect(R[0] + 1, R[1] + 1, R[2] - 3, R[3] - 3, Face);
    UiDrawText(S, R[0] + (R[2] - UiTextWidth(Caption, ufRegular)) div 2,
      R[1] + (R[3] - UiLineH) div 2, Caption, ColBlack, ufRegular);
  end;

  function Inside(const R: array of Integer): Boolean;
  begin
    Result := (CX >= R[0]) and (CY >= R[1]) and (CX < R[0] + R[2]) and (CY < R[1] + R[3]);
  end;

begin
  Result := False;
  ConfirmLayout(Text, W, H, Ok, Cancel);
  Win := TGWindow.Create(Title, W, H);
  S := TGSurface.Create(W, H);
  try
    if not Win.Ok then Exit;
    Win.Reshape(Title, W, H, True);
    Win.TakeChars;
    while True do
    begin
      Win.Pump;
      if Win.Closed then Exit;
      Chars := Win.TakeChars;
      if Pos(#27, Chars) > 0 then Exit;
      if Pos(#13, Chars) > 0 then
      begin
        Result := True;
        Exit;
      end;
      if Win.TakeClick(CX, CY) then
      begin
        if Inside(Ok) then
        begin
          Result := True;
          Exit;
        end;
        if Inside(Cancel) then Exit;
      end;
      S.Fill(Face);
      UiDrawText(S, 24, 24, Text, ColBlack, ufRegular);
      Button(Ok, 'OK');
      Button(Cancel, 'Cancel');
      Win.Present(S);
      Sleep(20);
    end;
  finally
    S.Free;
    Win.Free;
  end;
end;
{$ENDIF}

end.
