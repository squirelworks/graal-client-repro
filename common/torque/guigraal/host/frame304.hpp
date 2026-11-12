#pragma once

// One frame of the windowed 3.04 program, without the window: route the
// window's keys and clicks into the engine, advance 50 ms, tick the game,
// and draw the canvas content, the dialogs and the game into an image.

#include <string>
#include <vector>

#include "../../console/engine/engine.hpp"
#include "../../gui/canvas.hpp"
#include "../../gui/render.hpp"
#include "../guigraal304.hpp"
#include "window.hpp"

namespace Torque {

class Frame304 {
 public:
  Frame304(Engine& engine, GuiGraal304& graal, int width, int height);

  // Keys go to Engine::process_input, clicks to the control under them.
  // Returns false on a close request.
  bool handle(const WindowEvent& event);
  // Advance the engine 50 ms, tick the game, draw.
  void step();
  void draw();
  const Gui::Image& image() const { return canvas_.surface(); }
  Gui::Renderer& renderer() { return renderer_; }
  // What each routed event did, for the trace.
  std::vector<std::string> log;

 private:
  Engine& engine_;
  GuiGraal304& graal_;
  Gui::Canvas canvas_;
  Gui::Renderer renderer_;
};

// The canvas size from $pref::Video::resolution ("800 600 24"), else 800 x 600.
void canvas_size_304(const Engine& engine, int& width, int& height);

} // namespace Torque
