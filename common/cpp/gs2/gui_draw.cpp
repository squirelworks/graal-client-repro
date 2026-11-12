// Drawing the GS2 GUI through a Painter (plan step B4).

#include "gui_draw.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <sstream>

namespace gs2::gui {

namespace {

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

Rect intersect(const Rect& a, const Rect& b) {
  const int x0 = std::max(a.x, b.x), y0 = std::max(a.y, b.y);
  const int x1 = std::min(a.x + a.w, b.x + b.w), y1 = std::min(a.y + a.h, b.y + b.h);
  if (x1 <= x0 || y1 <= y0) return {x0, y0, 0, 0};
  return {x0, y0, x1 - x0, y1 - y0};
}

bool truthy(const std::string& s) { return lower(s) == "true" || std::strtod(s.c_str(), nullptr) != 0; }

// One profile field: the profile itself, then GuiDefaultProfile.
struct Lookup {
  ControlPtr own, fallback;
  bool get(const std::string& key, std::string& out) const {
    for (const auto& p : {own, fallback})
      if (p)
        if (auto v = p->child(key)) {
          out = v->string();
          return true;
        }
    return false;
  }
};

void frame(Painter& p, const Rect& r, Color c) {
  if (r.w <= 0 || r.h <= 0) return;
  p.fill({r.x, r.y, r.w, 1}, c);
  p.fill({r.x, r.y + r.h - 1, r.w, 1}, c);
  p.fill({r.x, r.y, 1, r.h}, c);
  p.fill({r.x + r.w - 1, r.y, 1, r.h}, c);
}

// A sizable frame from nine cells from `first` (corners kept, edges and
// centre stretched); with eight cells the centre is left out.
void sizable(Painter& p, const std::string& file, const std::vector<Rect>& cells, std::size_t first,
             std::size_t count, const Rect& r) {
  if (cells.size() < first + count) return;
  const Rect* c = &cells[first];
  const Rect tl = c[0], tr = c[2];
  const Rect bl = count == 9 ? c[6] : c[5], br = count == 9 ? c[8] : c[7];
  const Rect top = c[1], bottom = count == 9 ? c[7] : c[6];
  const Rect left = c[3], right = count == 9 ? c[5] : c[4];
  const int midW = std::max(0, r.w - tl.w - tr.w), midH = std::max(0, r.h - tl.h - bl.h);
  p.bitmap(file, tl, {r.x, r.y, tl.w, tl.h});
  p.bitmap(file, top, {r.x + tl.w, r.y, midW, top.h});
  p.bitmap(file, tr, {r.x + r.w - tr.w, r.y, tr.w, tr.h});
  p.bitmap(file, left, {r.x, r.y + tl.h, left.w, midH});
  if (count == 9) p.bitmap(file, c[4], {r.x + left.w, r.y + tl.h, std::max(0, r.w - left.w - right.w), midH});
  p.bitmap(file, right, {r.x + r.w - right.w, r.y + tr.h, right.w, midH});
  p.bitmap(file, bl, {r.x, r.y + r.h - bl.h, bl.w, bl.h});
  p.bitmap(file, bottom, {r.x + bl.w, r.y + r.h - bottom.h, std::max(0, r.w - bl.w - br.w), bottom.h});
  p.bitmap(file, br, {r.x + r.w - br.w, r.y + r.h - br.h, br.w, br.h});
}

// One line of text in a box, justified, centred vertically: the line box
// is the font height less two rows (common/torque/gui README, "Drawing").
void line(Painter& p, const Style& st, const Rect& box, const std::string& s, Color c) {
  if (s.empty()) return;
  const int w = p.textWidth(s, st.fontType, st.fontSize);
  const int h = p.fontHeight(st.fontType, st.fontSize);
  int x = box.x + st.textOffsetX;
  if (st.justify == "center") x = box.x + (box.w - w) / 2;
  else if (st.justify == "right") x = box.x + box.w - w - st.textOffsetX;
  const int y = box.y + (box.h - (h - 2)) / 2 + st.textOffsetY;
  p.text(x, y, s, st.fontType, st.fontSize, c);
}

std::vector<int> columns(const Control& c) {
  std::vector<int> out;
  std::istringstream in(c.prop("columns", "0"));
  int v;
  while (in >> v) out.push_back(v);
  if (out.empty()) out.push_back(0);
  return out;
}

// Markup the multi-line text controls carry (`<font:...>`, `<br>`); here
// tags are dropped and `<br>` breaks the line.
std::vector<std::string> plainLines(const std::string& s) {
  std::vector<std::string> lines(1);
  for (std::size_t i = 0; i < s.size(); ++i) {
    if (s[i] == '<') {
      const auto end = s.find('>', i);
      if (end != std::string::npos) {
        if (lower(s.substr(i, end - i + 1)) == "<br>") lines.emplace_back();
        i = end;
        continue;
      }
    }
    if (s[i] == '\n') lines.emplace_back();
    else lines.back() += s[i];
  }
  return lines;
}

class Drawer {
 public:
  Drawer(Screen& s, Painter& p) : s_(s), p_(p) {}

