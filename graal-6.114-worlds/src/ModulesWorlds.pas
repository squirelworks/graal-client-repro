{ ModulesWorlds: the IL2CPP assembly list of the 6.114 Worlds host.

  Primary list is build 614. The same host was dumped for 548, 610, 612,
  613 and 71243; the folder README records which names differ. Names and
  roles only. No type bodies, no player, no native plugin.

  ScaffoldOnly tells scripts/loopback.sh and scripts/stress.sh that this
  folder has no wire client. }
unit ModulesWorlds;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { No login, no board, no server. }
  ScaffoldOnly = True;
  WorldsAssemblyCount = 108;

type
  TWorldsAssemblyKind = (
    wakQuattro,   { game assemblies shipped with Quattro }
    wakUnity,     { Unity engine modules and Unity packages }
    wakRuntime,   { language runtime }
    wakPlugin,    { third-party plugin }
    wakGenerated  { IL2CPP generated image }
  );

  TWorldsAssembly = record
    Name: string;
    Kind: TWorldsAssemblyKind;
  end;

const
  WorldsAssemblies: array[0..WorldsAssemblyCount - 1] of TWorldsAssembly = (
    (Name: 'Assemblies-Quattro.dll'; Kind: wakQuattro),
    (Name: 'mscorlib.dll'; Kind: wakRuntime),
    (Name: 'UnityEngine.UIElementsModule.dll'; Kind: wakUnity),
    (Name: 'System.Xml.dll'; Kind: wakRuntime),
    (Name: 'UnityEngine.CoreModule.dll'; Kind: wakUnity),
    (Name: 'System.dll'; Kind: wakRuntime),
    (Name: 'Unity.InputSystem.dll'; Kind: wakUnity),
    (Name: 'Unity.RenderPipelines.Core.Runtime.dll'; Kind: wakUnity),
    (Name: 'Newtonsoft.Json.dll'; Kind: wakPlugin),
    (Name: 'System.Data.dll'; Kind: wakRuntime),
    (Name: 'Assemblies-quattroplugins.dll'; Kind: wakQuattro),
    (Name: 'Unity.RenderPipelines.Universal.Runtime.dll'; Kind: wakUnity),
    (Name: 'System.Core.dll'; Kind: wakRuntime),
    (Name: 'Cinemachine.dll'; Kind: wakPlugin),
    (Name: 'UnityEngine.UI.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.TextCoreTextEngineModule.dll'; Kind: wakUnity),
    (Name: 'PlayMaker.dll'; Kind: wakPlugin),
    (Name: 'Unity.RenderPipelines.Universal.2D.Runtime.dll'; Kind: wakUnity),
    (Name: 'Assemblies-Quattroshared.dll'; Kind: wakQuattro),
    (Name: 'Unity.Postprocessing.Runtime.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.IMGUIModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.Stores.dll'; Kind: wakUnity),
    (Name: 'Mono.Security.dll'; Kind: wakRuntime),
    (Name: 'Backtrace.Unity.dll'; Kind: wakPlugin),
    (Name: 'UnityEngine.PropertiesModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Physics2DModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.PhysicsModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.ParticleSystemModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.dll'; Kind: wakUnity),
    (Name: 'Unity.VisualEffectGraph.Runtime.dll'; Kind: wakUnity),
    (Name: 'SimpleFileBrowser.Runtime.dll'; Kind: wakPlugin),
    (Name: 'IngameDebugConsole.Runtime.dll'; Kind: wakPlugin),
    (Name: 'UnityEngine.AnimationModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.AndroidJNIModule.dll'; Kind: wakUnity),
    (Name: 'ICSharpCode.SharpZipLib.dll'; Kind: wakPlugin),
    (Name: 'System.Drawing.dll'; Kind: wakRuntime),
    (Name: 'Unity.Services.Analytics.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.InputForUIModule.dll'; Kind: wakUnity),
    (Name: 'System.Numerics.dll'; Kind: wakRuntime),
    (Name: 'Unity.Services.Core.Internal.dll'; Kind: wakUnity),
    (Name: 'System.Xml.Linq.dll'; Kind: wakRuntime),
    (Name: 'UnityEngine.UnityWebRequestModule.dll'; Kind: wakUnity),
    (Name: 'Unity.2D.SpriteShape.Runtime.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.TextCoreFontEngineModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Mathematics.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.AudioModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.VideoModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Burst.dll'; Kind: wakUnity),
    (Name: 'Assemblies-quattrosharedlowlevel.dll'; Kind: wakQuattro),
    (Name: 'UnityEngine.TextRenderingModule.dll'; Kind: wakUnity),
    (Name: 'Unity.2D.Common.Runtime.dll'; Kind: wakUnity),
    (Name: 'Unity.ResourceManager.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.InputLegacyModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.UIModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Services.Core.Telemetry.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.XRModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.VFXModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Collections.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.UnityAnalyticsModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.AccessibilityModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.TerrainModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.TilemapModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.UnityAnalyticsCommonModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Services.Core.Registration.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.SubsystemsModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.DirectorModule.dll'; Kind: wakUnity),
    (Name: 'Unity.InputSystem.ForUI.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.AssetBundleModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.HierarchyCoreModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.UnityWebRequestWWWModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.InputModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.JSONSerializeModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.MarshallingModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.VRModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.ImageConversionModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.SharedInternalsModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.SpriteShapeModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Services.Core.Configuration.dll'; Kind: wakUnity),
    (Name: 'Unity.Services.Core.Scheduler.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.AIModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.GridModule.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.ScreenCaptureModule.dll'; Kind: wakUnity),
    (Name: 'Assemblies-playmaker.dll'; Kind: wakPlugin),
    (Name: 'Purchasing.Common.dll'; Kind: wakPlugin),
    (Name: 'UnityEngine.SpriteMaskModule.dll'; Kind: wakUnity),
    (Name: 'Unity.Services.Core.dll'; Kind: wakUnity),
    (Name: 'Unity.Analytics.StandardEvents.dll'; Kind: wakUnity),
    (Name: 'Unity.Localization.dll'; Kind: wakUnity),
    (Name: 'Unity.RenderPipeline.Universal.ShaderLibrary.dll'; Kind: wakUnity),
    (Name: 'Assembly-CSharp.dll'; Kind: wakQuattro),
    (Name: 'UnityEngine.Purchasing.WinRTCore.dll'; Kind: wakUnity),
    (Name: 'System.Runtime.Serialization.dll'; Kind: wakRuntime),
    (Name: 'Unity.Services.Core.Device.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.SecurityCore.dll'; Kind: wakUnity),
    (Name: 'Assemblies-graalunity.dll'; Kind: wakQuattro),
    (Name: 'Unity.LevelPlay.dll'; Kind: wakPlugin),
    (Name: 'Unity.RenderPipelines.ShaderGraph.ShaderGraphLibrary.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.AppleCore.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.AppleMacosStub.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.AppleStub.dll'; Kind: wakUnity),
    (Name: 'com.rlabrecque.steamworks.net.dll'; Kind: wakPlugin),
    (Name: 'Unity.Services.Core.Environments.Internal.dll'; Kind: wakUnity),
    (Name: 'Unity.Services.Core.Threading.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.SecurityStub.dll'; Kind: wakUnity),
    (Name: 'UnityEngine.Purchasing.WinRTStub.dll'; Kind: wakUnity),
    (Name: 'Unity.Burst.Unsafe.dll'; Kind: wakUnity),
    (Name: '__Generated'; Kind: wakGenerated)
  );

