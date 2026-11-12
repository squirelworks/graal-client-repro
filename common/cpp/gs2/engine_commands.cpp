// Engine commands for the shell scripts. The 4.04r2 menus are the
// reference for which names exist and how they are called (README.md).

#include "engine_commands.hpp"

#include <cctype>

namespace gs2 {

std::string extractFileBase(const std::string& path) {
  const auto slash = path.find_last_of("/\\");
  std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
  const auto dot = name.find_last_of('.');
  if (dot != std::string::npos) name.erase(dot);
  return name;
}

std::string extractFilePath(const std::string& path) {
  const auto slash = path.find_last_of("/\\");
  return slash == std::string::npos ? std::string() : path.substr(0, slash + 1);
}

void addEngineCommands(Machine& m, EngineHost host) {
  if (host.log) {
    auto log = host.log;
    m.addCommand("echo", "s", [log](Machine& mm, Var&, std::vector<Value>& a) {
      log(mm.toString(a[0]));
      return Value::number(0);
    });
  }
  // setTimer(seconds): one `timeout` event, replacing any pending one.
  m.addCommand("setTimer", "f", [](Machine& mm, Var& self, std::vector<Value>& a) {
    auto v = self.shared_from_this();
    mm.cancelEvents(v, "timeout");
    const double t = mm.toNumber(a[0]);
    if (t > 0) mm.scheduleEvent(v, t, "timeout");
    return Value::number(0);
  });
  // catchevent(object name, event, function): when that object's event is
  // queued, the calling script's function is queued too.
  m.addCommand("catchevent", "sss", [](Machine& mm, Var& self, std::vector<Value>& a) {
    mm.catchEvent(mm.toString(a[0]), mm.toString(a[1]), self.shared_from_this(), mm.toString(a[2]));
    return Value::number(0);
  });
  // join(class) and leave(class) on the calling object.
  m.addCommand("join", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
    return Value::number(mm.joinClass(self.shared_from_this(), mm.toString(a[0])) ? 1 : 0);
  });
  m.addCommand("leave", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
    mm.leaveClass(self.shared_from_this(), mm.toString(a[0]));
    return Value::number(0);
  });
  m.addCommand("extractFileBase", "s", [](Machine& mm, Var&, std::vector<Value>& a) {
    return Value::string(extractFileBase(mm.toString(a[0])));
  });
  m.addCommand("extractFilePath", "s", [](Machine& mm, Var&, std::vector<Value>& a) {
    return Value::string(extractFilePath(mm.toString(a[0])));
  });
  m.addCommand("lowercase", "s", [](Machine& mm, Var&, std::vector<Value>& a) {
    std::string s = mm.toString(a[0]);
    for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return Value::string(s);
  });
  if (host.openUrl) {
    auto f = host.openUrl;
    m.addCommand("openURL", "s", [f](Machine& mm, Var&, std::vector<Value>& a) {
      f(mm.toString(a[0]));
      return Value::number(0);
    });
  }
  if (host.keyDown) {
    auto f = host.keyDown;
    m.addCommand("keydown", "f", [f](Machine& mm, Var&, std::vector<Value>& a) {
      return Value::number(f(static_cast<int>(mm.toNumber(a[0]))) ? 1 : 0);
    });
  }
  if (host.resolutionList) {
    auto f = host.resolutionList;
    m.addCommand("getResolutionList", "s", [f](Machine& mm, Var&, std::vector<Value>& a) {
      auto list = f(mm.toString(a[0]));
      auto arr = std::make_shared<Var>();
      arr->setArray(list.size());
      for (std::size_t i = 0; i < list.size(); ++i) arr->elements()[i]->setString(list[i]);
      return Value::object(arr);
    });
  }
  for (auto& [name, fn] : host.adventure) m.addCommand(name, "", fn);
}

}  // namespace gs2
