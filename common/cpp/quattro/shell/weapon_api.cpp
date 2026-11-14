// The GS2 weapon commands and events of the Quattro program, in the order
// of Graal_analysis npc-library/gs2-weapon-corpus-2026-11-14.md
// ("Implementation order"). The machine-level ones (opcodes, scheduleevent,
// cancelevents, trigger, destroy, md5) are in common/cpp/gs2; triggerserver,
// triggeraction, findweapon and the 48 receive path in shell/scripts.cpp.
//
// Where a command's argument form is not in the notes (the survey counts
// names, not signatures), the GS1 form from npc-library/gs1-reference-205.md
// is kept. Each reading is listed in the README ("GS2 weapon scripts").

#include "program.hpp"

#include "../draw/ui_font.hpp"
#include "../net/gtypes.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>

namespace Quattro::Shell {

namespace {

std::string low(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

double child_num(const gs2::VarPtr& v, const char* key, double def) {
  gs2::VarPtr c = v->child(key);
  return c ? c->number() : def;
}

std::string child_str(const gs2::VarPtr& v, const char* key) {
  gs2::VarPtr c = v->child(key);
  return c ? c->string() : std::string();
}

unsigned byte_of(double v) { return static_cast<unsigned>(std::lround(std::isfinite(v) ? std::clamp(v, 0.0, 223.0) : 0)); }

Torque::Gui::Color colour_of(const gs2::VarPtr& img) {
  auto c = [](double v) { return static_cast<std::uint8_t>(std::isfinite(v) ? std::clamp(v, 0.0, 1.0) * 255 + 0.5 : 0); };
  return {c(child_num(img, "red", 1)), c(child_num(img, "green", 1)), c(child_num(img, "blue", 1)),
          c(child_num(img, "alpha", 1))};
}

bool board_rect(double x, double y, double w, double h) {
  return std::isfinite(x) && std::isfinite(y) && std::isfinite(w) && std::isfinite(h) &&
         x >= -Files::kBoardSide && x <= 2 * Files::kBoardSide &&
         y >= -Files::kBoardSide && y <= 2 * Files::kBoardSide &&
         w >= 0 && w <= Files::kBoardSide && h >= 0 && h <= Files::kBoardSide;
}

int script_int(double v) {
  return static_cast<int>(std::isfinite(v) ? std::clamp(v, -1000000.0, 1000000.0) : 0);
}

bool pixel_int(double v, int& out) {
  if (!std::isfinite(v) || std::fabs(v) > 1000000) return false;
  out = static_cast<int>(std::lround(v));
  return true;
}

}  // namespace

// ------------------------------------------------------------ show-images

gs2::VarPtr ShowImages::find(const gs2::Var* owner, int index, bool create) {
  auto key = std::make_pair(owner, index);
  auto it = imgs_.find(key);
  if (it != imgs_.end()) return it->second;
  if (!create) return nullptr;
  auto v = std::make_shared<gs2::Var>("img" + std::to_string(index), "TShowImg");
  v->setAcceptsAllProperties(true);
  v->childOrCreate("index")->setNumber(index);
  v->childOrCreate("layer")->setNumber(1);
  for (const char* k : {"red", "green", "blue", "alpha", "zoom"}) v->childOrCreate(k)->setNumber(1);
  imgs_[key] = v;
  return v;
}

void ShowImages::hide(const gs2::Var* owner, int index) { imgs_.erase(std::make_pair(owner, index)); }

void ShowImages::hide_range(const gs2::Var* owner, int from, int to) {
  for (auto it = imgs_.begin(); it != imgs_.end();) {
    if (it->first.first == owner && it->first.second >= from && it->first.second <= to) it = imgs_.erase(it);
    else ++it;
  }
}

bool ShowImages::drop(const gs2::Var* v) {
  for (auto it = imgs_.begin(); it != imgs_.end(); ++it)
    if (it->second.get() == v) {
      imgs_.erase(it);
      return true;
    }
  return false;
}

void ShowImages::drop_owner(const gs2::Var* owner) {
  for (auto it = imgs_.begin(); it != imgs_.end();) {
    if (it->first.first == owner) it = imgs_.erase(it);
    else ++it;
  }
}

std::vector<gs2::VarPtr> ShowImages::in_order() const {
  std::vector<std::pair<double, gs2::VarPtr>> v;
  for (const auto& [k, img] : imgs_) v.emplace_back(child_num(img, "layer", 1), img);
  std::stable_sort(v.begin(), v.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
  std::vector<gs2::VarPtr> out;
  for (auto& p : v) out.push_back(p.second);
  return out;
}

// --------------------------------------------------------------- commands

void Program::register_script_commands() {
  gs2::Machine& m = scripts_.machine();
  using Args = std::vector<gs2::Value>;
  const auto zero = gs2::Value::number(0);
  auto owner = [&m](gs2::Var& self) -> const gs2::Var* {
    gs2::VarPtr t = m.currentThis();
    return t ? t.get() : &self;
  };
  auto img = [this, owner](gs2::Machine& mm, gs2::Var& self, const gs2::Value& index) {
    return show_images_.find(owner(self), script_int(mm.toNumber(index)), true);
  };

  // Step 2: the gani and the hold. setani(gani, params) and replaceani(old,
  // new) (GS1 setani/replaceani); freezeplayer(seconds); the default
  // movement and the weapons on and off.
  m.addCommand("setani", "s", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    std::string g = mm.toString(a[0]);
    if (g.size() > 5 && low(g.substr(g.size() - 5)) == ".gani") g.resize(g.size() - 5);
    me_.gani = g;
    return zero;
  });
  m.addCommand("replaceani", "ss", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    replace_ani_[low(mm.toString(a[0]))] = mm.toString(a[1]);
    return zero;
  });
  m.addCommand("freezeplayer", "f", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    freeze_left_ = std::max(0.0, mm.toNumber(a[0]));
    return zero;
  });
  m.addCommand("disabledefmovement", "", [this, zero](gs2::Machine&, gs2::Var&, Args&) {
    def_movement_ = false;
    return zero;
  });
  m.addCommand("enabledefmovement", "", [this, zero](gs2::Machine&, gs2::Var&, Args&) {
    def_movement_ = true;
    return zero;
  });
  m.addCommand("disableweapons", "", [this, zero](gs2::Machine&, gs2::Var&, Args&) {
    weapons_enabled_ = false;
    return zero;
  });
  m.addCommand("enableweapons", "", [this, zero](gs2::Machine&, gs2::Var&, Args&) {
    weapons_enabled_ = true;
    return zero;
  });

