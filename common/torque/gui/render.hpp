// Draws a 3.04 GUI control tree from the console engine onto a Canvas.
//
// The controls are the script objects the shipped .gui files create (see
// console/engine): class name, dynamic fields (`position`, `extent`,
// `profile`, `text`, `bitmap`, ...) and children in creation order. The
// profiles are GuiControlProfile objects as defaultProfiles.cs,
// customProfiles.cs and the theme (.th) script left them. Nothing here
// changes the objects: layout is computed from the .gui values on every
// draw (rebuild policy; the original resizes the objects themselves, so
// script calls such as getExtent() still report the .gui values here).
//
// Which control classes draw, how, and what each rule was checked against
// is in README.md ("Stock controls"). Classes not handled yet draw nothing
// themselves but still draw their children.
#pragma once

#include "bitmap_array.hpp"
#include "canvas.hpp"
#include "gft.hpp"
#include "image.hpp"
#include "profile.hpp"

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace Torque {
class Engine;
struct SimObject;
}  // namespace Torque

namespace Torque::Gui {

// Torque's horizSizing / vertSizing. The names are the .gui field values:
// horizontal right (default), width, left, center, relative; vertical
// bottom (default), height, top, center, relative.
enum class Sizing { keep, grow, move, center, relative };
Sizing parse_horiz_sizing(const std::string& s);
Sizing parse_vert_sizing(const std::string& s);

// New position and length of a child along one axis when its parent's
// length changes from `old_parent` to `new_parent`.
void resize_axis(Sizing sizing, int old_parent, int new_parent, int& pos, int& len);

// Top of a single text line centred in a box `box_height` tall: the line
// box is the font height less two rows. Fitted to the stage 0 screenshot
// (README.md, "Stock controls").
int text_line_top(int box_height, int font_height);

// Draws a sizable frame from nine consecutive cells starting at `first`
// (top-left, top, top-right, left, centre, right, bottom-left, bottom,
// bottom-right): corners as they are, edges and centre stretched. With
// `has_centre` false the cells are the eight pieces without the centre and
// `centre_fill` (when its alpha is non-zero) fills the middle instead.
void draw_sizable(Canvas& canvas, const Image& image, const BitmapArray& array, std::size_t first,
                  const Rect& rect, bool has_centre, Color centre_fill);

class Renderer {
 public:
  explicit Renderer(Engine& engine);
  ~Renderer();

  // Draws `content` sized to the whole canvas, then each dialog in
  // `dialogs` on top (as Canvas.pushDialog would), each also sized to the
  // canvas.
  void render(Canvas& canvas, SimObject* content, const std::vector<SimObject*>& dialogs = {});

  // Resolved values, exposed for tests and the lab tool.
  Profile profile_of(const SimObject* control) const;
  const GftFont* font(const std::string& face, int size);
  // `path` is a resolved, mod-relative path without extension (.png is
  // tried, then the path as given). Returns nullptr if it cannot be read.
  const Image* bitmap(const std::string& path);
  const BitmapArray* bitmap_array(const std::string& path);
  // The file a profile's `bitmap` field names (see README.md for the rule).
  std::string profile_bitmap_path(const SimObject* control);

  // Problems met while drawing (missing fonts or bitmaps), one per item.
  std::vector<std::string> notes;

 private:
  struct Cached {
    bool ok = false;
    Image image;
    BitmapArray array;
    bool split = false;
  };
  void draw_control(Canvas& canvas, SimObject* control, const Rect& rect);
  void draw_self(Canvas& canvas, SimObject* control, const Rect& rect);
  void draw_text_line(Canvas& canvas, const Profile& p, const Rect& box, const std::string& text,
                      Color color);
  void draw_button(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect);
  void draw_text_edit(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect);
  void draw_window(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect);
  void draw_bitmap_ctrl(Canvas& canvas, SimObject* control, const Rect& rect, bool tile);
  Cached* load(const std::string& path);
  void note(const std::string& line);

  Engine& engine_;
  std::map<std::string, std::unique_ptr<GftFont>> fonts_;
  std::map<std::string, std::unique_ptr<Cached>> bitmaps_;
};

}  // namespace Torque::Gui