  void draw(const Control& c, const Rect& clip) {
    if (!c.isControl() || !c.flag("visible", true)) return;
    const Rect r = s_.rectOf(c);
    const Rect cl = intersect(clip, r);
    if (cl.w <= 0 || cl.h <= 0) return;
    p_.setClip(cl);
    self(c, r);
    for (const auto& k : c.controls()) draw(*k, cl);
  }

 private:
  void self(const Control& c, const Rect& r) {
    const Style st = styleOf(s_, c);
    const std::string t = lower(c.type());
    const bool active = c.flag("active", true);
    if (t == "guishowimgctrl" || t == "guigraalctrl" || t == "guigraal3dctrl") {
      p_.engineControl(c, r);
      return;
    }
    if (t == "guibitmapctrl" || t == "guichunkedbitmapctrl") {
      bitmapCtrl(c, r);
      return;
    }
    if (t == "guibuttonctrl") {
      button(c, st, r, active);
      return;
    }
    if (t == "guicheckboxctrl" || t == "guiradioctrl") {
      check(c, st, r, active);
      return;
    }
    if (t == "guitexteditctrl" || t == "guimltexteditctrl") {
      textEdit(c, st, r, active);
      return;
    }
    background(st, r);
    if (t == "guitextctrl") {
      line(p_, st, r, c.prop("text"), active ? st.fontColor : st.fontColorNA);
    } else if (t == "guimltextctrl") {
      int y = r.y;
      const int h = p_.fontHeight(st.fontType, st.fontSize);
      for (const auto& l : plainLines(c.prop("text"))) {
        p_.text(r.x, y, l, st.fontType, st.fontSize, st.fontColor);
        y += h;
      }
    } else if (t == "guitextlistctrl") {
      textList(c, st, r);
    } else if (t == "guitabctrl") {
      // One tab per row, `tabwidth` wide, the selected one filled.
      const int tw = std::max(1, static_cast<int>(c.numProp("tabwidth", 64)));
      Style s2 = st;
      s2.justify = "center";
      for (std::size_t i = 0; i < c.rows.size(); ++i) {
        const Rect tab{r.x + static_cast<int>(i) * tw, r.y, tw, r.h};
        if (static_cast<int>(i) == c.selectedRow) p_.fill(tab, st.fillHL);
        frame(p_, tab, st.borderColor);
        line(p_, s2, tab, c.rows[i].text, st.fontColor);
      }
    } else if (t == "guipopupmenuctrl" || t == "guipopupeditctrl") {
      if (!st.opaque) p_.fill(r, st.fill);
      frame(p_, r, st.borderColor);
      Style s2 = st;
      s2.textOffsetX = std::max(st.textOffsetX, 3);
      line(p_, s2, r, c.prop("text"), st.fontColor);
    } else if (t == "guiwindowctrl") {
      if (!st.opaque) p_.fill(r, st.fill);
      frame(p_, r, st.borderColor);
      const int th = p_.fontHeight(st.fontType, st.fontSize) + 4;
      line(p_, st, {r.x, r.y, r.w, th}, c.prop("text"), st.fontColor);
    } else if (t == "guiprogressctrl") {
      const double v = std::clamp(c.numProp("value", 0), 0.0, 1.0);
      p_.fill({r.x, r.y, static_cast<int>(r.w * v), r.h}, st.fillHL);
    } else if (t == "guisliderctrl") {
      std::istringstream in(c.prop("range", "0 1"));
      double lo = 0, hi = 1;
      in >> lo >> hi;
      const double v = hi > lo ? std::clamp((c.numProp("value", lo) - lo) / (hi - lo), 0.0, 1.0) : 0;
      p_.fill({r.x, r.y + r.h / 2, r.w, 1}, st.fontColor);
      p_.fill({r.x + static_cast<int>((r.w - 6) * v), r.y, 6, r.h}, st.fontColor);
    }
  }