  // Step 3: the sign box.
  m.addCommand("say2", "s", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    sign_text_ = mm.toString(a[0]);
    return zero;
  });

  // Step 5: show-images.
  auto show_image = [img, zero](bool with_z) {
    return [img, zero, with_z](gs2::Machine& mm, gs2::Var& self, Args& a) {
      auto v = img(mm, self, a[0]);
      v->childOrCreate("type")->setString("image");
      v->childOrCreate("image")->setString(mm.toString(a[1]));
      v->childOrCreate("x")->setNumber(mm.toNumber(a[2]));
      v->childOrCreate("y")->setNumber(mm.toNumber(a[3]));
      if (with_z && a.size() > 4) v->childOrCreate("z")->setNumber(mm.toNumber(a[4]));
      return zero;
    };
  };
  m.addCommand("showimg", "nsnn", show_image(false));
  m.addCommand("showimg2", "nsnn", show_image(true));
  // showtext(index, x, y, font, style, text); showtext2 has z after y.
  auto show_text = [img, zero](bool with_z) {
    return [img, zero, with_z](gs2::Machine& mm, gs2::Var& self, Args& a) {
      auto v = img(mm, self, a[0]);
      const size_t o = with_z ? 1 : 0;
      v->childOrCreate("type")->setString("text");
      v->childOrCreate("x")->setNumber(mm.toNumber(a[1]));
      v->childOrCreate("y")->setNumber(mm.toNumber(a[2]));
      if (with_z) v->childOrCreate("z")->setNumber(mm.toNumber(a[3]));
      v->childOrCreate("font")->setString(mm.toString(a[3 + o]));
      v->childOrCreate("style")->setString(mm.toString(a[4 + o]));
      v->childOrCreate("text")->setString(mm.toString(a[5 + o]));
      return zero;
    };
  };
  m.addCommand("showtext", "nnnsss", show_text(false));
  m.addCommand("showtext2", "nnnnsss", show_text(true));
  // showpoly(index, {x1, y1, x2, y2, ...}).
  m.addCommand("showpoly", "no", [img, zero](gs2::Machine& mm, gs2::Var& self, Args& a) {
    auto v = img(mm, self, a[0]);
    v->childOrCreate("type")->setString("poly");
    auto pts = v->childOrCreate("polygon");
    gs2::VarPtr src = mm.toObject(a[1]);
    if (src && src->kind() == gs2::Var::Kind::Array) pts->assignFrom(*src);
    else pts->setArray(0);
    return zero;
  });
  // showani(index, x, y, dir, ani, params...); showani2 has z after y.
  auto show_ani = [img, zero](bool with_z) {
    return [img, zero, with_z](gs2::Machine& mm, gs2::Var& self, Args& a) {
      auto v = img(mm, self, a[0]);
      const size_t o = with_z ? 1 : 0;
      v->childOrCreate("type")->setString("ani");
      v->childOrCreate("x")->setNumber(mm.toNumber(a[1]));
      v->childOrCreate("y")->setNumber(mm.toNumber(a[2]));
      if (with_z) v->childOrCreate("z")->setNumber(mm.toNumber(a[3]));
      v->childOrCreate("dir")->setNumber(mm.toNumber(a[3 + o]));
      v->childOrCreate("ani")->setString(mm.toString(a[4 + o]));
      return zero;
    };
  };
  m.addCommand("showani", "nnnns", show_ani(false));
  m.addCommand("showani2", "nnnnns", show_ani(true));
  m.addCommand("findimg", "n", [img](gs2::Machine& mm, gs2::Var& self, Args& a) {
    return gs2::Value::object(img(mm, self, a[0]));
  });
  m.addCommand("hideimg", "n", [this, owner, zero](gs2::Machine& mm, gs2::Var& self, Args& a) {
    show_images_.hide(owner(self), script_int(mm.toNumber(a[0])));
    return zero;
  });
  m.addCommand("hideimgs", "nn", [this, owner, zero](gs2::Machine& mm, gs2::Var& self, Args& a) {
    show_images_.hide_range(owner(self), script_int(mm.toNumber(a[0])), script_int(mm.toNumber(a[1])));
    return zero;
  });
  m.addCommand("changeimgcolors", "nnnnn", [img, zero](gs2::Machine& mm, gs2::Var& self, Args& a) {
    auto v = img(mm, self, a[0]);
    const char* keys[4] = {"red", "green", "blue", "alpha"};
    for (int i = 0; i < 4; ++i) v->childOrCreate(keys[i])->setNumber(mm.toNumber(a[static_cast<size_t>(i) + 1]));
    return zero;
  });
  auto change_one = [img, zero](const char* key) {
    return [img, zero, key](gs2::Machine& mm, gs2::Var& self, Args& a) {
      img(mm, self, a[0])->childOrCreate(key)->setNumber(mm.toNumber(a[1]));
      return zero;
    };
  };
  m.addCommand("changeimgvis", "nn", change_one("layer"));
  m.addCommand("changeimgzoom", "nn", change_one("zoom"));
  m.addCommand("changeimgmode", "nn", change_one("mode"));
  m.addCommand("changeimgpart", "nnnnn", [img, zero](gs2::Machine& mm, gs2::Var& self, Args& a) {
    auto v = img(mm, self, a[0]);
    const char* keys[4] = {"partx", "party", "partw", "parth"};
    for (int i = 0; i < 4; ++i) v->childOrCreate(keys[i])->setNumber(mm.toNumber(a[static_cast<size_t>(i) + 1]));
    return zero;
  });
  m.addCommand("getimgwidth", "s", [this](gs2::Machine& mm, gs2::Var&, Args& a) {
    const auto* im = assets_->image(mm.toString(a[0]));
    return gs2::Value::number(im ? im->width : 0);
  });
  m.addCommand("getimgheight", "s", [this](gs2::Machine& mm, gs2::Var&, Args& a) {
    const auto* im = assets_->image(mm.toString(a[0]));
    return gs2::Value::number(im ? im->height : 0);
  });

  // Step 6: the board tests, keys, sound, focus and the rest.
  m.addCommand("onwall", "nn", [this](gs2::Machine& mm, gs2::Var&, Args& a) {
    if (!board_rect(mm.toNumber(a[0]), mm.toNumber(a[1]), 0, 0)) return gs2::Value::number(0);
    return gs2::Value::number(World::point_blocked(world_.level, tile_types_, mm.toNumber(a[0]), mm.toNumber(a[1])) ? 1 : 0);
  });
  m.addCommand("onwall2", "nnnn", [this](gs2::Machine& mm, gs2::Var&, Args& a) {
    // Any point of the rectangle, tested every half tile and at its edges.
    const double x = mm.toNumber(a[0]), y = mm.toNumber(a[1]), w = mm.toNumber(a[2]), h = mm.toNumber(a[3]);
    if (!board_rect(x, y, w, h)) return gs2::Value::number(0);
    for (double dy = 0;; dy = std::min(dy + 0.5, h)) {
      for (double dx = 0;; dx = std::min(dx + 0.5, w)) {
        if (World::point_blocked(world_.level, tile_types_, x + dx, y + dy)) return gs2::Value::number(1);
        if (dx >= w) break;
      }
      if (dy >= h) break;
    }
    return gs2::Value::number(0);
  });
  auto water_at = [this](double x, double y) {
    if (!std::isfinite(x) || !std::isfinite(y) || x < 0 || y < 0 ||
        x >= Files::kBoardSide || y >= Files::kBoardSide) return false;
    const int tx = static_cast<int>(std::floor(x)), ty = static_cast<int>(std::floor(y));
    if (!tile_types_.loaded || world_.level.layers.empty() || tx < 0 || ty < 0 || tx >= Files::kBoardSide ||
        ty >= Files::kBoardSide)
      return false;
    return static_cast<bool>(tile_types_.liquid[world_.level.tile(tx, ty) & 0xFFF]);
  };
  m.addCommand("onwater", "nn", [water_at](gs2::Machine& mm, gs2::Var&, Args& a) {
    return gs2::Value::number(water_at(mm.toNumber(a[0]), mm.toNumber(a[1])) ? 1 : 0);
  });
  m.addCommand("onwater2", "nnnn", [water_at](gs2::Machine& mm, gs2::Var&, Args& a) {
    const double x = mm.toNumber(a[0]), y = mm.toNumber(a[1]), w = mm.toNumber(a[2]), h = mm.toNumber(a[3]);
    if (!board_rect(x, y, w, h)) return gs2::Value::number(0);
    for (double dy = 0;; dy = std::min(dy + 0.5, h)) {
      for (double dx = 0;; dx = std::min(dx + 0.5, w)) {
        if (water_at(x + dx, y + dy)) return gs2::Value::number(1);
        if (dx >= w) break;
      }
      if (dy >= h) break;
    }
    return gs2::Value::number(0);
  });
  // Sound: logged until the program has a sound layer.
  for (const char* name : {"play", "play2", "playlooped", "playlooped2", "stopsound"})
    m.addCommand(name, "", [this, zero, name](gs2::Machine& mm, gs2::Var&, Args& a) {
      if (log) log(std::string(name) + " " + (a.empty() ? std::string() : mm.toString(a[0])));
      return zero;
    });
  // keydown(i): GS1's key indices, "0..10: up, left, down, right, S, A, D, M,
  // tab, Q, P" (the 1.41 commands.rtf). keydown2(code, ignorecase) and
  // getkeycode(name) use virtual-key codes.
  m.addCommand("keydown", "n", [this](gs2::Machine& mm, gs2::Var&, Args& a) {
    return gs2::Value::number(held_index(script_int(mm.toNumber(a[0]))) ? 1 : 0);
  });
  m.addCommand("keydown2", "n", [this](gs2::Machine& mm, gs2::Var&, Args& a) {
    return gs2::Value::number(keys_down_.count(script_int(mm.toNumber(a[0]))) ? 1 : 0);
  });
  for (const char* name : {"getkeycode", "keycode"})
    m.addCommand(name, "s", [](gs2::Machine& mm, gs2::Var&, Args& a) {
      const std::string k = mm.toString(a[0]);
      return gs2::Value::number(ScriptHost::keycode(k, k.size() == 1 ? static_cast<unsigned char>(k[0]) : 0));
    });
  m.addCommand("seticonsize", "", [zero](gs2::Machine&, gs2::Var&, Args&) { return zero; });
  m.addCommand("hideplayer", "f", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    hide_left_ = std::max(0.0, mm.toNumber(a[0]));
    return zero;
  });
  m.addCommand("setfocus", "nn", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    world_.focus = true;
    world_.focus_x = mm.toNumber(a[0]);
    world_.focus_y = mm.toNumber(a[1]);
    return zero;
  });
  m.addCommand("resetfocus", "", [this, zero](gs2::Machine&, gs2::Var&, Args&) {
    world_.focus = false;
    return zero;
  });

  // Step 7: setshootparams(params...) and shoot(x, y, z, angle, zangle,
  // power, gani, ganiparams). The shot goes as C->S 40 (PLI_SHOOT): GINT3 0,
  // x and y in half tiles, z + 50, the angle as 0..220 for 0..2 pi, the
  // vertical angle as 0..220 for -pi..pi, the power in 44ths of a tile, the
  // gani, then the shoot params with their length first, as GServer-v2
  // reads it [srv]. Whether 6.x sends 40 or 48 (PLI_SHOOT2) is not read.
  m.addCommand("setshootparams", "", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    std::vector<std::string> f;
    for (const auto& v : a) f.push_back(mm.toString(v));
    shoot_params_.clear();
    for (size_t i = 0; i < f.size(); ++i) shoot_params_ += (i ? "," : "") + f[i];
    return zero;
  });
  m.addCommand("shoot", "nnnnnn", [this, zero](gs2::Machine& mm, gs2::Var&, Args& a) {
    const double pi = 3.14159265358979323846;
    double ang = std::fmod(mm.toNumber(a[3]), 2 * pi);
    if (ang < 0) ang += 2 * pi;
    const double zang = std::clamp(mm.toNumber(a[4]), -pi, pi);
    const std::string gani = a.size() > 6 ? mm.toString(a[6]) : std::string();
    std::string body = Net::gint3(0) + Net::gchar(byte_of(mm.toNumber(a[0]) * 2)) +
                       Net::gchar(byte_of(mm.toNumber(a[1]) * 2)) + Net::gchar(byte_of(mm.toNumber(a[2]) + 50)) +
                       Net::gchar(byte_of(ang / (2 * pi) * 220)) + Net::gchar(byte_of((zang + pi) / (2 * pi) * 220)) +
                       Net::gchar(byte_of(mm.toNumber(a[5]) * 44)) + Net::gstring(gani) +
                       Net::gchar(byte_of(static_cast<double>(shoot_params_.size()))) + shoot_params_;
    if (props_sent_) session_.connection().send(40, body);
    shoot_params_.clear();
    return zero;
  });

  m.onDestroy = [this](const gs2::VarPtr& v) { on_destroy(v); };
}

