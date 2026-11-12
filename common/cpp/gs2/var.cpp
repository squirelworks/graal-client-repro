// TGraalVar: a value of its own plus named child variables.

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "gs2.hpp"

namespace gs2 {

namespace {
std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}
}  // namespace

bool Var::acceptsProperty(const std::string& key) const { return acceptsAll_ || child(key) != nullptr; }

double Var::number() const {
  switch (kind_) {
    case Kind::Number: return num_;
    case Kind::String: return std::strtod(str_.c_str(), nullptr);
    default: return 0;
  }
}

std::string Var::string() const {
  switch (kind_) {
    case Kind::Number: return Machine::numberText(num_);
    case Kind::String: return str_;
    case Kind::Object: {
      auto o = link_.lock();
      return o ? o->name() : std::string();
    }
    default: return std::string();
  }
}

void Var::setNumber(double d) { kind_ = Kind::Number; num_ = d; str_.clear(); link_.reset(); elems_.clear(); }
void Var::setString(const std::string& s) { kind_ = Kind::String; str_ = s; num_ = 0; link_.reset(); elems_.clear(); }
void Var::setObject(const VarPtr& o) { kind_ = Kind::Object; link_ = o; num_ = 0; str_.clear(); elems_.clear(); }

void Var::setArray(std::size_t n) {
  kind_ = Kind::Array;
  num_ = 0;
  str_.clear();
  link_.reset();
  elems_.clear();
  for (std::size_t i = 0; i < n; ++i) elems_.push_back(std::make_shared<Var>());
}

void Var::assignFrom(const Var& other) {
  if (&other == this) return;
  kind_ = other.kind_;
  num_ = other.num_;
  str_ = other.str_;
  link_ = other.link_;
  std::vector<VarPtr> copy;
  for (const auto& e : other.elems_) {
    auto v = std::make_shared<Var>();
    v->assignFrom(*e);
    copy.push_back(v);
  }
  elems_ = std::move(copy);
}

VarPtr Var::child(const std::string& key) const {
  auto it = children_.find(lower(key));
  return it == children_.end() ? nullptr : it->second;
}

VarPtr Var::childOrCreate(const std::string& key) {
  const std::string k = lower(key);
  auto it = children_.find(k);
  if (it != children_.end()) return it->second;
  auto v = std::make_shared<Var>(key);
  children_[k] = v;
  return v;
}

}  // namespace gs2
