// gs2-scan: find the compiled GS2 scripts a program carries as zlib
// streams, and report what the machine can run of them.
//   gs2-scan [--profile 4.2|5.0|6.00] [--out DIR] [--run [--gui]
//            [--draw LIST --theme DIR [--content NAME]]] FILE
// --run attaches every script to its own variable on one machine, runs
// `created` and reports the commands they called that nothing provides.
// --gui adds the GUI objects and commands (gui.hpp). --draw makes NAME
// (MainMenuGui2D by default) the content at 800 x 600 and writes every
// draw call to LIST, one per line, reading theme bitmaps from DIR.
// The program is the player's own copy; nothing it contains is kept here.

#include <zlib.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <map>
#include <string>

#include "../../../torque/gui/bitmap_array.hpp"
#include "../../../torque/gui/image.hpp"
#include "../engine_commands.hpp"
#include "../gs2.hpp"
#include "../gui.hpp"
#include "../gui_draw.hpp"
#include "../startscripts.hpp"

#include <algorithm>
#include <filesystem>
#include <memory>

namespace {

// Inflate one zlib stream that starts at `p`; empty when it is not one.
std::string inflateAt(const unsigned char* p, std::size_t n) {
  z_stream z;
  std::memset(&z, 0, sizeof z);
  if (inflateInit(&z) != Z_OK) return {};
  z.next_in = const_cast<unsigned char*>(p);
  z.avail_in = static_cast<uInt>(n > 0x7fffffff ? 0x7fffffff : n);
  std::string out;
  unsigned char buf[65536];
  int rc = Z_OK;
  while (rc == Z_OK && out.size() < (16u << 20)) {
    z.next_out = buf;
    z.avail_out = sizeof buf;
    rc = inflate(&z, Z_NO_FLUSH);
    out.append(reinterpret_cast<char*>(buf), sizeof buf - z.avail_out);
  }
  inflateEnd(&z);
  return rc == Z_STREAM_END ? out : std::string();
}

// Writes each draw call as a line. Bitmaps are read from the theme folder
// (names matched without case); text is measured at 7 pixels a character
// and 16 rows, a stand-in for the launcher's fonts.
class ListPainter : public gs2::gui::Painter {
 public:
  ListPainter(std::FILE* out, std::string dir) : out_(out), dir_(std::move(dir)) {}
  void setClip(const gs2::gui::Rect& r) override { std::fprintf(out_, "clip %d %d %d %d\n", r.x, r.y, r.w, r.h); }
  void fill(const gs2::gui::Rect& r, gs2::gui::Color c) override {
    std::fprintf(out_, "fill %d %d %d %d %d %d %d %d\n", r.x, r.y, r.w, r.h, c.r, c.g, c.b, c.a);
  }
  void text(int x, int y, const std::string& s, const std::string& font, int size, gs2::gui::Color c) override {
    std::fprintf(out_, "text %d %d %d %d %d %d %s|%s\n", x, y, size, c.r, c.g, c.b, font.c_str(), s.c_str());
  }
  int textWidth(const std::string& s, const std::string&, int) override { return 7 * static_cast<int>(s.size()); }
  int fontHeight(const std::string&, int) override { return 16; }
  bool bitmapSize(const std::string& f, int& w, int& h) override {
    auto* i = image(f);
    if (!i) return false;
    w = i->image.width;
    h = i->image.height;
    return true;
  }
  std::vector<gs2::gui::Rect> cells(const std::string& f) override {
    std::vector<gs2::gui::Rect> out;
    if (auto* i = image(f)) {
      if (!i->split) {
        i->array = Torque::Gui::split_bitmap_array(i->image);
        i->split = true;
      }
      for (const auto& c : i->array.cells) out.push_back({c.x, c.y, c.width, c.height});
    }
    return out;
  }
  void bitmap(const std::string& f, const gs2::gui::Rect& s, const gs2::gui::Rect& d) override {
    auto* i = image(f);
    std::fprintf(out_, "bitmap %s %d %d %d %d %d %d %d %d\n", i ? i->path.c_str() : f.c_str(), s.x, s.y, s.w, s.h, d.x,
                 d.y, d.w, d.h);
  }
  void engineControl(const gs2::gui::Control& c, const gs2::gui::Rect& r) override {
    std::fprintf(out_, "engine %s %s %d %d %d %d\n", c.type().c_str(), c.name().c_str(), r.x, r.y, r.w, r.h);
  }
  std::vector<std::string> missing;

 private:
  struct Loaded {
    std::string path;
    Torque::Gui::Image image;
    Torque::Gui::BitmapArray array;
    bool split = false;
  };
  static std::string lower(std::string s) {
    for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
  }
  Loaded* image(const std::string& f) {
    const std::string key = lower(f);
    auto it = cache_.find(key);
    if (it != cache_.end()) return it->second.get();
    std::unique_ptr<Loaded> l;
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator(dir_, ec)) {
      const std::string fn = lower(e.path().filename().string());
      if (fn != key && fn != key + ".png") continue;
      std::vector<std::uint8_t> bytes;
      std::string err;
      auto tmp = std::make_unique<Loaded>();
      if (Torque::Gui::read_file(e.path().string(), bytes, err) && Torque::Gui::decode_png(bytes, tmp->image, err)) {
        tmp->path = e.path().string();
        l = std::move(tmp);
      }
    }
    if (!l) missing.push_back(f);
    return (cache_[key] = std::move(l)).get();
  }
  std::FILE* out_;
  std::string dir_;
  std::map<std::string, std::unique_ptr<Loaded>> cache_;
};

}  // namespace