  void background(const Style& st, const Rect& r) {
    if (st.opaque) p_.fill(r, st.fill);
    if (st.border) frame(p_, r, st.borderColor);
  }

  void bitmapCtrl(const Control& c, const Rect& r) {
    const std::string f = c.prop("bitmap");
    int w = 0, h = 0;
    if (f.empty() || !p_.bitmapSize(f, w, h)) return;
    if (c.flag("tile") || c.flag("wrap")) {
      for (int y = r.y; y < r.y + r.h; y += h)
        for (int x = r.x; x < r.x + r.w; x += w)
          p_.bitmap(f, {0, 0, w, h}, {x, y, w, h});
    } else {
      p_.bitmap(f, {0, 0, w, h}, r);
    }
  }

  void button(const Control& c, const Style& st, const Rect& r, bool active) {
    const std::string f = st.bitmap;
    const auto cells = f.empty() ? std::vector<Rect>() : p_.cells(f);
    if (cells.size() >= 36) {
      sizable(p_, f, cells, active ? 0 : 27, 9, r);  // normal, or the inactive set
    } else {
      p_.fill(r, active ? st.fill : st.fillNA);
      frame(p_, r, st.borderColor);
    }
    Style s2 = st;
    s2.justify = "center";
    line(p_, s2, r, c.prop("text"), active ? st.fontColor : st.fontColorNA);
  }

  void check(const Control& c, const Style& st, const Rect& r, bool active) {
    const std::string f = st.bitmap;
    const auto cells = f.empty() ? std::vector<Rect>() : p_.cells(f);
    int boxW = 0;
    const bool on = c.flag("checked");
    if (cells.size() >= 4) {
      const Rect cell = cells[(on ? 1 : 0) + (active ? 0 : 2)];
      p_.bitmap(f, cell, {r.x, r.y + (r.h - cell.h) / 2, cell.w, cell.h});
      boxW = cell.w;
    } else {
      boxW = std::min(r.h, 12);
      const Rect box{r.x, r.y + (r.h - boxW) / 2, boxW, boxW};
      frame(p_, box, st.fontColor);
      if (on) p_.fill({box.x + 3, box.y + 3, box.w - 6, box.h - 6}, st.fontColor);
    }
    Style s2 = st;
    s2.justify = "left";
    s2.textOffsetX = 0;
    line(p_, s2, {r.x + boxW + 3, r.y, r.w - boxW - 3, r.h}, c.prop("text"), active ? st.fontColor : st.fontColorNA);
  }