void Program::on_destroy(const gs2::VarPtr& v) {
  if (!v) return;
  if (gui_ && gui_->screen().remove(v.get())) return;
  if (show_images_.drop(v.get())) return;
  show_images_.drop_owner(v.get());
  const std::string w = scripts_.weapon_name(v.get());
  if (!w.empty()) {
    // A weapon's own destroy(): off the list, here only.
    weapons_.remove(w);
    scripts_.remove_weapon(w);
  }
}

// ----------------------------------------------------------------- events

bool Program::held_index(int i) const {
  auto held = [this](Draw::Key k) { return window_.held(k); };
  switch (i) {
    case 0: return held(Draw::Key::Up) || (action_moves_ & 1u);
    case 1: return held(Draw::Key::Left) || (action_moves_ & 2u);
    case 2: return held(Draw::Key::Down) || (action_moves_ & 4u);
    case 3: return held(Draw::Key::Right) || (action_moves_ & 8u);
    case 4: return held(Draw::Key::S) || (action_items_ & World::kKeyS) || keys_down_.count('S');
    case 5: return held(Draw::Key::A) || (action_items_ & World::kKeyA) || keys_down_.count('A');
    case 6: return held(Draw::Key::D) || action_d_ || keys_down_.count('D');
    case 7: return keys_down_.count('M') > 0;
    case 8: return held(Draw::Key::Tab) || keys_down_.count(9);
    case 9: return held(Draw::Key::Q) || action_q_ || keys_down_.count('Q');
    case 10: return keys_down_.count('P') > 0;
    default: return false;
  }
}

