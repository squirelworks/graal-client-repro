#include "login.hpp"
using HostNet::gChar;
using HostNet::gString;
// Five-byte GINT5. Zero is five 0x20 bytes. See the provisional note
// on the filename prefix in login.hpp.
std::string gInt5(std::uint32_t v) {
  std::string out;
  out.push_back(static_cast<char>(((v >> 28) & 0x0F) + 0x20));
  out.push_back(static_cast<char>(((v >> 21) & 0x7F) + 0x20));
  out.push_back(static_cast<char>(((v >> 14) & 0x7F) + 0x20));
  out.push_back(static_cast<char>(((v >> 7) & 0x7F) + 0x20));
  out.push_back(static_cast<char>((v & 0x7F) + 0x20));
  return out;
}

bool buildLoginFrame(int key, const std::string &account, const std::string &password,
                     const std::string &language, LoginFrame &out, std::string &error) {
  if (key < 0 || key > 127) {
    error = "key must be 0..127";
    return false;
  }
  if (language.find('\n') != std::string::npos ||
      account.find('\n') != std::string::npos ||
      password.find('\n') != std::string::npos) {
    error = "login fields must not contain a newline";
    return false;
  }

  // Packet id is GCHAR(id), which is id + 0x20. Id 5 is the login line.
  // Ids 37 and 34 are the language and the two file requests.
  const int kLogin = 5;
  const int kLanguage = 37;
  const int kUpdateFile = 34;

  std::string plain;
  plain += gChar(kLogin);
  plain += gChar(key);
  plain += "G3D03014";
  plain += gString(account);
  plain += gString(password);
  plain += '\n';
  plain += gChar(kLanguage);
  plain += language;
  plain += '\n';
  // PROVISIONAL filename prefix: GINT5 zero, then the name. See login.hpp.
  plain += gChar(kUpdateFile);
  plain += gInt5(0);
  plain += "bigmap.txt";
  plain += '\n';
  plain += gChar(kUpdateFile);
  plain += gInt5(0);
  plain += "minimap.txt";
  plain += '\n';

  return HostNet::encodeFirstFrame(plain, key, out, error);
}

bool loginFrameRoundTrip(const LoginFrame &frame, std::string &error) {
  return HostNet::loginFrameRoundTrip(frame, "G3D03014", error);
}
