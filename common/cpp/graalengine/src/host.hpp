// The engine's side of the callback table.
//
// Every slot in graalengine_slots.def gets a function here with the slot's
// name in lower camel case's original spelling, e.g. host::DrawText(...).
// Each one calls the launcher's function when the launcher filled the slot
// and otherwise does nothing and returns the slot's default
// (torque/4208-launcher.md: "the matching draw helper calls it only when
// the pointer is set"). Engine code, and later the GS2 controls, draw only
// through these.
#pragma once

#include "graalengine.h"

namespace graalengine::host {

struct Table {
#define GE_SLOT(Name, Ret, Default, Params, Args, Builds) graal_##Name##_fn Name = nullptr;
#include "graalengine_slots.def"
#undef GE_SLOT
};

// The live table. Setters write it; the helpers below read it.
Table& table();

// Empties every slot (used by tests and by shutdown).
void clear();

#define GE_SLOT(Name, Ret, Default, Params, Args, Builds) \
  inline Ret Name Params {                                 \
    if (auto fn = table().Name) return fn Args;            \
    return Default;                                        \
  }                                                        \
  inline bool has##Name() { return table().Name != nullptr; }
#include "graalengine_slots.def"
#undef GE_SLOT

}  // namespace graalengine::host
