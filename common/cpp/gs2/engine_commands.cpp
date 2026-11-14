// Engine commands for the shell scripts. The 4.04r2 menus are the
// reference for which names exist and how they are called (README.md).

#include "engine_commands.hpp"

#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>

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

std::string md5Hex(const std::string& bytes) {
  // RFC 1321: per-round shift amounts and the sine-derived constants.
  static const std::uint32_t r[64] = {7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                                      5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20,
                                      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                                      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21};
  static std::uint32_t k[64];
  static bool ready = false;
  if (!ready) {
    for (int i = 0; i < 64; ++i) k[i] = static_cast<std::uint32_t>(std::fabs(std::sin(i + 1.0)) * 4294967296.0);
    ready = true;
  }
  std::uint32_t h[4] = {0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u};
  std::string msg = bytes;
  const std::uint64_t bits = static_cast<std::uint64_t>(bytes.size()) * 8;
  msg.push_back(static_cast<char>(0x80));
  while (msg.size() % 64 != 56) msg.push_back('\0');
  for (int i = 0; i < 8; ++i) msg.push_back(static_cast<char>((bits >> (8 * i)) & 0xFF));
  auto rotl = [](std::uint32_t x, std::uint32_t c) { return (x << c) | (x >> (32 - c)); };
  for (std::size_t off = 0; off < msg.size(); off += 64) {
    std::uint32_t w[16];
    for (int i = 0; i < 16; ++i) {
      w[i] = 0;
      for (int b = 0; b < 4; ++b)
        w[i] |= static_cast<std::uint32_t>(static_cast<unsigned char>(msg[off + 4 * i + b])) << (8 * b);
    }
    std::uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    for (std::uint32_t i = 0; i < 64; ++i) {
      std::uint32_t f, g;
      if (i < 16) { f = (b & c) | (~b & d); g = i; }
      else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
      else { f = c ^ (b | ~d); g = (7 * i) % 16; }
      const std::uint32_t t = d;
      d = c;
      c = b;
      b = b + rotl(a + f + k[i] + w[g], r[i]);
      a = t;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
  }
  std::string out;
  char buf[3];
  for (std::uint32_t v : h)
    for (int i = 0; i < 4; ++i) {
      std::snprintf(buf, sizeof buf, "%02x", (v >> (8 * i)) & 0xFF);
      out += buf;
    }
  return out;
}

void addEngineCommands(Machine& m, EngineHost host) {
  // scheduleevent(seconds, event, params...): the event on the object after
  // the delay (an `on` in front of the name is allowed); cancelevents(event)
  // drops the pending ones; trigger(event, params...) queues it now.
  m.addCommand("scheduleevent", "fs", [](Machine& mm, Var& self, std::vector<Value>& a) {
    std::vector<Value> params(a.begin() + 2, a.end());
    mm.scheduleEvent(self.shared_from_this(), mm.toNumber(a[0]), mm.toString(a[1]), std::move(params));
    return Value::number(0);
  });
  m.addCommand("cancelevents", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
    mm.cancelEvents(self.shared_from_this(), mm.toString(a[0]));
    return Value::number(0);
  });
  m.addCommand("trigger", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
    std::vector<Value> params(a.begin() + 1, a.end());
    mm.queueEvent(self.shared_from_this(), mm.toString(a[0]), std::move(params));
    return Value::number(0);
  });
  m.addCommand("destroy", "", [](Machine& mm, Var& self, std::vector<Value>&) {
    mm.destroy(self.shared_from_this());
    return Value::number(0);
  });
  m.addCommand("md5", "s", [](Machine& mm, Var&, std::vector<Value>& a) {
    return Value::string(md5Hex(mm.toString(a[0])));
  });
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
