// Recording-host tests for the engine library. No original files: the host
// here is a set of plain functions that log what the engine asks for.
#include "canvas.hpp"
#include "engine.hpp"
#include "graalengine.h"
#include "host.hpp"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace {

int failures = 0;

#define CHECK(cond)                                                      \
  do {                                                                   \
    if (!(cond)) {                                                       \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                        \
    }                                                                    \
  } while (0)

std::vector<std::string> calls;
int screenW = 800, screenH = 600;

int32_t GE_CALL recWidth() { return screenW; }
int32_t GE_CALL recHeight() { return screenH; }
void GE_CALL recClip(int32_t x, int32_t y, int32_t w, int32_t h) {
  calls.push_back("clip " + std::to_string(x) + "," + std::to_string(y) + "," + std::to_string(w) + "," +
                  std::to_string(h));
}
void GE_CALL recFill(int32_t x, int32_t y, int32_t w, int32_t h, uint32_t c) {
  char buf[96];
  std::snprintf(buf, sizeof buf, "fill %d,%d,%d,%d %08x", x, y, w, h, c);
  calls.push_back(buf);
}
void GE_CALL recText(int32_t x, int32_t y, const char* t, const char*, int32_t, int32_t, uint32_t) {
  calls.push_back("text " + std::to_string(x) + "," + std::to_string(y) + " " + t);
}
void GE_CALL recLog(const char* line) { calls.push_back(std::string("log ") + line); }
void GE_CALL rec3D() { calls.push_back("start3d"); }

void installRecorder() {
  graal_setGetScreenWidth(recWidth);
  graal_setGetScreenHeight(recHeight);
  graal_setSetClippingRectangle(recClip);
  graal_setFillScreenRectangle(recFill);
  graal_setDrawText(recText);
  graal_setLogGraalMessage(recLog);
  graal_setStartGraal3D(rec3D);
}

void reset() {
  graalengine::resetEngine();
  graalengine::host::clear();
  calls.clear();
  screenW = 800;
  screenH = 600;
}

// A control that fills its own rectangle and logs input it takes.
class Box : public graalengine::Control {
 public:
  Box(std::string name, graal_rect r, uint32_t color, bool takes = true)
      : Control(std::move(name)), color_(color), takes_(takes) {
    rect() = r;
  }
  void resize(int, int) override {}  // keeps its own rectangle
  std::vector<std::string> got;

 protected:
  void onRender(const graal_rect&) override {
    graalengine::host::FillScreenRectangle(rect().x, rect().y, rect().w, rect().h, color_);
  }
  bool onInput(const graalengine::InputEvent& ev) override {
    if (!takes_) return false;
    got.push_back(std::to_string(static_cast<int>(ev.kind)) + ":" + std::to_string(ev.vk) + ":" +
                  std::to_string(ev.x) + "," + std::to_string(ev.y));
    return true;
  }

 private:
  uint32_t color_;
  bool takes_;
};

void testSlotList() {
  const int n = graalengine_slotCount();
  int b4 = 0, b5 = 0, b3d = 0;
  std::vector<std::string> names;
  for (int i = 0; i < n; ++i) {
    const int b = graalengine_slotBuilds(i);
    if (b & GRAAL_BUILD_4208) ++b4;
    if (b & GRAAL_BUILD_5007) ++b5;
    if (b & GRAAL_BUILD_3D) ++b3d;
    CHECK(b != 0);
    const char* name = graalengine_slotName(i);
    CHECK(name && *name);
    for (const auto& seen : names) CHECK(seen != name);
    names.push_back(name);
  }
  // torque/4208-launcher.md: 94; torque/5007-launcher.md: 95, adding
  // eight and dropping seven; torque/engine-4208.md: 19 for 3D.
  std::fprintf(stderr, "slots: %d (4.x %d, 5.0 %d, 3D %d)\n", n, b4, b5, b3d);
  CHECK(b4 == 94);
  CHECK(b5 == 95);
  CHECK(b3d == 19);
  int only4 = 0, only5 = 0;
  for (int i = 0; i < n; ++i) {
    const int b = graalengine_slotBuilds(i);
    if ((b & GRAAL_BUILD_4208) && !(b & GRAAL_BUILD_5007)) ++only4;
    if ((b & GRAAL_BUILD_5007) && !(b & GRAAL_BUILD_4208)) ++only5;
  }
  CHECK(only4 == 7);
  CHECK(only5 == 8);
  CHECK(graalengine_slotName(-1) == nullptr);
  CHECK(graalengine_slotName(n) == nullptr);
  CHECK(graalengine_slotBuilds(n) == 0);
  CHECK(graalengine_abi() == GRAALENGINE_ABI);
}

