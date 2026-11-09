#include "login.hpp"
using HostNet::gChar;
using HostNet::gString;
const char kVersionToken[] = "G3D20126";
bool buildLoginFrame(int key, const std::string &account, const std::string &password,
                     LoginFrame &out, std::string &error) {
  if (key < 0 || key > 127) {
    error = "key must be 0..127";
    return false;
  }
  if (account.find('\n') != std::string::npos || password.find('\n') != std::string::npos) {
    error = "login fields must not contain a newline";
    return false;
  }

  // First frame only: id 5. GCHAR(id) is id + 0x20.
  // Token kVersionToken is the documented 4.20r8 row.
  // Machine fields stay empty, as in Test420.
  // Ids 37 and 23 are later gen-5 frames and are not appended here.
  const int kLogin = 5;

  std::string plain;
  plain += gChar(kLogin);
  plain += gChar(key);
  plain += kVersionToken;
  plain += gString(account);
  plain += gString(password);
  plain += "win,\"\",\"\",\"\"";
  plain += '\n';

  return HostNet::encodeFirstFrame(plain, key, out, error);
}

bool loginFrameRoundTrip(const LoginFrame &frame, std::string &error) {
  return HostNet::loginFrameRoundTrip(frame, kVersionToken, error);
}
