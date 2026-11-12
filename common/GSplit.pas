{ GSplit: splitting a line at one delimiter, the way TStrings.DelimitedText
  does with StrictDelimiter on.

  Delphi 5's TStrings has CommaText but no Delimiter, DelimitedText or
  StrictDelimiter (Delphi 6 added the first two, Delphi 2006 the third).
  SplitDelimited gives the same items Free Pascal 3.2.2's strict
  DelimitedText gives, quoting included, so the callers keep their
  behaviour:

  - items are split at the delimiter only; spaces and control characters
    are kept;
  - an item that starts with the quote character runs to the closing
    quote, a doubled quote inside it stands for one quote, and whatever
    follows the closing quote up to the next delimiter starts another item;
  - an empty line gives no items, and a delimiter at the end gives a last,
    empty item.

  Tests/TestSplit checks it against TStringList on a fixed and a random
  set of lines. }
unit GSplit;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes;

{ Clears Into and fills it with the items of S. }
procedure SplitDelimited(const S: string; Delim: Char; Into: TStrings;
  Quote: Char = '"');

implementation

uses
  SysUtils;

procedure SplitDelimited(const S: string; Delim: Char; Into: TStrings;
  Quote: Char);
var
  Len, I, J: Integer;
  NotFirst: Boolean;
begin
  Into.BeginUpdate;
  try
    Into.Clear;
    Len := Length(S);
    I := 1;
    NotFirst := False;
    while I <= Len do
    begin
      if NotFirst and (S[I] = Delim) then Inc(I);
      if I > Len then
      begin
        if NotFirst then Into.Add('');
      end
      else if (S[I] = Quote) and (Quote <> #0) then
      begin
        { quoted: to the closing quote; a doubled quote is one quote }
        J := I + 1;
        while (J <= Len) and ((S[J] <> Quote) or ((J + 1 <= Len) and (S[J + 1] = Quote))) do
          if S[J] = Quote then Inc(J, 2) else Inc(J);
        Into.Add(StringReplace(Copy(S, I + 1, J - I - 1), Quote + Quote, Quote,
          [rfReplaceAll]));
        I := J + 1;
      end
      else
      begin
        J := I;
        while (J <= Len) and (S[J] <> Delim) do Inc(J);
        Into.Add(Copy(S, I, J - I));
        I := J;
      end;
      NotFirst := True;
    end;
  finally
    Into.EndUpdate;
  end;
end;

end.
