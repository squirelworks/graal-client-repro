#pragma once

// Drawing the GS2 GUI (plan step B4). The screen's content and dialogs are
// drawn through a Painter: the 4.x engine library implements it on the
// launcher's draw slots, the Quattro program on its own renderer, and the
// tests record the calls. The rules per control follow the Torque stock
// controls (common/torque/gui README, "Stock controls"); README.md here
// lists which are readings.

#include <cstdint>
#include <string>
#include <vector>

#include "gui.hpp"

namespace gs2::gui {

struct Color {
  std::uint8_t r = 0, g = 0, b = 0, a = 255;
  bool operator==(const Color& o) const { return r == o.r && g == o.g && b == o.b && a == o.a; }
};

// "r g b" or "r g b a", each clamped to 0..255.
Color parseColor(const std::string& s);

// A profile's fields as the controls read them: the profile named by the
// control's `profile`, then GuiDefaultProfile, then the built-in value.
struct Style {
  bool opaque = false;
  Color fill{0, 0, 0, 0}, fillHL{0, 0, 0, 0}, fillNA{0, 0, 0, 0};
  int border = 0;
  Color borderColor{0, 0, 0, 255};
  std::string fontType = "Arial";
  int fontSize = 14;
  Color fontColor{0, 0, 0, 255}, fontColorHL{0, 0, 0, 255}, fontColorNA{128, 128, 128, 255},
      fontColorSel{255, 255, 255, 255};
  Color cursorColor{0, 0, 0, 255};
  std::string bitmap;  // as written, without an extension when the script gave none
  std::string justify = "left";
  int textOffsetX = 0, textOffsetY = 0;
};
Style styleOf(const Screen& s, const Control& c);

class Painter {
 public:
  virtual ~Painter() = default;
  virtual void setClip(const Rect& r) = 0;
  virtual void fill(const Rect& r, Color c) = 0;
  virtual void text(int x, int y, const std::string& s, const std::string& font, int size, Color c) = 0;
  virtual int textWidth(const std::string& s, const std::string& font, int size) = 0;
  virtual int fontHeight(const std::string& font, int size) = 0;
  // Bitmaps are named as the scripts name them (`defaultButton.png`,
  // `graalv4screen.jpg`); the painter finds and caches the file. A theme
  // bitmap is split into cells by its separator colour (the Torque bitmap
  // array); `cells` is empty when the image has none.
  virtual bool bitmapSize(const std::string& file, int& w, int& h) = 0;
  virtual std::vector<Rect> cells(const std::string& file) = 0;
  virtual void bitmap(const std::string& file, const Rect& src, const Rect& dst) = 0;
  // Controls the engine draws itself (GuiShowImgCtrl, GuiGraalCtrl,
  // GuiGraal3DCtrl): called with the control's rectangle, before its
  // children.
  virtual void engineControl(const Control&, const Rect&) {}
};

// Draws the content, then each dialog over it, at the screen's size.
void drawScreen(Screen& s, Painter& p);

}  // namespace gs2::gui
