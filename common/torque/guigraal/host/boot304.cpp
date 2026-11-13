#include "boot304.hpp"

#include <cstdlib>
#include <fstream>

#include "../../console/compiler/compile.hpp"

namespace Torque {
namespace {

void stub(Engine& e, const char* space, const char* name, std::size_t min, std::size_t max,
          std::string result = std::string()) {
  e.add_function(space, name, min, max, std::string(name) + "(...)",
                 [space = std::string(space), name = std::string(name), result](Engine& en, SimObject*, Args& a) {
                   std::string line = "host stub " + (space.empty() ? std::string() : space + "::") + name + "(";
                   for (std::size_t i = 1; i < a.size(); ++i) line += (i > 1 ? ", " : "") + a[i];
                   en.trace.push_back(line + ")");
                   return result;
                 });
}

void register_host_stubs(Engine& e) {
  e.add_function("", "createCanvas", 2, 2, "createCanvas(windowTitle)", [](Engine& en, SimObject*, Args& a) {
    en.trace.push_back("host stub createCanvas(" + a[1] + ")");
    if (!en.find_object("Canvas")) en.create_object("GuiCanvas", "Canvas");
    start_input_304(en);
    return std::string("1");
  });
  for (const char* name : {"videoSetGammaCorrection", "setOpenGLTextureCompressionHint", "setOpenGLAnisotropy",
                           "setOpenGLMipReduction", "setOpenGLInteriorMipReduction", "setOpenGLSkyMipReduction",
                           "setDisplayDevice", "toggleFullScreen",
                           "lockMouse", "gotoWebPage", "cursorOff", "cursorOn", "enableWinConsole"})
    stub(e, "", name, 1, 0);
  // setScreenMode(width, height, bpp, fullScreen): the Options dialog's
  // Apply. The engine keeps the mode in $pref::Video::resolution, which
  // the prefs export saves and the window follows (graal304_torque.cpp).
  // A bpp that is not a number ("Default") is stored as 32, so the
  // non-numeric depth rule of canvas_size_304 stays for the shipped prefs
  // only (rebuild policy). There is no full screen.
  e.add_function("", "setScreenMode", 3, 5, "setScreenMode(width, height, bpp, fullScreen)",
                 [](Engine& en, SimObject*, Args& a) {
                   const int w = std::atoi(a[1].c_str()), h = std::atoi(a[2].c_str());
                   if (w < 320 || h < 240 || w > 4096 || h > 4096) return std::string("0");
                   int bpp = a.size() > 3 ? std::atoi(a[3].c_str()) : 0;
                   if (bpp <= 0) bpp = 32;
                   en.set_global("$pref::Video::resolution",
                                 Value::of_string(std::to_string(w) + " " + std::to_string(h) + " " + std::to_string(bpp)));
                   en.trace.push_back("setScreenMode " + std::to_string(w) + " x " + std::to_string(h));
                   return std::string("1");
                 });
  stub(e, "", "isDeviceFullScreenOnly", 2, 2, "0");
  for (const char* name : {"repaint", "setCursor", "cursorOn", "cursorOff"})
    stub(e, "GuiCanvas", name, 2, 0);
  stub(e, "GuiCanvas", "isCursorOn", 2, 2, "0");
}

} // namespace

bool is_install_3153(const Engine& engine) {
  return engine.files.exists("scripts2D/main2D.cs.dso") || engine.files.exists("scripts2D/main2D.cs");
}

void setup_engine_304(Engine& engine, const std::string& root, const std::string& prefs,
                      std::function<void(const std::string&)> print) {
  engine.files.root = root;
  engine.files.prefs_dir = prefs;
  if (is_install_3153(engine)) {
    // The Mac PPC build: big-endian float tables in its .dso files
    // (Graal_analysis torque/scripting.md) and exec by file name.
    engine.float_order = FloatOrder::big;
    engine.exec_by_name = true;
    engine.trace.push_back("profile 3.153");
  }
  engine.print = [&engine, print](const std::string& text) {
    if (print) print(text);
    engine.add_console_text(text);
  };
  register_classes_304(engine);
  register_input_304(engine);
  register_engine_prefs_304(engine);
  register_text_list_304(engine);
  engine.compiler = [](const std::string& source, const std::string&, DsoBlock& out, std::string& error) {
    CompileError e;
    if (compile_script(source, out, e)) return true;
    error = "line " + std::to_string(e.line) + ": " + e.message;
    return false;
  };
  register_host_stubs(engine);
  engine.on_set_content = [&engine](SimObject*, SimObject* content) {
    engine.trace.push_back("canvas content " + (content->name.empty() ? std::to_string(content->id) : content->name));
  };
}

void boot_304(Engine& engine) {
  engine.set_global("$Game::argc", Value::of_int(1));
  engine.set_global("$Game::argv0", Value::of_string("graalexe"));
  engine.call_function("exec", {"main.cs"});
}

bool read_steps(const std::string& path, std::vector<Step>& out) {
  std::ifstream in(path);
  if (!in) return false;
  std::string line;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    std::size_t p = line.find_first_not_of(" \t");
    if (p == std::string::npos || line[p] == '#') continue;
    std::size_t q = line.find_first_of(" \t", p);
    Step s;
    s.at = static_cast<unsigned>(std::stoul(line.substr(p, q - p)));
    if (q != std::string::npos) s.code = line.substr(line.find_first_not_of(" \t", q));
    out.push_back(s);
  }
  return true;
}

static void put32(std::ofstream& f, std::uint32_t v) {
  const char b[4] = {char(v), char(v >> 8), char(v >> 16), char(v >> 24)};
  f.write(b, 4);
}

bool write_bmp(const std::string& path, const std::uint32_t* px, int w, int h) {
  std::ofstream f(path, std::ios::binary);
  if (!f || !px || w <= 0 || h <= 0) return false;
  const std::uint32_t row = static_cast<std::uint32_t>(w) * 3, pad = (4 - row % 4) % 4;
  const std::uint32_t size = (row + pad) * static_cast<std::uint32_t>(h);
  f.write("BM", 2); put32(f, 54 + size); put32(f, 0); put32(f, 54);
  put32(f, 40); put32(f, static_cast<std::uint32_t>(w)); put32(f, static_cast<std::uint32_t>(h));
  const char planes[4] = {1, 0, 24, 0};
  f.write(planes, 4);
  put32(f, 0); put32(f, size); put32(f, 2835); put32(f, 2835); put32(f, 0); put32(f, 0);
  for (int y = h - 1; y >= 0; --y) {
    for (int x = 0; x < w; ++x) {
      const std::uint32_t c = px[y * w + x];
      const char bgr[3] = {char(c), char(c >> 8), char(c >> 16)};
      f.write(bgr, 3);
    }
    f.write("\0\0\0", pad);
  }
  return static_cast<bool>(f);
}

} // namespace Torque
