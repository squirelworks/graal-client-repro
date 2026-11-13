// The C exports: one setter per slot, the entry points, and the rebuild's
// slot-list queries.
#include "engine.hpp"
#include "graalengine.h"
#include "host.hpp"

#include <algorithm>
#include <cstring>

namespace graalengine::host {

Table& table() {
  static Table t;
  return t;
}

void clear() { table() = Table{}; }

}  // namespace graalengine::host

namespace {

struct SlotInfo {
  const char* name;
  int builds;
};

const SlotInfo kSlots[] = {
#define GE_SLOT(Name, Ret, Default, Params, Args, Builds) {#Name, Builds},
#include "graalengine_slots.def"
#undef GE_SLOT
};

constexpr int kSlotCount = static_cast<int>(sizeof(kSlots) / sizeof(kSlots[0]));

}  // namespace

extern "C" {

#define GE_SLOT(Name, Ret, Default, Params, Args, Builds) \
  GE_API void GE_CALL graal_set##Name(graal_##Name##_fn fn) { graalengine::host::table().Name = fn; }
#include "graalengine_slots.def"
#undef GE_SLOT

GE_API int32_t GE_CALL graal_engineInitialize(const char* exe_path) {
  return graalengine::engine().initialize(exe_path) ? 1 : 0;
}

GE_API void GE_CALL loadGraalGui(void) { graalengine::engine().loadGui(); }

GE_API void GE_CALL renderGraalCanvas(void) { graalengine::engine().render(true); }

GE_API void GE_CALL renderGraal(void) { graalengine::engine().render(false); }

GE_API void GE_CALL invokeGraalKeyboardEvent(int32_t vk, int32_t ch, int32_t mods, int32_t down) {
  graalengine::engine().key(vk, ch, mods, down != 0);
}

GE_API void GE_CALL invokeGraalMouseEvent(int32_t x, int32_t y, int32_t action, int32_t button,
                                          int32_t clicks, int32_t mods, int32_t wheel) {
  graalengine::engine().mouse(x, y, action, button, clicks, mods, wheel);
}

GE_API void GE_CALL startOfflineMode(void) { graalengine::engine().startOffline(); }

GE_API void GE_CALL connectToGraalServer(const char* name, const char* host, int32_t port) {
  graalengine::engine().connect(name ? name : "", host ? host : "", port);
}

GE_API void GE_CALL openGraalServerList(void) { graalengine::engine().openServerList(); }

GE_API void GE_CALL enableScriptedControls(int32_t enable) {
  graalengine::engine().enableScriptedControls(enable != 0);
}

GE_API void GE_CALL prepareGraalShutdown(void) { graalengine::engine().prepareShutdown(); }

GE_API void GE_CALL shutdownGraalEngine(void) {
  graalengine::engine().shutdown();
  graalengine::resetEngine();
}

GE_API int32_t GE_CALL graalengine_abi(void) { return GRAALENGINE_ABI; }

GE_API int32_t GE_CALL graalengine_setBuild(const char* label) {
  return graalengine::engine().setBuild(label ? label : "") ? 1 : 0;
}

GE_API const char* GE_CALL graalengine_build(void) { return graalengine::engine().build().c_str(); }

GE_API void GE_CALL graalengine_graal3DLoginStep(int32_t step) { graalengine::engine().graal3DLoginStep(step); }

GE_API void GE_CALL graalengine_logLine(const char* line) { graalengine::engine().log(line ? line : ""); }

GE_API int32_t GE_CALL isGraal3DMode(void) { return graalengine::engine().graal3DMode() ? 1 : 0; }

GE_API void GE_CALL getGraalLoginInfo(char* account, int32_t accountSize, char* nickname, int32_t nicknameSize,
                                      char* password, int32_t passwordSize) {
  const auto a = graalengine::engine().loginAccount();
  auto put = [](char* out, int32_t size, const std::string& v) {
    if (!out || size <= 0) return;
    const size_t n = std::min(v.size(), static_cast<size_t>(size - 1));
    std::memcpy(out, v.data(), n);
    out[n] = '\0';
  };
  put(account, accountSize, a.account);
  put(nickname, nicknameSize, a.nickname);
  put(password, passwordSize, a.password);
}

GE_API void GE_CALL setGraal3DConnectionError(const char* reason) {
  graalengine::engine().graal3DConnectionError(reason ? reason : "");
}

GE_API int32_t GE_CALL graalengine_slotCount(void) { return kSlotCount; }

GE_API const char* GE_CALL graalengine_slotName(int32_t index) {
  return index >= 0 && index < kSlotCount ? kSlots[index].name : nullptr;
}

GE_API int32_t GE_CALL graalengine_slotBuilds(int32_t index) {
  return index >= 0 && index < kSlotCount ? kSlots[index].builds : 0;
}

}  // extern "C"
