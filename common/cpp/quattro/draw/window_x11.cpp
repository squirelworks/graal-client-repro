#include "window.hpp"

#ifdef QUATTRO_X11

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

#include <cstdlib>
#include <cstring>
#include <deque>
#include <set>
#include <vector>

namespace Quattro::Draw {

namespace {

class X11Window : public Window {
 public:
  X11Window(Display* d, int w, int h, const std::string& title) : d_(d), w_(w), h_(h) {
    int s = DefaultScreen(d_);
    win_ = XCreateSimpleWindow(d_, RootWindow(d_, s), 0, 0, static_cast<unsigned>(w), static_cast<unsigned>(h), 0,
                               BlackPixel(d_, s), BlackPixel(d_, s));
    XSizeHints hints{};
    hints.flags = PMinSize | PMaxSize;
    hints.min_width = hints.max_width = w;
    hints.min_height = hints.max_height = h;
    XSetWMNormalHints(d_, win_, &hints);
    XSelectInput(d_, win_, KeyPressMask | KeyReleaseMask | ExposureMask | StructureNotifyMask);
    wm_delete_ = XInternAtom(d_, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(d_, win_, &wm_delete_, 1);
    gc_ = XCreateGC(d_, win_, 0, nullptr);
    pixels_.resize(static_cast<size_t>(w) * static_cast<size_t>(h));
    img_ = XCreateImage(d_, DefaultVisual(d_, s), static_cast<unsigned>(DefaultDepth(d_, s)), ZPixmap, 0,
                        reinterpret_cast<char*>(pixels_.data()), static_cast<unsigned>(w), static_cast<unsigned>(h),
                        32, 0);
    set_title(title);
    XMapWindow(d_, win_);
    XFlush(d_);
  }

  ~X11Window() override {
    if (img_) {
      img_->data = nullptr;  // owned by pixels_
      XDestroyImage(img_);
    }
    XFreeGC(d_, gc_);
    XDestroyWindow(d_, win_);
    XCloseDisplay(d_);
  }

  void set_title(const std::string& t) override {
    title_ = t;
    XStoreName(d_, win_, t.c_str());
  }

  void present(const Torque::Gui::Image& f) override {
    for (int y = 0; y < h_ && y < f.height; ++y)
      for (int x = 0; x < w_ && x < f.width; ++x) {
        const auto& c = f.at(x, y);
        pixels_[static_cast<size_t>(y) * static_cast<size_t>(w_) + static_cast<size_t>(x)] =
            (uint32_t(c.r) << 16) | (uint32_t(c.g) << 8) | c.b;
      }
    XPutImage(d_, win_, gc_, img_, 0, 0, 0, 0, static_cast<unsigned>(w_), static_cast<unsigned>(h_));
    XFlush(d_);
  }

  Key poll_key() override {
    while (XPending(d_)) {
      XEvent e;
      XNextEvent(d_, &e);
      if (e.type == ClientMessage && static_cast<Atom>(e.xclient.data.l[0]) == wm_delete_) {
        keys_.push_back(Key::Close);
      } else if (e.type == KeyPress || e.type == KeyRelease) {
        // Skip the release half of an auto-repeat pair.
        if (e.type == KeyRelease && XEventsQueued(d_, QueuedAfterReading)) {
          XEvent n;
          XPeekEvent(d_, &n);
          if (n.type == KeyPress && n.xkey.time == e.xkey.time && n.xkey.keycode == e.xkey.keycode) continue;
        }
        Key k = map(XLookupKeysym(&e.xkey, 0));
        if (k == Key::NoKey) continue;
        if (e.type == KeyPress) {
          if (!down_.count(k)) keys_.push_back(k);
          down_.insert(k);
        } else {
          down_.erase(k);
        }
      }
    }
    if (keys_.empty()) return Key::NoKey;
    Key k = keys_.front();
    keys_.pop_front();
    return k;
  }

  bool held(Key k) const override { return down_.count(k) != 0; }
  const std::string& title() const override { return title_; }

 private:
  static Key map(KeySym s) {
    switch (s) {
      case XK_Left: return Key::Left;
      case XK_Right: return Key::Right;
      case XK_Up: return Key::Up;
      case XK_Down: return Key::Down;
      case XK_Escape: return Key::Escape;
      default: return Key::NoKey;
    }
  }

  Display* d_;
  ::Window win_;
  GC gc_;
  XImage* img_ = nullptr;
  Atom wm_delete_;
  int w_, h_;
  std::vector<uint32_t> pixels_;
  std::string title_;
  std::deque<Key> keys_;
  std::set<Key> down_;
};

}  // namespace

std::unique_ptr<Window> open_x11_window(int w, int h, const std::string& title) {
  if (!std::getenv("DISPLAY")) return nullptr;
  Display* d = XOpenDisplay(nullptr);
  if (!d) return nullptr;
  if (DefaultDepth(d, DefaultScreen(d)) < 24) {
    XCloseDisplay(d);
    return nullptr;
  }
  return std::make_unique<X11Window>(d, w, h, title);
}

}  // namespace Quattro::Draw

#else

namespace Quattro::Draw {
std::unique_ptr<Window> open_x11_window(int, int, const std::string&) { return nullptr; }
}  // namespace Quattro::Draw

#endif
