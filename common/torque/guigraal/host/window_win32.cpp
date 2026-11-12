// Window on Win32 (GDI): one 32-bit DIB drawn to the client area each frame.

#include "window.hpp"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <set>

namespace Torque {
namespace {

// Torque key names for the keys the 3.04 binds and dialogs use.
std::string key_name(WPARAM vk, LPARAM lparam) {
  const bool extended = (lparam >> 24) & 1;
  if (vk >= 'A' && vk <= 'Z') return std::string(1, char('a' + (vk - 'A')));
  if (vk >= '0' && vk <= '9') return std::string(1, char(vk));
  if (vk >= VK_F1 && vk <= VK_F12) return "f" + std::to_string(1 + (vk - VK_F1));
  switch (vk) {
    case VK_UP: return "up";
    case VK_DOWN: return "down";
    case VK_LEFT: return "left";
    case VK_RIGHT: return "right";
    case VK_ESCAPE: return "escape";
    case VK_RETURN: return extended ? "numpadenter" : "return";
    case VK_BACK: return "backspace";
    case VK_DELETE: return "delete";
    case VK_HOME: return "home";
    case VK_END: return "end";
    case VK_TAB: return "tab";
    case VK_SPACE: return "space";
    case VK_PRIOR: return "pageup";
    case VK_NEXT: return "pagedown";
    case VK_INSERT: return "insert";
    case VK_SHIFT: return MapVirtualKeyA(UINT((lparam >> 16) & 0xFF), MAPVK_VSC_TO_VK_EX) == VK_RSHIFT ? "rshift" : "lshift";
    case VK_CONTROL: return extended ? "rcontrol" : "lcontrol";
    case VK_MENU: return extended ? "ralt" : "lalt";
    default: break;
  }
  // Punctuation by the key's unshifted character, whatever the layout.
  const UINT ch = MapVirtualKeyA(UINT(vk), MAPVK_VK_TO_CHAR) & 0x7FFF;
  return ch > 0 && ch < 128 ? punctuation_key_name(char(ch)) : std::string();
}

unsigned modifiers() {
  unsigned m = 0;
  if (GetKeyState(VK_SHIFT) & 0x8000) m |= InputEvent::shift;
  if (GetKeyState(VK_CONTROL) & 0x8000) m |= InputEvent::ctrl;
  if (GetKeyState(VK_MENU) & 0x8000) m |= InputEvent::alt;
  return m;
}

const char kClassName[] = "GraalTorqueWindow";

class Win32Window : public Window {
 public:
  ~Win32Window() override {
    if (hwnd_) DestroyWindow(hwnd_);
  }

  bool init(const std::string& title, int w, int h, std::string& error) {
    HINSTANCE inst = GetModuleHandleA(nullptr);
    WNDCLASSA wc = {};
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &Win32Window::proc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hIcon = LoadIcon(inst, MAKEINTRESOURCE(1));
    if (!wc.hIcon) wc.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = kClassName;
    RegisterClassA(&wc);  // fails harmlessly when already registered

    // A fixed-size window whose client area is the canvas: no resize frame,
    // no maximize box (as the X11 window's min = max size hints).
    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    RECT r = {0, 0, w, h};
    AdjustWindowRect(&r, style, FALSE);
    hwnd_ = CreateWindowA(kClassName, title.c_str(), style, CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left,
                          r.bottom - r.top, nullptr, nullptr, inst, this);
    if (!hwnd_) {
      error = "cannot create the window (error " + std::to_string(GetLastError()) + ")";
      return false;
    }
    width_ = w;
    height_ = h;
    pixels_.assign(std::size_t(w) * h, 0);
    ShowWindow(hwnd_, SW_SHOWNORMAL);
    UpdateWindow(hwnd_);
    SetForegroundWindow(hwnd_);
    return true;
  }

  std::vector<WindowEvent> pump() override {
    MSG msg;
    while (PeekMessageA(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        push_close();
        continue;
      }
      TranslateMessage(&msg);  // posts WM_CHAR after the key, read below
      DispatchMessageA(&msg);
    }
    std::vector<WindowEvent> out;
    out.swap(events_);
    return out;
  }

  void present(const Gui::Image& img) override {
    const int w = std::min(width_, img.width), h = std::min(height_, img.height);
    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        const Gui::Color& c = img.at(x, y);
        pixels_[std::size_t(y) * width_ + x] = (std::uint32_t(c.r) << 16) | (std::uint32_t(c.g) << 8) | c.b;
      }
    HDC dc = GetDC(hwnd_);
    blit(dc);
    ReleaseDC(hwnd_, dc);
  }

