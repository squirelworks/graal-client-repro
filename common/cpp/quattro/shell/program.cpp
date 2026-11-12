#include "program.hpp"

#include "../net/gtypes.hpp"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <sstream>

namespace Quattro::Shell {

namespace {

bool read_file(const std::string& path, std::string& out) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
  return true;
}

// The playfield walks half a tile per 50 ms tick.
constexpr double kStep = 0.5;

// The build's label without the platform ("6.03r7").
std::string short_label(const std::string& label) { return label.substr(0, label.find(' ')); }

}  // namespace

Program::Program(const Net::BuildProfile& profile, Options opt, Draw::Window& window)
    : profile_(profile),
      opt_(std::move(opt)),
      window_(window),
      session_(profile, {}),
      canvas_(opt_.width, opt_.height) {
  Net::Session::Events ev;
  ev.connecting = [this](const std::string& name, const std::string& addr) {
    if (log) log("connecting to " + name + " (" + addr + ")");
  };
  ev.connect_failed = [this](const std::string& why) {
    if (log) log("connect failed: " + why);
  };
  ev.disconnected = [this](const std::string& why) {
    if (log) log("disconnected: " + why);
  };
  ev.message = [this](int id, std::string_view body) { on_message(id, body); };
  session_.set_events(std::move(ev));
  world_.lobby_tiles = profile_.login_draws_tiles;
  world_.player.x = 30;
  world_.player.y = 30;

  if (!opt_.assets.empty()) {
    std::vector<std::uint8_t> bytes;
    std::string err;
    Draw::Image sheet;
    for (const char* rel : {"/pics1.png", "/levels/pics1.png"}) {
      if (Torque::Gui::read_file(opt_.assets + rel, bytes, err) && Torque::Gui::decode_png(bytes, sheet, err)) {
        renderer_.set_tile_sheet(std::move(sheet));
        break;
      }
    }
  }
}

std::string Program::window_title() const {
  // "Graal 6.03r7 - Lab Server", as the lab saw after the warp.
  return "Graal " + short_label(profile_.label) + " - " + session_.server_name();
}

bool Program::start() {
  bool ok = session_.start(opt_.host, opt_.port, opt_.account, opt_.password, opt_.language);
  window_.set_title(window_title());
  return ok;
}

void Program::load_local_level(const std::string& name) {
  if (opt_.assets.empty()) return;
  std::string data, err;
  for (const std::string& dir : {opt_.assets + "/levels/", opt_.assets + "/"}) {
    if (!read_file(dir + name, data)) continue;
    Files::Level lv;
    if (Files::read_level(data, lv, err)) {
      world_.level = std::move(lv);
      world_.have_level = true;
    } else if (log) {
      log(name + ": " + err);
    }
    return;
  }
}

void Program::on_message(int id, std::string_view body) {
  Net::Reader r(body);
  switch (id) {
    case 6:  // PLO_LEVELNAME
      level_name_ = std::string(body);
      world_.level = Files::Level{};
      world_.have_level = false;
      load_local_level(level_name_);
      break;
    case 101: {  // PLO_BOARDPACKET
      std::string err;
      if (Files::apply_board_packet(body, world_.level, err))
        world_.have_level = true;
      else if (log)
        log(err);
      break;
    }
    case 1: {  // PLO_LEVELLINK: "dest x y w h newx newy"
      std::istringstream in{std::string(body)};
      std::vector<std::string> tok;
      for (std::string t; in >> t;) tok.push_back(t);
      if (tok.size() >= 7) {
        Files::Link k;
        size_t n = tok.size();
        for (size_t i = 0; i + 6 < n; ++i) k.dest += (i ? " " : "") + tok[i];
        k.x = std::atoi(tok[n - 6].c_str());
        k.y = std::atoi(tok[n - 5].c_str());
        k.w = std::atoi(tok[n - 4].c_str());
        k.h = std::atoi(tok[n - 3].c_str());
        k.newx = tok[n - 2];
        k.newy = tok[n - 1];
        world_.level.links.push_back(k);
      }
      break;
    }
    case 4: {  // PLO_LEVELCHEST: x, y, item, sign
      Files::Chest c;
      c.x = static_cast<int>(r.gchar());
      c.y = static_cast<int>(r.gchar());
      c.item = static_cast<int>(r.gchar());
      c.sign = static_cast<int>(r.gchar());
      if (r.ok()) world_.level.chests.push_back(c);
      break;
    }
    case 178:  // the session follows the warp; the title follows the name
      break;
    default:
      break;
  }
}

bool Program::tick() {
  session_.tick();
  world_.lobby = session_.lobby_mode();
  if (window_.title() != window_title()) window_.set_title(window_title());

  for (Draw::Key k = window_.poll_key(); k != Draw::Key::NoKey; k = window_.poll_key()) {
    if (k == Draw::Key::Close || k == Draw::Key::Escape) quit_ = true;
  }
  // Walking: local only until the props layer sends X2/Y2.
  if (!world_.lobby) {
    auto& p = world_.player;
    if (window_.held(Draw::Key::Left)) p.x -= kStep;
    if (window_.held(Draw::Key::Right)) p.x += kStep;
    if (window_.held(Draw::Key::Up)) p.y -= kStep;
    if (window_.held(Draw::Key::Down)) p.y += kStep;
    p.x = std::clamp(p.x, 0.0, Files::kBoardSide - 2.0);
    p.y = std::clamp(p.y, 0.0, Files::kBoardSide - 2.0);
  }

  passes_.clear();
  renderer_.draw(canvas_, world_, Draw::follow(world_, canvas_.width(), canvas_.height()),
                 [this](const std::string& name) { passes_.push_back(name); });
  window_.present(canvas_.surface());
  return !quit_;
}

}  // namespace Quattro::Shell