void Program::script_input(const Draw::InputEvent& e) {
  if (e.type == Draw::InputEvent::KeyUp) {
    keys_down_.erase(ScriptHost::keycode(e.key, e.ch));
    return;
  }
  if (e.type == Draw::InputEvent::KeyDown) {
    const int code = ScriptHost::keycode(e.key, e.ch);
    // The sign box closes on a key (A, S, D, Enter or Space) and takes it.
    if (!sign_text_.empty() && (code == 'A' || code == 'S' || code == 'D' || code == 13 || code == 32)) {
      sign_text_.clear();
      return;
    }
    if (code) keys_down_.insert(code);
    scripts_.key_pressed(e.key, e.ch);
    return;
  }
  // A press on the play area: mousex/mousey in level tiles, mousescreenx/y
  // in window pixels, then onMouseDown("left" or "double").
  Draw::View v = Draw::follow(world_, canvas_.width(), canvas_.height());
  gs2::VarPtr u = scripts_.machine().universe();
  u->childOrCreate("mousex")->setNumber(v.left + static_cast<double>(e.x) / Draw::kTile);
  u->childOrCreate("mousey")->setNumber(v.top + static_cast<double>(e.y) / Draw::kTile);
  u->childOrCreate("mousescreenx")->setNumber(e.x);
  u->childOrCreate("mousescreeny")->setNumber(e.y);
  scripts_.queue_all("MouseDown", {gs2::Value::string(e.clicks > 1 ? "double" : "left")});
}

