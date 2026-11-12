// Console variables the 3.04 engine itself owns. They export quoted even
// when a script stores a number in them, unlike script variables, which keep
// the type they were stored with. Observed in the lab: the prefs.cs the
// original 3.04 wrote on exit (Graal_analysis torque-304 stage 0 run) quotes
// these names, and the shipped scripts either never set them or set them as
// numbers. The $pref::Graal:: names are also the engine's own list in
// Graal_analysis torque/engine-304.md.
//
// Values are the ones that export shows. Whether each is the engine's
// initial value or one the engine set later (video, input or Graal start-up)
// is not read: $pref::Input::MouseEnabled and $pref::Video::appliedPref are
// set by the scripts first and still export as the engine's value, so the
// engine changes them after the scripts run.

#include "engine.hpp"

namespace Torque {

void register_engine_prefs_304(Engine& e) {
  static const char* const prefs[][2] = {
      {"$pref::Audio::choosenvoicecodec", "-1"},
      {"$pref::Audio::microactivatebyvolume", "1"},
      {"$pref::Audio::microactivationlevel", "75"},
      {"$pref::Audio::microinputdevice", "-1"},
      {"$pref::Audio::microon", "0"},
      {"$pref::Audio::midivolume", "100"},
      {"$pref::Audio::mp3volume", "100"},
      {"$pref::Audio::radiovolume", "20"},
      {"$pref::Audio::reversestereo", "0"},
      {"$pref::Audio::sfxvolume", "100"},
      {"$pref::Audio::voicevolume", "100"},
      {"$pref::CloudsOn", "1"},
      {"$pref::Decal::decalTimeout", "5000"},
      {"$pref::Decal::maxNumDecals", "256"},
      {"$pref::decalsOn", "1"},
      {"$pref::Editor::visibleDistance", "2100"},
      {"$pref::environmentMaps", "1"},
      {"$pref::Graal::accountname", ""},
      {"$pref::Graal::automapping", "1"},
      {"$pref::Graal::defaultfontsize", "24"},
      {"$pref::Graal::dontconnectlevels", "0"},
      {"$pref::Graal::dontloadlistheads", "0"},
      {"$pref::Graal::fixedport", "0"},
      {"$pref::Graal::fixedudpport", "14899"},
      {"$pref::Graal::language", "English"},
      {"$pref::Graal::limitnicknames", "0"},
      {"$pref::Graal::nickname", ""},
      {"$pref::Graal::nicknamelimit", "50"},
      {"$pref::Graal::notoalls", "0"},
      {"$pref::Graal::noudp", "0"},
      {"$pref::Input::JoystickEnabled", "0"},
      {"$pref::Input::KeyboardEnabled", "1"},
      {"$pref::Input::MouseEnabled", "1"},
      {"$pref::Interior::detailAdjust", "1"},
      {"$pref::Interior::DynamicLights", "1"},
      {"$pref::Interior::LightUpdatePeriod", "66"},
      {"$pref::Interior::lockArrays", "1"},
      {"$pref::Interior::ShowEnvironmentMaps", "1"},
      {"$pref::Interior::TexturedFog", "0"},
      {"$pref::Interior::VertexLighting", "0"},
      {"$Pref::Net::LagThreshold", "400"},
      {"$pref::Net::PacketRateToClient", "10"},
      {"$pref::Net::PacketRateToServer", "32"},
      {"$pref::Net::PacketSize", "200"},
      {"$pref::NumCloudLayers", "3"},
      {"$pref::OpenGL::allowCompression", "0"},
      {"$pref::OpenGL::allowTexGen", "1"},
      {"$pref::OpenGL::disableARBMultitexture", "0"},
      {"$pref::OpenGL::disableARBTextureCompression", "0"},
      {"$pref::OpenGL::disableEXTCompiledVertexArray", "0"},
      {"$pref::OpenGL::disableEXTFogCoord", "0"},
      {"$pref::OpenGL::disableEXTPalettedTexture", "0"},
      {"$pref::OpenGL::disableEXTTexEnvCombine", "0"},
      {"$pref::OpenGL::disableSubImage", "0"},
      {"$pref::OpenGL::gammaCorrection", "0.5"},
      {"$pref::OpenGL::maxHardwareLights", "3"},
      {"$pref::OpenGL::noDrawArraysAlpha", "0"},
      {"$pref::OpenGL::noEnvColor", "0"},
      {"$pref::OpenGL::textureAnisotropy", "0"},
      {"$pref::OpenGL::textureTrilinear", "0"},
      {"$pref::Player::renderMyItems", "1"},
      {"$pref::Player::renderMyPlayer", "1"},
      {"$pref::precipitationOn", "1"},
      {"$pref::prePause", "0"},
      {"$pref::SkyOn", "1"},
      {"$pref::Terrain::dynamicLights", "1"},
      {"$pref::Terrain::enableDetails", "1"},
      {"$pref::Terrain::screenError", "4"},
      {"$pref::Terrain::texDetail", "0"},
      {"$pref::Terrain::textureCacheSize", "512"},
      {"$pref::TS::autoDetail", "1"},
      {"$pref::TS::detailAdjust", "0.45"},
      {"$pref::TS::fogTexture", "0"},
      {"$pref::TS::screenError", "5"},
      {"$pref::TS::skipFirstFog", "0"},
      {"$pref::TS::skipLoadDLs", "0"},
      {"$pref::TS::skipRenderDLs", "0"},
      {"$pref::Video::appliedPref", "1"},
      {"$pref::Video::fullScreen", "0"},
      {"$pref::Video::resolution", "800 600 24"},
      {"$pref::visibleDistanceMod", "1"},
  };
  for (const auto& p : prefs) e.bind_variable(p[0], p[1]);
}

} // namespace Torque