void testEmptyTable() {
  reset();
  // No slot filled: every draw is skipped and every query gives its default.
  CHECK(graal_engineInitialize("/nowhere/Graal.exe") == 1);
  loadGraalGui();
  renderGraalCanvas();
  invokeGraalKeyboardEvent(65, 'a', 0, 1);
  invokeGraalMouseEvent(10, 10, GRAAL_MOUSE_DOWN, GRAAL_MOUSE_LEFT, 1, 0, 0);
  CHECK(graalengine::engine().canvas() != nullptr);
  CHECK(graalengine::engine().canvas()->screenWidth() == 640);
  CHECK(graalengine::engine().canvas()->screenHeight() == 480);
  CHECK(graalengine::engine().canvas()->content()->name() == "MainMenuGui2D");
  CHECK(graalengine::host::GetGraalApplicationActive() == 1);
  CHECK(std::strcmp(graalengine::host::GetClipBoard(), "") == 0);
  CHECK(!graalengine::host::hasDrawText());
  shutdownGraalEngine();
}

void testFrameOrderAndClip() {
  reset();
  installRecorder();
  CHECK(graal_engineInitialize("/x/Graal.exe") == 1);
  auto& e = graalengine::engine();
  e.setTimer([] { calls.push_back("timer"); });
  e.setGuiBuilder([](graalengine::Engine& en) {
    auto root = std::make_shared<graalengine::Control>("MainMenuGui2D");
    auto a = std::make_shared<Box>("a", graal_rect{10, 10, 100, 50}, 0xff0000ffu);
    auto inner = std::make_shared<Box>("inner", graal_rect{90, 40, 40, 40}, 0xff00ff00u);
    auto hidden = std::make_shared<Box>("hidden", graal_rect{0, 0, 5, 5}, 0xffffffffu);
    hidden->setVisible(false);
    a->add(inner);
    root->add(a);
    root->add(hidden);
    en.canvas()->setContentControl(root);
  });
  loadGraalGui();
  calls.clear();
  renderGraalCanvas();
  const std::vector<std::string> want = {
      "clip 0,0,800,600",               // the screen first
      "timer",                          // then the adventure timer
      "clip 0,0,800,600",               // the content
      "clip 10,10,100,50",              // child a
      "fill 10,10,100,50 ff0000ff",
      "clip 90,40,20,20",               // inner, clipped to a
      "fill 90,40,40,40 ff00ff00",
      "clip 0,0,800,600",               // restored after the walk
  };
  CHECK(calls == want);
  if (calls != want)
    for (const auto& c : calls) std::fprintf(stderr, "  got: %s\n", c.c_str());

  // renderGraal runs the timer and draws nothing.
  calls.clear();
  renderGraal();
  CHECK((calls == std::vector<std::string>{"clip 0,0,800,600", "timer"}));

  // A resize between frames refits the content.
  screenW = 1024;
  screenH = 768;
  renderGraalCanvas();
  CHECK(e.canvas()->content()->rect().w == 1024);
  CHECK(e.canvas()->frames() == 3);
  shutdownGraalEngine();
}

