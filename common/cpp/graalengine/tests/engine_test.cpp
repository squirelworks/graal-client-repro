// Recording-host tests for the engine library. No original files: the host
// here is a set of plain functions that log what the engine asks for.
#include "canvas.hpp"
#include "engine.hpp"
#include "graalengine.h"
#include "gui_host.hpp"
#include "host.hpp"
#include "image.hpp"

#include "../../gs2/tests/assembler.hpp"
#include "../../quattro/tests/fake_server.hpp"
#include "../../quattro/shell/program.hpp"
#include "session.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <chrono>
#include <string>
#include <thread>
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
void GE_CALL recOptions() { calls.push_back("options"); }
void GE_CALL recUrl(const char* u) { calls.push_back(std::string("url ") + u); }

void installRecorder() {
  graal_setGetScreenWidth(recWidth);
  graal_setGetScreenHeight(recHeight);
  graal_setSetClippingRectangle(recClip);
  graal_setFillScreenRectangle(recFill);
  graal_setDrawText(recText);
  graal_setLogGraalMessage(recLog);
  graal_setStartGraal3D(rec3D);
  graal_setOpenExternalOptions(recOptions);
  graal_setOpenURL(recUrl);
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

// The engine commands the start menus call, on the engine's own machine.
void testEngineCommands() {
  reset();
  installRecorder();
  CHECK(graal_engineInitialize("/x/Graal4.exe") == 1);
  auto& e = graalengine::engine();
  CHECK(e.machine() != nullptr);
  invokeGraalKeyboardEvent(0x26, 0, 0, 1);
  using gs2asm::Asm;
  Asm a;
  a.function("onCreated", {});
  a.op(Asm::MARKER).str("bob").callName("Adventure_setAccountName").op(Asm::POP);
  a.op(Asm::MARKER).str("pw").callName("Adventure_setPassWord").op(Asm::POP);
  a.op(Asm::MARKER).str("Bob").callName("Adventure_setNickName").op(Asm::POP);
  a.op(Asm::MARKER).num(1).num(50).callName("Adventure_updateMidiVolume").op(Asm::POP);
  a.op(Asm::MARKER).str("hi there").callName("echo").op(Asm::POP);
  a.op(Asm::MARKER).str("http://127.0.0.1/").callName("openURL").op(Asm::POP);
  a.op(Asm::MARKER).callName("Adventure_openExternalOptions").op(Asm::POP);
  a.var("up").op(Asm::MARKER).num(0x26).callName("keydown").op(Asm::ASSIGN);
  a.var("left").op(Asm::MARKER).num(0x25).callName("keydown").op(Asm::ASSIGN);
  a.var("inst").op(Asm::MARKER).callName("Adventure_getInstallationPath").op(Asm::ASSIGN);
  a.op(Asm::MARKER).callName("Adventure_saveGraalOptions").op(Asm::POP);
  a.num(0).op(Asm::RET);
  auto v = e.machine()->newVar("tester");
  std::string err;
  CHECK(e.machine()->setScript(v, a.bytes(), &err));
  calls.clear();
  e.machine()->runScripts();
  CHECK(e.account().account == "bob");
  CHECK(e.account().password == "pw");
  CHECK(e.account().nickname == "Bob");
  CHECK(e.account().fields.count("Adventure_updateMidiVolume") == 1);
  const std::vector<std::string> want = {"log hi there", "url http://127.0.0.1/", "options"};
  CHECK(calls == want);
  if (calls != want)
    for (const auto& c : calls) std::fprintf(stderr, "  got: %s\n", c.c_str());
  auto up = e.machine()->universe()->child("up");
  auto left = e.machine()->universe()->child("left");
  CHECK(up && up->number() == 1);
  CHECK(left && left->number() == 0);
  auto inst = e.machine()->universe()->child("inst");
  CHECK(inst && inst->string() == "/x/Graal4.exe");
  // Not provided yet: the engines' "not found" error, not a silent success.
  bool notFound = false;
  for (const auto& m : e.machine()->errors())
    if (m.find("Adventure_saveGraalOptions") != std::string::npos) notFound = true;
  CHECK(notFound);
  shutdownGraalEngine();
}

// With no engine file there are no start scripts, and the canvas still
// gets its MainMenuGui2D content.
void testNoStartScripts() {
  reset();
  installRecorder();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", "");
#else
  unsetenv("GRAAL_ENGINE_FILE");
#endif
  graal_engineInitialize("/nowhere/Graal4.exe");
  loadGraalGui();
  auto& e = graalengine::engine();
  CHECK(e.startScriptNames().empty());
  CHECK(e.canvas()->content() && e.canvas()->content()->name() == "MainMenuGui2D");
  bool logged = false;
  for (const auto& c : calls)
    if (c == "log GraalEngine: no start scripts") logged = true;
  CHECK(logged);
  startOfflineMode();
  CHECK(e.canvas()->content()->name() == "GUIContainer");
  shutdownGraalEngine();
}

// Owner-supplied: GRAAL404_ENGINE = the player's own 4.04r2 GraalEngine.dll.
// Its 14 start scripts load, and those the notes keep are made, in order.
void testLabStartScripts() {
  const char* file = std::getenv("GRAAL404_ENGINE");
  if (!file || !*file) {
    std::fprintf(stderr, "skip lab start scripts: GRAAL404_ENGINE not set\n");
    return;
  }
  reset();
  installRecorder();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", file);
#else
  setenv("GRAAL_ENGINE_FILE", file, 1);
#endif
  graal_engineInitialize("/x/Graal4.exe");
  std::vector<std::string> made;
  auto& e = graalengine::engine();
  e.setControlResolver([&](const gs2::VarPtr& v) {
    made.push_back(v->name());
    return std::make_shared<graalengine::Control>(v->name());
  });
  loadGraalGui();
  CHECK(e.startScriptNames().size() == 14);
  auto u = e.machine()->universe();
  for (const char* n : {"StartScript_MainMenu", "StartScript_OptionsWindow", "StartScript_PlayerProfile",
                        "StartScript_LoadLevelGui", "StartScript_QuitDialog", "StartScript_MessageBoxDialog",
                        "StartScript_SelectFileDialog"})
    CHECK(u->child(n) != nullptr);
  for (const char* n : {"StartScript_Profiles", "StartScript_MoveMap2D", "StartScript_MoveMap3D",
                        "StartScript_GraalGui"})
    CHECK(u->child(n) == nullptr);
  CHECK(e.canvas()->content()->name() == "MainMenuGui2D");
  std::fprintf(stderr, "lab: %zu start scripts, %zu objects, %zu distinct errors\n",
               e.startScriptNames().size(), e.machine()->objects().size(), e.machine()->errors().size());
  for (const auto& m : e.machine()->errors()) std::fprintf(stderr, "  %s\n", m.c_str());
  for (int i = 0; i < 20; ++i) renderGraalCanvas();
  startOfflineMode();
  CHECK(u->child("StartScript_GraalGui") != nullptr);
  shutdownGraalEngine();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", "");
#else
  unsetenv("GRAAL_ENGINE_FILE");
#endif
}

// Owner-supplied, as above: the default GS2 screen draws the main menu
// and a click on its Offline Test button starts offline mode.
void testLabMenuInput() {
  const char* file = std::getenv("GRAAL404_ENGINE");
  if (!file || !*file) return;
  reset();
  installRecorder();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", file);
#else
  setenv("GRAAL_ENGINE_FILE", file, 1);
#endif
  graal_engineInitialize("/x/Graal4.exe");
  screenW = 640;
  screenH = 480;
  loadGraalGui();
  auto& e = graalengine::engine();
  CHECK(e.screen() != nullptr);
  CHECK(e.canvas()->content()->name() == "GS2Screen");
  calls.clear();
  renderGraalCanvas();
  int fills = 0, texts = 0;
  for (const auto& c : calls) {
    if (c.rfind("fill ", 0) == 0) ++fills;
    if (c.rfind("text ", 0) == 0) ++texts;
  }
  std::fprintf(stderr, "lab menu: %d fills, %d texts in one frame\n", fills, texts);
  CHECK(texts >= 8);
  // Type a nickname into the first text edit, then press Offline Test on
  // its right half, under the inactive StartAni2 image control.
  invokeGraalMouseEvent(370, 182, GRAAL_MOUSE_DOWN, GRAAL_MOUSE_LEFT, 1, 0, 0);
  for (char ch : std::string("Tester")) {
    invokeGraalKeyboardEvent(0, ch, 0, 1);
    invokeGraalKeyboardEvent(0, ch, 0, 0);
  }
  invokeGraalMouseEvent(451, 435, GRAAL_MOUSE_DOWN, GRAAL_MOUSE_LEFT, 1, 0, 0);
  invokeGraalMouseEvent(451, 435, GRAAL_MOUSE_UP, GRAAL_MOUSE_LEFT, 0, 0, 0);
  for (int i = 0; i < 5; ++i) renderGraalCanvas();
  CHECK(e.offlineRequested());
  std::fprintf(stderr, "lab menu: nickname '%s', offline %d\n", e.account().nickname.c_str(),
               int(e.offlineRequested()));
  for (const auto& m : e.machine()->errors()) std::fprintf(stderr, "  %s\n", m.c_str());
  shutdownGraalEngine();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", "");
#else
  unsetenv("GRAAL_ENGINE_FILE");
#endif
}

// Owner-supplied: GRAAL512_ENGINE = the player's own 5.12 engine (its
// GraalEngine.dll, or a dump of it). Its start scripts carry no main menu
// (the 5.12 launcher's own window is the menu): loadGraalGui makes no
// content, and the 2D connect makes GraalGui's GUIContainer the screen.
void testLabMenu512() {
  const char* file = std::getenv("GRAAL512_ENGINE");
  if (!file || !*file) {
    std::fprintf(stderr, "skip lab 5.12 menus: GRAAL512_ENGINE not set\n");
    return;
  }
  reset();
  installRecorder();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", file);
#else
  setenv("GRAAL_ENGINE_FILE", file, 1);
#endif
  CHECK(graalengine_setBuild("5.12") == 1);
  graal_engineInitialize("/x/Graal.exe");
  screenW = 640;
  screenH = 480;
  loadGraalGui();
  auto& e = graalengine::engine();
  std::string names;
  bool mainMenu = false;
  for (const auto& n : e.startScriptNames()) {
    names += " " + n;
    if (n == "StartScript_MainMenu") mainMenu = true;
  }
  std::fprintf(stderr, "lab 5.12: %zu start scripts:%s\n", e.startScriptNames().size(), names.c_str());
  CHECK(!mainMenu);
  CHECK(e.screen() != nullptr && !e.screen()->content());
  for (const auto& c : calls)
    CHECK(c.find("no MainMenuGui2D") == std::string::npos);
  startOfflineMode();
  CHECK(e.screen() && e.screen()->content() && e.screen()->content()->name() == "GUIContainer");
  calls.clear();
  for (int i = 0; i < 3; ++i) renderGraalCanvas();
  int fills = 0, texts = 0;
  for (const auto& c : calls) {
    if (c.rfind("fill ", 0) == 0) ++fills;
    if (c.rfind("text ", 0) == 0) ++texts;
  }
  std::fprintf(stderr, "lab 5.12 GraalGui: %d fills, %d texts in three frames\n", fills, texts);
  for (const auto& m : e.machine()->errors()) std::fprintf(stderr, "  %s\n", m.c_str());
  shutdownGraalEngine();
#ifdef _WIN32
  _putenv_s("GRAAL_ENGINE_FILE", "");
#else
  unsetenv("GRAAL_ENGINE_FILE");
#endif
}

std::vector<std::string> gfx;
void GE_CALL recGfx(const graal_texture* t, int32_t x, int32_t y, int32_t sx, int32_t sy, int32_t sw, int32_t sh,
                    uint32_t) {
  char b[160];
  std::snprintf(b, sizeof b, "gfx %s %dx%d at %d,%d from %d,%d,%d,%d", t->name, t->width, t->height, x, y, sx, sy,
                sw, sh);
  gfx.push_back(b);
}
void GE_CALL recStretch(const graal_texture* t, int32_t x, int32_t y, int32_t w, int32_t h, int32_t sx, int32_t sy,
                        int32_t sw, int32_t sh, uint32_t) {
  char b[160];
  std::snprintf(b, sizeof b, "stretch %s to %d,%d,%d,%d from %d,%d,%d,%d", t->name, x, y, w, h, sx, sy, sw, sh);
  gfx.push_back(b);
}

void writePng(const std::filesystem::path& p, const Torque::Gui::Image& img) {
  std::string err;
  CHECK(Torque::Gui::write_file(p.string(), Torque::Gui::encode_png(img), err));
}

// The painter finds the menus' pictures by name, case and extension
// ignored, decodes them once and draws through the slots.
void testPainter() {
  reset();
  installRecorder();
  graal_setDrawGraphics(recGfx);
  graal_setDrawGraphicsStretched(recStretch);
  namespace fs = std::filesystem;
  const fs::path dir = fs::temp_directory_path() / "graalengine-painter-test";
  fs::remove_all(dir);
  fs::create_directories(dir / "levels3d" / "gui");
  // A 2 x 2 picture, and a bitmap array: two 2 x 2 cells split by a
  // magenta separator (top-left pixel) row and columns.
  Torque::Gui::Image pic(2, 2, {10, 20, 30, 255});
  writePng(dir / "levels3d" / "gui" / "TestPic.PNG", pic);
  Torque::Gui::Image arr(7, 4, {255, 0, 255, 255});
  for (int y = 1; y < 3; ++y)
    for (int x : {1, 2, 4, 5}) arr.at(x, y) = {0, 0, 0, 255};
  writePng(dir / "levels3d" / "gui" / "cells.png", arr);

  graalengine::TextureCache cache(dir.string());
  graalengine::SlotPainter p(cache);
  int w = 0, h = 0;
  CHECK(p.bitmapSize("testpic", w, h) && w == 2 && h == 2);       // no extension
  CHECK(p.bitmapSize("TESTPIC.png", w, h));                        // other case
  CHECK(!p.bitmapSize("missing.png", w, h));
  CHECK(!p.bitmapSize("missing.png", w, h));                       // a miss is cached too
  const auto cells = p.cells("cells");
  CHECK(cells.size() == 2);
  if (cells.size() == 2) CHECK(cells[0].x == 1 && cells[0].y == 1 && cells[0].w == 2 && cells[0].h == 2);
  CHECK(p.cells("testpic").empty() || p.cells("testpic").size() <= 1);
  gfx.clear();
  p.bitmap("testpic", {0, 0, 2, 2}, {5, 6, 2, 2});
  p.bitmap("testpic", {0, 0, 2, 2}, {5, 6, 8, 4});
  p.bitmap("missing.png", {0, 0, 2, 2}, {0, 0, 2, 2});
  const std::vector<std::string> want = {"gfx testpic 2x2 at 5,6 from 0,0,2,2",
                                         "stretch testpic to 5,6,8,4 from 0,0,2,2"};
  CHECK(gfx == want);
  if (gfx != want)
    for (const auto& g : gfx) std::fprintf(stderr, "  got: %s\n", g.c_str());
  calls.clear();
  p.fill({1, 2, 3, 4}, {255, 0, 0, 128});
  p.fill({1, 2, 3, 4}, {255, 0, 0, 0});  // clear: nothing drawn
  p.setClip({0, 0, 10, 10});
  CHECK((calls == std::vector<std::string>{"fill 1,2,3,4 80ff0000", "clip 0,0,10,10"}));

  CHECK(graalengine::torqueKeyName('A') == "a");
  CHECK(graalengine::torqueKeyName(0x71) == "F2");
  CHECK(graalengine::torqueKeyName(0x0D) == "return");
  CHECK(graalengine::torqueKeyName(0x26) == "up");
  CHECK(graalengine::torqueKeyName(0xFF).empty());
  fs::remove_all(dir);
}

// The 2D session on loopback, as connectToGraalServer starts it with no
// connector set: the 4.04r2 login line with the account the menus set,
// the 178 hand-on, the level, the own props, walking from the moveRight2D
// binding, and the chat bar's text as the player's chat.
// `build` is the launcher's build (graalengine_setBuild), `labEnv` the
// variable naming that build's own engine file for the lab half, and
// `loginTail` the machine fields its login line ends with.
void testLoopbackSession(const char* build, const char* labEnv, const std::string& loginTail) {
  using QuattroTest::FakeServer;
  using Quattro::Net::gchar;
  using Quattro::Net::gshort;
  using Quattro::Net::gstring;
  namespace QW = Quattro::World;
  namespace fs = std::filesystem;
  reset();
  installRecorder();
  const fs::path dir = fs::temp_directory_path() / "graalengine-session";
  fs::remove_all(dir);
  fs::create_directories(dir);
  const char* lab = std::getenv(labEnv);
  const bool withMenus = lab && *lab;
  if (withMenus) {
#ifdef _WIN32
    _putenv_s("GRAAL_ENGINE_FILE", lab);
#else
    setenv("GRAAL_ENGINE_FILE", lab, 1);
#endif
  }
  screenW = 640;
  screenH = 480;
  CHECK(graalengine_setBuild(build) == 1);
  CHECK(graal_engineInitialize((dir / "Graal4.exe").string().c_str()) == 1);
  auto& e = graalengine::engine();
  CHECK(e.build() == build);
  CHECK(e.machine()->profile() == (build[0] == '4' ? gs2::Profile::Engine42 : gs2::Profile::Engine50));
  loadGraalGui();
  auto run = [&](const std::string& code) {
    using gs2asm::Asm;
    Asm a;
    a.function("onCreated", {});
    a.op(Asm::MARKER).str(code.substr(code.find(' ') + 1)).callName(code.substr(0, code.find(' '))).op(Asm::POP);
    a.num(0).op(Asm::RET);
    auto v = e.machine()->newVar("t" + std::to_string(std::rand()));
    std::string err;
    CHECK(e.machine()->setScript(v, a.bytes(), &err));
    e.machine()->runScripts();
  };
  run("Adventure_setAccountName guest");
  run("Adventure_setPassWord pw");
  run("Adventure_setNickName Tester");

  FakeServer login, game;
  // A server for 5.12 steps short packed frames as 5.12 does.
  login.round_down = game.round_down = e.build() == "5.12";
  CHECK(login.start() && game.start());
  auto pump = [&](FakeServer* s, auto done) {
    auto end = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < end) {
      renderGraalCanvas();
      if (s->conn.connected()) s->pump();
      if (done()) return true;
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    return false;
  };
  connectToGraalServer("Login", "127.0.0.1", login.port());
  CHECK(e.session() != nullptr);
  if (!e.session()) return;
  CHECK(login.conn.accept_from(login.listener));
  CHECK(pump(&login, [&] { return login.saw(37, "English"); }));
  const std::string line = Quattro::Net::find_profile(build)->token + gstring("guest") + gstring("pw") + loginTail;
  CHECK(login.login_line == line);

  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::thread acc([&] { game.conn.accept_from(game.listener); });
  bool warped = pump(&login, [&] { return e.session()->program().session().logins() == 2; });
  acc.join();
  CHECK(warped);
  CHECK(pump(&game, [&] { return game.saw(37, "English"); }));

  std::string board;
  for (int i = 0; i < 64 * 64; ++i) board += std::string("\x07\x00", 2);
  const std::string raw = gchar(101) + board + "\n";
  game.send(gchar(6) + "onlinestartlocal.nw\n" + gchar(100) + Quattro::Net::gint3(uint32_t(raw.size())) + "\n" + raw);
  CHECK(pump(&game, [&] { return e.session()->program().world().have_level; }));
  game.send(gchar(9) + gchar(QW::kX2) + gshort(QW::to_pixels2(20)) + gchar(QW::kY2) + gshort(QW::to_pixels2(22)) + "\n");
  auto sentProps = [&](const std::string& part) {
    for (auto& [id, b] : game.got)
      if (id == 2 && b.find(part) != std::string::npos) return true;
    return false;
  };
  CHECK(pump(&game, [&] { return sentProps("Tester"); }));

  const std::size_t before = game.got.size();
  CHECK(e.session()->action("moveRight2D", true));
  CHECK(pump(&game, [&] { return e.session()->program().me().x > 20; }));
  e.session()->action("moveRight2D", false);
  CHECK(pump(&game, [&] {
    for (std::size_t i = before; i < game.got.size(); ++i)
      if (game.got[i].first == 2) return true;
    return false;
  }));
  CHECK(!e.session()->action("doA", true));

  run("Adventure_setChat hello there");
  CHECK(pump(&game, [&] { return game.saw(2, gchar(QW::kCurChat) + gstring("hello there")); }));

  CHECK(e.session()->haveFrame());
  CHECK(e.session()->frame().width == screenW && e.session()->frame().height == screenH);
  // With the player's own engine file (the lab run above leaves it set),
  // the 2D connect made GUIContainer the content, and its GuiGraalCtrl
  // (GraalControl) shows the world.
  if (withMenus) {
    graal_setDrawGraphics(recGfx);
    graal_setDrawGraphicsStretched(recStretch);
    gfx.clear();
    renderGraalCanvas();
    bool shown = false;
    for (const auto& g : gfx)
      if (g.find(" GraalControl ") != std::string::npos) shown = true;
    CHECK(shown);
    std::fprintf(stderr, "lab session: GraalControl drawn %s\n", shown ? "yes" : "no");
    // The arrow key through the MoveMap2D binding (moveRight2D) walks.
    const double x0 = e.session()->program().me().x;
    invokeGraalKeyboardEvent(0x27, 0, 0, 1);
    const bool walked = pump(&game, [&] { return e.session()->program().me().x > x0; });
    invokeGraalKeyboardEvent(0x27, 0, 0, 0);
    CHECK(walked);
    std::fprintf(stderr, "lab session: right arrow walks %s\n", walked ? "yes" : "no");
#ifdef _WIN32
    _putenv_s("GRAAL_ENGINE_FILE", "");
#else
    unsetenv("GRAAL_ENGINE_FILE");
#endif
  }
  shutdownGraalEngine();
  fs::remove_all(dir);
}

}  // namespace

