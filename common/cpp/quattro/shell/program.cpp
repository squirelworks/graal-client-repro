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
  me_.nickname = "unknown";  // the lab's 6.03r7 sent "unknown" with no nickname set
  me_.language = opt_.language;
  scripts_.set_send([this](int id, std::string_view body) { return session_.connection().send(id, body); });
  scripts_.on_log = [this](const std::string& s) {
    if (log) log(s);
  };
  world_.player.x = 30;
  world_.player.y = 30;
  assets_ = std::make_unique<Draw::Assets>(Draw::asset_dirs(opt_.assets));
  renderer_.set_assets(assets_.get());
  gui_ = std::make_unique<GuiHost>(scripts_.machine());
  gui_->screen().setSize(opt_.width, opt_.height);
  std::vector<std::string> dirs;
  if (!opt_.assets.empty())
    for (const char* sub : {"", "/gui", "/images", "/levels", "/levels/images"}) dirs.push_back(opt_.assets + sub);
  painter_ = std::make_unique<CanvasPainter>(canvas_, dirs);
  painter_->on_engine_control = [this](const gs2::gui::Control& c, const gs2::gui::Rect& r) {
    // The playfield: the world passes inside the control's rectangle.
    if (c.type() != "GuiGraalCtrl" && c.type() != "guigraalctrl") return;
    canvas_.push_clip({r.x, r.y, r.w, r.h});
    renderer_.draw(canvas_, world_, Draw::follow(world_, canvas_.width(), canvas_.height()),
                   [this](const std::string& name) { passes_.push_back(name); });
    canvas_.pop_clip();
  };
  if (!opt_.program.empty()) {
    std::string err;
    int n = gui_->load_start_scripts(opt_.program, err);
    if (log) log(n ? "start scripts: " + std::to_string(n) : err);
  }

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
    std::string table;
    if (read_file(opt_.assets + "/arrays.dat", table) && !World::read_arrays_dat(table, tile_types_, err) && log)
      log(err);
  }
}

Draw::Actor Program::actor_for(int id, const World::Player& p) {
  Draw::Actor a;
  a.x = p.x;
  a.y = p.y;
  a.chat = p.chat;
  a.gani = p.gani.empty() ? "idle" : p.gani;
  a.dir = p.dir;
  a.head = p.head;
  a.body = p.body;
  a.sword = p.sword_image;
  a.shield = p.shield_image;
  for (size_t i = 1; i < a.attr.size(); ++i) a.attr[i] = p.attr[i];
  // A gani plays from the tick it was set.
  auto& start = gani_start_[id];
  if (start.first != a.gani) start = {a.gani, frame_};
  a.ani_tick = frame_ - start.second;
  return a;
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
  // The script cache is per server host (weblevels/<host>).
  if (!opt_.assets.empty() && cache_server_ != session_.server_host()) {
    cache_server_ = session_.server_host();
    scripts_.set_cache_dir(opt_.assets + "/weblevels/" + cache_server_);
  }
  if (scripts_.on_message(id, body)) return;
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
    case 9: {  // PLO_PLAYERPROPS
      World::apply_props(r, me_, false);
      if (!props_sent_) {
        // Logged in: the client's own props, then only what moves.
        session_.connection().send(2, World::initial_props(me_, profile_.platform));
        mover_.reset(me_);
        props_sent_ = true;
      }
      break;
    }
    case 8: {  // PLO_OTHERPLPROPS: GSHORT id, then props
      if (body.size() < 2) break;
      int pid = static_cast<int>(r.gshort());
      World::Player& o = others_[pid];
      o.id = pid;
      World::apply_props(r, o, true);
      if (o.gone) {
        others_.erase(pid);
        gani_start_.erase(pid);
      }
      break;
    }
    case 14:    // PLO_PLAYERWARP: c x*2, c y*2, level
    case 49: {  // PLO_PLAYERWARP2: c x*2, c y*2, c z, c gmap x, c gmap y, level
      me_.x = r.gchar() / 2.0;
      me_.y = r.gchar() / 2.0;
      if (id == 49) {
        r.gchar();
        me_.gmap_x = static_cast<int>(r.gchar());
        me_.gmap_y = static_cast<int>(r.gchar());
      }
      me_.level = r.rest();
      others_.clear();
      mover_.reset(me_);
      break;
    }
    case 178:  // the session follows the warp; the title follows the name
      props_sent_ = false;
      others_.clear();
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
    if (k == Draw::Key::Close || (k == Draw::Key::Escape && !gui_->has_content())) quit_ = true;
  }
  for (Draw::InputEvent e; window_.poll_input(e);) {
    if (gui_->has_content()) gui_->input(e);
  }
  // Walking: half a tile per held arrow per tick, against the walls.
  if (!world_.lobby) {
    auto& p = me_;
    unsigned keys = (window_.held(Draw::Key::Up) ? 1u : 0u) | (window_.held(Draw::Key::Left) ? 2u : 0u) |
                    (window_.held(Draw::Key::Down) ? 4u : 0u) | (window_.held(Draw::Key::Right) ? 8u : 0u);
    std::string action = walker_.tick(p, keys, world_.level, tile_types_);
    if (!action.empty() && props_sent_) session_.connection().send(38, action);
    if (props_sent_) {
      std::string moved = mover_.diff(p);
      if (!moved.empty()) session_.connection().send(2, moved);
    }
  }
  ++frame_;
  world_.player = actor_for(-1, me_);
  world_.others.clear();
  for (const auto& [pid, o] : others_) {
    if (!o.level.empty() && !me_.level.empty() && o.level != me_.level) continue;
    world_.others.push_back(actor_for(pid, o));
  }

  scripts_.tick();
  gui_->pick_content();
  gui_->screen().advance(0.05);  // the show-images' emitters, one 50 ms tick
  passes_.clear();
  if (gui_->has_content()) {
    // RenderGUI: the content and dialogs; the world shows in the playfield.
    canvas_.clear({0, 0, 0, 255});
    gs2::gui::drawScreen(gui_->screen(), *painter_);
    painter_->reset_clip();
    passes_.push_back("RenderGUI");
  } else {
    renderer_.draw(canvas_, world_, Draw::follow(world_, canvas_.width(), canvas_.height()),
                   [this](const std::string& name) { passes_.push_back(name); });
  }
  window_.present(canvas_.surface());
  return !quit_;
}

}  // namespace Quattro::Shell
