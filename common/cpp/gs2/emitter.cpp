// The GuiShowImgCtrl particle emitter (plan step B5). Behaviour from
// Graal_analysis client-internals/showimg-particles-and-gs2-format.md.

#include "emitter.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>

namespace gs2::gui {

namespace {

const char* const kFieldNames[FieldCount] = {"x",        "y",     "z",        "movex",    "movey",   "movez",
                                             "angle",    "zangle", "speed",   "rotation", "spin",    "stretchx",
                                             "stretchy", "red",   "green",    "blue",     "alpha",   "zoom"};

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

constexpr std::size_t kMaxModifiers = 1000;

// Default template values (README.md: readings, the note gives none).
double fieldDefault(int i) {
  switch (i) {
    case FStretchX: case FStretchY: case FRed: case FGreen: case FBlue: case FAlpha: case FZoom: return 1;
    default: return 0;
  }
}

// The movement vector from direction and speed. Angle 0 points right and
// pi/2 up the screen (README.md, a reading).
void derive(std::array<double, FieldCount>& f) {
  const double c = std::cos(f[FZAngle]);
  f[FMoveX] = std::cos(f[FAngle]) * c * f[FSpeed];
  f[FMoveY] = -std::sin(f[FAngle]) * c * f[FSpeed];
  f[FMoveZ] = std::sin(f[FZAngle]) * f[FSpeed];
}

bool steers(int field) { return field == FAngle || field == FZAngle || field == FSpeed; }

}  // namespace

int fieldIndex(const std::string& name) {
  const std::string n = lower(name);
  for (int i = 0; i < FieldCount; ++i)
    if (n == kFieldNames[i]) return i;
  return -1;
}

Emitter::Emitter(Machine& m) : Var("emitter", "TParticleEmitter"), m_(m) {
  setAcceptsAllProperties(true);
  template_ = std::make_shared<Var>("particle", "TParticle");
  template_->setAcceptsAllProperties(true);
  childOrCreate("particle")->setObject(template_);
}

double Emitter::prop(const char* key, double def) const {
  auto v = child(key);
  return v ? v->number() : def;
}

bool Emitter::addModifier(List which, const std::string& type, double t1, double t2, const std::string& field,
                          const std::string& op, double min, double max) {
  Modifier md;
  const std::string t = lower(type), o = lower(op);
  if (t == "once") md.type = Modifier::Once;
  else if (t == "impulse") md.type = Modifier::Impulse;
  else if (t == "range") md.type = Modifier::Range;
  else return false;
  if (o == "replace") md.op = Modifier::Replace;
  else if (o == "add") md.op = Modifier::Add;
  else if (o == "multiply") md.op = Modifier::Multiply;
  else return false;
  md.field = fieldIndex(field);
  if (md.field < 0) return false;
  md.t1 = t1;
  md.t2 = t2;
  md.min = min;
  md.max = max;
  auto& list = which == List::Local ? local_ : which == List::Global ? global_ : emit_;
  if (list.size() >= kMaxModifiers) return false;
  list.push_back(md);
  const double due = t1 + (t2 - t1) * m_.random01();
  if (which == List::Global) globalDue_.push_back(clock_ + due);
  if (which == List::Emit) emitDue_.push_back(clock_ + due);
  return true;
}

void Emitter::removeModifiers() {
  local_.clear();
  global_.clear();
  emit_.clear();
  globalDue_.clear();
  emitDue_.clear();
  for (auto& p : parts_) p.due.clear();
}

void Emitter::apply(std::array<double, FieldCount>& f, const Modifier& m, double value, double scale) {
  double& v = f[static_cast<std::size_t>(m.field)];
  switch (m.op) {
    case Modifier::Replace: v = value; break;
    case Modifier::Add: v += (m.field <= FZ ? value * scale : value); break;
    case Modifier::Multiply: v *= value; break;
  }
}

void Emitter::emit(int count) {
  const double scale = prop("movementfactor", 1);
  double ox = 0, oy = 0, oz = 0;
  if (auto off = child("emissionoffset"); off && off->kind() == Kind::Array) {
    auto& e = off->elements();
    if (e.size() > 0 && e[0]) ox = e[0]->number();
    if (e.size() > 1 && e[1]) oy = e[1]->number();
    if (e.size() > 2 && e[2]) oz = e[2]->number();
  }
  for (int n = 0; n < count; ++n) {
    Particle p;
    for (int i = 0; i < FieldCount; ++i) {
      auto v = template_->child(kFieldNames[i]);
      p.f[static_cast<std::size_t>(i)] = v ? v->number() : fieldDefault(i);
    }
    p.f[FX] += x_ + ox * scale;
    p.f[FY] += y_ + oy * scale;
    p.f[FZ] += oz * scale;
    if (!template_->child("movex") && !template_->child("movey") && !template_->child("movez")) derive(p.f);
    auto life = template_->child("lifetime");
    p.lifetime = life ? life->number() : 1;
    if (auto img = template_->child("image")) p.image = img->string();
    if (auto mode = template_->child("mode")) p.mode = static_cast<int>(mode->number());
    for (const auto& md : local_) p.due.push_back(md.t1 + (md.t2 - md.t1) * m_.random01());
    parts_.insert(parts_.begin(), std::move(p));
    ++emitted_;
  }
  childOrCreate("emittedparticles")->setNumber(static_cast<double>(emitted_));
}

void Emitter::advance(double dt) {
  if (dt <= 0 || prop("isfrozen", 0) != 0) return;
  clock_ += dt;
  const double scale = prop("movementfactor", 1);

  // Bursts: the first tick starts the timer; each burst emits up to
  // nrofparticles, capped by maxparticles.
  if (prop("emitautomatically", 1) != 0) {
    const double lo = prop("delaymin", 0.1), hi = std::max(lo, prop("delaymax", lo));
    if (nextBurst_ < 0) {
      nextBurst_ = clock_ + lo + (hi - lo) * m_.random01();
    } else if (clock_ >= nextBurst_) {
      const long room = static_cast<long>(prop("maxparticles", 100)) - static_cast<long>(parts_.size());
      const long n = std::min(static_cast<long>(prop("nrofparticles", 1)), room);
      if (n > 0) emit(static_cast<int>(n));
      nextBurst_ = clock_ + std::max(lo + (hi - lo) * m_.random01(), 1e-3);
    }
  }

  // Global modifiers: one clock, applied to every live particle.
  for (std::size_t i = 0; i < global_.size(); ++i) {
    const Modifier& md = global_[i];
    if (md.type == Modifier::Range) {
      if (clock_ < md.t1 || md.op == Modifier::Multiply) continue;
      const double span = md.t2 > md.t1 ? std::min(1.0, (clock_ - md.t1) / (md.t2 - md.t1)) : 1;
      const double v = md.min + (md.max - md.min) * span;
      for (auto& p : parts_) {
        if (md.op == Modifier::Replace) apply(p.f, md, v, scale);
        else if (clock_ <= md.t2) apply(p.f, md, v * dt, scale);
        if (steers(md.field)) derive(p.f);
      }
      continue;
    }
    if (globalDue_[i] < 0 || clock_ < globalDue_[i]) continue;
    for (auto& p : parts_) {
      apply(p.f, md, md.min + (md.max - md.min) * m_.random01(), scale);
      if (steers(md.field)) derive(p.f);
    }
    globalDue_[i] = md.type == Modifier::Once ? -1 : clock_ + std::max(md.t1 + (md.t2 - md.t1) * m_.random01(), dt);
  }

  // Emit modifiers change the template for particles emitted later.
  for (std::size_t i = 0; i < emit_.size(); ++i) {
    const Modifier& md = emit_[i];
    if (md.type == Modifier::Range || emitDue_[i] < 0 || clock_ < emitDue_[i]) continue;
    std::array<double, FieldCount> f{};
    auto slot = template_->childOrCreate(kFieldNames[md.field]);
    f[static_cast<std::size_t>(md.field)] = template_->child(kFieldNames[md.field]) ? slot->number() : fieldDefault(md.field);
    apply(f, md, md.min + (md.max - md.min) * m_.random01(), 1);
    slot->setNumber(f[static_cast<std::size_t>(md.field)]);
    emitDue_[i] = md.type == Modifier::Once ? -1 : clock_ + std::max(md.t1 + (md.t2 - md.t1) * m_.random01(), dt);
  }

  // Each particle: its own modifiers, movement, spin, age.
  for (auto& p : parts_) {
    p.age += dt;
    for (std::size_t i = 0; i < local_.size() && i < p.due.size(); ++i) {
      const Modifier& md = local_[i];
      if (md.type == Modifier::Range) {
        if (p.age < md.t1 || md.op == Modifier::Multiply) continue;
        const double span = md.t2 > md.t1 ? std::min(1.0, (p.age - md.t1) / (md.t2 - md.t1)) : 1;
        const double v = md.min + (md.max - md.min) * span;
        if (md.op == Modifier::Replace) apply(p.f, md, v, scale);
        else if (p.age <= md.t2) apply(p.f, md, v * dt, scale);
      } else {
        if (p.due[i] < 0 || p.age < p.due[i]) continue;
        apply(p.f, md, md.min + (md.max - md.min) * m_.random01(), scale);
        p.due[i] = md.type == Modifier::Once ? -1 : p.age + std::max(md.t1 + (md.t2 - md.t1) * m_.random01(), dt);
      }
      if (steers(md.field)) derive(p.f);
    }
    p.f[FX] += dt * p.f[FMoveX] * scale;
    p.f[FY] += dt * p.f[FMoveY] * scale;
    p.f[FZ] += dt * p.f[FMoveZ] * scale;
    p.f[FRotation] += p.f[FSpin] * dt;
  }
  parts_.erase(std::remove_if(parts_.begin(), parts_.end(), [](const Particle& p) { return p.age >= p.lifetime; }),
               parts_.end());
  childOrCreate("currentparticlecount")->setNumber(static_cast<double>(parts_.size()));
}

std::vector<const Particle*> Emitter::drawOrder() const {
  std::vector<const Particle*> out;
  for (const auto& p : parts_) out.push_back(&p);
  // The list is newest first; by default the oldest draws first so newer
  // particles are on top, and `firstinfront` reverses that.
  if (prop("firstinfront", 0) == 0) std::reverse(out.begin(), out.end());
  return out;
}

}  // namespace gs2::gui