void testInput() {
  reset();
  installRecorder();
  graal_engineInitialize("/x/Graal.exe");
  loadGraalGui();
  auto* canvas = graalengine::engine().canvas();
  auto content = std::make_shared<graalengine::Control>("content");
  auto back = std::make_shared<Box>("back", graal_rect{0, 0, 200, 200}, 0);
  auto front = std::make_shared<Box>("front", graal_rect{50, 50, 50, 50}, 0);
  content->add(back);
  content->add(front);
  canvas->setContentControl(content);

  // Mouse goes to the front-most control under the point.
  invokeGraalMouseEvent(60, 60, GRAAL_MOUSE_DOWN, GRAAL_MOUSE_LEFT, 1, 0, 0);
  invokeGraalMouseEvent(10, 10, GRAAL_MOUSE_UP, GRAAL_MOUSE_LEFT, 0, 0, 0);
  CHECK(front->got.size() == 1 && front->got[0] == "3:0:60,60");
  CHECK(back->got.size() == 1 && back->got[0] == "4:0:10,10");
  // Keys go front to back.
  invokeGraalKeyboardEvent(0x26, 0, 0, 1);
  CHECK(front->got.size() == 2 && front->got[1] == "0:38:0,0");

  // A dialog takes input before the content.
  auto dialog = std::make_shared<Box>("dialog", graal_rect{0, 0, 640, 480}, 0);
  canvas->pushDialog(dialog);
  invokeGraalKeyboardEvent(0x0d, 13, 0, 0);
  CHECK(dialog->got.size() == 1 && dialog->got[0] == "1:13:0,0");
  CHECK(front->got.size() == 2);
  CHECK(canvas->popDialog(dialog.get()));
  shutdownGraalEngine();
}

void testConnectAndLicence() {
  reset();
  installRecorder();
  namespace fs = std::filesystem;
  const fs::path dir = fs::temp_directory_path() / "graalengine-test-install";
  fs::create_directories(dir / "license");
  {
    std::ofstream lic(dir / "license" / "license.graal", std::ios::binary);
    lic << "127.0.0.1\r\n14900\r\n";
  }
  const std::string exe = (dir / "Graal.exe").string();
  CHECK(graal_engineInitialize(exe.c_str()) == 1);
  auto& e = graalengine::engine();
  CHECK(e.installDir() == dir.string());
  CHECK(e.licenseLines().size() == 2);

  std::string seen;
  e.setConnector([&](graalengine::Engine&, const std::string& name, const std::string& host, int port, bool is3d) {
    seen = name + "@" + host + ":" + std::to_string(port) + (is3d ? " 3d" : "");
  });
  openGraalServerList();
  CHECK(seen == "Login@127.0.0.1:14900");

  calls.clear();
  connectToGraalServer("3 Seihai Test", "127.0.0.1", 14800);
  CHECK(seen == "Seihai Test@127.0.0.1:14800 3d");
  CHECK((calls == std::vector<std::string>{"start3d"}));

  connectToGraalServer("U Classic", "127.0.0.1", 14801);
  CHECK(seen == "Classic@127.0.0.1:14801");
  CHECK(!e.lastTarget().is3d);

  bool offline = false;
  e.setOfflineStarter([&](graalengine::Engine&) { offline = true; });
  startOfflineMode();
  CHECK(offline && e.offlineRequested());

  // A second initialize only resets the script environment.
  CHECK(graal_engineInitialize("/elsewhere/Graal.exe") == 1);
  CHECK(e.installDir() == dir.string());
  CHECK(e.initializeCount() == 2);

  e.log("hello");
  CHECK(calls.back() == "log hello");
  prepareGraalShutdown();
  shutdownGraalEngine();
  fs::remove_all(dir);
}

}  // namespace

int main() {
  testSlotList();
  testEmptyTable();
  testFrameOrderAndClip();
  testInput();
  testConnectAndLicence();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("engine-test: all checks passed\n");
  return 0;
}
