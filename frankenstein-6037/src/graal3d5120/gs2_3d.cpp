#include "gs2_3d.hpp"

#include <cmath>
#include <cstdio>
#include <sstream>
#include <vector>

namespace Frank {

namespace {

constexpr double kPi = 3.14159265358979323846;
using V = std::array<double, 3>;

V column(const Pose3& p, int c) { return {p.r[0][c], p.r[1][c], p.r[2][c]}; }

V normalized(V v) {
  const double l = std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (!(l > 1e-12) || !std::isfinite(l)) return {0, 0, 0};
  return {v[0] / l, v[1] / l, v[2] / l};
}

// The standard right-handed rotation of `rad` about the unit `a`.
void rotation(Pose3& p, const V& a, double rad) {
  const double c = std::cos(rad), s = std::sin(rad), t = 1 - c;
  const double x = a[0], y = a[1], z = a[2];
  p.r = {{{t * x * x + c, t * x * y - s * z, t * x * z + s * y},
          {t * x * y + s * z, t * y * y + c, t * y * z - s * x},
          {t * x * z - s * y, t * y * z + s * x, t * z * z + c}}};
}

// Up to n numbers from text separated by spaces or commas.
std::vector<double> numbers(const std::string& s, size_t n) {
  std::vector<double> out;
  std::string t = s;
  for (char& c : t)
    if (c == ',') c = ' ';
  std::istringstream in(t);
  double d;
  while (out.size() < n && in >> d) out.push_back(std::isfinite(d) ? d : 0);
  return out;
}

bool vec3(const std::string& s, V& v) {
  auto n = numbers(s, 3);
  if (n.size() < 3) return false;
  v = {n[0], n[1], n[2]};
  return true;
}

GameObject3D* as3d(gs2::Var& v) { return dynamic_cast<GameObject3D*>(&v); }

}  // namespace

std::string g3d_number(double d) {
  if (!std::isfinite(d)) return "0";
  char buf[64];
  std::snprintf(buf, sizeof buf, "%.9f", d);
  std::string s = buf;
  if (s.find('.') != std::string::npos) {
    while (!s.empty() && s.back() == '0') s.pop_back();
    if (!s.empty() && s.back() == '.') s.pop_back();
  }
  if (s == "-0") s = "0";
  return s;
}

std::string g3d_vector(const V& v) { return g3d_number(v[0]) + " " + g3d_number(v[1]) + " " + g3d_number(v[2]); }

void g3d_set_axis_angle(Pose3& p, V axis, double degrees) {
  axis = normalized(axis);
  if (axis == V{0, 0, 0}) axis = {1, 0, 0}, degrees = 0;
  rotation(p, axis, -degrees * kPi / 180.0);
}

void g3d_set_wire_rotation(Pose3& p, V axis, double radians) {
  axis = normalized(axis);
  if (axis == V{0, 0, 0}) axis = {1, 0, 0}, radians = 0;
  rotation(p, axis, -radians);
}

void g3d_axis_angle(const Pose3& p, V& axis, double& degrees) {
  const auto& m = p.r;
  const double tr = m[0][0] + m[1][1] + m[2][2];
  double rad = std::acos(std::fmax(-1.0, std::fmin(1.0, (tr - 1) / 2)));
  V a{m[2][1] - m[1][2], m[0][2] - m[2][0], m[1][0] - m[0][1]};
  if (rad < 1e-9) {
    axis = {1, 0, 0};
    degrees = 0;
    return;
  }
  if (kPi - rad < 1e-6) {
    // A half turn: the axis from the diagonal.
    a = {std::sqrt(std::fmax(0.0, (m[0][0] + 1) / 2)), std::sqrt(std::fmax(0.0, (m[1][1] + 1) / 2)),
         std::sqrt(std::fmax(0.0, (m[2][2] + 1) / 2))};
    if (m[0][1] < 0) a[1] = -a[1];
    if (m[0][2] < 0) a[2] = -a[2];
  }
  a = normalized(a);
  // The script side's angle is the other way round; the 5.12 shows it
  // positive with the axis turned over.
  axis = {-a[0], -a[1], -a[2]};
  degrees = rad * 180.0 / kPi;
  for (double& c : axis)
    if (std::fabs(c) < 1e-12) c = 0;
}

void g3d_set_euler(Pose3& p, const V& e) {
  // Torque's EulerF: z, then x, then y (MatrixF::set).
  const double cx = std::cos(e[0]), sx = std::sin(e[0]), cy = std::cos(e[1]), sy = std::sin(e[1]),
               cz = std::cos(e[2]), sz = std::sin(e[2]);
  p.r = {{{cz * cy - sz * sx * sy, -sz * cx, cz * sy + sz * sx * cy},
          {sz * cy + cz * sx * sy, cz * cx, sz * sy - cz * sx * cy},
          {-cx * sy, sx, cx * cy}}};
}

V g3d_euler(const Pose3& p) {
  const auto& m = p.r;
  V e{std::asin(std::fmax(-1.0, std::fmin(1.0, m[2][1]))), 0, 0};
  if (std::cos(e[0]) > 1e-9) {
    e[1] = std::atan2(-m[2][0], m[2][2]);
    e[2] = std::atan2(-m[0][1], m[1][1]);
  } else {
    e[2] = std::atan2(m[1][0], m[0][0]);
  }
  return e;
}

// ------------------------------------------------------------ the object

GameObject3D::GameObject3D(std::string name, std::string type) : gs2::Var(std::move(name), std::move(type)) {}

bool GameObject3D::changed(const std::string& key, std::string& now) const {
  const auto c = child(key);
  const auto w = written_.find(key);
  if (!c || w == written_.end()) return false;
  now = c->string();
  return now != w->second;
}

void GameObject3D::fold() {
  if (written_.empty()) return;
  std::string s;
  if (!mirror) {
    // In the order a later one wins: the whole transform, then its parts.
    if (changed("transform", s)) {
      auto n = numbers(s, 7);
      if (n.size() >= 3) pose.p = {n[0], n[1], n[2]};
      if (n.size() >= 7) g3d_set_axis_angle(pose, {n[3], n[4], n[5]}, n[6]);
    }
    if (changed("rotation", s)) {
      auto n = numbers(s, 4);
      if (n.size() >= 4) g3d_set_axis_angle(pose, {n[0], n[1], n[2]}, n[3]);
    }
    if (changed("eulerrotation", s)) {
      V e;
      if (vec3(s, e)) g3d_set_euler(pose, e);
    }
    if (changed("position", s)) vec3(s, pose.p);
    const char* parts[3] = {"x", "y", "z"};
    for (int i = 0; i < 3; ++i)
      if (changed(parts[i], s)) pose.p[i] = child(parts[i])->number();
    if (changed("scale", s)) vec3(s, scale);
  }
  if (changed("shape", s)) shape = s;
  if (changed("nickname", s)) nickname = s;
  if (changed("alpha", s)) alpha = child("alpha")->number();
  if (changed("solid", s)) solid = child("solid")->number() != 0;
  if (changed("collision", s)) collision = child("collision")->number() != 0;
}

void GameObject3D::publish() {
  auto put_s = [this](const std::string& k, const std::string& v) {
    childOrCreate(k)->setString(v);
    written_[k] = childOrCreate(k)->string();
  };
  auto put_n = [this](const std::string& k, double v) {
    childOrCreate(k)->setNumber(v);
    written_[k] = childOrCreate(k)->string();
  };
  V axis;
  double deg;
  g3d_axis_angle(pose, axis, deg);
  const std::string rot = g3d_vector(axis) + " " + g3d_number(deg);
  put_s("position", g3d_vector(pose.p));
  put_n("x", pose.p[0]);
  put_n("y", pose.p[1]);
  put_n("z", pose.p[2]);
  put_s("rotation", rot);
  put_s("transform", g3d_vector(pose.p) + " " + rot);
  put_s("eulerrotation", g3d_vector(g3d_euler(pose)));
  put_s("scale", g3d_vector(scale));
  put_s("velocity", "0 0 0");
  put_s("forwardvector", g3d_vector(column(pose, 1)));
  put_s("rightvector", g3d_vector(column(pose, 0)));
  put_s("upvector", g3d_vector(column(pose, 2)));
  put_s("objectbox", "0 0 0 0 0 0");
  put_s("worldbox", g3d_vector(pose.p) + " " + g3d_vector(pose.p));
  put_s("worldboxcenter", g3d_vector(pose.p));
  put_s("shape", shape);
  put_s("nickname", nickname);
  put_n("alpha", alpha);
  put_n("solid", solid);
  put_n("collision", collision);
}

void GameObject3D::beforeMemberAccess(const std::string&) {
  fold();
  publish();
}

// ------------------------------------------------------------ the classes

void install_gs2_3d(gs2::Machine& m) {
  using gs2::Value;
  using Args = std::vector<Value>;
  auto before = m.objectFactory();
  m.setObjectFactory([before](gs2::Machine& mm, const std::string& type, const std::string& name) -> gs2::VarPtr {
    std::string t;
    for (char c : type) t += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (t == "gameobject" || t == "camera") {
      auto o = std::make_shared<GameObject3D>(name, t == "camera" ? "Camera" : "GameObject");
      o->publish();
      return o;
    }
    return before ? before(mm, type, name) : nullptr;
  });

  // Each member on both classes: GameObject.<name> and Camera.<name>.
  auto add = [&m](const std::string& name, const std::string& sig,
                  std::function<Value(gs2::Machine&, GameObject3D&, Args&)> fn) {
    for (const char* cls : {"GameObject.", "Camera."}) {
      m.addCommand(cls + name, sig, [fn](gs2::Machine& mm, gs2::Var& self, Args& a) {
        GameObject3D* o = as3d(self);
        if (!o) return Value::number(0);
        o->fold();
        Value r = fn(mm, *o, a);
        o->publish();
        return r;
      });
    }
  };
  auto str = [](const std::string& s) { return Value::string(s); };
  auto zero = Value::number(0);

  add("getPosition", "", [str](gs2::Machine&, GameObject3D& o, Args&) { return str(g3d_vector(o.pose.p)); });
  add("setPosition", "s", [zero](gs2::Machine& mm, GameObject3D& o, Args& a) {
    if (!o.mirror) vec3(mm.toString(a[0]), o.pose.p);
    return zero;
  });
  add("getScale", "", [str](gs2::Machine&, GameObject3D& o, Args&) { return str(g3d_vector(o.scale)); });
  add("setScale", "s", [zero](gs2::Machine& mm, GameObject3D& o, Args& a) {
    if (!o.mirror) vec3(mm.toString(a[0]), o.scale);
    return zero;
  });
  add("getTransform", "", [](gs2::Machine&, GameObject3D& o, Args&) {
    o.publish();
    return Value::string(o.child("transform")->string());
  });
  add("setTransform", "s", [zero](gs2::Machine& mm, GameObject3D& o, Args& a) {
    if (o.mirror) return zero;
    auto n = numbers(mm.toString(a[0]), 7);
    if (n.size() >= 3) o.pose.p = {n[0], n[1], n[2]};
    if (n.size() >= 7) g3d_set_axis_angle(o.pose, {n[3], n[4], n[5]}, n[6]);
    return zero;
  });
  add("getForwardVector", "", [str](gs2::Machine&, GameObject3D& o, Args&) { return str(g3d_vector(column(o.pose, 1))); });
  add("getRightVector", "", [str](gs2::Machine&, GameObject3D& o, Args&) { return str(g3d_vector(column(o.pose, 0))); });
  add("getUpVector", "", [str](gs2::Machine&, GameObject3D& o, Args&) { return str(g3d_vector(column(o.pose, 2))); });
  // A direction: the object turns so its forward vector points that way
  // (setDirection("1 0 0") gave eulerrotation "0 0 -1.5708" on the 5.12).
  auto face = [zero](gs2::Machine& mm, GameObject3D& o, Args& a) {
    V d;
    if (o.mirror || !vec3(mm.toString(a[0]), d)) return zero;
    d = normalized(d);
    if (d == V{0, 0, 0}) return zero;
    g3d_set_euler(o.pose, {std::asin(std::fmax(-1.0, std::fmin(1.0, d[2]))), 0, std::atan2(-d[0], d[1])});
    return zero;
  };
  add("setDirection", "s", face);
  add("setForwardVector", "s", face);
  add("getObjectBox", "", [str](gs2::Machine&, GameObject3D&, Args&) { return str("0 0 0 0 0 0"); });
  add("getWorldBox", "", [str](gs2::Machine&, GameObject3D& o, Args&) {
    return str(g3d_vector(o.pose.p) + " " + g3d_vector(o.pose.p));
  });
  add("getWorldBoxCenter", "", [str](gs2::Machine&, GameObject3D& o, Args&) { return str(g3d_vector(o.pose.p)); });
  add("isDrawn", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("isMounted", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("isInInterior", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("getMountedObjectCount", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("getMountedObject", "n", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("getObjectMount", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("unmount", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  // No terrain or interior under a script-made object: 0 (T3D-125).
  add("getdropz", "s", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("light", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
  add("updatePosition", "", [zero](gs2::Machine&, GameObject3D&, Args&) { return zero; });
}

}  // namespace Frank
