// The GS2 GUI (common/cpp/gs2/gui.hpp, plan B4) on the engine library:
// a Painter on the launcher's draw slots, the canvas control that draws the
// GS2 screen, and the key and mouse forwarding into it.
#pragma once

#include "canvas.hpp"
#include "graalengine.h"
#include "gui_draw.hpp"

#include <map>
#include <memory>
#include <functional>
#include <string>
#include <vector>

namespace graalengine {

// Finds the pictures the menus name (`defaultButton.png`, `graalv4screen`)
// in the install: levels3d/gui, then levels/gui, then the install root,
// with the name's case ignored and, when the name has no extension,
// .png, .jpg, .gif and .bmp tried in turn. Loaded pictures stay cached as
// engine-owned textures for the launcher's slots.
class TextureCache {
 public:
  explicit TextureCache(std::string installDir) : dir_(std::move(installDir)) {}

  struct Entry {
    graal_texture tex{};
    std::string name;
    std::vector<uint32_t> pixels;           // 0xAARRGGBB
    std::vector<gs2::gui::Rect> cells;      // the bitmap array, empty when none
    bool cellsRead = false;
  };
  // Null when no file is found or it does not decode.
  Entry* get(const std::string& name);
  std::string pathOf(const std::string& name) const;

 private:
  std::string dir_;
  std::map<std::string, std::unique_ptr<Entry>> byName_;  // lower-cased; null when missing
};

// gs2::gui::Painter on the slots: SetClippingRectangle, FillScreenRectangle,
// DrawText, GetTextWidth, GetTextHeight, DrawGraphics and
// DrawGraphicsStretched.
class SlotPainter : public gs2::gui::Painter {
 public:
  explicit SlotPainter(TextureCache& cache) : cache_(cache) {}
  void setClip(const gs2::gui::Rect& r) override;
  void fill(const gs2::gui::Rect& r, gs2::gui::Color c) override;
  void text(int x, int y, const std::string& s, const std::string& font, int size, gs2::gui::Color c) override;
  int textWidth(const std::string& s, const std::string& font, int size) override;
  int fontHeight(const std::string& font, int size) override;
  bool bitmapSize(const std::string& file, int& w, int& h) override;
  std::vector<gs2::gui::Rect> cells(const std::string& file) override;
  void bitmap(const std::string& file, const gs2::gui::Rect& src, const gs2::gui::Rect& dst) override;
  void engineControl(const gs2::gui::Control& c, const gs2::gui::Rect& r) override {
    if (onEngineControl) onEngineControl(c, r);
  }
  // The engine-drawn controls (GuiGraalCtrl, GuiShowImgCtrl): the session's
  // playfield draws here.
  std::function<void(const gs2::gui::Control&, const gs2::gui::Rect&)> onEngineControl;

 private:
  TextureCache& cache_;
};

// Torque's key name for a Windows virtual-key code ("a", "up", "return",
// "F2"), empty for keys the menus never bind.
std::string torqueKeyName(int vk);

// The canvas content while the GS2 screen is up: one full-screen control
// that draws the screen's content and dialogs and passes input to it.
class ScreenControl : public Control {
 public:
  ScreenControl(gs2::gui::Screen& screen, gs2::gui::Painter& painter)
      : Control("GS2Screen"), screen_(screen), painter_(painter) {}
  void resize(int w, int h) override;

 protected:
  void onRender(const graal_rect& clip) override;
  bool onInput(const InputEvent& ev) override;

 private:
  gs2::gui::Screen& screen_;
  gs2::gui::Painter& painter_;
};

}  // namespace graalengine
