// The library glue: the C exports, the engine slots the library fills, a
// UDP socket on one side of the link and the engine on the other.
#include "graal3dengine.h"
#include "graalengine.h"
#include "link.hpp"
#include "udp.hpp"

#include <chrono>
#include <memory>
#include <sstream>
#include <string>

namespace {

struct State {
  std::unique_ptr<graal3d::Link> link;
  graal3d::UdpSocket socket;
  std::string connectString, protocolString;
  uint32_t sequence = 0;
  bool loaded = false;
};

State& st() {
  static State s;
  return s;
}

uint32_t nowMs() {
  using namespace std::chrono;
  return static_cast<uint32_t>(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
}

void flushOut() {
  auto& s = st();
  if (!s.link) return;
  for (const auto& d : s.link->takeOutgoing()) s.socket.send(d);
}

void G3D_CALL cbConnect(const char* host, int32_t port) {
  auto& s = st();
  if (s.link) {
    s.link->disconnect("");
    flushOut();
  }
  char account[256] = "", nickname[256] = "", password[256] = "";
  getGraalLoginInfo(account, sizeof account, nickname, sizeof nickname, password, sizeof password);
  graal3d::LinkLogin login;
  login.account = account;
  login.nickname = nickname;
  login.password = password;
  const char* build = graalengine_build();
  login.protocol = graal3d::protocolForBuild(build ? build : "");
  uint32_t seq = s.sequence;
  if (!seq) seq = (nowMs() * 2654435761u) & 0x7FFFFFFEu;
  login.connectSequence = seq;

  graal3d::Link::Callbacks cb;
  cb.log = [](const std::string& line) {
    // The engine's log slot, or stderr with GRAALENGINE_LOG (5.0 has no slot).
    graalengine_logLine(line.c_str());
  };
  cb.loginStep = [](int step) { graalengine_graal3DLoginStep(step); };
  cb.error = [](const std::string& reason) { setGraal3DConnectionError(reason.c_str()); };
  cb.text = [](const graal3d::BigText& t) {
    graalengine_logLine(("Graal3D: server text " + t.s2 + (t.s1.empty() ? "" : " for " + t.s1) + " (" +
                         std::to_string(t.data.size()) + " bytes)")
                            .c_str());
  };
  s.link = std::make_unique<graal3d::Link>(login, cb);
  // The client's own UDP port is random (the fixed-port option is not read
  // yet) (torque/udp-session.md §1).
  if (!s.socket.isOpen() && !s.socket.open(0)) {
    setGraal3DConnectionError("The connection to the Graal3D server couldn't be established.");
    return;
  }
  if (!s.socket.setPeer(host ? host : "", static_cast<uint16_t>(port))) {
    setGraal3DConnectionError("The connection to the Graal3D server couldn't be established.");
    return;
  }
  // The challenge leaves before the TCP connect (§1, "Ordering").
  s.link->start(nowMs());
  flushOut();
}

void G3D_CALL cbRemoveConnection(void) {
  auto& s = st();
  if (!s.link) return;
  s.link->disconnect("");
  flushOut();
  s.link.reset();
  s.socket.close();
}

void G3D_CALL cbScriptEvent(const char* line) {
  if (st().link && line) st().link->queueEventLine(line);
}

void G3D_CALL cbScriptEvents(const char* lines) {
  auto& s = st();
  if (!s.link) return;
  if (lines) {
    std::istringstream in(lines);
    std::string l;
    while (std::getline(in, l)) s.link->queueEventLine(l);
  }
  s.link->flushEventLines();
}

void G3D_CALL cbRemoveMissionGroup(void) {}

void registerSlots(bool on) {
  graal_setConnectTo3DServer(on ? cbConnect : nullptr);
  graal_setRemoveGraal3DConnection(on ? cbRemoveConnection : nullptr);
  graal_setSendGraal3DScriptEvent(on ? cbScriptEvent : nullptr);
  graal_setSendGraal3DScriptEvents(on ? cbScriptEvents : nullptr);
  graal_setRemoveGraal3DMissionGroup(on ? cbRemoveMissionGroup : nullptr);
}

}  // namespace

extern "C" {

G3D_API int32_t G3D_CALL loadGraal3DEngine(const char* cmdline) {
  auto& s = st();
  std::istringstream in(cmdline ? cmdline : "");
  std::string word;
  while (in >> word) {
    if (word == "-connect") in >> s.connectString;
    else if (word.rfind("graal://", 0) == 0 || word.rfind("graal3://", 0) == 0) s.protocolString = word;
  }
  registerSlots(true);
  // Loading the library removes the launcher's StartGraal3D callback
  // (graal3d/torque-engine-4x.md), then initialises the engine again,
  // which only resets the script environment.
  graal_setStartGraal3D(nullptr);
  graal_engineInitialize(nullptr);
  graalengine_logLine("Graal3D activated");
  s.loaded = true;
  return 1;
}

G3D_API void G3D_CALL runGraal3DEngine(void) {
  auto& s = st();
  if (!s.link) return;
  const uint32_t now = nowMs();
  std::string d;
  while (s.link && s.socket.receive(d)) s.link->receive(d, now);
  if (!s.link) return;
  s.link->tick(now);
  flushOut();
}

G3D_API void G3D_CALL endGraal3DEngine(void) {
  cbRemoveConnection();
  registerSlots(false);
  st().loaded = false;
}

G3D_API void G3D_CALL resizeGraal3DWindow(int32_t, int32_t) {}

G3D_API void G3D_CALL toggleGraal3DFullScreen(void) {}

G3D_API int32_t G3D_CALL graal3dengine_abi(void) { return GRAAL3DENGINE_ABI; }

G3D_API int32_t G3D_CALL graal3dengine_loginStep(void) { return st().link ? st().link->loginStep() : 0; }

G3D_API int32_t G3D_CALL graal3dengine_state(void) {
  return st().link ? static_cast<int32_t>(st().link->state()) : 0;
}

G3D_API int32_t G3D_CALL graal3dengine_ghostCount(void) {
  return st().link ? static_cast<int32_t>(st().link->ghosts().size()) : 0;
}

G3D_API void G3D_CALL graal3dengine_setConnectSequence(uint32_t sequence) { st().sequence = sequence; }

}  // extern "C"
