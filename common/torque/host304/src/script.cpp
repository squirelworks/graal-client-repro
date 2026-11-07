#include "script.hpp"

#include "guigraal.hpp"

#include <cmath>
#include <fstream>
#include <map>
#include <sstream>

namespace {

std::string trim(const std::string &s) {
  std::size_t a = 0;
  while (a < s.size() && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r')) {
    ++a;
  }
  std::size_t b = s.size();
  while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r')) {
    --b;
  }
  return s.substr(a, b - a);
}

std::string stripSemi(std::string s) {
  s = trim(s);
  if (!s.empty() && s[s.size() - 1] == ';') {
    s.erase(s.size() - 1);
  }
  return trim(s);
}

std::string fmtNum(double v) {
  if (std::isfinite(v) && std::floor(v) == v && std::fabs(v) < 1.0e9) {
    return std::to_string(static_cast<long long>(v));
  }
  std::ostringstream o;
  o << v;
  return o.str();
}

struct Camera {
  double x;
  double y;
  double z;
};

bool parseQuoted(const std::string &inside, std::string &quoted, std::string &error) {
  const std::size_t q1 = inside.find('"');
  if (q1 == std::string::npos) {
    error = "setTransform needs a quoted string";
    return false;
  }
  const std::size_t q2 = inside.find('"', q1 + 1);
  if (q2 == std::string::npos) {
    error = "setTransform string is not closed";
    return false;
  }
  quoted = inside.substr(q1 + 1, q2 - q1 - 1);
  return true;
}

bool parseVec3(const std::string &text, double &x, double &y, double &z) {
  std::istringstream in(text);
  if (!(in >> x >> y >> z)) {
    return false;
  }
  return true;
}

int countArgs(const std::string &inside) {
  const std::string t = trim(inside);
  if (t.empty()) {
    return 0;
  }
  int n = 1;
  bool quote = false;
  for (std::size_t i = 0; i < t.size(); ++i) {
    if (t[i] == '"') {
      quote = !quote;
    } else if (t[i] == ',' && !quote) {
      ++n;
    }
  }
  return n;
}

bool callGui(const std::string &method, const std::string &inside, ScriptResult &out) {
  const GuiMethod *m = findGuiMethod(method);
  const int argc = countArgs(inside);
  if (m == 0) {
    out.log.push_back("stub GuiGraalCtrl::" + method +
                      " unknown method (not on the 3.04 table)");
    return true;
  }
  const int expect = guiScriptArgs(*m);
  std::ostringstream line;
  line << "stub GuiGraalCtrl::" << method << " args=" << argc;
  if (expect >= 0 && argc != expect) {
    line << " expected=" << expect;
  }
  // Body is unknown. The call is logged and does not change the camera.
  line << " (body unknown)";
  out.log.push_back(line.str());
  return true;
}

bool execLine(const std::string &raw, std::map<std::string, Camera> &cameras,
              ScriptResult &out, std::string &error) {
  const std::string line = stripSemi(raw);
  if (line.empty() || line.compare(0, 2, "//") == 0) {
    return true;
  }

  const std::string neu = "new Camera(";
  if (line.compare(0, neu.size(), neu) == 0) {
    const std::size_t end = line.find(')', neu.size());
    if (end == std::string::npos) {
      error = "new Camera is missing a closing parenthesis";
      return false;
    }
    const std::string name = trim(line.substr(neu.size(), end - neu.size()));
    if (name.empty()) {
      error = "new Camera needs a name";
      return false;
    }
    cameras[name] = Camera{0, 0, 0};
    out.log.push_back("new Camera " + name + " at 0 0 0");
    return true;
  }

  const std::string marker = ".setTransform(";
  const std::size_t at = line.find(marker);
  if (at != std::string::npos) {
    const std::string name = trim(line.substr(0, at));
    const std::string inside = line.substr(at + marker.size());
    std::string quoted;
    if (!parseQuoted(inside, quoted, error)) {
      return false;
    }
    std::map<std::string, Camera>::iterator cam = cameras.find(name);
    if (cam == cameras.end()) {
      out.log.push_back("console stub: setTransform on unknown camera " + name);
      return true;
    }
    double x = 0;
    double y = 0;
    double z = 0;
    if (!parseVec3(quoted, x, y, z)) {
      error = "setTransform needs three numbers";
      return false;
    }
    const std::string from =
        fmtNum(cam->second.x) + " " + fmtNum(cam->second.y) + " " + fmtNum(cam->second.z);
    cam->second.x = x;
    cam->second.y = y;
    cam->second.z = z;
    const std::string to = fmtNum(x) + " " + fmtNum(y) + " " + fmtNum(z);
    // PROVISIONAL method name. engine-304.md says Camera has three
    // methods and does not name them. setTransform is the stock TGE
    // call this runner understands. It is not a recovered 3.04 name.
    out.cameraLine = "camera moved: " + name + " from " + from + " to " + to;
    out.cameraMoved = true;
    out.log.push_back(out.cameraLine);
    return true;
  }

  const std::size_t dot = line.find('.');
  const std::size_t paren = line.find('(');
  if (dot != std::string::npos && paren != std::string::npos && dot < paren &&
      line[line.size() - 1] == ')') {
    const std::string obj = trim(line.substr(0, dot));
    const std::string method = trim(line.substr(dot + 1, paren - dot - 1));
    const std::string inside = line.substr(paren + 1, line.size() - paren - 2);
    if (obj == "Adventure") {
      return callGui(method, inside, out);
    }
    out.log.push_back("console stub: " + line);
    return true;
  }

  out.log.push_back("console stub: " + line);
  return true;
}

} // namespace

bool runScriptFile(const std::string &path, ScriptResult &out, std::string &error) {
  out.cameraMoved = false;
  out.cameraLine.clear();
  out.log.clear();

  std::ifstream in(path.c_str());
  if (!in) {
    error = "could not open " + path;
    return false;
  }

  std::ostringstream names;
  const int n = guiMethodCount();
  const GuiMethod *methods = guiMethods();
  for (int i = 0; i < n; ++i) {
    if (i) {
      names << ", ";
    }
    names << methods[i].name;
  }
  out.log.push_back("registered GuiGraalCtrl Adventure: " + std::to_string(n) +
                    " methods (bodies unknown)");
  out.log.push_back("registered GuiGraalCtrl methods: " + names.str());
  out.log.push_back(
      "registered Camera (stock TGE class; the 3.04 note says three methods "
      "and does not name them; setTransform is provisional)");

  std::map<std::string, Camera> cameras;
  std::string line;
  int number = 0;
  while (std::getline(in, line)) {
    ++number;
    if (!execLine(line, cameras, out, error)) {
      error = path + ":" + std::to_string(number) + ": " + error;
      return false;
    }
  }
  if (!out.cameraMoved) {
    error = "script did not move a camera";
    return false;
  }
  return true;
}
