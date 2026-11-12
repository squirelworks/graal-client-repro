#include "render.hpp"

#include "../console/engine/engine.hpp"

#include <algorithm>
#include <cctype>
#include <tuple>

namespace Torque::Gui {

namespace {

std::string lowered(std::string s) {
  for (auto& c : s) c = char(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

bool is_control(const Engine& e, const SimObject* o) {
  for (const ClassInfo* c = o ? o->info : nullptr; c; c = e.find_class(c->parent))
    if (lowered(c->name) == "guicontrol") return true;
  return false;
}

// A field that may be absent (SimObject::field cannot tell absent from empty).
bool has_field(const SimObject* o, const std::string& name, std::string& out) {
  if (!o) return false;
  auto it = o->fields.find(lowered(name));
  if (it == o->fields.end()) return false;
  out = it->second.second;
  return true;
}

std::string field_or(const SimObject* o, const char* name, const char* fallback) {
  std::string v;
  return has_field(o, name, v) ? v : std::string(fallback);
}

Rect rect_of(const SimObject* o) {
  Point pos = parse_point(field_or(o, "position", "0 0"));
  Point ext = parse_point(field_or(o, "extent", "64 64"));
  return {pos.x, pos.y, ext.x, ext.y};
}

std::size_t cell_count(const BitmapArray* a) { return a ? a->cells.size() : 0; }

}  // namespace

Sizing parse_horiz_sizing(const std::string& s) {
  const std::string l = lowered(s);
  if (l == "width") return Sizing::grow;
  if (l == "left") return Sizing::move;
  if (l == "center") return Sizing::center;
  if (l == "relative") return Sizing::relative;
  return Sizing::keep;
}

Sizing parse_vert_sizing(const std::string& s) {
  const std::string l = lowered(s);
  if (l == "height") return Sizing::grow;
  if (l == "top") return Sizing::move;
  if (l == "center") return Sizing::center;
  if (l == "relative") return Sizing::relative;
  return Sizing::keep;
}

void resize_axis(Sizing sizing, int old_parent, int new_parent, int& pos, int& len) {
  const int delta = new_parent - old_parent;
  switch (sizing) {
    case Sizing::keep: break;
    case Sizing::grow: len += delta; break;
    case Sizing::move: pos += delta; break;
    case Sizing::center: pos = (new_parent - len) / 2; break;
    case Sizing::relative:
      if (old_parent > 0) {
        const int end = int((long long)(pos + len) * new_parent / old_parent);
        pos = int((long long)pos * new_parent / old_parent);
        len = end - pos;
      }
      break;
  }
}

int text_line_top(int box_height, int font_height) { return (box_height - (font_height - 2)) / 2; }

void draw_sizable(Canvas& canvas, const Image& image, const BitmapArray& array, std::size_t first,
                  const Rect& rect, bool has_centre, Color centre_fill) {
  const std::size_t need = has_centre ? 9 : 8;
  if (array.cells.size() < first + need || rect.empty()) return;
  const Rect* c = &array.cells[first];
  const Rect &tl = c[0], &t = c[1], &tr = c[2], &l = c[3];
  const Rect& r = c[has_centre ? 5 : 4];
  const Rect& bl = c[has_centre ? 6 : 5];
  const Rect& b = c[has_centre ? 7 : 6];
  const Rect& br = c[has_centre ? 8 : 7];
  const int right = rect.x + rect.width, bottom = rect.y + rect.height;
  canvas.blit(image, tl, rect.x, rect.y);
  canvas.blit(image, tr, right - tr.width, rect.y);
  canvas.blit(image, bl, rect.x, bottom - bl.height);
  canvas.blit(image, br, right - br.width, bottom - br.height);
  canvas.smooth_stretch_blit(image, t, {rect.x + tl.width, rect.y, rect.width - tl.width - tr.width, t.height});
  canvas.smooth_stretch_blit(image, b, {rect.x + bl.width, bottom - b.height, rect.width - bl.width - br.width, b.height});
  canvas.smooth_stretch_blit(image, l, {rect.x, rect.y + tl.height, l.width, rect.height - tl.height - bl.height});
  canvas.smooth_stretch_blit(image, r, {right - r.width, rect.y + tr.height, r.width, rect.height - tr.height - br.height});
  const Rect middle{rect.x + l.width, rect.y + t.height, rect.width - l.width - r.width,
                    rect.height - t.height - b.height};
  if (has_centre) canvas.smooth_stretch_blit(image, c[4], middle);
  else if (centre_fill.a) canvas.fill_rect(middle, centre_fill);
}

Renderer::Renderer(Engine& engine) : engine_(engine) {}
Renderer::~Renderer() = default;

void Renderer::note(const std::string& line) {
  if (std::find(notes.begin(), notes.end(), line) == notes.end()) notes.push_back(line);
}

Profile Renderer::profile_of(const SimObject* control) const {
  std::string name = field_or(control, "profile", "");
  const SimObject* own = name.empty() ? nullptr : engine_.find_object(name);
  const SimObject* fallback = engine_.find_object("GuiDefaultProfile");
  if (!own) own = fallback;
  if (fallback == own) fallback = nullptr;
  auto lookup = [](const SimObject* o) -> FieldLookup {
    if (!o) return {};
    return [o](const std::string& n, std::string& v) { return has_field(o, n, v); };
  };
  return read_profile(lookup(own), lookup(fallback));
}

const GftFont* Renderer::font(const std::string& face, int size) {
  std::string dir = engine_.global("$Gui::fontCacheDirectory").str();
  if (dir.empty()) dir = "common/ui/cache";
  const std::string path = dir + "/" + gft_cache_name(face, size);
  auto it = fonts_.find(lowered(path));
  if (it != fonts_.end()) return it->second.get();
  std::unique_ptr<GftFont> loaded;
  std::string data, error;
  if (engine_.files.read(path, data)) {
    auto f = std::make_unique<GftFont>();
    if (load_gft(std::vector<std::uint8_t>(data.begin(), data.end()), *f, error)) loaded = std::move(f);
    else note("font " + path + ": " + error);
  } else {
    note("font " + path + ": not found");
  }
  return (fonts_[lowered(path)] = std::move(loaded)).get();
}

Renderer::Cached* Renderer::load(const std::string& path) {
  if (path.empty()) return nullptr;
  auto it = bitmaps_.find(lowered(path));
  if (it != bitmaps_.end()) return it->second->ok ? it->second.get() : nullptr;
  auto c = std::make_unique<Cached>();
  for (const std::string& name : {path + ".png", path}) {
    std::string data, error;
    if (!engine_.files.read(name, data)) continue;
    // The whole-file reader rejects bytes after IEND; the 3.04 install's
    // graalDarkButton.png has one, and the original draws it, so images
    // are read up to IEND here.
    Image image;
    if (decode_png(reinterpret_cast<const std::uint8_t*>(data.data()), data.size(), image, error)) {
      c->image = std::move(image);
      c->ok = true;
      break;
    }
    note("bitmap " + name + ": " + error);
  }
  Cached* result = c->ok ? c.get() : nullptr;
  bitmaps_[lowered(path)] = std::move(c);
  return result;
}

const Image* Renderer::bitmap(const std::string& path) {
  Cached* c = load(path);
  return c ? &c->image : nullptr;
}

const BitmapArray* Renderer::bitmap_array(const std::string& path) {
  Cached* c = load(path);
  if (!c) return nullptr;
  if (!c->split) {
    c->array = split_bitmap_array(c->image);
    c->split = true;
  }
  return &c->array;
}

std::string Renderer::profile_bitmap_path(const SimObject* control) {
  const Profile p = profile_of(control);
  if (p.bitmap.empty()) return {};
  std::string name = field_or(control, "profile", "");
  const SimObject* holder = p.bitmap_from_fallback || name.empty() ? nullptr : engine_.find_object(name);
  if (!holder) holder = engine_.find_object("GuiDefaultProfile");
  // Relative to the script that created the profile (observed: see README.md).
  std::string path = Engine::expand_path_from(holder ? holder->source : std::string(), p.bitmap);
  if (load(path)) return path;
  // Otherwise relative to the theme script (rebuild policy).
  std::string theme = engine_.global("$pref::Video::theme").str();
  if (theme.empty()) theme = "default";
  std::string themed =
      Engine::expand_path_from("common/ui/themes/" + theme + "/" + theme + "theme.th", p.bitmap);
  if (load(themed)) return themed;
  note("profile " + name + " bitmap " + p.bitmap + ": not found");
  return {};
}

void Renderer::render(Canvas& canvas, SimObject* content, const std::vector<SimObject*>& dialogs) {
  const Rect screen{0, 0, canvas.width(), canvas.height()};
  layout_.clear();
  if (content) draw_control(canvas, content, screen);
  for (SimObject* d : dialogs)
    if (d) draw_control(canvas, d, screen);
}

void Renderer::draw_control(Canvas& canvas, SimObject* control, const Rect& rect) {
  if (!is_control(engine_, control)) return;
  std::string visible;
  if (has_field(control, "visible", visible) && !parse_bool(visible)) return;
  canvas.push_clip(rect);
  if (!canvas.clip().empty()) {
    layout_.push_back({control->id, rect, canvas.clip()});
    draw_self(canvas, control, rect);
    const Rect own = rect_of(control);
    const auto members = control->members;
    for (std::uint32_t id : members) {
      SimObject* child = engine_.object(id);
      if (!is_control(engine_, child)) continue;
      Rect r = rect_of(child);
      resize_axis(parse_horiz_sizing(field_or(child, "horizSizing", "")), own.width, rect.width, r.x, r.width);
      resize_axis(parse_vert_sizing(field_or(child, "vertSizing", "")), own.height, rect.height, r.y, r.height);
      if (lowered(child->class_name) == "guitextctrl") {
        // Text controls size themselves to their text (autoSizeWidth /
        // autoSizeHeight): the 3.04 menu labels are set from the language
        // file after the .gui was saved, and "Language:" is wider than
        // its .gui extent. The height is the font height plus four, which
        // reproduces the saved 3.04 label extents (rebuild policy).
        const Profile cp = profile_of(child);
        if (cp.auto_size_width || cp.auto_size_height) {
          if (const GftFont* f = font(cp.font_type, cp.font_size)) {
            if (cp.auto_size_width) r.width = f->text_width(child->field("text"));
            if (cp.auto_size_height) r.height = int(f->height) + 4;
          }
        }
      }
      if (lowered(child->class_name) == "guitextlistctrl") {
        // A text list is as tall as its rows (its scroll parent clips it).
        r.height = std::max(r.height, int(child->rows.size()) * row_height(child));
      }
      const Point min = parse_point(field_or(child, "minExtent", "8 8"));
      r.width = std::max(r.width, min.x);
      r.height = std::max(r.height, min.y);
      draw_control(canvas, child, {rect.x + r.x, rect.y + r.y, r.width, r.height});
    }
  }
  canvas.pop_clip();
}

void Renderer::draw_text_line(Canvas& canvas, const Profile& p, const Rect& box, const std::string& text,
                              Color color) {
  if (text.empty()) return;
  const GftFont* f = font(p.font_type, p.font_size);
  if (!f) return;
  const int width = f->text_width(text);
  int x = box.x;
  if (p.justify == Justify::center) x += (box.width - width) / 2;
  else if (p.justify == Justify::right) x += box.width - width;
  canvas.draw_text(*f, x, box.y + text_line_top(box.height, int(f->height)), text, color);
}

std::uint32_t Renderer::hit(int x, int y, Rect* out) const {
  for (auto it = layout_.rbegin(); it != layout_.rend(); ++it) {
    const Rect& v = it->visible;
    if (x >= v.x && y >= v.y && x < v.x + v.width && y < v.y + v.height) {
      if (out) *out = it->rect;
      return it->id;
    }
  }
  return 0;
}

int Renderer::row_height(const SimObject* list) {
  const Profile p = profile_of(list);
  const GftFont* f = font(p.font_type, p.font_size);
  return f ? int(f->height) + 2 : 16;   // rebuild policy
}

void Renderer::draw_self(Canvas& canvas, SimObject* control, const Rect& rect) {
  const std::string cls = lowered(control->class_name);
  auto hook = draw_hooks.find(cls);
  if (hook != draw_hooks.end()) {
    hook->second(canvas, control, rect);
    return;
  }
  const Profile p = profile_of(control);
  if (cls == "guicontrol") {
    if (p.opaque) canvas.fill_rect(rect, p.fill_color);
    if (p.border) canvas.frame_rect(rect, p.border_color);
  } else if (cls == "guitextctrl") {
    if (p.opaque) canvas.fill_rect(rect, p.fill_color);
    draw_text_line(canvas, p, rect, control->field("text"), p.font_color);
  } else if (cls == "guibuttonctrl") {
    draw_button(canvas, control, p, rect);
  } else if (cls == "guitexteditctrl") {
    draw_text_edit(canvas, control, p, rect);
  } else if (cls == "guiwindowctrl") {
    draw_window(canvas, control, p, rect);
  } else if (cls == "guichunkedbitmapctrl") {
    draw_bitmap_ctrl(canvas, control, rect, parse_bool(field_or(control, "tile", "0")));
  } else if (cls == "guibitmapctrl") {
    draw_bitmap_ctrl(canvas, control, rect, parse_bool(field_or(control, "wrap", "0")));
  } else if (cls == "guitextlistctrl") {
    draw_text_list(canvas, control, p, rect);
  } else if (cls == "guimltextctrl") {
    draw_ml_text(canvas, control, p, rect);
  } else if (cls == "guiconsole") {
    // The newest console lines that fit, bottom-aligned (rebuild policy).
    if (const GftFont* f = font(p.font_type, p.font_size)) {
      const int lh = std::max(1, int(f->height));
      const auto& lines = engine_.console_buffer;
      const std::size_t fit = std::size_t(std::max(0, rect.height / lh));
      const std::size_t first = lines.size() > fit ? lines.size() - fit : 0;
      int y = rect.y + rect.height - int(lines.size() - first) * lh;
      for (std::size_t i = first; i < lines.size(); ++i, y += lh)
        canvas.draw_text(*f, rect.x + 2, y, lines[i], p.font_color);
    }
  }
}

// Rows top down, one line each; the "columns" field gives each column's x
// offset, tab-separated text fills them. The selected row is filled with
// the profile's highlight colour and drawn in its selection colour. Row
// height and colours are rebuild policy until a 3.04 capture of a filled
// list exists.
void Renderer::draw_text_list(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect) {
  const GftFont* f = font(p.font_type, p.font_size);
  if (!f) return;
  const int h = row_height(control);
  std::vector<int> cols;
  {
    std::string c = control->field("columns");
    std::size_t at = 0;
    while (at < c.size()) {
      std::size_t sp = c.find(' ', at);
      std::string w = c.substr(at, sp == std::string::npos ? std::string::npos : sp - at);
      if (!w.empty()) cols.push_back(parse_int_field(w));
      if (sp == std::string::npos) break;
      at = sp + 1;
    }
  }
  if (cols.empty()) cols.push_back(0);
  const std::string selected = control->field("selected");
  for (std::size_t i = 0; i < control->rows.size(); ++i) {
    const Rect row{rect.x, rect.y + int(i) * h, rect.width, h};
    const bool sel = !selected.empty() && control->rows[i].second == selected;
    if (sel) canvas.fill_rect(row, p.fill_color_hl);
    const std::string& text = control->rows[i].first;
    std::size_t start = 0;
    for (std::size_t c = 0; c < cols.size(); ++c) {
      std::size_t tab = text.find('\t', start);
      std::string cell = text.substr(start, tab == std::string::npos ? std::string::npos : tab - start);
      const int x0 = row.x + cols[c];
      const int x1 = c + 1 < cols.size() ? row.x + cols[c + 1] : row.x + row.width;
      canvas.push_clip({x0, row.y, x1 - x0, row.height});
      canvas.draw_text(*f, x0, row.y + text_line_top(row.height, int(f->height)), cell,
                       sel ? p.font_color_sel : p.font_color);
      canvas.pop_clip();
      if (tab == std::string::npos) break;
      start = tab + 1;
    }
  }
}

// Plain text, wrapped at spaces to the box width; no markup tags yet.
void Renderer::draw_ml_text(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect) {
  const GftFont* f = font(p.font_type, p.font_size);
  if (!f) return;
  const std::string text = control->field("text");
  int y = rect.y;
  std::string line;
  auto flush = [&] {
    canvas.draw_text(*f, rect.x, y, line, p.font_color);
    y += int(f->height);
    line.clear();
  };
  std::size_t i = 0;
  while (i <= text.size()) {
    std::size_t end = text.find_first_of(" \n", i);
    if (end == std::string::npos) end = text.size();
    const std::string word = text.substr(i, end - i);
    const std::string trial = line.empty() ? word : line + " " + word;
    if (!line.empty() && f->text_width(trial) > rect.width) {
      flush();
      line = word;
    } else {
      line = trial;
    }
    if (end < text.size() && text[end] == '\n') flush();
    i = end + 1;
  }
  if (!line.empty()) flush();
}

void Renderer::draw_button(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect) {
  const bool active = parse_bool(field_or(control, "active", "1"));
  // Cell sets in the 36-cell button arrays, four of nine: normal,
  // highlighted, depressed, inactive. Only normal and inactive are drawn
  // until input exists.
  const std::size_t state = active ? 0 : 3;
  const std::string path = p.has_bitmap_array ? profile_bitmap_path(control) : std::string();
  const BitmapArray* array = path.empty() ? nullptr : bitmap_array(path);
  if (cell_count(array) >= 36) {
    draw_sizable(canvas, *bitmap(path), *array, state * 9, rect, true, Color{0, 0, 0, 0});
  } else {
    if (p.opaque) canvas.fill_rect(rect, active ? p.fill_color : p.fill_color_na);
    if (p.border) canvas.frame_rect(rect, active ? p.border_color : p.border_color_na);
  }
  draw_text_line(canvas, p, rect, control->field("text"), active ? p.font_color : p.font_color_na);
}

void Renderer::draw_text_edit(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect) {
  const std::string path = p.has_bitmap_array ? profile_bitmap_path(control) : std::string();
  const BitmapArray* array = path.empty() ? nullptr : bitmap_array(path);
  const Color fill = p.opaque ? p.fill_color : Color{0, 0, 0, 0};
  Rect inner = rect;
  if (cell_count(array) >= 8) {
    const bool centre = array->cells.size() >= 9;
    // The whole box is filled first: the frame's corner pieces are partly
    // transparent and show the fill colour, not the parent (observed).
    if (fill.a) canvas.fill_rect(rect, fill);
    draw_sizable(canvas, *bitmap(path), *array, 0, rect, centre, Color{0, 0, 0, 0});
    const Rect& left = array->cells[3];
    const Rect& right = array->cells[centre ? 5 : 4];
    inner = {rect.x + left.width, rect.y, rect.width - left.width - right.width, rect.height};
  } else {
    if (fill.a) canvas.fill_rect(rect, fill);
    if (p.border) canvas.frame_rect(rect, p.border_color);
  }
  // The edit buffer is "value" (setText, setValue and typing all use it);
  // a "text" field the .gui saved shows until the buffer is set.
  std::string text = control->field("value");
  if (text.empty()) text = control->field("text");
  if (parse_bool(field_or(control, "password", "0"))) text.assign(text.size(), '*');
  canvas.push_clip(inner);
  Profile left = p;
  left.justify = Justify::left;
  draw_text_line(canvas, left, {inner.x + p.text_offset.x, inner.y, inner.width, inner.height}, text,
                 p.font_color);
  canvas.pop_clip();
}

// Window bitmap arrays (defaultWindow.png 24 cells, macWindow.png and
// windowsWindow.png 23), cell meanings read from the images: four bands of
// title buttons (close, restore, maximize, minimize) in three states
// (normal, pressed, inactive); the title bar's left end, right end and
// middle for the active window, then the same for an inactive one; the
// left edge, right edge, bottom-left corner, bottom edge and bottom-right
// corner; and, in the default theme only, a 64 x 64 background tile.
void Renderer::draw_window(Canvas& canvas, SimObject* control, const Profile& p, const Rect& rect) {
  enum { kClose = 0, kMaximize = 6, kMinimize = 9, kTitle = 12, kLeft = 18, kRight, kBottomLeft,
         kBottom, kBottomRight, kTile };
  const std::string path = p.has_bitmap_array ? profile_bitmap_path(control) : std::string();
  const BitmapArray* array = path.empty() ? nullptr : bitmap_array(path);
  if (cell_count(array) < 23) {
    if (p.opaque) canvas.fill_rect(rect, p.fill_color);
    if (p.border) canvas.frame_rect(rect, p.border_color);
    draw_text_line(canvas, p, {rect.x + p.text_offset.x, rect.y, rect.width - p.text_offset.x, 20},
                   control->field("text"), p.font_color);
    return;
  }
  const Image& image = *bitmap(path);
  const auto& c = array->cells;
  const int right = rect.x + rect.width, bottom = rect.y + rect.height;
  const Rect &tl = c[kTitle], &tr = c[kTitle + 1], &tm = c[kTitle + 2];
  const int title_h = tm.height;
  const Rect &l = c[kLeft], &r = c[kRight], &bl = c[kBottomLeft], &b = c[kBottom], &br = c[kBottomRight];

  const Rect inside{rect.x + l.width, rect.y + title_h, rect.width - l.width - r.width,
                    rect.height - title_h - b.height};
  if (c.size() > kTile && (p.tile || parse_bool(field_or(control, "tile", "0"))))
    canvas.tile_blit(image, c[kTile], inside);
  else if (p.opaque)
    canvas.fill_rect(inside, p.fill_color);

  canvas.blit(image, tl, rect.x, rect.y);
  canvas.blit(image, tr, right - tr.width, rect.y);
  canvas.smooth_stretch_blit(image, tm, {rect.x + tl.width, rect.y, rect.width - tl.width - tr.width, title_h});
  canvas.smooth_stretch_blit(image, l, {rect.x, rect.y + title_h, l.width, rect.height - title_h - bl.height});
  canvas.smooth_stretch_blit(image, r, {right - r.width, rect.y + title_h, r.width, rect.height - title_h - br.height});
  canvas.blit(image, bl, rect.x, bottom - bl.height);
  canvas.blit(image, br, right - br.width, bottom - br.height);
  canvas.smooth_stretch_blit(image, b, {rect.x + bl.width, bottom - b.height, rect.width - bl.width - br.width, b.height});

  // Title buttons, right to left, centred in the title bar (rebuild policy).
  int x = right - tr.width;
  for (auto [flag, cell, fallback] : {std::tuple{"canClose", kClose, "1"}, std::tuple{"canMaximize", kMaximize, "1"},
                                      std::tuple{"canMinimize", kMinimize, "1"}}) {
    if (!parse_bool(field_or(control, flag, fallback))) continue;
    const Rect& button = c[std::size_t(cell)];
    x -= button.width;
    canvas.blit(image, button, x, rect.y + (title_h - button.height) / 2);
  }

  const Rect title{rect.x + tl.width, rect.y, x - rect.x - tl.width, title_h};
  canvas.push_clip(title);
  const GftFont* f = font(p.font_type, p.font_size);
  const std::string text = control->field("text");
  if (f && !text.empty()) {
    const int width = f->text_width(text);
    int tx = rect.x + p.text_offset.x;
    if (p.justify == Justify::center) tx = rect.x + (rect.width - width) / 2;
    else if (p.justify == Justify::right) tx = right - p.text_offset.x - width;
    canvas.draw_text(*f, tx, rect.y + p.text_offset.y, text, p.font_color);
  }
  canvas.pop_clip();
}

void Renderer::draw_bitmap_ctrl(Canvas& canvas, SimObject* control, const Rect& rect, bool tile) {
  std::string name = control->field("bitmap");
  if (parse_bool(field_or(control, "useVariable", "0"))) {
    const std::string var = control->field("variable");
    if (!var.empty()) name = engine_.global(var).str();
  }
  if (name.empty()) return;
  const std::string path = Engine::expand_path_from(control->source, name);
  const Image* image = bitmap(path);
  if (!image) {
    note("bitmap " + path + ": not found or not a PNG");
    return;
  }
  const Rect whole{0, 0, image->width, image->height};
  if (tile) canvas.tile_blit(*image, whole, rect);
  else canvas.stretch_blit(*image, whole, rect);
}

}  // namespace Torque::Gui
