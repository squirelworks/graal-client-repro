#pragma once

// The particle emitter a GuiShowImgCtrl carries as `emitter` (plan step
// B5), from Graal_analysis client-internals/showimg-particles-and-gs2-format.md.
// The script sets its properties (`delaymin`, `nrofparticles`,
// `emissionoffset`, ...) and the particle template's (`emitter.particle.
// lifetime`, `image`, `angle`, ...) as child variables, and adds modifiers
// with addlocalmodifier, addglobalmodifier and addemitmodifier. advance()
// runs the emitter; the GUI draws its particles through the painter.
// Defaults the note does not give are readings, listed in README.md.

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "gs2.hpp"

namespace gs2::gui {

// The fields a modifier can change, in the engines' order.
enum Field {
  FX, FY, FZ, FMoveX, FMoveY, FMoveZ, FAngle, FZAngle, FSpeed, FRotation, FSpin, FStretchX, FStretchY,
  FRed, FGreen, FBlue, FAlpha, FZoom, FieldCount
};
int fieldIndex(const std::string& name);  // -1 when not a modifier field

struct Modifier {
  enum Type { Once, Impulse, Range } type = Once;
  enum Op { Replace, Add, Multiply } op = Replace;
  double t1 = 0, t2 = 0, min = 0, max = 0;
  int field = 0;
};

struct Particle {
  std::array<double, FieldCount> f{};
  double age = 0, lifetime = 1;
  std::string image;
  int mode = 1;
  std::vector<double> due;  // per local modifier: the next fire time, < 0 when spent
};

class Emitter : public Var {
 public:
  explicit Emitter(Machine& m);

  // The template: `emitter.particle`.
  VarPtr particleTemplate() const { return template_; }

  // add*modifier; false for an unknown type, operation or field, or past
  // 1000 in that list.
  enum class List { Local, Global, Emit };
  bool addModifier(List which, const std::string& type, double t1, double t2, const std::string& field,
                   const std::string& op, double min, double max);
  void removeModifiers();

  // Where the emitter is, in screen pixels (the show-image's position).
  void setPosition(double x, double y) { x_ = x; y_ = y; }

  // Runs `dt` seconds: bursts, movement, modifiers, deaths.
  void advance(double dt);

  // Live particles in draw order (oldest first unless `firstinfront`).
  std::vector<const Particle*> drawOrder() const;
  const std::vector<Particle>& particles() const { return parts_; }

 private:
  double prop(const char* key, double def) const;
  void emit(int count);
  void fire(Particle& p, const Modifier& m, double dt);
  void apply(std::array<double, FieldCount>& f, const Modifier& m, double value, double scale);

  Machine& m_;
  VarPtr template_;
  std::vector<Modifier> local_, global_, emit_;
  std::vector<double> globalDue_, emitDue_;
  std::vector<Particle> parts_;  // newest first
  double x_ = 0, y_ = 0;
  double clock_ = 0;
  double nextBurst_ = -1;  // < 0 until the first tick starts the timer
  std::size_t emitted_ = 0;
};

}  // namespace gs2::gui
