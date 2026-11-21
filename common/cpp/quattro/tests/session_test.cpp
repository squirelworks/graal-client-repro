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
  // key, token, account, password, then "linux" and the four made-up machine fields.
  std::string want = "G3D0511C" + gstring("guest") + gstring("pw") + "linux,c3adb4be4be05a76d9ffdc3e88ba180b,b94291e395c1ae186c7ee9b2d6c685be,\"\",\"2.6.38-1-squirrelos  #1-SquirrelOS SMP Mon Jun 27 12:00:00 UTC 2011\"";
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

// 4.04r2: the same login and 178 warp; "win" and three fields; 108 is not
// in its switch, so a ping goes unanswered and is dropped; 41 is delivered.
void test_session_404() {
  const BuildProfile* prof = find_profile("4.04r2");
  CHECK(prof);
  if (!prof) return;
  FakeServer login, game;
  CHECK(login.start() && game.start());
  std::vector<std::pair<int, std::string>> delivered;
  Session::Events ev;
  ev.message = [&](int id, std::string_view b) { delivered.emplace_back(id, std::string(b)); };
  Session s(*prof, ev);
  s.next_key = [] { return uint8_t(0x33); };
  CHECK(s.start("127.0.0.1", login.port(), "guest", "pw"));
  CHECK(login.conn.accept_from(login.listener));
  CHECK(s.lobby_mode());
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(37, "English"); }));
  const std::string want = "G3D17026" + gstring("guest") + gstring("pw") + "win,c2482de76c59ac3c4ce0b7e065a2d09c,3c639304427ab3b3c6439a39c31c9df5,217767adb74e936b5ee209ed65ecc400";
  CHECK(login.login_line == want);
  login.send(gchar(108) + gchar(0) + gshort(1234) + "\n" + gchar(41) + "hello\n");
  CHECK(run_until(s, &login, nullptr, [&] { return !delivered.empty(); }));
  CHECK(delivered.size() == 1 && delivered[0].first == 41 && delivered[0].second == "hello");
  CHECK(!login.saw(162, "!" + gshort(1234)));
  CHECK(s.connection().dropped() == 1);
  CHECK(!s.connection().send(39, "x"));
  CHECK(!s.connection().send(162, "x"));
  CHECK(s.connection().send(6, "hi"));
  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::atomic<bool> accepted{false};
  std::thread acc([&] { accepted = game.conn.accept_from(game.listener); });
  bool warped = run_until(s, &login, nullptr, [&] { return s.logins() == 2; });
  acc.join();
  CHECK(warped && accepted);
  CHECK(s.server_name() == "Lab Server");
  CHECK(run_until(s, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(game.login_line == want);
}

// 5.12: the 5-field login line, every frame zlib with 5.12's step rule,
// and the 178 hand-on, against a server stepping as 5.12 does.
void test_session_512() {
  const BuildProfile* prof = find_profile("5.12");
  CHECK(prof);
  if (!prof) return;
  FakeServer login, game;
  login.round_down = game.round_down = true;
  CHECK(login.start() && game.start());
  std::vector<std::pair<int, std::string>> delivered;
  Session::Events ev;
  ev.message = [&](int id, std::string_view b) { delivered.emplace_back(id, std::string(b)); };
  Session s(*prof, ev);
  s.next_key = [] { return uint8_t(0x4B); };
  CHECK(s.start("127.0.0.1", login.port(), "guest", "pw"));
  CHECK(login.conn.accept_from(login.listener));
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(37, "English"); }));
  const std::string want = "G3D14097" + gstring("guest") + gstring("pw") + "win,c2482de76c59ac3c4ce0b7e065a2d09c,3c639304427ab3b3c6439a39c31c9df5,217767adb74e936b5ee209ed65ecc400,\"6.2 9200 \"";
  CHECK(login.login_line == want);
  CHECK(!login.frame_types.empty());
  for (int t : login.frame_types) CHECK(t == kZlib);
  // Short frames from the server (13 and 7 bytes of zlib are typical) keep
  // both iterators in step.
  for (int i = 0; i < 5; ++i) login.send(gchar(41) + std::string(static_cast<size_t>(i), 'x') + "\n");
  CHECK(run_until(s, &login, nullptr, [&] { return delivered.size() == 5; }));
  CHECK(delivered.size() == 5 && delivered[4].second == "xxxx");
  CHECK(s.connection().send(6, "hi"));
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(6, "hi"); }));
  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::atomic<bool> accepted{false};
  std::thread acc([&] { accepted = game.conn.accept_from(game.listener); });
  bool warped = run_until(s, &login, nullptr, [&] { return s.logins() == 2; });
  acc.join();
  CHECK(warped && accepted);
  CHECK(run_until(s, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(game.login_line == want);
}

// 5.24r4: win + OS version login, tiles in Login, no ping answer, 178 hand-on.
void test_session_524() {
  const BuildProfile* prof = find_profile("5.24r4");
  CHECK(prof && prof->login_draws_tiles && !prof->answers_ping);
  if (!prof) return;
  FakeServer login, game;
  CHECK(login.start() && game.start());
  std::vector<std::pair<int, std::string>> delivered;
  Session::Events ev;
  ev.message = [&](int id, std::string_view b) { delivered.emplace_back(id, std::string(b)); };
  Session s(*prof, ev);
  s.next_key = [] { return uint8_t(0x5A); };
  CHECK(s.start("127.0.0.1", login.port(), "guest", "pw"));
  CHECK(login.conn.accept_from(login.listener));
  CHECK(s.lobby_mode());
  CHECK(run_until(s, &login, nullptr, [&] { return login.saw(37, "English"); }));
  const std::string want = "G3D15010" + gstring("guest") + gstring("pw") +
    "win,c2482de76c59ac3c4ce0b7e065a2d09c,3c639304427ab3b3c6439a39c31c9df5,217767adb74e936b5ee209ed65ecc400,\"6.2 9200 \"";
  CHECK(login.login_line == want);
  // 108 is pre-switch; without answers_ping it is dropped. 41 is not in
  // 5.24's receive switch (Protocol524r4.PLOKnown). 6 is delivered.
  login.send(gchar(108) + gchar(0) + gshort(1234) + "\n" + gchar(41) + "hello\n" +
             gchar(6) + "onlinestartlocal.nw\n");
  CHECK(run_until(s, &login, nullptr, [&] { return !delivered.empty(); }));
  CHECK(delivered.size() == 1 && delivered[0].first == 6 &&
        delivered[0].second == "onlinestartlocal.nw");
  CHECK(!login.saw(162, "!" + gshort(1234)));
  CHECK(s.connection().dropped() >= 1);
  CHECK(!s.connection().send(39, "x"));
  CHECK(s.connection().send(6, "hi"));
  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::atomic<bool> accepted{false};
  std::thread acc([&] { accepted = game.conn.accept_from(game.listener); });
  bool warped = run_until(s, &login, nullptr, [&] { return s.logins() == 2; });
  acc.join();
  CHECK(warped && accepted);
  CHECK(s.server_name() == "Lab Server");
  CHECK(run_until(s, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(game.login_line == want);
}

// 6.00r4 shares the 5.31 token, not its receive switch. Exercise the
// production connection filter after a real synthetic gen-5 login.
void test_session_600() {
  const BuildProfile* prof = find_profile("6.00r4");
  CHECK(prof);
  if (!prof) return;
  FakeServer server;
  CHECK(server.start());
  std::vector<int> delivered;
  Session::Events ev;
  ev.message = [&](int id, std::string_view) { delivered.push_back(id); };
  Session session(*prof, ev);
  session.next_key = [] { return uint8_t(0x5A); };
  CHECK(session.start("127.0.0.1", server.port(), "guest", "pw"));
  CHECK(server.conn.accept_from(server.listener));
  CHECK(run_until(session, &server, nullptr, [&] { return server.saw(37, "English"); }));
  const std::string want = "G3D26090" + gstring("guest") + gstring("pw") +
    "win" + kFakeWinFields + ",\"6.2 9200 \"";
  CHECK(server.login_line == want);
  server.send(gchar(165) + "ignored\n" + gchar(169) + "ignored\n" +
              gchar(111) + "ignored\n" + gchar(175) + "accepted\n" +
              gchar(184) + "accepted\n" + gchar(6) + "done.nw\n");
  CHECK(run_until(session, &server, nullptr, [&] { return delivered.size() == 3; }));
  CHECK((delivered == std::vector<int>{175, 184, 6}));
  CHECK(session.connection().dropped() == 3);
  CHECK(!session.connection().send(39, "x"));
  CHECK(!session.connection().send(160, "x"));
}

int main() {
  test_warp_parse();
  test_session();
  test_session_404();
  test_session_512();
  test_session_524();
  test_session_600();
  TEST_MAIN_END();
}
