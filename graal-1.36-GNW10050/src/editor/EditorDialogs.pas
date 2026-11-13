{ EditorDialogs: the object dialogs of the 2.05 built-in editor.

  One class per 2.05 form, laid out from its form resource (captions,
  positions, sizes): TLinkList and TLinkOptions, TEditSigns with
  TShowCodes, TChestEdit, TEditPerson with TPersonAction, TEditBaddy and
  TEditFlags. See graal_analysis client-internals/level-editor-205.md
  ("Object types").

  They are built on TFormDialog, a small form: labels, one-line edits, a
  multi-line memo, buttons, list views, drop-down combo boxes. Tab moves
  the focus, Enter in a one-line edit presses the default button, Esc
  closes. A dialog can open a child dialog over itself (the link list
  opens the link dialog, a chest opens the sign editor). }
unit EditorDialogs;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GLevel, EditorUI, EditorDoc, GCompat;

type
  TCtlKind = (ckLabel, ckEdit, ckMemo, ckButton, ckList, ckCombo, ckGroup,
    ckStatus { read-only yellow line, the 2.05 script editor's ErrorEdit });

  TCtl = class
  public
    Kind: TCtlKind;
    R: TRectI;
    Caption: string;
    Text: string;
    Items: TStringList;  { list / combo rows; list columns split by #9 }
    Columns: array of Integer; { list column widths }
    Index: Integer;      { list / combo selection }
    Top: Integer;        { first row shown }
    Enabled, Visible: Boolean;
    Id: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TFormDialog = class(TEditorDialog)
  private
    FLastClickMs: Int64;
    FLastClickCtl: Integer;
    function Focusable(N: Integer): Boolean;
    procedure DrawCtl(S: TGSurface; C: TCtl; Focused: Boolean);
    function DropRect(C: TCtl): TRectI;
  protected
    Ctls: array of TCtl;
    Focus: Integer;
    DropOpen: Integer;
    Child: TEditorDialog;
    DefaultButton: Integer; { id pressed by Enter in a one-line edit }
    Closing: Boolean;
    function Add(Kind: TCtlKind; X, Y, W, H: Integer; const Caption: string; Id: Integer): TCtl;
    function Ctl(Id: Integer): TCtl;
    procedure Close(R: TDialogResult);
    procedure OpenChild(D: TEditorDialog);
    { Events: a button or a double-clicked list row; a changed edit,
      memo, combo or list selection. }
    procedure Clicked(Id: Integer); virtual;
    procedure Changed(Id: Integer); virtual;
    procedure DoubleClicked(Id: Integer); virtual;
    procedure ChildClosed(D: TEditorDialog); virtual;
  public
    constructor Create(const ACaption: string; W, H: Integer);
    destructor Destroy; override;
    function Step(const I: TEditorInput): Boolean; override;
    procedure Draw(S: TGSurface); override;
    function TextOf(Id: Integer): string;
    procedure SetText(Id: Integer; const T: string);
  end;

  { TLinkOptions: one link. OK checks the fields ("Wrong values! ..."),
    stores the link (adding it if new) and marks the level modified. }
  TLinkOptionsDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
  public
    Doc: TEditorDoc;
    LinkIndex: Integer;
    Error: string;
    constructor Create(ADoc: TEditorDoc; AIndex: Integer); overload;
    constructor Create(ADoc: TEditorDoc; const L: TLevelLink); overload;
    function Apply: Boolean;
  end;

  { TLinkList: the links of the level. Load closes it with LoadFile set,
    for the editor to open in a new tab. }
  TLinkListDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
    procedure DoubleClicked(Id: Integer); override;
    procedure ChildClosed(D: TEditorDialog); override;
  public
    Doc: TEditorDoc;
    LoadFile: string;
    constructor Create(ADoc: TEditorDoc);
    procedure Refresh;
  end;

  { TEditSigns: the signs, with X / Y and the text; edits apply as typed. }
  TSignsDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
    procedure Changed(Id: Integer); override;
  public
    Doc: TEditorDoc;
    constructor Create(ADoc: TEditorDoc; Select: Integer);
    procedure Refresh;
    procedure LoadSelected;
  end;

  TChestDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
    procedure Changed(Id: Integer); override;
  public
    Doc: TEditorDoc;
    ChestIndex: Integer;
    constructor Create(ADoc: TEditorDoc; AIndex: Integer);
  end;

  TPersonDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
    procedure Changed(Id: Integer); override;
  public
    Doc: TEditorDoc;
    NPCIndex: Integer;
    constructor Create(ADoc: TEditorDoc; AIndex: Integer);
  end;

  { TPersonAction: the NPC's script. }
  TScriptDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
  public
    Doc: TEditorDoc;
    NPCIndex: Integer;
    constructor Create(ADoc: TEditorDoc; AIndex: Integer);
    { Test: compiles the script and puts the first error, or nothing, in
      the yellow line. Returns that text. }
    function TestScript: string;
  end;

  TBaddyDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
    procedure Changed(Id: Integer); override;
  public
    Doc: TEditorDoc;
    BaddyIndex: Integer;
    constructor Create(ADoc: TEditorDoc; AIndex: Integer);
    procedure Store;
  end;

  { TEditFlags: the in-memory flag list (not saved in the level). }
  TFlagsDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
  public
    Flags: TStrings;
    constructor Create(AFlags: TStrings);
  end;

  TShowCodesDialog = class(TFormDialog)
  protected
    procedure Clicked(Id: Integer); override;
  public
    constructor Create;
  end;

const
  { control ids }
  IdOK = 1;
  IdCancel = 2;
  IdClose = 3;
  IdDelete = 4;
  IdEdit = 5;
  IdLoad = 6;
  IdNew = 7;
  IdList = 8;
  IdX = 10;
  IdY = 11;
  IdW = 12;
  IdH = 13;
  IdNewX = 14;
  IdNewY = 15;
  IdFile = 16;
  IdText = 17;
  IdCodes = 18;
  IdItem = 19;
  IdSign = 20;
  IdSigns = 21;
  IdImage = 22;
  IdAction = 23;
  IdScript = 24;
  IdTest = 25;
  IdTestError = 31;
  IdType = 26;
  IdVerse1 = 27;
  IdVerse2 = 28;
  IdVerse3 = 29;
  IdFlags = 30;

  WrongLinkValues = 'Wrong values! Type in a filename and the numbers of the warp field.';

{ Checks link fields as the link dialog does. }
function LinkFromFields(const Dest, X, Y, W, H, NewX, NewY: string; out L: TLevelLink;
  out Error: string): Boolean;

implementation

uses
  SysUtils, GFont, GLevelWrite, GGs1;

const
  SignCodes: array[0..13] of string = ('#A  A button', '#B  B button', '#X  X button',
    '#Y  Y button', '#u  up arrow', '#d  down arrow', '#l  left arrow', '#r  right arrow',
    '#h  head', '#x  x', '#y  y', '#z  z', '#4  (two codes)', '#.  dot');

function LinkFromFields(const Dest, X, Y, W, H, NewX, NewY: string; out L: TLevelLink;
  out Error: string): Boolean;
begin
  Result := False;
  Error := WrongLinkValues;
  L.Dest := Trim(Dest);
  L.X := StrToIntDef(Trim(X), -1);
  L.Y := StrToIntDef(Trim(Y), -1);
  L.W := StrToIntDef(Trim(W), -1);
  L.H := StrToIntDef(Trim(H), -1);
  L.NewX := Trim(NewX);
  L.NewY := Trim(NewY);
  if (L.Dest = '') or (L.NewX = '') or (L.NewY = '') then Exit;
  if (L.X < 0) or (L.Y < 0) or (L.W < 1) or (L.H < 1) or (L.X + L.W > BoardW) or
    (L.Y + L.H > BoardH) then Exit;
  Error := '';
  Result := True;
end;

{ TCtl }

constructor TCtl.Create;
begin
  inherited Create;
  Items := TStringList.Create;
  Enabled := True;
  Visible := True;
  Index := -1;
end;

destructor TCtl.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

{ TFormDialog }

constructor TFormDialog.Create(const ACaption: string; W, H: Integer);
begin
  inherited Create(ACaption, W + 6, H + 25);
  Focus := -1;
  DropOpen := -1;
  FLastClickCtl := -1;
  DefaultButton := IdOK;
end;

destructor TFormDialog.Destroy;
var
  I: Integer;
begin
  Child.Free;
  for I := 0 to High(Ctls) do Ctls[I].Free;
  inherited Destroy;
end;

function TFormDialog.Add(Kind: TCtlKind; X, Y, W, H: Integer; const Caption: string;
  Id: Integer): TCtl;
begin
  Result := TCtl.Create;
  Result.Kind := Kind;
  Result.R := RectI(CX + X, CY + Y, W, H);
  Result.Caption := Caption;
  Result.Id := Id;
  SetLength(Ctls, Length(Ctls) + 1);
  Ctls[High(Ctls)] := Result;
  if (Focus < 0) and (Kind in [ckEdit, ckMemo]) then Focus := High(Ctls);
end;

function TFormDialog.Ctl(Id: Integer): TCtl;
var
  I: Integer;
begin
  for I := 0 to High(Ctls) do
    if (Ctls[I].Id = Id) and (Ctls[I].Kind <> ckLabel) then
    begin
      Result := Ctls[I];
      Exit;
    end;
  Result := nil;
end;

function TFormDialog.TextOf(Id: Integer): string;
var
  C: TCtl;
begin
  C := Ctl(Id);
  if C <> nil then Result := C.Text else Result := '';
end;

procedure TFormDialog.SetText(Id: Integer; const T: string);
var
  C: TCtl;
begin
  C := Ctl(Id);
  if C <> nil then C.Text := T;
end;

procedure TFormDialog.Close(R: TDialogResult);
begin
  Result := R;
  Closing := True;
end;

procedure TFormDialog.OpenChild(D: TEditorDialog);
begin
  Child.Free;
  Child := D;
end;

procedure TFormDialog.Clicked(Id: Integer);
begin
  case Id of
    IdOK: Close(drOk);
    IdCancel: Close(drCancel);
    IdClose: Close(drOk);
  end;
end;

procedure TFormDialog.Changed(Id: Integer);
begin
end;

procedure TFormDialog.DoubleClicked(Id: Integer);
begin
end;

procedure TFormDialog.ChildClosed(D: TEditorDialog);
begin
end;

function TFormDialog.Focusable(N: Integer): Boolean;
begin
  Result := (N >= 0) and (N <= High(Ctls)) and (Ctls[N].Kind in [ckEdit, ckMemo]) and
    Ctls[N].Enabled and Ctls[N].Visible;
end;

function TFormDialog.DropRect(C: TCtl): TRectI;
var
  N: Integer;
begin
  N := C.Items.Count;
  if N > 10 then N := 10;
  Result := RectI(C.R.X, C.R.Y + C.R.H, C.R.W, N * LineH + 2);
end;

function TFormDialog.Step(const I: TEditorInput): Boolean;
var
  K, N, Row: Integer;
  C: TCtl;
  Dbl: Boolean;
  Old: string;
  R: TRectI;
begin
  Result := True;
  if Child <> nil then
  begin
    if not Child.Step(I) then
    begin
      ChildClosed(Child);
      FreeAndNil(Child);
    end;
    Exit;
  end;
  { typing }
  for K := 1 to Length(I.Chars) do
  begin
    case I.Chars[K] of
      #27:
        begin
          if DropOpen >= 0 then DropOpen := -1
          else Close(drCancel);
        end;
      #9:
        if Length(Ctls) > 0 then
        begin
          N := Focus;
          repeat
            N := (N + 1) mod Length(Ctls);
          until Focusable(N) or (N = Focus) or ((Focus < 0) and (N = 0));
          if Focusable(N) then Focus := N;
        end;
    else
      if Focusable(Focus) then
      begin
        C := Ctls[Focus];
        Old := C.Text;
        if C.Kind = ckMemo then
          EditMulti(C.Text, I.Chars[K], 20000)
        else if EditLine(C.Text, I.Chars[K], 255) then
          Clicked(DefaultButton);
        if C.Text <> Old then Changed(C.Id);
      end
      else if I.Chars[K] = #13 then
        Clicked(DefaultButton);
    end;
    if Closing then Break;
  end;
  if not Closing and (I.Wheel <> 0) then
    for K := 0 to High(Ctls) do
      if (Ctls[K].Kind = ckList) and InRect(Ctls[K].R, I.MouseX, I.MouseY) then
        Ctls[K].Top := Ctls[K].Top + I.Wheel;
  { clicks }
  if not Closing and I.LeftPress then
  begin
    if DropOpen >= 0 then
    begin
      C := Ctls[DropOpen];
      R := DropRect(C);
      if InRect(R, I.PressX, I.PressY) then
      begin
        Row := (I.PressY - R.Y - 1) div LineH + C.Top;
        if (Row >= 0) and (Row < C.Items.Count) and (Row <> C.Index) then
        begin
          C.Index := Row;
          Changed(C.Id);
        end;
      end;
      DropOpen := -1;
    end
    else
      for K := 0 to High(Ctls) do
      begin
        C := Ctls[K];
        if not C.Visible or not C.Enabled or (C.Kind in [ckLabel, ckGroup]) then Continue;
        if not InRect(C.R, I.PressX, I.PressY) then Continue;
        Dbl := (K = FLastClickCtl) and (I.NowMs - FLastClickMs <= 400);
        FLastClickCtl := K;
        FLastClickMs := I.NowMs;
        case C.Kind of
          ckButton: Clicked(C.Id);
          ckEdit, ckMemo: Focus := K;
          ckCombo:
            if C.Items.Count > 0 then
            begin
              DropOpen := K;
              C.Top := 0;
            end;
          ckList:
            begin
              Row := (I.PressY - C.R.Y - 2) div LineH;
              if Length(C.Columns) > 0 then Dec(Row); { the header row }
              Row := Row + C.Top;
              if (Row >= 0) and (Row < C.Items.Count) then
              begin
                if Row <> C.Index then
                begin
                  C.Index := Row;
                  Changed(C.Id);
                end;
                if Dbl then DoubleClicked(C.Id);
              end;
            end;
        end;
        Break;
      end;
  end;
  for K := 0 to High(Ctls) do
    if Ctls[K].Kind = ckList then
    begin
      C := Ctls[K];
      N := (C.R.H - 4) div LineH;
      if Length(C.Columns) > 0 then Dec(N);
      if C.Top > C.Items.Count - N then C.Top := C.Items.Count - N;
      if C.Top < 0 then C.Top := 0;
    end;
  Result := not Closing;
end;

procedure TFormDialog.DrawCtl(S: TGSurface; C: TCtl; Focused: Boolean);
var
  Col: Cardinal;
  Rows, Row, Y, X, J, K, P: Integer;
  Line, Cell, T: string;
begin
  if not C.Visible then Exit;
  if C.Enabled then Col := ColText else Col := ColGrayText;
  case C.Kind of
    ckLabel:
      if C.R.H <= 20 then
        DrawLabel(S, C.R.X, C.R.Y, C.Caption, Col)
      else
      begin
        T := WrapLines(C.Caption, C.R.W) + #10;
        Y := C.R.Y;
        repeat
          P := Pos(#10, T);
          DrawLabel(S, C.R.X, Y, Copy(T, 1, P - 1), Col);
          T := Copy(T, P + 1, MaxInt);
          Inc(Y, 11);
        until (T = '') or (Y > C.R.Y + C.R.H);
      end;
    ckGroup:
      GroupCtl(S, C.R, C.Caption);
    ckButton:
      ButtonCtl(S, C.R, StringReplace(C.Caption, '&', '', []), False, C.Enabled);
    ckEdit:
      EditCtl(S, C.R, C.Text, Focused, C.Enabled);
    ckStatus:
      begin
        S.FillRect(C.R.X, C.R.Y, C.R.W, C.R.H, ColYellow);
        Sunken(S, C.R);
        TextClip(S, C.R.X + 4, C.R.Y + (C.R.H - GlyphH) div 2 + 1, C.R.W - 8, C.Text, ColText);
      end;
    ckMemo:
      begin
        S.FillRect(C.R.X, C.R.Y, C.R.W, C.R.H, ColWindow);
        Sunken(S, C.R);
        T := C.Text;
        if Focused then T := T + '_';
        T := WrapLines(T, C.R.W - 10);
        { keep the end (where typing happens) in view }
        Rows := (C.R.H - 6) div 11;
        K := 1;
        for J := 1 to Length(T) do if T[J] = #10 then Inc(K);
        T := T + #10;
        Row := 0;
        Y := C.R.Y + 4;
        repeat
          P := Pos(#10, T);
          if Row >= K - Rows then
          begin
            DrawLabel(S, C.R.X + 4, Y, Copy(T, 1, P - 1), ColText);
            Inc(Y, 11);
          end;
          T := Copy(T, P + 1, MaxInt);
          Inc(Row);
        until T = '';
      end;
    ckCombo:
      begin
        EditCtl(S, RectI(C.R.X, C.R.Y, C.R.W, C.R.H), '', False, C.Enabled);
        if (C.Index >= 0) and (C.Index < C.Items.Count) then
          TextClip(S, C.R.X + 4, C.R.Y + (C.R.H - GlyphH) div 2 + 1, C.R.W - 26,
            C.Items[C.Index], Col);
        ButtonCtl(S, RectI(C.R.X + C.R.W - 18, C.R.Y + 2, 16, C.R.H - 4), 'v', False, C.Enabled);
      end;
    ckList:
      begin
        S.FillRect(C.R.X, C.R.Y, C.R.W, C.R.H, ColWindow);
        Sunken(S, C.R);
        Y := C.R.Y + 2;
        if Length(C.Columns) > 0 then
        begin
          X := C.R.X + 2;
          Line := C.Caption + #9;
          for J := 0 to High(C.Columns) do
          begin
            P := Pos(#9, Line);
            if P = 0 then P := Length(Line) + 1;
            Cell := Copy(Line, 1, P - 1);
            Line := Copy(Line, P + 1, MaxInt);
            ButtonCtl(S, RectI(X, Y, C.Columns[J], LineH), '', False, True);
            TextClip(S, X + 3, Y + 4, C.Columns[J] - 5, Cell, ColText);
            Inc(X, C.Columns[J]);
          end;
          Inc(Y, LineH);
        end;
        Rows := (C.R.Y + C.R.H - 2 - Y) div LineH;
        for Row := C.Top to C.Top + Rows - 1 do
        begin
          if Row >= C.Items.Count then Break;
          if Row = C.Index then
          begin
            S.FillRect(C.R.X + 2, Y, C.R.W - 4, LineH, ColHighlight);
            Col := ColHighlightText;
          end
          else
            Col := ColText;
          Line := C.Items[Row];
          X := C.R.X + 4;
          if Length(C.Columns) = 0 then
            TextClip(S, X, Y + 4, C.R.W - 8, StringReplace(Line, #9, ' ', [rfReplaceAll]), Col)
          else
          begin
            Line := Line + #9;
            for J := 0 to High(C.Columns) do
            begin
              P := Pos(#9, Line);
              if P = 0 then P := Length(Line) + 1;
              TextClip(S, X, Y + 4, C.Columns[J] - 5, Copy(Line, 1, P - 1), Col);
              Line := Copy(Line, P + 1, MaxInt);
              Inc(X, C.Columns[J]);
            end;
          end;
          Inc(Y, LineH);
        end;
      end;
  end;
end;

procedure TFormDialog.Draw(S: TGSurface);
var
  K, Row: Integer;
  C: TCtl;
  R: TRectI;
begin
  inherited Draw(S);
  for K := 0 to High(Ctls) do
    DrawCtl(S, Ctls[K], K = Focus);
  if DropOpen >= 0 then
  begin
    C := Ctls[DropOpen];
    R := DropRect(C);
    S.FillRect(R.X, R.Y, R.W, R.H, ColWindow);
    FrameRect(S, R.X, R.Y, R.W, R.H, ColDark);
    for Row := 0 to 9 do
    begin
      if Row + C.Top >= C.Items.Count then Break;
      if Row + C.Top = C.Index then
      begin
        S.FillRect(R.X + 1, R.Y + 1 + Row * LineH, R.W - 2, LineH, ColHighlight);
        DrawLabel(S, R.X + 4, R.Y + 5 + Row * LineH, C.Items[Row + C.Top], ColHighlightText);
      end
      else
        DrawLabel(S, R.X + 4, R.Y + 5 + Row * LineH, C.Items[Row + C.Top], ColText);
    end;
  end;
  if Child <> nil then Child.Draw(S);
end;

{ TLinkOptionsDialog }

constructor TLinkOptionsDialog.Create(ADoc: TEditorDoc; AIndex: Integer);
begin
  Create(ADoc, ADoc.Level.Links[AIndex]);
  LinkIndex := AIndex;
end;

constructor TLinkOptionsDialog.Create(ADoc: TEditorDoc; const L: TLevelLink);
begin
  inherited Create('Edit link', 353, 337);
  Doc := ADoc;
  LinkIndex := -1;
  Add(ckLabel, 32, 16, 297, 73, 'Specify the warp field and the file/URL where the player ' +
    'should be transported to. Also type in the new player position ( you can use math. ' +
    'operations and variables like playerx/y).', 0);
  Add(ckGroup, 24, 88, 313, 57, 'Warp field', 0);
  Add(ckLabel, 40, 112, 12, 16, 'X:', 0);
  Add(ckLabel, 112, 112, 12, 16, 'Y:', 0);
  Add(ckLabel, 184, 112, 16, 16, 'W:', 0);
  Add(ckLabel, 262, 112, 13, 16, 'H:', 0);
  Add(ckLabel, 22, 165, 90, 16, 'Link to level:', 0);
  Add(ckGroup, 24, 192, 313, 97, 'Destination coordinates', 0);
  Add(ckLabel, 40, 222, 41, 16, 'New X:', 0);
  Add(ckLabel, 40, 262, 42, 16, 'New Y:', 0);
  Add(ckEdit, 112, 158, 233, 22, '', IdFile).Text := L.Dest;
  Add(ckEdit, 56, 106, 41, 22, '', IdX).Text := IntToStr(L.X);
  Add(ckEdit, 128, 106, 41, 22, '', IdY).Text := IntToStr(L.Y);
  Add(ckEdit, 205, 106, 41, 22, '', IdW).Text := IntToStr(L.W);
  Add(ckEdit, 280, 106, 41, 22, '', IdH).Text := IntToStr(L.H);
  Add(ckEdit, 96, 214, 225, 22, '', IdNewX).Text := L.NewX;
  Add(ckEdit, 96, 254, 225, 22, '', IdNewY).Text := L.NewY;
  Add(ckButton, 192, 304, 75, 28, '&OK', IdOK);
  Add(ckButton, 272, 304, 75, 28, '&Cancel', IdCancel);
end;

function TLinkOptionsDialog.Apply: Boolean;
var
  L: TLevelLink;
begin
  Result := LinkFromFields(TextOf(IdFile), TextOf(IdX), TextOf(IdY), TextOf(IdW),
    TextOf(IdH), TextOf(IdNewX), TextOf(IdNewY), L, Error);
  if not Result then Exit;
  if (LinkIndex >= 0) and (LinkIndex <= High(Doc.Level.Links)) then
  begin
    Doc.Level.Links[LinkIndex] := L;
    Doc.Modified := True;
  end
  else
    LinkIndex := Doc.AddLink(L);
end;

procedure TLinkOptionsDialog.Clicked(Id: Integer);
begin
  if Id = IdOK then
  begin
    if Apply then Close(drOk)
    else OpenChild(TMessageDialog.Create('Graal', Error, 1));
  end
  else
    inherited Clicked(Id);
end;

{ TLinkListDialog }

constructor TLinkListDialog.Create(ADoc: TEditorDoc);
var
  C: TCtl;
begin
  inherited Create('Link List', 432, 266);
  Doc := ADoc;
  Add(ckLabel, 150, 16, 200, 16, 'Select a link to edit:', 0);
  C := Add(ckList, 8, 40, 417, 185, 'Linkfile'#9'X'#9'Y'#9'W'#9'H'#9'New X'#9'New Y', IdList);
  SetLength(C.Columns, 7);
  C.Columns[0] := 133; C.Columns[1] := 35; C.Columns[2] := 35; C.Columns[3] := 35;
  C.Columns[4] := 35; C.Columns[5] := 70; C.Columns[6] := 70;
  Add(ckButton, 72, 232, 83, 28, '&Edit', IdEdit);
  Add(ckButton, 160, 232, 89, 28, '&Load', IdLoad);
  Add(ckButton, 256, 232, 91, 28, '&Delete', IdDelete);
  Add(ckButton, 352, 232, 75, 28, '&Close', IdClose);
  DefaultButton := IdEdit;
  Refresh;
end;

procedure TLinkListDialog.Refresh;
var
  C: TCtl;
  I: Integer;
begin
  C := Ctl(IdList);
  C.Items.Clear;
  for I := 0 to High(Doc.Level.Links) do
    with Doc.Level.Links[I] do
      C.Items.Add(Dest + #9 + IntToStr(X) + #9 + IntToStr(Y) + #9 + IntToStr(W) + #9 +
        IntToStr(H) + #9 + NewX + #9 + NewY);
  if C.Index >= C.Items.Count then C.Index := C.Items.Count - 1;
  if (C.Index < 0) and (C.Items.Count > 0) then C.Index := 0;
end;

procedure TLinkListDialog.Clicked(Id: Integer);
var
  N: Integer;
begin
  N := Ctl(IdList).Index;
  case Id of
    IdEdit:
      if (N >= 0) and (N <= High(Doc.Level.Links)) then
        OpenChild(TLinkOptionsDialog.Create(Doc, N));
    IdDelete:
      if (N >= 0) and (N <= High(Doc.Level.Links)) then
      begin
        Doc.DeleteObject(okLink, N);
        Refresh;
      end;
    IdLoad:
      if (N >= 0) and (N <= High(Doc.Level.Links)) then
      begin
        LoadFile := Doc.Level.Links[N].Dest;
        Close(drOk);
      end;
  else
    inherited Clicked(Id);
  end;
end;

procedure TLinkListDialog.DoubleClicked(Id: Integer);
begin
  Clicked(IdEdit);
end;

procedure TLinkListDialog.ChildClosed(D: TEditorDialog);
begin
  Refresh;
end;

{ TSignsDialog }

constructor TSignsDialog.Create(ADoc: TEditorDoc; Select: Integer);
begin
  inherited Create('Edit Signs', 359, 314);
  Doc := ADoc;
  Add(ckLabel, 120, 16, 200, 16, 'Select a sign to edit:', 0);
  Add(ckList, 8, 40, 345, 81, '', IdList);
  Add(ckButton, 8, 128, 65, 25, '&New', IdNew);
  Add(ckButton, 80, 128, 65, 25, '&Delete', IdDelete);
  Add(ckLabel, 168, 134, 11, 16, 'X:', 0);
  Add(ckEdit, 184, 128, 57, 22, '', IdX);
  Add(ckLabel, 264, 134, 12, 16, 'Y:', 0);
  Add(ckEdit, 280, 128, 57, 22, '', IdY);
  Add(ckMemo, 8, 160, 345, 112, '', IdText);
  Add(ckButton, 8, 280, 153, 25, '&Show special codes', IdCodes);
  Add(ckButton, 280, 280, 75, 25, '&Close', IdClose);
  DefaultButton := IdClose;
  Refresh;
  if (Select >= 0) and (Select <= High(Doc.Level.Signs)) then Ctl(IdList).Index := Select;
  LoadSelected;
end;

function SignTitle(const T: string): string;
var
  P: Integer;
begin
  Result := StringReplace(T, '#K(13)', '', [rfReplaceAll]);
  P := Pos(#10, Result);
  if P > 0 then Result := Copy(Result, 1, P - 1);
  if Result = '' then Result := '(empty)';
end;

procedure TSignsDialog.Refresh;
var
  C: TCtl;
  I: Integer;
begin
  C := Ctl(IdList);
  C.Items.Clear;
  for I := 0 to High(Doc.Level.Signs) do
    C.Items.Add(IntToStr(I) + ': ' + SignTitle(Doc.Level.Signs[I].Text));
  if C.Index >= C.Items.Count then C.Index := C.Items.Count - 1;
  if (C.Index < 0) and (C.Items.Count > 0) then C.Index := 0;
end;

procedure TSignsDialog.LoadSelected;
var
  N: Integer;
  Has: Boolean;
begin
  N := Ctl(IdList).Index;
  Has := (N >= 0) and (N <= High(Doc.Level.Signs));
  Ctl(IdX).Enabled := Has;
  Ctl(IdY).Enabled := Has;
  Ctl(IdText).Enabled := Has;
  Ctl(IdDelete).Enabled := Has;
  if Has then
  begin
    SetText(IdX, IntToStr(Doc.Level.Signs[N].X));
    SetText(IdY, IntToStr(Doc.Level.Signs[N].Y));
    SetText(IdText, StringReplace(Doc.Level.Signs[N].Text, '#K(13)', '', [rfReplaceAll]));
    Focus := High(Ctls) - 2;
  end
  else
  begin
    SetText(IdX, '');
    SetText(IdY, '');
    SetText(IdText, '');
    Focus := -1;
  end;
end;

procedure TSignsDialog.Changed(Id: Integer);
var
  N: Integer;
begin
  N := Ctl(IdList).Index;
  if Id = IdList then
  begin
    LoadSelected;
    Exit;
  end;
  if (N < 0) or (N > High(Doc.Level.Signs)) then Exit;
  case Id of
    IdX: Doc.Level.Signs[N].X := StrToIntDef(TextOf(IdX), Doc.Level.Signs[N].X);
    IdY: Doc.Level.Signs[N].Y := StrToIntDef(TextOf(IdY), Doc.Level.Signs[N].Y);
    IdText:
      begin
        Doc.Level.Signs[N].Text := TextOf(IdText);
        Ctl(IdList).Items[N] := IntToStr(N) + ': ' + SignTitle(TextOf(IdText));
      end;
  end;
  Doc.Modified := True;
end;

procedure TSignsDialog.Clicked(Id: Integer);
var
  N: Integer;
begin
  case Id of
    IdNew:
      begin
        N := Doc.AddSign(0, 0);
        Refresh;
        Ctl(IdList).Index := N;
        LoadSelected;
      end;
    IdDelete:
      begin
        N := Ctl(IdList).Index;
        if (N >= 0) and (N <= High(Doc.Level.Signs)) then
        begin
          Doc.DeleteObject(okSign, N);
          Refresh;
          LoadSelected;
        end;
      end;
    IdCodes:
      OpenChild(TShowCodesDialog.Create);
    IdClose:
      begin
        { empty trailing lines are removed (1.41) }
        for N := 0 to High(Doc.Level.Signs) do
          while (Doc.Level.Signs[N].Text <> '') and
            (Doc.Level.Signs[N].Text[Length(Doc.Level.Signs[N].Text)] = #10) do
            Delete(Doc.Level.Signs[N].Text, Length(Doc.Level.Signs[N].Text), 1);
        Close(drOk);
      end;
  else
    inherited Clicked(Id);
  end;
end;

{ TShowCodesDialog }

constructor TShowCodesDialog.Create;
var
  C: TCtl;
  I: Integer;
begin
  inherited Create('Special Codes', 312, 395);
  Add(ckLabel, 60, 16, 250, 16, 'Special graphics codes', 0);
  Add(ckLabel, 30, 32, 280, 16, '(e.g. type #h for the head graphics):', 0);
  C := Add(ckList, 8, 56, 297, 297, '', IdList);
  for I := 0 to High(SignCodes) do C.Items.Add(SignCodes[I]);
  Add(ckButton, 232, 360, 75, 28, '&Close', IdClose);
  DefaultButton := IdClose;
end;

procedure TShowCodesDialog.Clicked(Id: Integer);
begin
  inherited Clicked(Id);
end;

{ TChestDialog }

constructor TChestDialog.Create(ADoc: TEditorDoc; AIndex: Integer);
var
  C: TCtl;
  I: Integer;
begin
  inherited Create('Chest Item', 424, 231);
  Doc := ADoc;
  ChestIndex := AIndex;
  Add(ckGroup, 5, 3, 412, 182, 'Select Item and Sign', 0);
  Add(ckLabel, 24, 32, 360, 57, 'Select an item to place inside the chest and a sign that ' +
    'should be displayed when the player opens the chest (type in -1 if no sign should be ' +
    'displayed).', 0);
  Add(ckLabel, 32, 103, 40, 16, 'Item:', 0);
  Add(ckLabel, 32, 143, 70, 16, 'Sign index:', 0);
  Add(ckEdit, 120, 136, 169, 22, '', IdSign).Text := IntToStr(Doc.Level.Chests[AIndex].Sign);
  Add(ckButton, 304, 134, 97, 28, '&Signs', IdSigns);
  Add(ckButton, 208, 195, 123, 28, '&Delete Chest', IdDelete);
  Add(ckButton, 339, 195, 75, 28, '&Close', IdClose);
  C := Add(ckCombo, 120, 96, 177, 22, '', IdItem);
  for I := 0 to High(ItemNames) do C.Items.Add(ItemNames[I]);
  C.Index := Doc.Level.Chests[AIndex].Item;
  DefaultButton := IdClose;
end;

procedure TChestDialog.Changed(Id: Integer);
begin
  if (ChestIndex < 0) or (ChestIndex > High(Doc.Level.Chests)) then Exit;
  case Id of
    IdItem: Doc.Level.Chests[ChestIndex].Item := Ctl(IdItem).Index;
    IdSign: Doc.Level.Chests[ChestIndex].Sign :=
      StrToIntDef(Trim(TextOf(IdSign)), Doc.Level.Chests[ChestIndex].Sign);
  else
    Exit;
  end;
  Doc.Modified := True;
end;

procedure TChestDialog.Clicked(Id: Integer);
begin
  case Id of
    IdSigns:
      OpenChild(TSignsDialog.Create(Doc, StrToIntDef(Trim(TextOf(IdSign)), -1)));
    IdDelete:
      begin
        Doc.DeleteObject(okChest, ChestIndex);
        Close(drOk);
      end;
  else
    inherited Clicked(Id);
  end;
end;

{ TPersonDialog }

constructor TPersonDialog.Create(ADoc: TEditorDoc; AIndex: Integer);
begin
  inherited Create('Edit non-player character', 418, 225);
  Doc := ADoc;
  NPCIndex := AIndex;
  Add(ckGroup, 8, 8, 401, 177, 'Npc options', 0);
  Add(ckLabel, 16, 24, 380, 73, 'Specify a GIF image for the npc. It should exist in the game ' +
    'directory. When you give the level to other people then you should also copy that ' +
    'image. Press the action button if you want the npc saying something or doing something.', 0);
  Add(ckLabel, 16, 111, 50, 16, 'GIF file:', 0);
  Add(ckEdit, 72, 104, 217, 22, '', IdImage).Text := Doc.Level.NPCs[AIndex].Image;
  Add(ckButton, 288, 136, 105, 28, '&Action', IdAction);
  Add(ckButton, 184, 192, 139, 28, '&Delete Npc', IdDelete);
  Add(ckButton, 328, 192, 83, 28, '&Close', IdClose);
  DefaultButton := IdClose;
end;

procedure TPersonDialog.Changed(Id: Integer);
begin
  if (Id = IdImage) and (NPCIndex >= 0) and (NPCIndex <= High(Doc.Level.NPCs)) then
  begin
    Doc.Level.NPCs[NPCIndex].Image := Trim(TextOf(IdImage));
    Doc.Modified := True;
  end;
end;

procedure TPersonDialog.Clicked(Id: Integer);
begin
  case Id of
    IdAction:
      OpenChild(TScriptDialog.Create(Doc, NPCIndex));
    IdDelete:
      begin
        Doc.DeleteObject(okNPC, NPCIndex);
        Close(drOk);
      end;
  else
    inherited Clicked(Id);
  end;
end;

{ TScriptDialog }

constructor TScriptDialog.Create(ADoc: TEditorDoc; AIndex: Integer);
begin
  inherited Create('Set Npc''s Action', 517, 361);
  Doc := ADoc;
  NPCIndex := AIndex;
  Add(ckGroup, 0, 0, 517, 322, 'Npc''s Action', 0);
  Add(ckLabel, 14, 22, 490, 40, 'Specify the actions that should be invoked in special ' +
    'situations. Press the ''Test'' button to check the syntax.', 0);
  Add(ckMemo, 8, 66, 500, 212, '', IdScript).Text := Doc.Level.NPCs[AIndex].Script;
  Add(ckButton, 433, 286, 75, 28, '&Test', IdTest);
  Add(ckStatus, 8, 331, 336, 24, '', IdTestError);
  Add(ckButton, 352, 328, 75, 28, '&OK', IdOK);
  Add(ckButton, 434, 328, 75, 28, '&Cancel', IdCancel);
  DefaultButton := IdOK;
end;

procedure TScriptDialog.Clicked(Id: Integer);
begin
  case Id of
    IdOK:
      begin
        if (NPCIndex >= 0) and (NPCIndex <= High(Doc.Level.NPCs)) and
          (Doc.Level.NPCs[NPCIndex].Script <> TextOf(IdScript)) then
        begin
          Doc.Level.NPCs[NPCIndex].Script := TextOf(IdScript);
          Doc.Modified := True;
        end;
        Close(drOk);
      end;
    IdTest:
      TestScript;
  else
    inherited Clicked(Id);
  end;
end;

function TScriptDialog.TestScript: string;
var
  G: TGsScript;
begin
  G := TGsScript.Create;
  try
    G.Compile(TextOf(IdScript));
    if G.Errors.Count > 0 then Result := G.Errors[0] else Result := '';
  finally
    G.Free;
  end;
  Ctl(IdTestError).Text := Result;
end;

{ TBaddyDialog }

constructor TBaddyDialog.Create(ADoc: TEditorDoc; AIndex: Integer);
var
  C: TCtl;
  I: Integer;
  V1, V2, V3: string;
begin
  inherited Create('Edit Baddy', 397, 281);
  Doc := ADoc;
  BaddyIndex := AIndex;
  Add(ckGroup, 8, 8, 385, 225, 'Baddy options', 0);
  Add(ckLabel, 40, 32, 313, 33, 'Change the baddy type or the verses the baddy should say ' +
    'in special situations.', 0);
  Add(ckLabel, 24, 87, 40, 16, 'Type:', 0);
  Add(ckLabel, 24, 127, 90, 16, 'Attack verse:', 0);
  Add(ckLabel, 24, 159, 130, 16, 'Saying when hurted:', 0);
  Add(ckLabel, 24, 191, 165, 16, 'Saying when player hurted:', 0);
  SplitVerses(Doc.Level.Baddies[AIndex].Verses, V1, V2, V3);
  Add(ckEdit, 112, 120, 257, 22, '', IdVerse1).Text := V1;
  Add(ckEdit, 160, 152, 209, 22, '', IdVerse2).Text := V2;
  Add(ckEdit, 192, 184, 177, 22, '', IdVerse3).Text := V3;
  Add(ckButton, 176, 248, 129, 28, '&Delete Baddy', IdDelete);
  Add(ckButton, 312, 248, 75, 28, '&Close', IdClose);
  C := Add(ckCombo, 192, 81, 177, 22, '', IdType);
  for I := 0 to High(BaddyTypeNames) do C.Items.Add(BaddyTypeNames[I]);
  C.Index := Doc.Level.Baddies[AIndex].Kind;
  DefaultButton := IdClose;
  Changed(IdType);
end;

procedure TBaddyDialog.Store;
var
  K: Integer;
begin
  if (BaddyIndex < 0) or (BaddyIndex > High(Doc.Level.Baddies)) then Exit;
  K := Ctl(IdType).Index;
  if K < 0 then K := 0;
  Doc.Level.Baddies[BaddyIndex].Kind := K;
  if BaddyTalks(K) then
    Doc.Level.Baddies[BaddyIndex].Verses := StringReplace(TextOf(IdVerse1), '\', '/', [rfReplaceAll]) +
      '\' + StringReplace(TextOf(IdVerse2), '\', '/', [rfReplaceAll]) + '\' +
      StringReplace(TextOf(IdVerse3), '\', '/', [rfReplaceAll])
  else
    Doc.Level.Baddies[BaddyIndex].Verses := '\\';
end;

procedure TBaddyDialog.Changed(Id: Integer);
var
  Talks: Boolean;
begin
  if Id = IdType then
  begin
    { swamp soldiers, frogs and spiders do not talk }
    Talks := BaddyTalks(Ctl(IdType).Index);
    Ctl(IdVerse1).Enabled := Talks;
    Ctl(IdVerse2).Enabled := Talks;
    Ctl(IdVerse3).Enabled := Talks;
    if not Talks and (Focus >= 0) and not Ctls[Focus].Enabled then Focus := -1;
  end;
  if (BaddyIndex >= 0) and (BaddyIndex <= High(Doc.Level.Baddies)) then
  begin
    Store;
    Doc.Modified := True;
  end;
end;

procedure TBaddyDialog.Clicked(Id: Integer);
begin
  case Id of
    IdDelete:
      begin
        Doc.DeleteObject(okBaddy, BaddyIndex);
        BaddyIndex := -1;
        Close(drOk);
      end;
  else
    inherited Clicked(Id);
  end;
end;

{ TFlagsDialog }

constructor TFlagsDialog.Create(AFlags: TStrings);
begin
  inherited Create('Edit Flags', 283, 386);
  Flags := AFlags;
  Add(ckGroup, 8, 8, 265, 337, 'Flag list', 0);
  Add(ckLabel, 24, 24, 217, 57, 'These are the current flags set by the npc''s action ' +
    'scripts. Modify them at your will.', 0);
  Add(ckMemo, 24, 84, 233, 250, '', IdFlags).Text := StringReplace(Flags.Text, #13, '', [rfReplaceAll]);
  Add(ckButton, 192, 352, 75, 28, '&Close', IdClose);
  DefaultButton := IdClose;
end;

procedure TFlagsDialog.Clicked(Id: Integer);
var
  I: Integer;
begin
  if Id = IdClose then
  begin
    Flags.Text := TextOf(IdFlags);
    for I := Flags.Count - 1 downto 0 do
      if Trim(Flags[I]) = '' then Flags.Delete(I)
      else Flags[I] := Trim(Flags[I]);
  end;
  inherited Clicked(Id);
end;

end.