  void textEdit(const Control& c, const Style& st, const Rect& r, bool active) {
    p_.fill(r, active ? st.fill : st.fillNA);
    const std::string f = st.bitmap;
    const auto cells = f.empty() ? std::vector<Rect>() : p_.cells(f);
    int left = 0;
    if (cells.size() >= 8) {
      sizable(p_, f, cells, 0, 8, r);
      left = cells[3].w;
    } else if (st.border) {
      frame(p_, r, st.borderColor);
    }
    std::string s = c.prop("text");
    if (c.flag("password")) s.assign(s.size(), '*');
    Style s2 = st;
    s2.justify = "left";
    s2.textOffsetX = left + st.textOffsetX;
    line(p_, s2, r, s, active ? st.fontColor : st.fontColorNA);
    if (s_.firstResponder().get() == &c) {
      const std::size_t cur = std::min(c.cursor, s.size());
      const int x = r.x + s2.textOffsetX + p_.textWidth(s.substr(0, cur), st.fontType, st.fontSize);
      const int h = p_.fontHeight(st.fontType, st.fontSize);
      p_.fill({x, r.y + (r.h - h) / 2, 1, h}, st.cursorColor);
    }
  }

  void textList(const Control& c, const Style& st, const Rect& r) {
    const int h = std::max(1, static_cast<int>(c.numProp("rowHeight", p_.fontHeight(st.fontType, st.fontSize))));
    const auto cols = columns(c);
    int y = r.y;
    for (std::size_t i = 0; i < c.rows.size(); ++i, y += h) {
      const bool sel = static_cast<int>(i) == c.selectedRow;
      if (sel) p_.fill({r.x, y, r.w, h}, st.fillHL);
      std::istringstream in(c.rows[i].text);
      std::string field;
      for (std::size_t k = 0; std::getline(in, field, '\t'); ++k) {
        if (k >= cols.size()) break;
        p_.text(r.x + cols[k] + st.textOffsetX, y, field, st.fontType, st.fontSize, sel ? st.fontColorSel : st.fontColor);
      }
    }
  }

  Screen& s_;
  Painter& p_;
};

}  // namespace

Color parseColor(const std::string& s) {
  std::istringstream in(s);
  int v[4] = {0, 0, 0, 255};
  for (int i = 0; i < 4 && (in >> v[i]); ++i) {
  }
  auto cl = [](int x) { return static_cast<std::uint8_t>(std::clamp(x, 0, 255)); };
  return {cl(v[0]), cl(v[1]), cl(v[2]), cl(v[3])};
}

Style styleOf(const Screen& s, const Control& c) {
  Lookup l{s.find(c.prop("profile", "GuiDefaultProfile")), s.find("GuiDefaultProfile")};
  Style st;
  std::string v;
  if (l.get("opaque", v)) st.opaque = truthy(v);
  if (l.get("fillColor", v)) st.fill = parseColor(v);
  st.fillHL = st.fillNA = st.fill;
  if (l.get("fillColorHL", v)) st.fillHL = parseColor(v);
  if (l.get("fillColorNA", v)) st.fillNA = parseColor(v);
  if (l.get("border", v)) st.border = static_cast<int>(std::strtod(v.c_str(), nullptr));
  if (l.get("borderColor", v)) st.borderColor = parseColor(v);
  if (l.get("fontType", v)) st.fontType = v;
  if (l.get("fontSize", v)) st.fontSize = static_cast<int>(std::strtod(v.c_str(), nullptr));
  if (l.get("fontColor", v)) st.fontColor = parseColor(v);
  st.fontColorHL = st.fontColor;
  if (l.get("fontColorHL", v)) st.fontColorHL = parseColor(v);
  if (l.get("fontColorNA", v)) st.fontColorNA = parseColor(v);
  if (l.get("fontColorSEL", v)) st.fontColorSel = parseColor(v);
  st.cursorColor = st.fontColor;
  if (l.get("cursorColor", v)) st.cursorColor = parseColor(v);
  if (l.get("bitmap", v)) st.bitmap = v;
  if (l.get("justify", v)) st.justify = lower(v);
  if (l.get("textOffset", v)) {
    std::istringstream in(v);
    in >> st.textOffsetX >> st.textOffsetY;
  }
  return st;
}

void drawScreen(Screen& s, Painter& p) {
  const Rect all{0, 0, s.width(), s.height()};
  Drawer d(s, p);
  if (auto c = s.content()) d.draw(*c, all);
  for (const auto& dlg : s.dialogs()) d.draw(*dlg, all);
  p.setClip(all);
}

}  // namespace gs2::gui
