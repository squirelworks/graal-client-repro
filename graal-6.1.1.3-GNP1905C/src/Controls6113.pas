{ Controls6113: the 6.1.1.3 control names on quattro_lib.

  The Gui set matches 6.037. This build has TFontData and drops
  TDrawableObject. StartScript_Connector and StartScript_Fail are script
  names, not a login layout. No packet id is declared here. }
unit Controls6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

function ControlCount: Integer;
function ControlName(Index: Integer): string;
function LevelViewLog: string;

implementation

const
  Controls: array[0..70] of string = (
    'GuiCanvas', 'GuiControl', 'GuiControlProfile', 'GuiCursor',
    'GuiGraalCtrl', 'GuiTilesCtrl',
    'GuiTextEditCtrl', 'GuiTextCtrl', 'GuiMLTextCtrl', 'GuiMLTextEditCtrl',
    'GuiPMCtrl', 'GuiPMEditCtrl', 'GuiPMHistoryCtrl',
    'GuiWindowCtrl', 'GuiScrollCtrl', 'GuiFrameSetCtrl', 'GuiTabCtrl',
    'GuiButtonCtrl', 'GuiCheckBoxCtrl', 'GuiRadioCtrl', 'GuiBitmapButtonCtrl',
    'GuiTextListCtrl', 'GuiTreeViewCtrl', 'GuiPopUpMenuCtrl', 'GuiMenuCtrl',
    'GuiContextMenuCtrl',
    'GuiBitmapCtrl', 'GuiBitmapBorderCtrl', 'GuiStretchCtrl', 'GuiSliderCtrl',
    'GuiProgressCtrl', 'GuiArrayCtrl',
    'GuiShowImgCtrl', 'GuiDrawingPanel',
    'GuiAccountPasswordCtrl', 'GuiStartMenuCtrl', 'GuiTaskbar',
    'GuiAccordionCtrl', 'GuiAnimationCtrl', 'GuiSlideShowCtrl', 'GuiFlash',
    'TWindowDirectX9', 'TWindowOpenGL', 'TWindowGDI',
    'TScreenPanelDirectX9', 'TScreenPanelOpenGL',
    'TDrawingPanel', 'TPanelInterface', 'TDummyPanel',
    'TPanelOperation_Clear', 'TPanelOperation_DrawImage',
    'TPanelOperation_DrawStretched', 'TPanelOperation_DrawLine',
    'TPanelOperation_DrawRectangle', 'TPanelOperation_DrawCurve',
    'TPanelOperation_DrawText',
    'TTilesLayer',
    'TTileMap', 'TTileMapLayer', 'TTileMapObject', 'TTileLayer', 'TTileSprite',
    'TTileImageMap', 'TTileAnimation', 'TLayerTilesVar',
    'TControlBinding', 'TGUIStyle', 'TGUIAnimation',
    'TServerSign', 'TBodyPanel', 'TFontData'
  );

function ControlCount: Integer;
begin
  Result := Length(Controls);
end;

function ControlName(Index: Integer): string;
begin
  if (Index < 0) or (Index >= Length(Controls)) then Result := ''
  else Result := Controls[Index];
end;

{ provisional: open GraalControl as the GuiGraalCtrl level view }
function OpenGraalControl: string;
begin
  Result := 'level view opened: GraalControl (GuiGraalCtrl)' + #10;
end;

{ provisional: leave GuiTilesCtrl's parent against GuiGraalCtrl unsettled }
function GapTiles: string;
begin
  Result := 'stub tiles: GuiTilesCtrl is live and its parent is unsettled' + #10;
end;

{ provisional: leave GUIContainer, GraalControl and ChatBar unlinked }
function GapParent: string;
begin
  Result := 'stub parent: GUIContainer, GraalControl, GuiTilesCtrl and ChatBar' + #10;
end;

{ provisional: scroll a sign by action 0 for up and any other action for down }
function GapSign: string;
begin
  Result := 'stub sign: action 0 scrolls up while a sign is open' + #10;
end;

{ provisional: leave the level paint unconnected to the panel operations }
function GapPaint: string;
begin
  Result := 'stub paint: panel operations are not called from the level control' + #10;
end;

{ provisional: keep TTileSprite and GuiShowImgCtrl as separate names }
function GapShowimg: string;
begin
  Result := 'stub showimg: TTileSprite and GuiShowImgCtrl are not one path' + #10;
end;

{ provisional: leave hearts as properties and item images }
function GapHearts: string;
begin
  Result := 'stub hearts: no HUD control' + #10;
end;

{ provisional: leave TBodyPanel as RTTI with no caption }
function GapBody: string;
begin
  Result := 'stub body: TBodyPanel has no caption' + #10;
end;

{ provisional: keep StartScript_Connector and StartScript_Fail unnamed as layouts }
function GapConnector: string;
begin
  Result := 'stub connector: StartScript_Connector and StartScript_Fail are not a login layout' + #10;
end;

function LevelViewLog: string;
begin
  Result :=
    OpenGraalControl +
    GapTiles +
    GapParent +
    'script-bound action pause' + #10 +
    'script-bound action itemlist' + #10 +
    'script-bound action switchtochat' + #10 +
    'script-bound action map' + #10 +
    'script-bound action action' + #10 +
    'script-bound action attack' + #10 +
    'script-bound action item' + #10 +
    'script-bound keyset F5 position' + #10 +
    'script-bound keyset F8 server list' + #10 +
    GapSign +
    GapPaint +
    GapShowimg +
    GapHearts +
    GapBody +
    GapConnector;
end;

end.
