// Login-shaped first frame for the 4.2.0.8 host.
//
// Provisional: 4.2.0.8 has no exact row. Neighbour is Linux 6.037,
// token G3D0511C.
//
// The first frame is the login line alone: plain zlib, no compression
// byte, id 5, key, token, account, password, then win and three fields.
// That is what graal-4.20r8-G3D20126/tests/Test420.dpr asserts.
//
// Machine fields: the real client sends three machine hashes. This host
// sends the empty fields from that test (win,"","",""). Ids 37 and 23
// follow in later gen-5 frames. They are not this frame and this host
// does not send them.

#ifndef HOST4208_LOGIN_HPP
#define HOST4208_LOGIN_HPP

#include <cstdint>
#include <string>

// Provisional neighbour of Linux 6.037. 4.2.0.8 has no exact row.
extern const char kVersionToken[];

struct LoginFrame {
  std::string plain;
  std::string wire;
  int key;
};

bool buildLoginFrame(int key, const std::string &account, const std::string &password,
                     LoginFrame &out, std::string &error);

bool loginFrameRoundTrip(const LoginFrame &frame, std::string &error);

enum class SendStatus { Sent, Refused, RejectedHost, Error };

struct SendResult {
  SendStatus status;
  std::string detail;
};

SendResult sendLoginFrame(const std::string &host, std::uint16_t port,
                          const std::string &wire);

std::string hexBytes(const std::string &bytes);
std::string escapeBytes(const std::string &bytes);

#endif
