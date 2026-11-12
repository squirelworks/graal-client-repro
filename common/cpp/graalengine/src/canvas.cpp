#include "canvas.hpp"

#include "host.hpp"

#include <algorithm>

namespace graalengine {

namespace {

graal_rect intersect(const graal_rect& a, const graal_rect& b) {
  const int x0 = std::max(a.x, b.x);
  const int y0 = std::max(a.y, b.y);
  const int x1 = std::min(a.x + a.w, b.x + b.w);
  const int y1 = std::min(a.y + a.h, b.y + b.h);
  if (x1 <= x0 || y1 <= y0) return {x0, y0, 0, 0};
  return {x0, y0, x1 - x0, y1 - y0};
}

bool contains(const graal_rect& r, int x, int y) {
  return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
}

void setClip(const graal_rect& r) { host::SetClippingRectangle(r.x, r.y, r.w, r.h); }

}  // namespace

void Control::add(std::shared_ptr<Control> child) {
  if (child) children_.push_back(std::move(child));
}

bool Control::remove(const Control* child) {
  auto it = std::find_if(children_.begin(), children_.end(),
                         [&](const std::shared_ptr<Control>& c) { return c.get() == child; });
  if (it == children_.end()) return false;
  children_.erase(it);
  return true;
}

void Control::resize(int w, int h) {
  rect_.x = 0;
  rect_.y = 0;
  rect_.w = w;
  rect_.h = h;
}

void Control::renderTree(const graal_rect& parentClip) {
  if (!visible_) return;
  const graal_rect clip = intersect(parentClip, rect_);
  if (clip.w <= 0 || clip.h <= 0) return;
  setClip(clip);
  onRender(clip);
  for (const auto& child : children_) child->renderTree(clip);
}

bool Control::dispatch(const InputEvent& ev) {
  if (!visible_) return false;
  const bool mouse = ev.kind != InputEvent::KeyDown && ev.kind != InputEvent::KeyUp;
  if (mouse && !contains(rect_, ev.x, ev.y)) return false;
  // Front to back: the last child drawn is the first asked.
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    if ((*it)->dispatch(ev)) return true;
  }
  return onInput(ev);
}

int Canvas::screenWidth() const {
  const int w = host::GetScreenWidth();
  return w > 0 ? w : 640;
}

int Canvas::screenHeight() const {
  const int h = host::GetScreenHeight();
  return h > 0 ? h : 480;
}

void Canvas::setContentControl(std::shared_ptr<Control> content) {
  content_ = std::move(content);
  if (content_) content_->resize(screenWidth(), screenHeight());
}

void Canvas::pushDialog(std::shared_ptr<Control> dialog) {
  if (!dialog) return;
  dialog->resize(screenWidth(), screenHeight());
  dialogs_.push_back(std::move(dialog));
}

bool Canvas::popDialog(const Control* dialog) {
  auto it = std::find_if(dialogs_.begin(), dialogs_.end(),
                         [&](const std::shared_ptr<Control>& c) { return c.get() == dialog; });
  if (it == dialogs_.end()) return false;
  dialogs_.erase(it);
  return true;
}

void Canvas::renderFrame(bool draw) {
  ++frames_;
  const int w = screenWidth();
  const int h = screenHeight();
  const graal_rect screen{0, 0, w, h};
  setClip(screen);
  // Fit the main controls to the screen (a resize between frames).
  if (content_ && (content_->rect().w != w || content_->rect().h != h)) content_->resize(w, h);
  for (const auto& d : dialogs_) {
    if (d->rect().w != w || d->rect().h != h) d->resize(w, h);
  }
  if (timer_) timer_();
  if (!draw) return;
  if (content_) content_->renderTree(screen);
  for (const auto& d : dialogs_) d->renderTree(screen);
  setClip(screen);
}

void Canvas::processInputEvent(const InputEvent& ev) {
  for (auto it = dialogs_.rbegin(); it != dialogs_.rend(); ++it) {
    if ((*it)->dispatch(ev)) return;
  }
  if (content_) content_->dispatch(ev);
}

}  // namespace graalengine