void Program::script_tick() {
  freeze_left_ = std::max(0.0, freeze_left_ - 0.05);
  hide_left_ = std::max(0.0, hide_left_ - 0.05);
  world_.player_hidden = hide_left_ > 0;
}

void Program::player_changed(int old_power) {
  if (me_.power < old_power) {
    scripts_.queue_all("PlayerHurt", {gs2::Value::number((old_power - me_.power) / 2.0)});
    if (old_power > 0 && me_.power <= 0) scripts_.queue_all("PlayerDies");
  }
}

// ---------------------------------------------------------------- drawing

void Program::draw_show_images(bool screen_layer) {
  if (show_images_.size() == 0) return;
  Draw::View view = Draw::follow(world_, canvas_.width(), canvas_.height());
  for (const auto& im : show_images_.in_order()) {
    const double layer = child_num(im, "layer", 1);
    if (!std::isfinite(layer)) continue;
    if ((layer >= 4) != screen_layer) continue;
    const std::string type = child_str(im, "type");
    auto to_px = [&](double x, double y) {
      if (screen_layer) return std::make_pair(x, y);
      return std::make_pair((x - view.left) * Draw::kTile, (y - view.top) * Draw::kTile);
    };
    auto pos = to_px(child_num(im, "x", 0), child_num(im, "y", 0));
    int px, py;
    if (!pixel_int(pos.first, px) || !pixel_int(pos.second, py)) continue;
    const Torque::Gui::Color col = colour_of(im);
    if (type == "image") {
      const Torque::Gui::Image* pic = assets_->image(child_str(im, "image"));
      if (!pic) continue;
      Draw::Rect src{0, 0, pic->width, pic->height};
      if (child_num(im, "partw", 0) > 0 && child_num(im, "parth", 0) > 0) {
        if (!pixel_int(child_num(im, "partx", 0), src.x) || !pixel_int(child_num(im, "party", 0), src.y) ||
            !pixel_int(child_num(im, "partw", 0), src.width) || !pixel_int(child_num(im, "parth", 0), src.height)) continue;
      }
      if (src.x < 0 || src.y < 0 || src.width <= 0 || src.height <= 0 ||
          src.x + src.width > pic->width || src.y + src.height > pic->height) continue;
      const double zoom = child_num(im, "zoom", 1);
      int dw, dh;
      if (!pixel_int(src.width * zoom, dw) || !pixel_int(src.height * zoom, dh)) continue;
      if (dw <= 0 || dh <= 0) continue;
      if (col == Torque::Gui::Color{255, 255, 255, 255}) {
        if (dw == src.width && dh == src.height) canvas_.blit(*pic, src, px, py);
        else canvas_.stretch_blit(*pic, src, {px, py, dw, dh});
        continue;
      }
      // Tinted or see-through: each pixel times the colours.
      for (int y = std::max(0, -py); y < std::min(dh, canvas_.height() - py); ++y)
        for (int x = std::max(0, -px); x < std::min(dw, canvas_.width() - px); ++x) {
          const int sx = src.x + static_cast<int>(static_cast<long long>(x) * src.width / dw);
          const int sy = src.y + static_cast<int>(static_cast<long long>(y) * src.height / dh);
          if (sx < 0 || sy < 0 || sx >= pic->width || sy >= pic->height) continue;
          Torque::Gui::Color c = pic->at(sx, sy);
          c.r = static_cast<std::uint8_t>(c.r * col.r / 255);
          c.g = static_cast<std::uint8_t>(c.g * col.g / 255);
          c.b = static_cast<std::uint8_t>(c.b * col.b / 255);
          c.a = static_cast<std::uint8_t>(c.a * col.a / 255);
          if (c.a) canvas_.blend_pixel(px + x, py + y, c);
        }
    } else if (type == "text") {
      const std::string style = low(child_str(im, "style"));
      Draw::ui_draw_text(canvas_, px, py, child_str(im, "text"), col, style.find('b') != std::string::npos);
    } else if (type == "poly") {
      gs2::VarPtr pts = im->child("polygon");
      if (!pts || pts->elements().size() < 6 || pts->elements().size() > 2048) continue;
      std::vector<std::pair<double, double>> p;
      for (size_t i = 0; i + 1 < pts->elements().size(); i += 2) {
        auto q = to_px(pts->elements()[i]->number(), pts->elements()[i + 1]->number());
        int x, y;
        if (!pixel_int(q.first, x) || !pixel_int(q.second, y)) { p.clear(); break; }
        p.emplace_back(x, y);
      }
      if (p.empty()) continue;
      // Even-odd scanline fill.
      double top = p[0].second, bottom = p[0].second;
      for (const auto& q : p) top = std::min(top, q.second), bottom = std::max(bottom, q.second);
      for (int y = std::max(0, static_cast<int>(std::floor(top)));
           y <= std::min(canvas_.height() - 1, static_cast<int>(std::ceil(bottom))); ++y) {
        std::vector<double> xs;
        const double sy = y + 0.5;
        for (size_t i = 0; i < p.size(); ++i) {
          const auto& a = p[i];
          const auto& b = p[(i + 1) % p.size()];
          if ((a.second <= sy) != (b.second <= sy)) xs.push_back(a.first + (sy - a.second) * (b.first - a.first) / (b.second - a.second));
        }
        std::sort(xs.begin(), xs.end());
        for (size_t i = 0; i + 1 < xs.size(); i += 2)
          for (int x = std::max(0, static_cast<int>(std::ceil(xs[i] - 0.5)));
               x < std::min(canvas_.width(), static_cast<int>(std::ceil(xs[i + 1] - 0.5))); ++x)
            canvas_.blend_pixel(x, y, col);
      }
    } else if (type == "ani") {
      Draw::Actor a;
      a.gani = child_str(im, "ani");
      int dir;
      if (!pixel_int(child_num(im, "dir", 2), dir)) continue;
      a.dir = dir & 3;
      // The clock belongs to this image object, never an actor/index slot.
      auto name = im->childOrCreate("_repro_ani");
      auto start = im->childOrCreate("_repro_start");
      int started;
      const double stamp = start->number();
      if (name->string() != a.gani || !std::isfinite(stamp) || stamp < 0 || stamp > frame_) {
        name->setString(a.gani);
        start->setNumber(frame_);
        started = frame_;
      } else started = static_cast<int>(stamp);
      a.ani_tick = frame_ - started;
      renderer_.draw_actor(canvas_, a, px, py, {200, 200, 60, 255});
    }
  }
}

