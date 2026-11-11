{ Worlds71243: what the Worlds 71243 image shows. A scaffold only.

  Worlds.exe is a Unity 2023.2.20f1 player. Its version resource is the Unity
  version, not a Graal version. The game code is an IL2CPP GameAssembly.dll
  beside it, and the native plugin is Graal3DEngine.dll (no version resource).
  No eight-character token is stored in this build, so none is written. }
unit Worlds71243;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  ScaffoldOnly = True;
  BuildLabel = '71243';
  { Unity bundleVersion (Application.version), from data.unity3d. }
  BundleVersion = '71243';
  BundleVersionProven = True;
  UnityVersion = '2023.2.20f1';
  { Graal3DEngine FileVersion. Empty: the plugin has no version resource. }
  PluginFileVersion = '';
  { GameAssembly.dll PE time stamp, as a date. }
  BuildDate = '2024-10-15';
  CompanyName = 'toonslab';
  ProductName = 'GraalOnline Worlds';
  MainExe = 'Worlds.exe';
  HasGameAssembly = True;
  LinksTorque = False;
  StoresEightCharToken = False;
  TokenLiteral = '';

implementation

end.
