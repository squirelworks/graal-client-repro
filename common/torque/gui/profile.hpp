// GuiControlProfile values as the stock controls read them.
//
// In 3.04 a profile is a script object: common/ui/defaultProfiles.cs and
// graaldata/client/ui/customProfiles.cs create them with `new
// GuiControlProfile(Name) { ... }` (optionally `: Parent`, which copies the
// parent's fields), and the theme script (common/ui/themes/<theme>/
// <theme>theme.th, exec'd by loadTheme() in optionsDlg.cs) then assigns
// fields such as `GuiButtonProfile.bitmap = "./defaultButton";`. Every value
// is a dynamic string field on the object. This unit turns those strings
// into typed values and has no dependency on the script engine: the caller
// supplies a field lookup.
//
// Lookup order for each field (rebuild policy): the profile itself, then
// the fallback profile (GuiDefaultProfile, which every 3.04 profile
// inherits from in the stock classes), then the built-in default below.
// The built-in defaults matter only for a profile set the shipped scripts
// never create; they are the values GuiDefaultProfile is created with in
// the 3.04 defaultProfiles.cs where one exists, otherwise zero or empty.
#pragma once

#include "image.hpp"

#include <functional>
#include <string>

namespace Torque::Gui {

// Reads one field by name (case-insensitive is up to the source). Returns
// false when the object has no such field.
using FieldLookup = std::function<bool(const std::string& name, std::string& value)>;

struct Point { int x = 0, y = 0; };

enum class Justify { left, center, right };

struct Profile {
  bool opaque = false;
  Color fill_color{0, 128, 0, 255}, fill_color_hl{0, 192, 0, 255}, fill_color_na{0, 96, 0, 255};
  int border = 0;              // 0 none; other values select a border style
  int border_thickness = 1;
  Color border_color{0, 0, 0, 255}, border_color_hl{128, 128, 128, 255},
      border_color_na{64, 64, 64, 255};
  std::string font_type = "Arial";
  int font_size = 14;
  Color font_color{0, 0, 0, 255}, font_color_hl{32, 100, 100, 255}, font_color_na{0, 0, 0, 255},
      font_color_sel{200, 200, 200, 255};
  Color cursor_color{224, 255, 224, 128};
  std::string bitmap;          // the field as written, not yet a path
  bool bitmap_from_fallback = false;  // `bitmap` came from the fallback profile
  bool has_bitmap_array = false;
  bool tile = false;
  Point text_offset;
  Justify justify = Justify::left;
  bool auto_size_width = false, auto_size_height = false;
  bool modal = true;
  bool can_key_focus = false;
};

// Script value parsers. Colours are "r g b" or "r g b a" (alpha 255 when
// absent), each clamped to 0..255; a missing component is 0. Booleans are
// true for "true" (any case) or a non-zero number. Points are "x y".
Color parse_color(const std::string& s);
bool parse_bool(const std::string& s);
int parse_int_field(const std::string& s);
Point parse_point(const std::string& s);
Justify parse_justify(const std::string& s);

// Builds a profile from `own`, falling back to `fallback` (may be empty)
// field by field.
Profile read_profile(const FieldLookup& own, const FieldLookup& fallback);

}  // namespace Torque::Gui