void Program::draw_sign() {
  if (sign_text_.empty()) return;
  // The say2 box: a dark panel on the lower part of the view, the text's
  // lines split at "#b" and line ends (rebuild layout; no 6.x sign was
  // measured).
  std::vector<std::string> lines;
  std::string cur;
  for (size_t i = 0; i < sign_text_.size(); ++i) {
    if (sign_text_.compare(i, 2, "#b") == 0) {
      lines.push_back(cur);
      cur.clear();
      ++i;
    } else if (sign_text_[i] == '\n') {
      lines.push_back(cur);
      cur.clear();
    } else {
      cur += sign_text_[i];
    }
  }
  lines.push_back(cur);
  const int w = std::min(canvas_.width() - 20, 400), h = 16 * static_cast<int>(lines.size()) + 16;
  const int x = (canvas_.width() - w) / 2, y = canvas_.height() - h - 40;
  canvas_.fill_rect({x, y, w, h}, {0, 0, 64, 200});
  canvas_.frame_rect({x, y, w, h}, {255, 255, 255, 255});
  for (size_t i = 0; i < lines.size(); ++i)
    Draw::ui_draw_text(canvas_, x + 8, y + 8 + 16 * static_cast<int>(i), lines[i], {255, 255, 255, 255}, false);
  passes_.push_back("Sign");
}

}  // namespace Quattro::Shell
