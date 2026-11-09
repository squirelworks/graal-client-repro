// Shared first-frame codec and loopback lab transport. Not a session engine.
#ifndef GRAAL_HOST_FIRST_FRAME_HPP
#define GRAAL_HOST_FIRST_FRAME_HPP
#include <cstdint>
#include <string>
namespace HostNet {
struct LoginFrame { std::string plain; std::string wire; int key = 0; };
enum class SendStatus { Sent, Refused, RejectedHost, Error };
struct SendResult { SendStatus status; std::string detail; };
std::string gChar(int value);
std::string gString(const std::string &value);
bool encodeFirstFrame(const std::string &plain, int key, LoginFrame &out, std::string &error);
bool loginFrameRoundTrip(const LoginFrame &frame, const std::string &token, std::string &error);
SendResult sendLoginFrame(const std::string &host, std::uint16_t port, const std::string &wire);
std::string hexBytes(const std::string &bytes);
std::string escapeBytes(const std::string &bytes);
}
#endif
