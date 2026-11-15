// Generated level and native messages exercise the production window and
// Program loop. No original assets, binaries or server connections.
#include "../shell/program.hpp"
#include "check.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <filesystem>
#include <fstream>

using namespace Quattro;

int main() {
  auto win = Draw::open_window(320, 240, "Quattro native test");
  CHECK(win);
  if (!win) return 1;
  HWND hwnd = FindWindowA("GraalReproQuattroWindow", "Quattro native test");
  CHECK(hwnd);
  if (!hwnd) return 1;
  win->poll_key();
  Draw::InputEvent event;
  while (win->poll_input(event)) {}

  // The exact frame channels and orientation reach the native client area.
  Draw::Image image(320, 240, {17, 83, 201, 255});
  image.at(3, 4) = {201, 41, 73, 255};
  win->present(image);
  HDC dc = GetDC(hwnd);
  CHECK(GetPixel(dc, 3, 4) == RGB(201, 41, 73));
  CHECK(GetPixel(dc, 3, 235) == RGB(17, 83, 201));
  ReleaseDC(hwnd, dc);

  SendMessageA(hwnd, WM_KEYDOWN, VK_RIGHT, 0);
  SendMessageA(hwnd, WM_KEYDOWN, VK_RIGHT, 1 << 30); // autorepeat
  CHECK(win->poll_key() == Draw::Key::Right);
  CHECK(win->poll_key() == Draw::Key::NoKey);
  CHECK(win->held(Draw::Key::Right));
  CHECK(win->poll_input(event) && event.type == Draw::InputEvent::KeyDown && event.key == "right");
  // GUI controls receive text/navigation repeats, while gameplay actions
  // remain edge-triggered and movement uses held state.
  CHECK(win->poll_input(event) && event.type == Draw::InputEvent::KeyDown && event.key == "right");
  CHECK(!win->poll_input(event));
  SendMessageA(hwnd, WM_KILLFOCUS, 0, 0);
  CHECK(!win->held(Draw::Key::Right));
  CHECK(win->poll_input(event) && event.type == Draw::InputEvent::KeyUp && event.key == "right");
  SendMessageA(hwnd, WM_LBUTTONDBLCLK, 0, MAKELPARAM(12, 34));
  CHECK(win->poll_input(event) && event.type == Draw::InputEvent::MouseDown &&
        event.x == 12 && event.y == 34 && event.clicks == 2);

  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() / ("quattro-native-" + std::to_string(GetCurrentProcessId()));
  fs::create_directories(root / "levels");
  Files::Board board{};
  std::ofstream(root / "levels/native.graal", std::ios::binary)
      << "GR-V1.03" << Files::write_board_stream(board) << "#\n\xFF\xFF\xFF\n#\n#\n\n";
  std::string error;
  CHECK(Torque::Gui::write_file((root / "pics1.png").string(),
        Torque::Gui::encode_png(Draw::Image(256, 32, {21, 67, 193, 255})), error));
  const auto* profile = Net::find_profile("6.03r7");
  CHECK(profile);
  if (!profile) return 1;
  Shell::Options opt;
  opt.assets = root.string();
  opt.width = 320; opt.height = 240;
  {
    Shell::Program program(*profile, opt, *win);
    CHECK(program.start_offline("native.graal", 30, 30));
    CHECK(program.tick());
    CHECK(program.world().have_level);
    auto passes = Draw::pass_order();
    passes.push_back("HUD"); // offline 6.x play includes the HUD after world passes
    CHECK(program.last_passes() == passes);
    dc = GetDC(hwnd);
    CHECK(GetPixel(dc, 10, 180) == RGB(21, 67, 193)); // loaded tile sheet, through Program
    ReleaseDC(hwnd, dc);
    const double x = program.me().x;
    SendMessageA(hwnd, WM_KEYDOWN, VK_RIGHT, 0);
    CHECK(program.tick());
    CHECK(program.me().x > x);
    SendMessageA(hwnd, WM_KEYUP, VK_RIGHT, 0);
    const double stopped = program.me().x;
    CHECK(program.tick());
    CHECK(program.me().x == stopped);
    SendMessageA(hwnd, WM_KEYDOWN, VK_LEFT, 0);
    SendMessageA(hwnd, WM_KILLFOCUS, 0, 0);
    CHECK(program.tick());
    CHECK(program.me().x == stopped);
    SendMessageA(hwnd, WM_CLOSE, 0, 0);
    CHECK(!program.tick());
  }
  fs::remove_all(root);
  TEST_MAIN_END();
}
#else
int main() { TEST_MAIN_END(); }
#endif
