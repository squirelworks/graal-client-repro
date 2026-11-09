#include "functions.hpp"

namespace Torque {
namespace {
bool valid_name(const std::string& value, bool empty_allowed) {
  return (empty_allowed || !value.empty()) && value.size() <= 1024 &&
         value.find('\0') == std::string::npos;
}
} // namespace

NativeStatus NativeFunctions::add(const std::string& space, const std::string& name,
                                  std::size_t min, std::size_t max, Callback callback) {
  if (!valid_name(space, true) || !valid_name(name, false)) return NativeStatus::invalid_name;
  if (min == 0 || min > max_arguments ||
      (max != 0 && (max < min || max > max_arguments))) return NativeStatus::invalid_signature;
  if (!callback) return NativeStatus::missing_callback;
  const Key key{space, name};
  if (functions.find(key) != functions.end()) return NativeStatus::duplicate;
  if (functions.size() == max_functions) return NativeStatus::registry_limit;
  functions.emplace(key, Entry{min, max, std::make_shared<Callback>(std::move(callback))});
  return NativeStatus::ok;
}

bool NativeFunctions::remove(const std::string& space, const std::string& name) {
  return functions.erase(Key{space, name}) != 0;
}

NativeResult NativeFunctions::call(const std::string& space, const std::string& name,
                                    const Arguments& script_arguments) const {
  if (!valid_name(space, true) || !valid_name(name, false))
    return {NativeStatus::invalid_name, {}};
  const auto found = functions.find(Key{space, name});
  if (found == functions.end()) return {NativeStatus::unknown_function, {}};
  if (script_arguments.size() >= max_arguments) return {NativeStatus::argument_limit, {}};
  const auto argc = script_arguments.size() + 1;
  if (argc < found->second.min || (found->second.max && argc > found->second.max))
    return {NativeStatus::arity, {}};
  std::size_t bytes = name.size();
  for (const auto& argument : script_arguments) {
    if (argument.size() > max_argument_bytes - bytes)
      return {NativeStatus::argument_limit, {}};
    bytes += argument.size();
  }
  Arguments argv;
  argv.reserve(argc);
  argv.push_back(name);
  argv.insert(argv.end(), script_arguments.begin(), script_arguments.end());
  // Keep the actual callback alive if it unregisters itself. Copying the
  // std::function instead would lose persistent mutable closure state.
  const auto callback = found->second.callback;
  try {
    return {NativeStatus::ok, (*callback)(argv)};
  } catch (...) {
    return {NativeStatus::callback_failed, {}};
  }
}
} // namespace Torque
