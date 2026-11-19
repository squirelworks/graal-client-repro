// Server NPCs in the Quattro program, on the 3.153-5.12 path
// (world/npcs.hpp has the packets and their sources).
//
// Each NPC with a script (131) has a script object on the program's GS2
// machine. Its props are its children, as the scripts read them:
// `this.x`, `this.y` (tiles), `this.image`, `this.ani`, `this.dir`,
// `this.nick`, `this.chat` (the NPC's message) and `this.visible`. The
// server's props are written there when they come; after each script pass
// the children are read back onto the NPC, which is drawn from them.
//
// Events: `created` when the script is set, then `playerenters`;
// `playerenters` again for each new level; `playertouchsme` when the
// player's body box starts to overlap the NPC (its image or image part,
// or a character's 2 x 2 tile body). The boxes are the rebuild's reading.
//
// The NPC commands: setimg(image), setimgpart(image, x, y, w, h), show(),
// hide(), message(text), setcharani(gani, params), showcharacter(). They
// act on the NPC whose script calls them (GS1 names, kept in GS2 by the
// 4.x compiler; npc-library/gs1-reference-205.md).
#include "program.hpp"

#include "../net/gtypes.hpp"

#include <cmath>

namespace Quattro::Shell {

int Program::npc_of(const gs2::Var* v) const {
  for (const auto& [id, var] : npc_vars_)
    if (var.get() == v) return id;
  return 0;
}

void Program::drop_npc(int id) {
  auto it = npc_vars_.find(id);
  if (it != npc_vars_.end()) {
    if (scripts_.machine().hasScript(it->second))
      scripts_.machine().setScript(it->second, std::shared_ptr<const gs2::Script>());
    npc_vars_.erase(it);
  }
  npcs_.erase(id);
  npc_touching_.erase(id);
}

void Program::clear_level_npcs() {
  std::vector<int> ids;
  for (const auto& [id, n] : npcs_)
    if (id < 1000) ids.push_back(id);
  for (int id : ids) drop_npc(id);
  // The server-wide NPCs that stay see the new level.
  for (const auto& [id, v] : npc_vars_)
    if (scripts_.machine().hasScript(v)) scripts_.machine().queueEvent(v, "PlayerEnters");
}

void Program::npc_to_script(int id) {
  auto vit = npc_vars_.find(id);
  auto nit = npcs_.find(id);
  if (vit == npc_vars_.end() || nit == npcs_.end()) return;
  const World::ServerNpc& n = nit->second;
  gs2::Var& v = *vit->second;
  v.childOrCreate("id")->setNumber(id);
  v.childOrCreate("x")->setNumber(n.x);
  v.childOrCreate("y")->setNumber(n.y);
  v.childOrCreate("image")->setString(n.image);
  v.childOrCreate("ani")->setString(n.gani);
  v.childOrCreate("dir")->setNumber(n.dir);
  v.childOrCreate("nick")->setString(n.nickname);
  v.childOrCreate("chat")->setString(n.message);
  v.childOrCreate("visible")->setNumber(n.visible() ? 1 : 0);
}

void Program::npcs_from_scripts() {
  for (const auto& [id, var] : npc_vars_) {
    auto nit = npcs_.find(id);
    if (nit == npcs_.end()) continue;
    World::ServerNpc& n = nit->second;
    auto num = [&](const char* k, double d) {
      gs2::VarPtr c = var->child(k);
      return c ? c->number() : d;
    };
    auto str = [&](const char* k, const std::string& d) {
      gs2::VarPtr c = var->child(k);
      return c ? c->string() : d;
    };
    n.x = num("x", n.x);
    n.y = num("y", n.y);
    n.image = str("image", n.image);
    n.gani = str("ani", n.gani);
    n.dir = static_cast<int>(num("dir", n.dir)) & 3;
    n.nickname = str("nick", n.nickname);
    n.message = str("chat", n.message);
    n.visflags = num("visible", n.visible() ? 1 : 0) != 0 ? (n.visflags | 1) : (n.visflags & ~1);
  }
}

namespace {

struct Box {
  double l, t, r, b;
};

bool overlap(const Box& a, const Box& b) { return a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b; }

}  // namespace

void Program::npc_touches() {
  const Box body{me_.x + 0.5, me_.y + 1, me_.x + 2.5, me_.y + 3};
  std::set<int> now;
  for (const auto& [id, n] : npcs_) {
    if (!n.visible()) continue;
    Box box{n.x + 0.5, n.y + 1, n.x + 2.5, n.y + 3};
    if (!n.character()) {
      double w = 0, h = 0;
      if (n.has_part) {
        w = n.part_w / 16.0;
        h = n.part_h / 16.0;
      } else if (assets_ && !n.image.empty()) {
        if (const auto* img = assets_->image(n.image)) {
          w = img->width / 16.0;
          h = img->height / 16.0;
        }
      }
      if (w <= 0 || h <= 0) continue;
      box = {n.x, n.y, n.x + w, n.y + h};
    }
    if (!overlap(body, box)) continue;
    now.insert(id);
    if (npc_touching_.count(id)) continue;
    auto vit = npc_vars_.find(id);
    if (vit != npc_vars_.end() && scripts_.machine().hasScript(vit->second))
      scripts_.machine().queueEvent(vit->second, "PlayerTouchsMe");
  }
  npc_touching_ = std::move(now);
}

void Program::npcs_to_world() {
  world_.npcs.clear();
  for (const auto& [id, n] : npcs_) {
    if (!n.visible()) continue;
    Draw::NpcSprite s;
    s.x = n.x;
    s.y = n.y;
    s.image = n.image;
    s.has_part = n.has_part;
    s.part = {n.part_x, n.part_y, n.part_w, n.part_h};
    s.character = n.character();
    if (s.character) {
      s.actor.x = n.x;
      s.actor.y = n.y;
      s.actor.gani = n.gani;
      s.actor.dir = n.dir;
      s.actor.chat = n.message;
      s.actor.head = n.head;
      s.actor.body = n.body;
      s.actor.sword = n.sword;
      s.actor.shield = n.shield;
      s.actor.attr = n.attr;
      s.actor.colors = n.colors;
      s.actor.ani_tick = static_cast<int>(frame_);
    }
    world_.npcs.push_back(std::move(s));
  }
}

bool Program::on_npc_message(int id, std::string_view body) {
  switch (id) {
    case 3: {  // PLO_NPCPROPS: GINT3 id, then the prop stream
      Net::Reader r(body);
      int nid = static_cast<int>(r.gint3());
      if (!r.ok() || nid <= 0) return true;
      const bool fresh = npcs_.find(nid) == npcs_.end();
      World::ServerNpc& n = npcs_[nid];
      n.id = nid;
      World::apply_npc_props(n, body.substr(3));
      npc_to_script(nid);
      if (fresh) {
        auto vit = npc_vars_.find(nid);
        if (vit != npc_vars_.end() && scripts_.machine().hasScript(vit->second))
          scripts_.machine().queueEvent(vit->second, "PlayerEnters");
      }
      return true;
    }
    case 131: {  // PLO_NPCBYTECODE: GINT3 id, then the bytecode
      Net::Reader r(body);
      int nid = static_cast<int>(r.gint3());
      if (!r.ok() || nid <= 0) return true;
      World::ServerNpc& n = npcs_[nid];
      n.id = nid;
      gs2::VarPtr& v = npc_vars_[nid];
      if (!v) {
        v = scripts_.machine().newVar("npc" + std::to_string(nid));
        v->setAcceptsAllProperties(true);
      }
      npc_to_script(nid);
      std::string err;
      if (!scripts_.machine().setScript(v, std::string(body.substr(3)), &err)) {
        if (log) log("npc " + std::to_string(nid) + ": " + err);
        return true;
      }
      scripts_.machine().queueEvent(v, "PlayerEnters");
      if (log) log("npc " + std::to_string(nid) + " script loaded");
      return true;
    }
    case 29: {  // PLO_NPCDEL: GINT3 id
      Net::Reader r(body);
      int nid = static_cast<int>(r.gint3());
      if (r.ok()) drop_npc(nid);
      return true;
    }
    case 150: {  // PLO_NPCDEL2: level name, GINT3 id
      Net::Reader r(body);
      r.gstring();
      int nid = static_cast<int>(r.gint3());
      if (r.ok()) drop_npc(nid);
      return true;
    }
    case 151:  // PLO_HIDENPCS: the active level's NPCs 1 to 999
      clear_level_npcs();
      return true;
    default:
      return false;
  }
}

void Program::register_npc_commands() {
  gs2::Machine& m = scripts_.machine();
  auto self_var = [this](gs2::Var& self) -> gs2::VarPtr {
    int id = npc_of(&self);
    return id ? npc_vars_[id] : nullptr;
  };
  m.addCommand("setimg", "s", [self_var](gs2::Machine& mm, gs2::Var& self, std::vector<gs2::Value>& a) {
    if (auto v = self_var(self)) v->childOrCreate("image")->setString(mm.toString(a[0]));
    return gs2::Value::number(0);
  });
  m.addCommand("setimgpart", "snnnn", [this, self_var](gs2::Machine& mm, gs2::Var& self, std::vector<gs2::Value>& a) {
    int id = npc_of(&self);
    auto v = self_var(self);
    if (!v) return gs2::Value::number(0);
    v->childOrCreate("image")->setString(mm.toString(a[0]));
    World::ServerNpc& n = npcs_[id];
    n.has_part = true;
    n.part_x = static_cast<int>(mm.toNumber(a[1]));
    n.part_y = static_cast<int>(mm.toNumber(a[2]));
    n.part_w = static_cast<int>(mm.toNumber(a[3]));
    n.part_h = static_cast<int>(mm.toNumber(a[4]));
    return gs2::Value::number(0);
  });
  m.addCommand("show", "", [self_var](gs2::Machine&, gs2::Var& self, std::vector<gs2::Value>&) {
    if (auto v = self_var(self)) v->childOrCreate("visible")->setNumber(1);
    return gs2::Value::number(0);
  });
  m.addCommand("hide", "", [self_var](gs2::Machine&, gs2::Var& self, std::vector<gs2::Value>&) {
    if (auto v = self_var(self)) v->childOrCreate("visible")->setNumber(0);
    return gs2::Value::number(0);
  });
  m.addCommand("message", "s", [self_var](gs2::Machine& mm, gs2::Var& self, std::vector<gs2::Value>& a) {
    if (auto v = self_var(self)) v->childOrCreate("chat")->setString(mm.toString(a[0]));
    return gs2::Value::number(0);
  });
  m.addCommand("setcharani", "s", [self_var](gs2::Machine& mm, gs2::Var& self, std::vector<gs2::Value>& a) {
    if (auto v = self_var(self)) v->childOrCreate("ani")->setString(mm.toString(a[0]));
    return gs2::Value::number(0);
  });
  m.addCommand("showcharacter", "", [self_var](gs2::Machine&, gs2::Var& self, std::vector<gs2::Value>&) {
    if (auto v = self_var(self)) {
      auto ani = v->childOrCreate("ani");
      if (ani->string().empty()) ani->setString("idle");
    }
    return gs2::Value::number(0);
  });
}

}  // namespace Quattro::Shell
