#include "login.hpp"
#include <zlib.h>
#include <iostream>
#include <stdexcept>
#include <string>
void check(bool ok, const char *what) { if (!ok) throw std::runtime_error(what); }
int main() {
  try {
    LoginFrame frame;
    std::string error;
#ifdef PROFILE304
    auto build = [&](int key, const std::string &account, const std::string &password) {
      return buildLoginFrame(key, account, password, "English", frame, error);
    };
    const std::string expected = std::string("%!G3D03014#lab#lab\nEEnglish\nB     bigmap.txt\nB     minimap.txt\n");
#else
    auto build = [&](int key, const std::string &account, const std::string &password) {
      return buildLoginFrame(key, account, password, frame, error);
    };
    const std::string expected = "%!G3D20126#lab#labwin,\"\",\"\",\"\"\n";
#endif
    check(build(1, "lab", "lab"), "build fixture");
    check(frame.plain == expected, "profile bytes changed");
    // Independent zlib decoder: no codec round-trip helper in this assertion.
    const unsigned length = (static_cast<unsigned char>(frame.wire[0]) << 8) |
                            static_cast<unsigned char>(frame.wire[1]);
    check(length + 2 == frame.wire.size(), "u16 framing");
    char decoded[2048]; uLongf size = sizeof decoded;
    check(uncompress(reinterpret_cast<Bytef *>(decoded), &size,
                     reinterpret_cast<const Bytef *>(frame.wire.data()+2), length) == Z_OK,
          "independent inflate");
    check(std::string(decoded, size) == expected, "independent decoded bytes");
    check(loginFrameRoundTrip(frame, error), "valid frame");
    LoginFrame bad = frame; bad.wire.pop_back();
    check(!loginFrameRoundTrip(bad, error), "truncated wire rejected");
    bad = frame; bad.wire += 'x';
    check(!loginFrameRoundTrip(bad, error), "trailing wire rejected");
    bad = frame; bad.wire[2] = 0;
    check(!loginFrameRoundTrip(bad, error), "invalid zlib rejected");
    bad = frame; bad.plain[2] = 'X';
    check(!loginFrameRoundTrip(bad, error), "mismatched body rejected");
    check(!build(-1, "lab", "lab"), "negative key rejected");
    check(!build(128, "lab", "lab"), "large key rejected");
    check(!build(1, "a\nb", "lab"), "account newline rejected");
    check(!build(1, "lab", "a\nb"), "password newline rejected");
#ifdef PROFILE304
    check(!buildLoginFrame(1, "lab", "lab", "a\nb", frame, error), "language newline rejected");
#endif
    check(build(0, std::string(224, 'a'), "lab"), "long account bounded");
    check(static_cast<unsigned char>(frame.plain[10]) == 255, "account length clamped to 223");
    check(build(127, std::string("a\0b",3), "lab"), "embedded NUL preserved");
    check(frame.plain.substr(11,3) == std::string("a\0b",3), "binary account bytes");
    std::cout << "first-frame profile tests passed\n";
  } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
