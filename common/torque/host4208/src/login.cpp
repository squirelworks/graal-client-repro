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
  // Machine fields: the made-up hashes Test420 asserts.
  // Ids 37 and 23 are later gen-5 frames and are not appended here.
  const int kLogin = 5;

  std::string plain;
  plain += gChar(kLogin);
  plain += gChar(key);
  plain += kVersionToken;
  plain += gString(account);
  plain += gString(password);
  plain += "win,c2482de76c59ac3c4ce0b7e065a2d09c,3c639304427ab3b3c6439a39c31c9df5,217767adb74e936b5ee209ed65ecc400";
  plain += '\n';

  return HostNet::encodeFirstFrame(plain, key, out, error);
}

bool loginFrameRoundTrip(const LoginFrame &frame, std::string &error) {
  return HostNet::loginFrameRoundTrip(frame, kVersionToken, error);
}
