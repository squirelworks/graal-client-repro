#include "gmap.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>

namespace Quattro::Files {

namespace {

std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

// One LEVELNAMES row: quoted names split on commas.
std::vector<std::string> row_names(const std::string& line) {
  std::vector<std::string> out;
  std::string cur;
  bool quoted = false, any = false;
  for (char c : line) {
    if (c == '"') {
      quoted = !quoted;
      any = true;
    } else if (c == ',' && !quoted) {
      out.push_back(lower(cur));
      cur.clear();
      any = false;
    } else if (quoted || !std::isspace(static_cast<unsigned char>(c))) {
      cur += c;
      any = true;
    }
  }
  if (any || !cur.empty()) out.push_back(lower(cur));
  return out;
}

// "offlinetutorial_c-3.graal" -> prefix "offlinetutorial_", column 2, row 2.
bool split_generated(const std::string& name, std::string& prefix, int& col, int& row, std::string& ext) {
  const auto dot = name.rfind('.');
  ext = dot == std::string::npos ? "" : name.substr(dot);
  const std::string stem = dot == std::string::npos ? name : name.substr(0, dot);
  const auto dash = stem.rfind('-');
  if (dash == std::string::npos || dash == 0 || dash + 1 >= stem.size()) return false;
  const char letter = static_cast<char>(std::tolower(static_cast<unsigned char>(stem[dash - 1])));
  if (letter < 'a' || letter > 'z') return false;
  for (size_t i = dash + 1; i < stem.size(); ++i)
    if (!std::isdigit(static_cast<unsigned char>(stem[i]))) return false;
  prefix = lower(stem.substr(0, dash - 1));
  col = letter - 'a';
  row = std::atoi(stem.c_str() + dash + 1) - 1;
  return row >= 0;
}

}  // namespace

bool Gmap::find(const std::string& name, int& x, int& y) const {
  const std::string want = lower(name);
  for (size_t i = 0; i < names.size(); ++i) {
    if (!names[i].empty() && names[i] == want) {
      x = static_cast<int>(i) % width;
      y = static_cast<int>(i) / width;
      return true;
    }
  }
  return false;
}

bool read_gmap(std::string_view data, Gmap& out, std::string& error) {
  out = Gmap{};
  std::istringstream in{std::string(data)};
  std::string line, generated;
  std::vector<std::vector<std::string>> rows;
  bool signature = false, in_names = false, have_names = false;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (!signature) {
      if (line.rfind("GRMAP001", 0) != 0) {
        error = "gmap: no GRMAP001 signature";
        return false;
      }
      signature = true;
      continue;
    }
    std::istringstream words(line);
    std::string key;
    words >> key;
    if (in_names) {
      if (key == "LEVELNAMESEND") in_names = false;
      else if (!key.empty()) rows.push_back(row_names(line));
      continue;
    }
    if (key == "WIDTH") words >> out.width;
    else if (key == "HEIGHT") words >> out.height;
    else if (key == "GENERATED") words >> generated;
    else if (key == "LEVELNAMES") in_names = have_names = true;
  }
  if (!signature) {
    error = "gmap: empty file";
    return false;
  }
  if (out.width <= 0 || out.height <= 0 || out.width > 1024 || out.height > 1024) {
    error = "gmap: no WIDTH and HEIGHT";
    return false;
  }
  out.names.assign(static_cast<size_t>(out.width * out.height), {});
  if (have_names) {
    for (size_t y = 0; y < rows.size() && y < static_cast<size_t>(out.height); ++y)
      for (size_t x = 0; x < rows[y].size() && x < static_cast<size_t>(out.width); ++x)
        out.names[y * out.width + x] = rows[y][x];
    return true;
  }
  std::string prefix, ext;
  int col = 0, row = 0;
  if (generated.empty() || !split_generated(generated, prefix, col, row, ext) || out.width > 26) {
    error = "gmap: no LEVELNAMES and no level name in GENERATED";
    return false;
  }
  for (int y = 0; y < out.height; ++y)
    for (int x = 0; x < out.width; ++x)
      out.names[static_cast<size_t>(y * out.width + x)] =
          prefix + static_cast<char>('a' + x) + "-" + std::to_string(y + 1) + ext;
  return true;
}

}  // namespace Quattro::Files
