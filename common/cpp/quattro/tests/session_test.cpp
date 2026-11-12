// The session against a fake server on loopback: the login frame, the
// language packet, the ping, the receive filter, and the 178 warp to a
// second server under a new name and key.
#include "../net/connection.hpp"
#include "../net/gtypes.hpp"
#include "check.hpp"
#include "fake_server.hpp"

#include <atomic>
#include <chrono>
#include <string>
#include <thread>
#include <vector>

using namespace Quattro::Net;
using QuattroTest::FakeServer;

namespace {

template <typename Pred>
bool run_until(Session& s, FakeServer* a, FakeServer* b, Pred done, int ms = 3000) {
  auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(ms);
  while (std::chrono::steady_clock::now() < end) {
    s.tick();
    if (a && a->conn.connected()) a->pump();
    if (b && b->conn.connected()) b->pump();
    if (done()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  return false;
}

void test_session() {
  const BuildProfile* prof = find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;

  FakeServer login, game;
  CHECK(login.start() && game.start());

  std::vector<std::pair<int, std::string>> delivered;
  std::vector<std::string> connecting;
  Session::Events ev;
  ev.connecting = [&](const std::string& name, const std::string&) { connecting.push_back(name); };
  ev.message = [&](int id, std::string_view b) { delivered.emplace_back(id, std::string(b)); };
  Session s(*prof, ev);
  uint8_t keys[] = {0x11, 0x22};
  int next = 0;
  s.next_key = [&] { return keys[next++ % 2]; };

  // The client connects (blocking, with the listener's backlog) before the
  // server accepts.
  CHECK(s.start("127.0.0.1", login.port(), "guest", "pw"));
  CHECK(login.conn.accept_from(login.listener));
  CHECK(s.lobby_mode());
  CHECK(s.server_name() == "Login");

  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(37, "English"); }));
  CHECK(login.key == 0x11);
  // key, token, account, password, then "linux" and four empty fields.
  std::string want = "G3D0511C" + gstring("guest") + gstring("pw") + "linux,\"\",\"\",\"\",\"\"";
  CHECK(login.login_line == want);
  // No tamper check follows the language packet.
  for (auto& [id, b] : login.got) CHECK(id != 39);

  // Ping sub 0 is answered with 162; 41 is not in the 6.x set and is dropped;
  // 6 is delivered.
  login.send(gchar(108) + gchar(0) + gshort(1234) + "\n" + gchar(41) + "hello\n" + gchar(6) + "onlinestartlocal.nw\n");
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(162, "!" + gshort(1234)); }));
  CHECK(run_until(s, &login, nullptr, [&] { return !delivered.empty(); }));
  CHECK(delivered.size() == 1 && delivered[0].first == 6 && delivered[0].second == "onlinestartlocal.nw");
  CHECK(s.connection().dropped() == 1);
  // A ping value above 0x6FFF is capped in the answer.
  login.send(gchar(108) + gchar(0) + gshort(0x3FFF) + "\n");
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(162, "!" + gshort(0x3FFF)); }));
  login.send(gchar(108) + gchar(1) + gshort(77) + "\n");
  CHECK(run_until(s, &login, nullptr, [&] { return s.connection().ping_value() == 77; }));

  // Outgoing rules: newline refused; an id the build does not send refused.
  CHECK(!s.connection().send(6, "a\nb"));
  CHECK(s.connection().error() == "Illegal characters in the outgoing data");
  CHECK(!s.connection().send(39, "x"));
  CHECK(s.connection().send(6, "hi"));
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(6, "hi"); }));

  // 178 warps to the game server under its name, with a new key.
  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::atomic<bool> accepted{false};
  std::thread acc([&] { accepted = game.conn.accept_from(game.listener); });
  bool warped = run_until(s, &login, nullptr, [&] { return s.logins() == 2; });
  acc.join();
  CHECK(warped && accepted);
  CHECK(s.server_name() == "Lab Server");
  CHECK(!s.lobby_mode());
  CHECK(connecting.size() == 2 && connecting[1] == "Lab Server");
  CHECK(run_until(s, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(game.key == 0x22);
  CHECK(game.login_line == want);
}

void test_warp_parse() {
  ServerWarp w;
  CHECK(parse_server_warp("0,Lab Server,127.0.0.1,14900", w));
  CHECK(w.name == "Lab Server" && w.host == "127.0.0.1" && w.port == 14900);
  CHECK(!parse_server_warp("0,x,127.0.0.1", w));
  CHECK(!parse_server_warp("0,x,127.0.0.1,99999", w));
  CHECK(!parse_server_warp("0,x,,14900", w));
  CHECK(!parse_server_warp("0,x,h,1a", w));
}

}  // namespace

int main() {
  test_warp_parse();
  test_session();
  TEST_MAIN_END();
}
