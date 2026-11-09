#include "functions.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

using Torque::NativeFunctions;
using Torque::NativeStatus;
void require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}
int main() {
  NativeFunctions registry;
  std::vector<NativeFunctions::Arguments> calls;
  auto record = [&](const NativeFunctions::Arguments& argv) {
    calls.push_back(argv);
    return argv.back();
  };
  require(registry.add("", "fixture", 2, 2, record) == NativeStatus::ok, "registration failed");
  const std::string binary("A\0B", 3);
  auto result = registry.call("", "fixture", {binary});
  require(result.status == NativeStatus::ok && result.value == binary &&
          calls == std::vector<NativeFunctions::Arguments>{{"fixture", binary}},
          "callback argument order/bytes/result differ");
  require(registry.call("", "fixture", {}).status == NativeStatus::arity &&
          registry.call("", "fixture", {"1","2"}).status == NativeStatus::arity &&
          calls.size() == 1, "arity failure invoked callback");
  require(registry.add("", "fixture", 1, 0, record) == NativeStatus::duplicate &&
          registry.size() == 1, "duplicate replaced entry");
  require(registry.call("", "Fixture", {}).status == NativeStatus::unknown_function,
          "exact key lookup changed");
  require(registry.add("other", "fixture", 1, 1, record) == NativeStatus::ok &&
          registry.call("other", "fixture", {}).value == "fixture", "namespace isolation failed");
  require(registry.call("missing", "fixture", {}).status == NativeStatus::unknown_function,
          "unexpected namespace fallback");
  require(registry.add("", "varargs", 1, 0, record) == NativeStatus::ok &&
          registry.call("", "varargs", {}).status == NativeStatus::ok &&
          registry.call("", "varargs", {"x","y","z"}).status == NativeStatus::ok,
          "zero maximum is not variadic");
  require(registry.add("", "", 1, 1, record) == NativeStatus::invalid_name &&
          registry.add("", std::string("a\0b",3), 1, 1, record) == NativeStatus::invalid_name &&
          registry.add(std::string("a\0b",3), "x", 1, 1, record) == NativeStatus::invalid_name &&
          registry.add("", std::string(1025,'x'), 1, 1, record) == NativeStatus::invalid_name,
          "invalid key accepted");
  require(registry.add("", "bad", 0, 0, record) == NativeStatus::invalid_signature &&
          registry.add("", "bad", 3, 2, record) == NativeStatus::invalid_signature &&
          registry.add("", "bad", 1025, 0, record) == NativeStatus::invalid_signature &&
          registry.add("", "bad", 1, 1025, record) == NativeStatus::invalid_signature &&
          registry.add("", "bad", 1, 1, {}) == NativeStatus::missing_callback,
          "invalid signature/callback accepted");
  const auto before_limits = calls.size();
  require(registry.call("", "varargs", NativeFunctions::Arguments(1024)).status ==
          NativeStatus::argument_limit, "argument count limit missed");
  require(registry.call("", "varargs", {std::string(NativeFunctions::max_argument_bytes,'x')}).status ==
          NativeStatus::argument_limit && calls.size() == before_limits,
          "byte limit missed or callback ran");
  require(registry.call("", "varargs", NativeFunctions::Arguments(1023)).status == NativeStatus::ok,
          "exact argument count boundary rejected");

  // Test-only native body: no historical command is claimed implemented.
  require(registry.add("", "counter", 1, 1,
          [count=0](const NativeFunctions::Arguments&) mutable { return std::to_string(++count); }) ==
          NativeStatus::ok, "counter registration failed");
  require(registry.call("", "counter", {}).value == "1" &&
          registry.call("", "counter", {}).value == "2", "callback closure state was copied away");
  require(registry.add("", "once", 1, 1, [&](const NativeFunctions::Arguments&) {
    require(registry.remove("", "once"), "self removal failed"); return std::string("done");
  }) == NativeStatus::ok, "self-removing registration failed");
  require(registry.call("", "once", {}).value == "done" &&
          registry.call("", "once", {}).status == NativeStatus::unknown_function,
          "self removal invalidated active callback");
  require(registry.add("", "throws", 1, 1, [](const NativeFunctions::Arguments&) -> std::string {
    throw std::runtime_error("fixture failure");
  }) == NativeStatus::ok, "throwing callback registration failed");
  result = registry.call("", "throws", {});
  require(result.status == NativeStatus::callback_failed && result.value.empty(),
          "exception escaped or partial result returned");
  require(registry.remove("", "fixture") && !registry.remove("", "fixture") &&
          registry.call("other", "fixture", {}).status == NativeStatus::ok,
          "removal affected another namespace");

  NativeFunctions full;
  auto empty = [](const NativeFunctions::Arguments&) { return std::string(); };
  for (std::size_t i = 0; i < NativeFunctions::max_functions; ++i)
    require(full.add("", std::to_string(i), 1, 1, empty) == NativeStatus::ok,
            "registry reached limit early");
  require(full.add("", "overflow", 1, 1, empty) == NativeStatus::registry_limit,
          "registry limit missed");
  require(full.remove("", "0") && full.add("", "replacement", 1, 1, empty) == NativeStatus::ok,
          "removed slot was not reusable");
  std::cout << "Native function arity, dispatch, ownership and resource tests passed\n";
}
