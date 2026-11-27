// The 5.12 GS2 3D objects on the 6.x GS2 machine: `GameObject` and
// `Camera`, made by `new GameObject(name)` or handed to scripts by the host
// (`player.camera`, the 3D view's camera).
//
// Written from Graal_analysis torque/gs2-3d-typed-surface-512-2026-11-26.md
// (the typed member table) and the real 5.12's answers to conformance
// C026 and C030 (torque/conformance/results.tsv): the defaults, the value
// formats and the rotation rules below are what the 5.12 reported.
//
// - position, scale, velocity: "x y z". x, y and z are the position's parts.
// - transform: "x y z ax ay az deg", rotation: "ax ay az deg", the angle in
//   degrees and never negative (the axis turns over instead). A positive
//   angle about +z turns clockwise seen from above, as the wire's does
//   (graal3dengine render/math.hpp graalRotation): setTransform("1 2 3 0 0 1
//   1.5708") gave forward (0.0274, 0.9996, 0) on the 5.12.
// - eulerrotation: "x y z" in radians, Torque's order (z, then x, then y),
//   counter-clockwise about +z for a positive z: eulerrotation "0 0 90" gave
//   transform "... 0 0 -1 116.62" on the 5.12 (90 rad is 116.62 degrees on
//   the other side of the turn).
// - Numbers print with up to nine decimals, trailing zeros cut (the 5.12's
//   "0.999624192", "116.62015253").
// - velocity takes no value from a script (the 5.12 read back 0 0 0 after
//   `velocity = "1 0 0"`, and the object stayed put); an object a script
//   makes is never drawn (T3D-016), so isDrawn is 0, its boxes are empty at
//   its position and getdropz is 0.
//
// A member a script assigns directly (`obj.x = 7`, `obj.eulerrotation =
// ...`) is taken in the next time any member of the object is read, so the
// others follow it (`obj.x = 7; obj.getPosition()` gives "7 -2 3.25").
#pragma once

#include "../../../common/cpp/gs2/gs2.hpp"

#include <array>
#include <map>
#include <string>

namespace Frank {

struct Pose3 {
  std::array<double, 3> p{0, 0, 0};
  // Column-vector rotation: column 0 right, 1 forward, 2 up.
  std::array<std::array<double, 3>, 3> r{{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}};
};

// The 5.12's number text: up to nine decimals, trailing zeros cut, no "-0".
std::string g3d_number(double d);
std::string g3d_vector(const std::array<double, 3>& v);

// Rotation helpers in the 5.12's conventions (above).
void g3d_set_axis_angle(Pose3& p, std::array<double, 3> axis, double degrees);
void g3d_axis_angle(const Pose3& p, std::array<double, 3>& axis, double& degrees);
void g3d_set_euler(Pose3& p, const std::array<double, 3>& e);
std::array<double, 3> g3d_euler(const Pose3& p);
// From the wire: an axis and an angle in radians (a positive angle turns
// clockwise, as on the script side).
void g3d_set_wire_rotation(Pose3& p, std::array<double, 3> axis, double radians);

class GameObject3D : public gs2::Var {
 public:
  GameObject3D(std::string name, std::string type);

  bool acceptsProperty(const std::string&) const override { return true; }
  void beforeMemberAccess(const std::string& key) override;

  // Takes in what a script assigned since publish(), then writes every
  // member again.
  void fold();
  void publish();

  Pose3 pose;
  std::array<double, 3> scale{1, 1, 1};
  std::string shape, nickname;
  double alpha = 1, solid = 0, collision = 1;
  // A mirror of a server object (the camera): script writes to its pose
  // are dropped at the next publish.
  bool mirror = false;

 private:
  std::map<std::string, std::string> written_;  // member -> text as published
  bool changed(const std::string& key, std::string& now) const;
};

// Registers the GameObject and Camera classes in front of the machine's
// own factory, and their typed members (`GameObject.setPosition`, ...).
void install_gs2_3d(gs2::Machine& m);

}  // namespace Frank
