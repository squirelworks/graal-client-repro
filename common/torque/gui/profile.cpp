#include "profile.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <sstream>

namespace Torque::Gui {

namespace {

std::string lower(std::string s) {
  for (auto& c : s) c = char(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

std::uint8_t channel(long v) { return std::uint8_t(std::clamp(v, 0L, 255L)); }

}  // namespace

Color parse_color(const std::string& s) {
  std::istringstream in(s);
  long v[4] = {0, 0, 0, 255};
  for (int i = 0; i < 4; ++i) {
    double d;
    if (!(in >> d)) break;
    v[i] = long(d);
  }
  return {channel(v[0]), channel(v[1]), channel(v[2]), channel(v[3])};
}

bool parse_bool(const std::string& s) {
  if (lower(s) == "true") return true;
  return std::strtod(s.c_str(), nullptr) != 0;
}

int parse_int_field(const std::string& s) {
  return int(std::clamp(std::strtod(s.c_str(), nullptr), -1e9, 1e9));
}

Point parse_point(const std::string& s) {
  std::istringstream in(s);
  double x = 0, y = 0;
  in >> x >> y;
  return {int(std::clamp(x, -1e9, 1e9)), int(std::clamp(y, -1e9, 1e9))};
}

Justify parse_justify(const std::string& s) {
  const std::string l = lower(s);
  if (l == "center") return Justify::center;
  if (l == "right") return Justify::right;
  return Justify::left;
}

Profile read_profile(const FieldLookup& own, const FieldLookup& fallback) {
  Profile p;
  bool from_fallback = false;
  auto get = [&](const char* name, std::string& out) {
    from_fallback = false;
    if (own && own(name, out)) return true;
    from_fallback = true;
    return fallback && fallback(name, out);
  };
  std::string v;
  auto color = [&](const char* name, Color& out) { if (get(name, v)) out = parse_color(v); };
  auto flag = [&](const char* name, bool& out) { if (get(name, v)) out = parse_bool(v); };
  auto number = [&](const char* name, int& out) { if (get(name, v)) out = parse_int_field(v); };

  flag("opaque", p.opaque);
  color("fillColor", p.fill_color);
  color("fillColorHL", p.fill_color_hl);
  color("fillColorNA", p.fill_color_na);
  number("border", p.border);
  number("borderThickness", p.border_thickness);
  color("borderColor", p.border_color);
  color("borderColorHL", p.border_color_hl);
  color("borderColorNA", p.border_color_na);
  if (get("fontType", v)) p.font_type = v;
  number("fontSize", p.font_size);
  color("fontColor", p.font_color);
  color("fontColorHL", p.font_color_hl);
  color("fontColorNA", p.font_color_na);
  color("fontColorSEL", p.font_color_sel);
  color("cursorColor", p.cursor_color);
  if (get("bitmap", v)) {
    p.bitmap = v;
    p.bitmap_from_fallback = from_fallback;
  }
  flag("hasBitmapArray", p.has_bitmap_array);
  flag("tile", p.tile);
  if (get("textOffset", v)) p.text_offset = parse_point(v);
  if (get("justify", v)) p.justify = parse_justify(v);
  flag("autoSizeWidth", p.auto_size_width);
  flag("autoSizeHeight", p.auto_size_height);
  flag("modal", p.modal);
  flag("canKeyFocus", p.can_key_focus);
  return p;
}

}  // namespace Torque::Gui