 private:
  void blit(HDC dc) {
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = width_;
    bi.bmiHeader.biHeight = -height_;  // top-down rows
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    SetDIBitsToDevice(dc, 0, 0, DWORD(width_), DWORD(height_), 0, 0, 0, UINT(height_), pixels_.data(), &bi,
                      DIB_RGB_COLORS);
  }

  void push_close() {
    WindowEvent we;
    we.kind = WindowEvent::Kind::close;
    events_.push_back(we);
  }

  void key(WPARAM vk, LPARAM lparam, bool make) {
    const std::string name = key_name(vk, lparam);
    if (name.empty()) return;
    WindowEvent we;
    we.key.key = name;
    we.key.modifiers = modifiers();
    we.key.make = make;
    we.key.repeat = make && held_.count(name) != 0;
    if (make) held_.insert(name); else held_.erase(name);
    events_.push_back(we);
    last_key_ = make ? int(events_.size()) - 1 : -1;
  }

  // The character a key typed goes on that key's press, as XLookupString's
  // does on X11. Characters outside ASCII are dropped (the 3.04 edits are
  // byte strings).
  void character(WPARAM ch) {
    if (last_key_ < 0 || last_key_ >= int(events_.size())) return;
    if (ch >= 32 && ch < 127) events_[std::size_t(last_key_)].key.ascii = char(ch);
    last_key_ = -1;
  }

  void click(LPARAM lparam) {
    const auto now = std::chrono::steady_clock::now();
    WindowEvent we;
    we.kind = WindowEvent::Kind::click;
    we.x = short(LOWORD(lparam));
    we.y = short(HIWORD(lparam));
    we.double_click = now - last_click_ < std::chrono::milliseconds(400) && std::abs(we.x - last_x_) < 5 &&
                      std::abs(we.y - last_y_) < 5;
    last_click_ = now;
    last_x_ = we.x;
    last_y_ = we.y;
    events_.push_back(we);
  }

  static LRESULT CALLBACK proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_NCCREATE) {
      auto* cs = reinterpret_cast<CREATESTRUCTA*>(lp);
      SetWindowLongPtrA(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    }
    auto* self = reinterpret_cast<Win32Window*>(GetWindowLongPtrA(hwnd, GWLP_USERDATA));
    if (!self) return DefWindowProcA(hwnd, msg, wp, lp);
    switch (msg) {
      case WM_CLOSE:
        self->push_close();
        return 0;  // the program closes the window when it ends
      case WM_KEYDOWN:
      case WM_SYSKEYDOWN:
        self->key(wp, lp, true);
        if (msg == WM_SYSKEYDOWN && wp == VK_F4) break;  // keep Alt+F4
        return 0;
      case WM_KEYUP:
      case WM_SYSKEYUP:
        self->key(wp, lp, false);
        return 0;
      case WM_CHAR:
        self->character(wp);
        return 0;
      case WM_SYSCHAR:
        return 0;  // no menu bar: no beep on Alt+key
      case WM_LBUTTONDOWN:
      case WM_LBUTTONDBLCLK:
        self->click(lp);
        return 0;
      case WM_KILLFOCUS:
        // Keys held when the window loses focus never see their release.
        for (const std::string& k : self->held_) {
          WindowEvent we;
          we.key.key = k;
          we.key.make = false;
          self->events_.push_back(we);
        }
        self->held_.clear();
        return 0;
      case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        self->blit(dc);
        EndPaint(hwnd, &ps);
        return 0;
      }
      case WM_ERASEBKGND:
        return 1;
      default:
        break;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
  }

  HWND hwnd_ = nullptr;
  int width_ = 0, height_ = 0;
  std::vector<std::uint32_t> pixels_;
  std::vector<WindowEvent> events_;
  int last_key_ = -1;
  std::set<std::string> held_;
  std::chrono::steady_clock::time_point last_click_{};
  int last_x_ = -100, last_y_ = -100;
};

} // namespace

std::unique_ptr<Window> Window::open(const std::string& title, int width, int height, std::string& error) {
  auto w = std::make_unique<Win32Window>();
  if (!w->init(title, width, height, error)) return nullptr;
  return w;
}

} // namespace Torque