int main(int argc, char** argv) {
  gs2::Profile profile = gs2::Profile::Engine42;
  std::string outDir, file;
  bool runThem = false, withGui = false;
  std::string drawList, themeDir, contentName = "MainMenuGui2D";
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--profile" && i + 1 < argc) {
      const std::string p = argv[++i];
      profile = p == "5.0" ? gs2::Profile::Engine50 : p == "6.00" ? gs2::Profile::Engine600 : gs2::Profile::Engine42;
    } else if (a == "--run") {
      runThem = true;
    } else if (a == "--gui") {
      withGui = true;
    } else if (a == "--draw" && i + 1 < argc) {
      drawList = argv[++i];
      withGui = true;
    } else if (a == "--theme" && i + 1 < argc) {
      themeDir = argv[++i];
    } else if (a == "--content" && i + 1 < argc) {
      contentName = argv[++i];
    } else if (a == "--out" && i + 1 < argc) {
      outDir = argv[++i];
    } else {
      file = a;
    }
  }
  if (file.empty()) {
    std::fprintf(stderr, "usage: gs2-scan [--profile 4.2|5.0|6.00] [--out DIR] FILE\n");
    return 2;
  }
  std::ifstream f(file, std::ios::binary);
  if (!f) {
    std::fprintf(stderr, "cannot open %s\n", file.c_str());
    return 2;
  }
  const std::string data((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  const auto* d = reinterpret_cast<const unsigned char*>(data.data());

  int scripts = 0, failed = 0;
  std::size_t functions = 0, instructions = 0;
  std::map<int, std::size_t> refused;
  gs2::Machine machine(profile);
  machine.logMissingFunctions = true;
  {
    gs2::EngineHost host;
    host.log = [](const std::string& t) { std::printf("  echo: %s\n", t.c_str()); };
    gs2::addEngineCommands(machine, host);
  }
  gs2::gui::Screen screen(machine);
  if (withGui) screen.install();
  for (std::size_t i = 0; i + 2 < data.size(); ++i) {
    if (d[i] != 0x78 || (d[i + 1] != 0x01 && d[i + 1] != 0x5e && d[i + 1] != 0x9c && d[i + 1] != 0xda)) continue;
    const std::string s = inflateAt(d + i, data.size() - i);
    static const char head[8] = {0, 0, 0, 1, 0, 0, 0, 4};
    if (s.size() < 16 || std::memcmp(s.data(), head, 8) != 0) continue;
    auto r = gs2::load(s);
    if (!r.ok()) {
      std::printf("stream %d: %s\n", scripts, r.error.c_str());
      ++failed;
      ++scripts;
      continue;
    }
    functions += r.script->functions.size();
    instructions += r.script->code.size();
    for (const auto& in : r.script->code)
      if (!gs2::opcodeInProfile(in.op, profile) || !gs2::opcodeImplemented(in.op)) ++refused[in.op];
    const std::string startName = gs2::identifyStartScript(*r.script);
    std::printf("stream %02d: %-30s %3zu functions %5zu instructions\n", scripts,
                startName.empty() ? "(not a start script)" : startName.c_str(), r.script->functions.size(),
                r.script->code.size());
    if (runThem) {
      char name[32];
      std::snprintf(name, sizeof name, "script%02d", scripts);
      machine.setScript(machine.newVar(startName.empty() ? name : startName), r.script);
    }
    if (!outDir.empty()) {
      char name[64];
      std::snprintf(name, sizeof name, "/script%02d.gs2", scripts);
      std::ofstream o(outDir + name, std::ios::binary);
      o << s;
    }
    ++scripts;
  }
  std::printf("scripts %d, unreadable %d, functions %zu, instructions %zu\n", scripts, failed, functions, instructions);
  if (!refused.empty()) {
    std::printf("opcodes not yet run on engine %s:", gs2::profileName(profile));
    for (const auto& [op, n] : refused) std::printf(" %s(%d)x%zu", gs2::opcodeName(op).c_str(), op, n);
    std::printf("\n");
  }
  if (runThem) {
    for (int pass = 0; pass < 3; ++pass) machine.runScripts();
    std::printf("ran %llu instructions, %zu objects made\n",
                static_cast<unsigned long long>(machine.instructionsRun()), machine.objects().size());
    for (const auto& e : machine.errors()) std::printf("  %s\n", e.c_str());
  }
  if (runThem && withGui) {
    std::map<std::string, int> kinds;
    for (const auto& c : screen.all()) ++kinds[c->isProfile() ? "profile" : c->isActionMap() ? "key map" : c->isControl() ? "control" : "other"];
    std::printf("gui objects:");
    for (const auto& [k, n] : kinds) std::printf(" %d %s", n, k.c_str());
    std::size_t bindings = 0;
    for (const auto& c : screen.all()) bindings += c->bindings.size();
    std::printf(", %zu key bindings\n", bindings);
  }
  if (runThem && !drawList.empty()) {
    auto c = screen.find(contentName);
    if (!c) {
      std::fprintf(stderr, "no control named %s\n", contentName.c_str());
      return 1;
    }
    machine.clearErrors();
    screen.setSize(800, 600);
    screen.setContent(c);
    for (int pass = 0; pass < 3; ++pass) machine.runScripts();
    std::FILE* out = std::fopen(drawList.c_str(), "w");
    if (!out) return 2;
    ListPainter p(out, themeDir);
    gs2::gui::drawScreen(screen, p);
    std::fclose(out);
    std::sort(p.missing.begin(), p.missing.end());
    p.missing.erase(std::unique(p.missing.begin(), p.missing.end()), p.missing.end());
    for (const auto& f : p.missing) std::printf("  bitmap not read: %s\n", f.c_str());
    for (const auto& e : machine.errors()) std::printf("  %s\n", e.c_str());
  }
  return failed ? 1 : 0;
}
