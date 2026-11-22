// Private adapter state: physical keys keep their press identity through
// modifier changes, auto-repeat and focus loss. Typed characters stay current.
#pragma once
#include "window.hpp"
#include <map>
#include <optional>
#include <vector>

namespace Quattro::Draw::detail {
class InputKeys {
 public:
  InputEvent press(unsigned physical, InputEvent event) {
    auto [it, inserted] = down_.emplace(physical, event);
    if (!inserted) event.key = it->second.key;
    return event;
  }
  std::optional<InputEvent> release(unsigned physical) {
    auto it = down_.find(physical);
    if (it == down_.end()) return std::nullopt;
    InputEvent event = it->second;
    event.type = InputEvent::KeyUp;
    down_.erase(it);
    return event;
  }
  std::vector<InputEvent> release_all() {
    std::vector<InputEvent> events;
    for (const auto& entry : down_) {
      InputEvent event = entry.second;
      event.type = InputEvent::KeyUp;
      events.push_back(event);
    }
    down_.clear();
    return events;
  }
 private:
  std::map<unsigned, InputEvent> down_;
};
}  // namespace Quattro::Draw::detail
