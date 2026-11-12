// Weapon and class scripts in the Quattro program: 140 delivery, the
// GRESCR01 cache, 197 hits and misses, and the GS2 machine running them.
// Scripts are hand-assembled with the gs2 test assembler; nothing comes
// from a compiler or a server.
#include "../../gs2/tests/assembler.hpp"
#include "../shell/scripts.hpp"
#include "../net/gtypes.hpp"
#include "check.hpp"

#include <filesystem>
#include <fstream>
#include <iterator>

using namespace Quattro;
using gs2asm::Asm;

namespace {

std::string echo_script(const std::string& text) {
  Asm a;
  a.function("onCreated", {});
  a.op(Asm::MARKER).str(text).callName("echo").op(Asm::POP);
  a.num(0).op(Asm::RET);
  a.function("onServerListerConnect", {});
  a.op(Asm::MARKER).str("lister").callName("echo").op(Asm::POP);
  a.num(0).op(Asm::RET);
  return a.bytes();
}

bool logged(const Shell::ScriptHost& h, const std::string& line) {
  for (const auto& l : h.log())
    if (l == line) return true;
  return false;
}

void test_descriptors() {
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "-System";
  d.cache_flag = 1;
  d.key = Cache::ScriptKey{0x01020304u, 0xA0B0C0D0u};
  std::string payload = Shell::make_script_packet(d, "BODY");
  Shell::ScriptDescriptor got;
  std::string body;
  CHECK(Shell::parse_script_packet(payload, got, body));
  CHECK(got.type == "weapon" && got.name == "-System" && got.cache_flag == 1);
  CHECK(got.key && got.key->lo == 0x01020304u && got.key->hi == 0xA0B0C0D0u);
  CHECK(body == "BODY");
  // H counts the descriptor alone; the body starts at H + 2.
  unsigned h = ((static_cast<unsigned char>(payload[0]) - 32) << 7) | (static_cast<unsigned char>(payload[1]) - 32);
  CHECK(payload.substr(2 + h) == "BODY");

  d.crc = 0xDEADBEEFu;
  Shell::ScriptDescriptor ls;
  CHECK(Shell::parse_load_script(Shell::make_load_script(d), ls));
  CHECK(ls.crc == 0xDEADBEEFu && ls.key->hi == 0xA0B0C0D0u && ls.name == "-System");
  CHECK(!Shell::parse_load_script("weapon,x,1,short", ls));

  // As Seihai's gserver writes it: CSV fields, the 10 key bytes as one
  // field and the CRC as another, a field quoted when it holds a byte past
  // 126, a comma, a quote or a backslash (doubled inside the quotes).
  auto csv = [](const std::string& f) {
    bool complex = false;
    for (unsigned char c : f) complex |= c < 32 || c > 126 || c == '"' || c == ',' || c == '\\';
    if (!complex) return f;
    std::string q = "\"";
    for (char c : f) {
      q += c;
      if (c == '"' || c == '\\') q += c;
    }
    return q + "\"";
  };
  for (uint32_t lo : {0x01020304u, 0x0000000Cu, 0x7FFFFFFFu}) {
    const uint32_t hi = 0xA0B0C0D0u, crc = 0x2C2C2C2Cu ^ lo;
    const std::string hdr = "weapon,-gr_movement,1," + csv(Quattro::Net::gint5(lo) + Quattro::Net::gint5(hi)) + "," + csv(Quattro::Net::gint5(crc));
    Shell::ScriptDescriptor g;
    CHECK(Shell::parse_load_script(hdr, g));
    CHECK(g.name == "-gr_movement" && g.cache_flag == 1 && g.key && g.key->lo == lo && g.key->hi == hi && g.crc == crc);
  }
  CHECK(!Shell::parse_load_script("weapon,x,1,\"unclosed", ls));
  CHECK(!Shell::parse_script_packet("\x20", got, body));
}

void test_delivery_and_cache() {
  namespace fs = std::filesystem;
  fs::path dir = fs::temp_directory_path() / "quattro-scripts-test";
  fs::remove_all(dir);

  Shell::ScriptHost host;
  std::vector<std::pair<int, std::string>> sent;
  host.set_send([&](int id, std::string_view b) {
    sent.emplace_back(id, std::string(b));
    return true;
  });
  host.set_cache_dir(dir.string());

  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "-System";
  d.cache_flag = 1;
  d.key = Cache::ScriptKey{0x11111111u, 0x22222222u};
  const std::string script = echo_script("hello");
  CHECK(host.on_message(33, std::string("\x27-System", 8)));
  CHECK(host.on_message(140, Shell::make_script_packet(d, script)));
  host.tick();
  CHECK(logged(host, "weapon -System loaded"));
  CHECK(logged(host, "echo: hello"));
  CHECK(host.machine().errors().empty());

  // The cache file holds GRESCR01 and the stored body.
  fs::path file = dir / "weapons" / "-System.code";
  std::string bytes;
  {
    // Closed before the folder is removed: Windows will not delete an open file.
    std::ifstream in(file, std::ios::binary);
    bytes.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
  }
  CHECK(bytes.substr(0, 8) == "GRESCR01");
  uint32_t crc = Cache::crc32(std::string_view(bytes).substr(8));

  // A fresh program: 197 with the right CRC loads the cached copy.
  Shell::ScriptHost again;
  again.set_send([&](int id, std::string_view b) {
    sent.emplace_back(id, std::string(b));
    return true;
  });
  again.set_cache_dir(dir.string());
  d.crc = crc;
  sent.clear();
  CHECK(again.on_message(197, Shell::make_load_script(d)));
  again.tick();
  CHECK(sent.empty());
  CHECK(logged(again, "echo: hello"));

  // 190 reaches the loaded weapon.
  again.on_message(190, "");
  again.tick();
  CHECK(logged(again, "echo: lister"));

  // A wrong CRC, or CRC 0, asks again with 158; a class asks with 161.
  d.crc = crc ^ 1;
  again.on_message(197, Shell::make_load_script(d));
  d.crc = 0;
  again.on_message(197, Shell::make_load_script(d));
  Shell::ScriptDescriptor cls = d;
  cls.type = "class";
  cls.name = "door";
  cls.crc = 5;
  again.on_message(197, Shell::make_load_script(cls));
  CHECK(sent.size() == 3);
  if (sent.size() == 3) {
    CHECK(sent[0].first == 158 && sent[0].second == "-System");
    CHECK(sent[1].first == 158);
    CHECK(sent[2].first == 161 && sent[2].second == "door");
  }

  // A class body is stored by name.
  cls.cache_flag = 0;
  again.on_message(140, Shell::make_script_packet(cls, script));
  CHECK(again.classes().count("door") == 1);
  // Names cannot leave the cache folder.
  Shell::ScriptDescriptor evil = d;
  evil.name = "../../x";
  evil.cache_flag = 1;
  again.on_message(140, Shell::make_script_packet(evil, script));
  CHECK(fs::exists(dir / "weapons" / "______x.code"));
  fs::remove_all(dir);
}

}  // namespace

int main() {
  test_descriptors();
  test_delivery_and_cache();
  TEST_MAIN_END();
}
