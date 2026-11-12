{ GVer.inc: period Delphi version defines for the shared units (issue #114).
  GC_D4: Delphi 4 (VER120). GC_D5DOWN: Delphi 4 or 5. GC_D6DOWN: Delphi 4,
  5 or 6. None is defined under Free Pascal or Delphi 7 and later. }
{$IFNDEF FPC}
{$IFDEF VER120}{$DEFINE GC_D4}{$DEFINE GC_D5DOWN}{$DEFINE GC_D6DOWN}{$ENDIF}
{$IFDEF VER130}{$DEFINE GC_D5DOWN}{$DEFINE GC_D6DOWN}{$ENDIF}
{$IFDEF VER140}{$DEFINE GC_D6DOWN}{$ENDIF}
{$ENDIF}
