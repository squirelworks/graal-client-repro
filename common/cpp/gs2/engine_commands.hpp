#pragma once

// The engine's own commands the shell scripts call that are not GUI
// controls: logging, timers, event catches, file-name helpers, and the
// `Adventure_*` calls into the game. The engine program (the 4.x engine
// library, the Quattro program) supplies what reaches outside the machine
// through EngineHost; a hook it leaves empty leaves that command
// unregistered, so a script calling it gets the engines' "not found" error.
//
// Also the object and event commands every script has: scheduleevent,
// cancelevents, trigger and destroy (on the calling object, or the object
// a method call names), and md5.

#include <functional>
#include <map>
#include <string>
#include <vector>

#include "gs2.hpp"

namespace gs2 {

struct EngineHost {
  std::function<void(const std::string&)> log;     // echo
  std::function<void(const std::string&)> openUrl;
  std::function<bool(int virtualKey)> keyDown;
  std::function<std::vector<std::string>(const std::string& device)> resolutionList;
  // Adventure_* by name (case-insensitive), e.g. "Adventure_setNickName".
  std::map<std::string, Command> adventure;
};

void addEngineCommands(Machine& m, EngineHost host);

// File-name helpers, exposed for tests.
std::string extractFileBase(const std::string& path);  // name without folder or extension
std::string extractFilePath(const std::string& path);  // folder with its trailing separator
// MD5 of the bytes, as 32 lower-case hex digits (RFC 1321).
std::string md5Hex(const std::string& bytes);

}  // namespace gs2
