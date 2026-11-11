{ Worlds70175: what the Worlds 7.0.1.7.5.0 image shows. A scaffold only.

  Worlds.exe is a Unity 6000.0.63f1 player. Its version resource is the Unity
  version, not a Graal version. The game code is an IL2CPP GameAssembly.dll
  beside it, and the native plugin is Graal3DEngine.dll (no version resource).
  No eight-character token is stored in this build, so none is written. }
unit Worlds70175;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  ScaffoldOnly = True;
  BuildLabel = '7.0.1.7.5.0';
  { Unity bundleVersion (Application.version), from data.unity3d. }
  BundleVersion = '701750';
  BundleVersionProven = False;
  UnityVersion = '6000.0.63f1';
  { Graal3DEngine FileVersion. Empty: the plugin has no version resource. }
  PluginFileVersion = '';
  { GameAssembly.dll PE time stamp, as a date. }
  BuildDate = '2026-04-03';
  CompanyName = 'toonslab';
  ProductName = 'GraalOnline Worlds';
  MainExe = 'Worlds.exe';
  HasGameAssembly = True;
  LinksTorque = False;
  StoresEightCharToken = False;
  TokenLiteral = '';

implementation

end.
