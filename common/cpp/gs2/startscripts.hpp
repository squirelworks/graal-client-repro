#pragma once

// The shell scripts the 4.x and 5.x engines carry compiled inside their own
// program file and attach at start-up as named variables (StartScript_*).
// They are read from the player's own copy at run time; none is kept here.

#include <memory>
#include <string>
#include <vector>

#include "gs2.hpp"

namespace gs2 {

struct StartScript {
  std::string name;  // StartScript_..., or empty when not recognised
  std::shared_ptr<const Script> script;
};

// Every zlib stream in `image` that inflates to a four-segment script, in
// file order.
std::vector<std::string> findEmbeddedScripts(const std::string& image);

// Which start script this is, from the functions it defines; empty if none.
std::string identifyStartScript(const Script& s);

// Find, load and name the start scripts of a program image.
std::vector<StartScript> loadStartScripts(const std::string& image, Profile profile);

// Give each recognised script to a universe variable of its name, in file
// order, which queues `created` on each.
void attachStartScripts(Machine& m, const std::vector<StartScript>& scripts);

}  // namespace gs2
