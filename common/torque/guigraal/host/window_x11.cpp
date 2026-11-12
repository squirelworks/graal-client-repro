// Window on X11 (Xlib): one 32-bit image put to the window each frame.

#include "window.hpp"

#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <set>

namespace Torque {
namespace {

// Torque key names for the keys the 3.04 binds and dialogs use.
std::string key_name(KeySym k) {
  if (k >= XK_a && k <= XK_z) return std::string(1, char('a' + (k - XK_a)));
  if (k >= XK_A && k <= XK_Z) return std::string(1, char('a' + (k - XK_A)));
  if (k >= XK_0 && k <= XK_9) return std::string(1, char('0' + (k - XK_0)));
  if (k >= XK_F1 && k <= XK_F12) return "f" + std::to_string(1 + (k - XK_F1));
  switch (k) {
    case XK_Up: return "up";
    case XK_Down: return "down";
    case XK_Left: return "left";
    case XK_Right: return "right";
    case XK_Escape: return "escape";
    case XK_Return: return "return";
    case XK_KP_Enter: return "numpadenter";
    case XK_BackSpace: return "backspace";
    case XK_Delete: return "delete";
    case XK_Home: return "home";
    case XK_End: return "end";
    case XK_Tab: return "tab";
    case XK_space: return "space";
    case XK_grave: return "tilde";
    case XK_Shift_L: return "lshift";
    case XK_Shift_R: return "rshift";
    case XK_Control_L: return "lcontrol";
    case XK_Control_R: return "rcontrol";
    case XK_Alt_L: return "lalt";
    case XK_Alt_R: return "ralt";
    case XK_Page_Up: return "pageup";
    case XK_Page_Down: return "pagedown";
    case XK_Insert: return "insert";
    default: return std::string();
  }
}

unsigned modifiers(unsigned state) {
  unsigned m = 0;
  if (state & ShiftMask) m |= InputEvent::shift;
  if (state & ControlMask) m |= InputEvent::ctrl;
  if (state & Mod1Mask) m |= InputEvent::alt;
  return m;
}

class X11Window : public Window {
 public:
  ~X11Window() override {
    if (image_) {
      image_->data = nullptr;
      XDestroyImage(image_);
    }
    if (display_) {
      XDestroyWindow(display_, window_);
      XCloseDisplay(display_);
    }
  }

  bool init(const std::string& title, int w, int h, std::string& error) {
    display_ = XOpenDisplay(nullptr);
    if (!display_) {
      error = "no X display";
      return false;
    }
    const int screen = DefaultScreen(display_);
    Visual* visual = DefaultVisual(display_, screen);
    if (DefaultDepth(display_, screen) < 24) {
      error = "the X display is not 24 or 32 bits deep";
      return false;
    }
    width_ = w;
    height_ = h;
    window_ = XCreateSimpleWindow(display_, RootWindow(display_, screen), 0, 0, unsigned(w), unsigned(h), 0,
                                  BlackPixel(display_, screen), BlackPixel(display_, screen));
    XStoreName(display_, window_, title.c_str());
    XSizeHints* hints = XAllocSizeHints();
    hints->flags = PMinSize | PMaxSize;
    hints->min_width = hints->max_width = w;
    hints->min_height = hints->max_height = h;
    XSetWMNormalHints(display_, window_, hints);
    XFree(hints);
    XSelectInput(display_, window_, KeyPressMask | KeyReleaseMask | ButtonPressMask | ExposureMask |
                                        StructureNotifyMask);
    wm_delete_ = XInternAtom(display_, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(display_, window_, &wm_delete_, 1);
    Bool supported = False;
    XkbSetDetectableAutoRepeat(display_, True, &supported);
    XMapWindow(display_, window_);
    gc_ = DefaultGC(display_, screen);
    pixels_.assign(std::size_t(w) * h, 0);
    image_ = XCreateImage(display_, visual, unsigned(DefaultDepth(display_, screen)), ZPixmap, 0,
                          reinterpret_cast<char*>(pixels_.data()), unsigned(w), unsigned(h), 32, 0);
    return image_ != nullptr;
  }

  std::vector<WindowEvent> pump() override {
    std::vector<WindowEvent> out;
    while (XPending(display_)) {
      XEvent ev;
      XNextEvent(display_, &ev);
      if (ev.type == ClientMessage && Atom(ev.xclient.data.l[0]) == wm_delete_) {
        WindowEvent we;
        we.kind = WindowEvent::Kind::close;
        out.push_back(we);
      } else if (ev.type == KeyPress || ev.type == KeyRelease) {
        char buf[8] = {0};
        KeySym sym = 0;
        const int n = XLookupString(&ev.xkey, buf, sizeof buf, &sym, nullptr);
        const std::string name = key_name(XLookupKeysym(&ev.xkey, 0) ? XLookupKeysym(&ev.xkey, 0) : sym);
        if (name.empty()) continue;
        WindowEvent we;
        we.key.key = name;
        we.key.modifiers = modifiers(ev.xkey.state);
        we.key.make = ev.type == KeyPress;
        we.key.repeat = we.key.make && held_.count(name) != 0;
        if (we.key.make) held_.insert(name); else held_.erase(name);
        if (we.key.make && n == 1 && static_cast<unsigned char>(buf[0]) >= 32 && buf[0] != 127) we.key.ascii = buf[0];
        out.push_back(we);
      } else if (ev.type == ButtonPress && ev.xbutton.button == Button1) {
        const auto now = std::chrono::steady_clock::now();
        WindowEvent we;
        we.kind = WindowEvent::Kind::click;
        we.x = ev.xbutton.x;
        we.y = ev.xbutton.y;
        we.double_click = now - last_click_ < std::chrono::milliseconds(400) &&
                          std::abs(we.x - last_x_) < 5 && std::abs(we.y - last_y_) < 5;
        last_click_ = now;
        last_x_ = we.x;
        last_y_ = we.y;
        out.push_back(we);
      }
    }
    return out;
  }

  void present(const Gui::Image& img) override {
    const int w = std::min(width_, img.width), h = std::min(height_, img.height);
    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        const Gui::Color& c = img.at(x, y);
        pixels_[std::size_t(y) * width_ + x] = (std::uint32_t(c.r) << 16) | (std::uint32_t(c.g) << 8) | c.b;
      }
    XPutImage(display_, window_, gc_, image_, 0, 0, 0, 0, unsigned(width_), unsigned(height_));
    XFlush(display_);
  }

 private:
  Display* display_ = nullptr;
  ::Window window_ = 0;
  GC gc_ = nullptr;
  XImage* image_ = nullptr;
  Atom wm_delete_ = 0;
  int width_ = 0, height_ = 0;
  std::vector<std::uint32_t> pixels_;
  std::set<std::string> held_;
  std::chrono::steady_clock::time_point last_click_{};
  int last_x_ = -100, last_y_ = -100;
};

} // namespace

std::unique_ptr<Window> Window::open(const std::string& title, int width, int height, std::string& error) {
  auto w = std::make_unique<X11Window>();
  if (!w->init(title, width, height, error)) return nullptr;
  return w;
}

} // namespace Torque
