// GuiTextListCtrl rows for the 3.04 scripts and GuiGraalCtrl (stage 4).
//
// The server list (ServerList in ServerListGui.gui) and the player list are
// text lists: the game adds rows with addRow (Graal_analysis
// torque/304-net.md), the scripts read the selection and get onSelect.
// Drawing the list is the GUI stage; this is the data the control keeps.
//
// Rebuild policy, not read from the original:
// - A row is (id, text); text holds the columns with a tab between them.
// - setSelectedById and setSelectedRow call the script's onSelect(id, text),
//   which is how ServerList::onSelect reaches Adventure.selectServer.
// - Sorting compares the given column without case; equal rows keep order.

#include <algorithm>

#include "engine.hpp"

namespace Torque {
namespace {

std::string column(const std::string& text, std::size_t col) {
  std::size_t start = 0;
  for (std::size_t i = 0; i < col; ++i) {
    const std::size_t tab = text.find('\t', start);
    if (tab == std::string::npos) return std::string();
    start = tab + 1;
  }
  const std::size_t end = text.find('\t', start);
  return text.substr(start, end == std::string::npos ? std::string::npos : end - start);
}

long index_of(const SimObject* o, const std::string& id) {
  for (std::size_t i = 0; i < o->rows.size(); ++i)
    if (o->rows[i].second == id) return static_cast<long>(i);
  return -1;
}

std::string select(Engine& e, SimObject* o, long index) {
  if (index < 0 || static_cast<std::size_t>(index) >= o->rows.size()) {
    o->set_field("selected", "");
    return std::string();
  }
  const std::string id = o->rows[static_cast<std::size_t>(index)].second;
  const std::string text = o->rows[static_cast<std::size_t>(index)].first;
  o->set_field("selected", id);
  e.call_method(o, "onSelect", {id, text});
  return std::string();
}

} // namespace

void register_text_list_304(Engine& e) {
  const char* tl = "GuiTextListCtrl";
  // rows holds (text, id), the layout GuiPopUpMenuCtrl uses.
  e.add_function(tl, "clear", 2, 2, "list.clear()", [](Engine&, SimObject* o, Args&) {
    if (o) { o->rows.clear(); o->set_field("selected", ""); }
    return std::string();
  });
  e.add_function(tl, "addRow", 4, 5, "list.addRow(id, text, index = -1)", [](Engine&, SimObject* o, Args& a) {
    if (!o) return std::string("-1");
    long at = a.size() > 4 ? static_cast<long>(static_cast<std::int32_t>(parse_int(a[4]))) : -1;
    if (at < 0 || static_cast<std::size_t>(at) > o->rows.size()) at = static_cast<long>(o->rows.size());
    o->rows.insert(o->rows.begin() + at, {a[3], format_int(parse_int(a[2]))});
    return std::to_string(at);
  });
  e.add_function(tl, "setRowById", 4, 4, "list.setRowById(id, text)", [](Engine&, SimObject* o, Args& a) {
    const long i = o ? index_of(o, format_int(parse_int(a[2]))) : -1;
    if (i >= 0) o->rows[static_cast<std::size_t>(i)].first = a[3];
    return std::string();
  });
  e.add_function(tl, "removeRowById", 3, 3, "list.removeRowById(id)", [](Engine&, SimObject* o, Args& a) {
    const std::string id = format_int(parse_int(a[2]));
    const long i = o ? index_of(o, id) : -1;
    if (i >= 0) {
      o->rows.erase(o->rows.begin() + i);
      if (o->field("selected") == id) o->set_field("selected", "");
    }
    return std::string();
  });
  e.add_function(tl, "removeRow", 3, 3, "list.removeRow(index)", [](Engine&, SimObject* o, Args& a) {
    const long i = static_cast<std::int32_t>(parse_int(a[2]));
    if (o && i >= 0 && static_cast<std::size_t>(i) < o->rows.size()) {
      if (o->field("selected") == o->rows[static_cast<std::size_t>(i)].second) o->set_field("selected", "");
      o->rows.erase(o->rows.begin() + i);
    }
    return std::string();
  });
  e.add_function(tl, "rowCount", 2, 2, "list.rowCount()", [](Engine&, SimObject* o, Args&) {
    return std::to_string(o ? o->rows.size() : 0);
  });
  e.add_function(tl, "getRowId", 3, 3, "list.getRowId(index)", [](Engine&, SimObject* o, Args& a) {
    const long i = static_cast<std::int32_t>(parse_int(a[2]));
    if (o && i >= 0 && static_cast<std::size_t>(i) < o->rows.size()) return o->rows[static_cast<std::size_t>(i)].second;
    return std::string("-1");
  });
  e.add_function(tl, "getRowText", 3, 3, "list.getRowText(index)", [](Engine&, SimObject* o, Args& a) {
    const long i = static_cast<std::int32_t>(parse_int(a[2]));
    if (o && i >= 0 && static_cast<std::size_t>(i) < o->rows.size()) return o->rows[static_cast<std::size_t>(i)].first;
    return std::string();
  });
  e.add_function(tl, "getRowTextById", 3, 3, "list.getRowTextById(id)", [](Engine&, SimObject* o, Args& a) {
    const long i = o ? index_of(o, format_int(parse_int(a[2]))) : -1;
    return i >= 0 ? o->rows[static_cast<std::size_t>(i)].first : std::string();
  });
  e.add_function(tl, "getRowNumById", 3, 3, "list.getRowNumById(id)", [](Engine&, SimObject* o, Args& a) {
    return std::to_string(o ? index_of(o, format_int(parse_int(a[2]))) : -1);
  });
  e.add_function(tl, "findTextIndex", 3, 3, "list.findTextIndex(text)", [](Engine&, SimObject* o, Args& a) {
    if (o)
      for (std::size_t i = 0; i < o->rows.size(); ++i)
        if (lower(o->rows[i].first) == lower(a[2])) return std::to_string(i);
    return std::string("-1");
  });
  e.add_function(tl, "getSelectedId", 2, 2, "list.getSelectedId()", [](Engine&, SimObject* o, Args&) {
    const std::string v = o ? o->field("selected") : std::string();
    return v.empty() ? std::string("-1") : v;
  });
  e.add_function(tl, "setSelectedById", 3, 3, "list.setSelectedById(id)", [](Engine& en, SimObject* o, Args& a) {
    return o ? select(en, o, index_of(o, format_int(parse_int(a[2])))) : std::string();
  });
  e.add_function(tl, "setSelectedRow", 3, 3, "list.setSelectedRow(index)", [](Engine& en, SimObject* o, Args& a) {
    return o ? select(en, o, static_cast<std::int32_t>(parse_int(a[2]))) : std::string();
  });
  e.add_function(tl, "clearSelection", 2, 2, "list.clearSelection()", [](Engine&, SimObject* o, Args&) {
    if (o) o->set_field("selected", "");
    return std::string();
  });
  e.add_function(tl, "sort", 3, 4, "list.sort(column, increasing = 1)", [](Engine&, SimObject* o, Args& a) {
    if (!o) return std::string();
    const std::size_t col = parse_int(a[2]);
    const bool up = a.size() < 4 || parse_int(a[3]) != 0;
    std::stable_sort(o->rows.begin(), o->rows.end(), [&](const auto& x, const auto& y) {
      const std::string l = lower(column(x.first, col)), r = lower(column(y.first, col));
      return up ? l < r : r < l;
    });
    return std::string();
  });
  e.add_function(tl, "sortNumerical", 3, 4, "list.sortNumerical(column, increasing = 1)", [](Engine&, SimObject* o, Args& a) {
    if (!o) return std::string();
    const std::size_t col = parse_int(a[2]);
    const bool up = a.size() < 4 || parse_int(a[3]) != 0;
    std::stable_sort(o->rows.begin(), o->rows.end(), [&](const auto& x, const auto& y) {
      const double l = parse_float(column(x.first, col)), r = parse_float(column(y.first, col));
      return up ? l < r : r < l;
    });
    return std::string();
  });
}

} // namespace Torque