{ The clear eight-character login token was not in these builds. }
function WorldsLoginTokenKnown: Boolean;
function WorldsAssemblyIndex(const Name: string): Integer;
function WorldsAssemblyPurpose(const Name: string): string;

implementation

function WorldsLoginTokenKnown: Boolean;
begin
  Result := False;
end;

function WorldsAssemblyIndex(const Name: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(WorldsAssemblies) do
    if WorldsAssemblies[I].Name = Name then
    begin
      Result := I;
      Exit;
    end;
end;

function WorldsAssemblyPurpose(const Name: string): string;
var
  I: Integer;
begin
  if Name = 'Assemblies-Quattro.dll' then
    Result := 'Quattro gameplay assembly. Its type bodies were not recovered, so none are named here.'
  else if Name = 'Assemblies-quattroplugins.dll' then
    Result := 'Small Quattro plugin assembly: runtime sky, a spinning planet, and mesh-file loading.'
  else if Name = 'Assemblies-Quattroshared.dll' then
    Result := 'Shared Quattro scene: tiles, lights, warps, mesh helpers, and editor map objects.'
  else if Name = 'Assemblies-quattrosharedlowlevel.dll' then
    Result := 'Low-level Quattro client: asset bundles, streaming files, and a cipher helper.'
  else if Name = 'Assemblies-graalunity.dll' then
    Result := 'C# side of the native bridge: an actor and the data passed across from the Graal plugin.'
  else if Name = 'Assembly-CSharp.dll' then
    Result := 'Unity script assembly. Here it is a render-pass feature and an id helper, not the game.'
  else if Name = 'Assemblies-playmaker.dll' then
    Result := 'PlayMaker UI event glue shipped with the game.'
  else if Name = 'PlayMaker.dll' then
    Result := 'PlayMaker visual-scripting product.'
  else if Name = 'Unity.LevelPlay.dll' then
    Result := 'Third-party ads package.'
  else if Name = '__Generated' then
    Result := 'IL2CPP generated image, not a game module.'
  else
  begin
    Result := '';
    I := WorldsAssemblyIndex(Name);
    if I < 0 then Exit;
    case WorldsAssemblies[I].Kind of
      wakQuattro: Result := 'Quattro game assembly.';
      wakUnity: Result := 'Unity engine module or Unity package.';
      wakRuntime: Result := 'Language runtime.';
      wakPlugin: Result := 'Third-party plugin.';
      wakGenerated: Result := 'IL2CPP generated image, not a game module.';
    end;
  end;
end;

end.
