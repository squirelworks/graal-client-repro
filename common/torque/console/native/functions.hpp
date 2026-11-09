#pragma once

#include <cstddef>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace Torque {
enum class NativeStatus {
  ok, invalid_name, invalid_signature, missing_callback, duplicate,
  registry_limit, unknown_function, argument_limit, arity, callback_failed
};
struct NativeResult {
  NativeStatus status;
  std::string value;
};

class NativeFunctions {
 public:
  using Arguments = std::vector<std::string>;
  using Callback = std::function<std::string(const Arguments&)>;
  static constexpr std::size_t max_functions = 4096;
  static constexpr std::size_t max_arguments = 1024;
  static constexpr std::size_t max_argument_bytes = 1024 * 1024;

  NativeFunctions() = default;
  NativeFunctions(const NativeFunctions&) = delete;
  NativeFunctions& operator=(const NativeFunctions&) = delete;

  // Counts include argv[0], the command name; max == 0 means unbounded
  // subject to this component's resource policy. No method/object argument.
  NativeStatus add(const std::string& space, const std::string& name,
                   std::size_t min, std::size_t max, Callback callback);
  bool remove(const std::string& space, const std::string& name);
  NativeResult call(const std::string& space, const std::string& name,
                    const Arguments& script_arguments) const;
  std::size_t size() const { return functions.size(); }

 private:
  struct Entry {
    std::size_t min, max;
    std::shared_ptr<Callback> callback;
  };
  using Key = std::pair<std::string, std::string>;
  std::map<Key, Entry> functions;
};
} // namespace Torque
