#include "frame304.hpp"

#include <sstream>

#include "../../gui/mouse.hpp"

namespace Torque {

Frame304::Frame304(Engine& engine, GuiGraal304& graal, int width, int height)
    : engine_(engine), graal_(graal), canvas_(width, height), renderer_(engine) {
  // GuiGraalCtrl draws the game's last frame into its box, scaled to it.
  renderer_.draw_hooks["guigraalctrl"] = [this](Gui::Canvas& c, SimObject*, const Gui::Rect& rect) {
    int w = 0, h = 0;
    const std::uint32_t* px = graal_.playing() ? graal_.game().frame(w, h) : nullptr;
    if (!px || w <= 0 || h <= 0 || rect.width <= 0 || rect.height <= 0) {
      c.fill_rect(rect, Gui::Color{0, 0, 0, 255});
      return;
    }
    for (int y = 0; y < rect.height; ++y) {
      const int sy = y * h / rect.height;
      for (int x = 0; x < rect.width; ++x) {
        const std::uint32_t p = px[std::size_t(sy) * w + x * w / rect.width];
        c.blend_pixel(rect.x + x, rect.y + y,
                      Gui::Color{std::uint8_t(p >> 16), std::uint8_t(p >> 8), std::uint8_t(p), 255});
      }
    }
  };
}

bool Frame304::handle(const WindowEvent& ev) {
  switch (ev.kind) {
    case WindowEvent::Kind::close:
      return false;
    case WindowEvent::Kind::key: {
      const bool took = engine_.process_input(ev.key);
      if (!took && ev.key.make && !ev.key.repeat) log.push_back("key " + ev.key.key + ": not taken");
      return true;
    }
    case WindowEvent::Kind::click: {
      draw();  // a script may have changed the content since the last frame
      const std::string what = Gui::mouse_click(engine_, renderer_, ev.x, ev.y, ev.double_click);
      log.push_back("click " + std::to_string(ev.x) + "," + std::to_string(ev.y) +
                    (ev.double_click ? " double" : "") + ": " + (what.empty() ? "nothing" : what));
      return true;
    }
  }
  return true;
}

void Frame304::draw() {
  canvas_.clear(Gui::Color{0, 0, 0, 255});
  SimObject* canvas = engine_.find_object("Canvas");
  SimObject* content = canvas ? engine_.find_object(canvas->field("content")) : nullptr;
  std::vector<SimObject*> dialogs;
  for (const DialogLayer& d : engine_.dialogs)
    if (SimObject* o = engine_.object(d.control)) dialogs.push_back(o);
  renderer_.render(canvas_, content, dialogs);
  // what the renderer could not draw (a missing font or bitmap), once each
  for (; notes_seen_ < renderer_.notes.size(); ++notes_seen_)
    engine_.trace.push_back("gui: " + renderer_.notes[notes_seen_]);
}

void Frame304::step() {
  engine_.advance(50);
  graal_.tick(true);
  draw();
}

void canvas_size_304(const Engine& engine, int& width, int& height) {
  width = 800;
  height = 600;
  std::istringstream in(engine.global("$pref::Video::resolution").str());
  int w = 0, h = 0;
  if (in >> w >> h && w >= 320 && h >= 240 && w <= 4096 && h <= 4096) {
    width = w;
    height = h;
  }
}

} // namespace Torque