// The engine's half of the 3D bridge (Track C4): a `3 ` server with the 3D
// library's ConnectTo3DServer slot filled goes to 3D mode and dials port
// + 1; without it the launcher is asked to load the library.
std::string connected3d;
void GE_CALL rec3DConnect(const char* host, int32_t port) {
  connected3d = std::string(host) + ":" + std::to_string(port);
}
int removed3d = 0;
void GE_CALL rec3DRemove() { ++removed3d; }

void testGraal3DBridge() {
  reset();
  installRecorder();
  CHECK(graalengine_setBuild("5.12") == 1);
  CHECK(std::string(graalengine_build()) == "5.12");
  CHECK(graal_engineInitialize("/nowhere/Graal.exe") == 1);
  loadGraalGui();
  auto& e = graalengine::engine();
  std::string seen;
  e.setConnector([&](graalengine::Engine&, const std::string& name, const std::string&, int port, bool is3d) {
    seen = name + ":" + std::to_string(port) + (is3d ? " 3d" : "");
  });

  // No 3D library: StartGraal3D, no 3D mode.
  calls.clear();
  connectToGraalServer("3 Lab", "127.0.0.1", 14900);
  CHECK((calls == std::vector<std::string>{"start3d"}));
  CHECK(isGraal3DMode() == 0);

  // With it: the link on port + 1, 3D mode, the TCP side as for 2D.
  graal_setConnectTo3DServer(rec3DConnect);
  graal_setRemoveGraal3DConnection(rec3DRemove);
  calls.clear();
  connectToGraalServer("3 Lab", "127.0.0.1", 14900);
  CHECK(connected3d == "127.0.0.1:14901");
  CHECK(isGraal3DMode() == 1);
  CHECK(seen == "Lab:14900 3d");
  CHECK(calls.empty());

  // 5.x logs in as the built-in guest when no account was given.
  char account[16], nickname[16], password[4];
  getGraalLoginInfo(account, sizeof account, nickname, sizeof nickname, password, sizeof password);
  CHECK(std::string(account) == "guest");
  CHECK(std::string(nickname).empty());
  CHECK(std::string(password) == "7Y3");  // cut to the buffer

  // Login steps reach the engine; step 6 asks for GUIContainer (5.x).
  graalengine_graal3DLoginStep(2);
  CHECK(e.graal3DStep() == 2);
  calls.clear();
  graalengine_graal3DLoginStep(6);
  CHECK(e.graal3DStep() == 6);
  bool named = false;
  for (const auto& c : calls) named |= c.find("GUIContainer") != std::string::npos;
  CHECK(named);

  // Shutdown removes the 3D connection; an error leaves 3D mode.
  prepareGraalShutdown();
  CHECK(removed3d == 1);
  CHECK(isGraal3DMode() == 0);
  connectToGraalServer("3 Lab", "127.0.0.1", 14900);
  CHECK(isGraal3DMode() == 1);
  calls.clear();
  setGraal3DConnectionError("The 3D server connection has timed out");
  CHECK(isGraal3DMode() == 0);
  CHECK((calls == std::vector<std::string>{"log GraalEngine: The 3D server connection has timed out"}));
  graalengine_logLine("a line");
  CHECK(calls.back() == "log a line");
  reset();
}

int main() {
  testSlotList();
  testEmptyTable();
  testFrameOrderAndClip();
  testInput();
  testConnectAndLicence();
  testEngineCommands();
  testNoStartScripts();
  testLabStartScripts();
  testPainter();
  testLabMenuInput();
  testLabMenu512();
  testLoopbackSession("4.04r2", "GRAAL404_ENGINE", "win,\"\",\"\",\"\"");
  testLoopbackSession("5.12", "GRAAL512_ENGINE", "win,\"\",\"\",\"\",\"6.2 9200 \"");
  testGraal3DBridge();
  CHECK(graalengine_setBuild("9.99") == 0);
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("engine-test: all checks passed\n");
  return 0;
}
