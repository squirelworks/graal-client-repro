#include "window.hpp"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <set>
#include <vector>

namespace Quattro::Draw {
namespace {
Key game_key(WPARAM k) {
  switch (k) {
    case VK_LEFT: return Key::Left;
    case VK_RIGHT: return Key::Right;
    case VK_UP: return Key::Up;
    case VK_DOWN: return Key::Down;
    case VK_ESCAPE: return Key::Escape;
    case VK_TAB: return Key::Tab;
    case 'A': return Key::A;
    case 'S': return Key::S;
    case 'D': return Key::D;
    case 'Q': return Key::Q;
    default: return Key::NoKey;
  }
}
std::string key_name(WPARAM k) {
  switch (k) {
    case VK_LEFT: return "left";
    case VK_RIGHT: return "right";
    case VK_UP: return "up";
    case VK_DOWN: return "down";
    case VK_ESCAPE: return "escape";
    case VK_TAB: return "tab";
    case VK_RETURN: return "enter";
    case VK_BACK: return "backspace";
    case VK_DELETE: return "delete";
    case VK_HOME: return "home";
    case VK_END: return "end";
    case VK_SPACE: return "space";
    default:
      if (k >= VK_F1 && k <= VK_F12) return "f" + std::to_string(k - VK_F1 + 1);
      if (k >= 'A' && k <= 'Z') return std::string(1, static_cast<char>(k + 'a' - 'A'));
      if (k >= '0' && k <= '9') return std::string(1, static_cast<char>(k));
      return {};
  }
}
class WinWindow final : public Window {
 public:
  WinWindow(int w, int h, const std::string& title) : title_(title) {
    WNDCLASSA wc{};
    wc.style = CS_DBLCLKS;
    wc.lpfnWndProc = procedure;
    wc.hInstance = GetModuleHandleA(nullptr);
    wc.lpszClassName = "GraalReproQuattroWindow";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassA(&wc);
    constexpr DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    RECT r{0, 0, w, h};
    AdjustWindowRect(&r, style, FALSE);
    hwnd_ = CreateWindowA(wc.lpszClassName, title.c_str(), style,
                          CW_USEDEFAULT, CW_USEDEFAULT, r.right-r.left, r.bottom-r.top,
                          nullptr, nullptr, wc.hInstance, this);
    if (hwnd_) ShowWindow(hwnd_, SW_SHOW);
  }
  ~WinWindow() override { if (hwnd_) DestroyWindow(hwnd_); }
  bool valid() const { return hwnd_ != nullptr; }
  void set_title(const std::string& s) override { title_ = s; SetWindowTextA(hwnd_, s.c_str()); }
  const std::string& title() const override { return title_; }
  bool held(Key k) const override { return down_.count(k) != 0; }
  Key poll_key() override {
    MSG m;
    while (PeekMessageA(&m, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&m);
      DispatchMessageA(&m);
    }
    if (keys_.empty()) return Key::NoKey;
    const auto k = keys_.front(); keys_.pop_front(); return k;
  }
  bool poll_input(InputEvent& e) override {
    if (input_.empty()) return false;
    e = input_.front(); input_.pop_front(); return true;
  }
  void present(const Torque::Gui::Image& frame) override {
    pixels_.resize(frame.pixels.size());
    for (size_t i = 0; i < frame.pixels.size(); ++i) {
      const auto c = frame.pixels[i];
      pixels_[i] = (static_cast<unsigned>(c.r) << 16) | (static_cast<unsigned>(c.g) << 8) | c.b;
    }
    width_ = frame.width; height_ = frame.height;
    InvalidateRect(hwnd_, nullptr, FALSE);
    UpdateWindow(hwnd_);
  }
 private:
  static LRESULT CALLBACK procedure(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
    auto* self = reinterpret_cast<WinWindow*>(GetWindowLongPtrA(hwnd, GWLP_USERDATA));
    if (msg == WM_NCCREATE) {
      self = static_cast<WinWindow*>(reinterpret_cast<CREATESTRUCTA*>(l)->lpCreateParams);
      SetWindowLongPtrA(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcA(hwnd, msg, w, l);
    if (msg == WM_CLOSE) { self->keys_.push_back(Key::Close); return 0; }
    if (msg == WM_KILLFOCUS) {
      for (const auto& key : self->pressed_) {
        InputEvent e; e.type = InputEvent::KeyUp; e.key = key_name(key); self->input_.push_back(e);
      }
      self->pressed_.clear(); self->down_.clear(); return 0;
    }
    if (msg == WM_KEYDOWN || msg == WM_KEYUP || msg == WM_SYSKEYDOWN || msg == WM_SYSKEYUP) {
      // Keep the platform's Alt+F4 close command.
      if (msg == WM_SYSKEYDOWN && w == VK_F4) return DefWindowProcA(hwnd, msg, w, l);
      const bool press = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
      const auto k = game_key(w);
      if (press) {
        if (!self->pressed_.insert(w).second) return 0;
        if (k != Key::NoKey) { self->down_.insert(k); self->keys_.push_back(k); }
      } else { self->pressed_.erase(w); self->down_.erase(k); }
      InputEvent e; e.type = press ? InputEvent::KeyDown : InputEvent::KeyUp; e.key = key_name(w);
      BYTE state[256]{};
      WCHAR chars[4]{};
      GetKeyboardState(state);
      // GUI input currently uses one character per event, as XLookupString does.
      if (ToUnicodeEx(static_cast<UINT>(w), static_cast<UINT>((l >> 16) & 255), state,
                      chars, 4, 4, GetKeyboardLayout(0)) == 1 && chars[0] >= 32) {
        e.ch = chars[0];
        if (e.key.empty() && e.ch < 127) e.key = std::string(1, static_cast<char>(e.ch));
      }
      auto mod = [&](const char* s) { if (!e.mods.empty()) e.mods += ' '; e.mods += s; };
      if (state[VK_SHIFT] & 0x80) mod("shift");
      if (state[VK_CONTROL] & 0x80) mod("ctrl");
      if (state[VK_MENU] & 0x80) mod("alt");
      if (!e.key.empty()) self->input_.push_back(e);
      return 0;
    }
    if (msg == WM_LBUTTONDOWN || msg == WM_LBUTTONDBLCLK) {
      InputEvent e; e.type = InputEvent::MouseDown;
      e.x = static_cast<short>(LOWORD(l)); e.y = static_cast<short>(HIWORD(l));
      e.clicks = msg == WM_LBUTTONDBLCLK ? 2 : 1; self->input_.push_back(e); return 0;
    }
    if (msg == WM_PAINT) {
      PAINTSTRUCT ps; HDC dc = BeginPaint(hwnd, &ps);
      if (!self->pixels_.empty()) {
        BITMAPINFO bi{}; bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = self->width_; bi.bmiHeader.biHeight = -self->height_;
        bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
        SetDIBitsToDevice(dc, 0, 0, self->width_, self->height_, 0, 0, 0, self->height_,
                          self->pixels_.data(), &bi, DIB_RGB_COLORS);
      }
      EndPaint(hwnd, &ps); return 0;
    }
    return DefWindowProcA(hwnd, msg, w, l);
  }
  HWND hwnd_ = nullptr;
  std::string title_;
  std::set<Key> down_;
  std::set<WPARAM> pressed_;
  std::deque<Key> keys_;
  std::deque<InputEvent> input_;
  std::vector<unsigned> pixels_;
  int width_ = 0, height_ = 0;
};
}
std::unique_ptr<Window> open_window(int w, int h, const std::string& title) {
  auto win = std::make_unique<WinWindow>(w, h, title);
  if (!win->valid()) return nullptr;
  return win;
}
}
#else
namespace Quattro::Draw {
std::unique_ptr<Window> open_window(int w, int h, const std::string& title) {
  return open_x11_window(w, h, title);
}
}
#endif
