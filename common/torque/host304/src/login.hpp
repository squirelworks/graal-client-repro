// Login-shaped first frame for the 3.04 host.
//
// Token G3D03014 is the folder name and the game-server token in
// Graal_analysis protocol/v3x-clients.md, confirmed on the wire in
// version-profiles/lab-304-linux-2026-10-30.md. It is not provisional.
//
// The message list (5, 37, 34 bigmap.txt, 34 minimap.txt) in one plain
// zlib frame, no compression byte and no XOR, is that lab note. The
// byte encoding (GCHAR id, GCHAR key, GSTRING account and password,
// raw language, newline between messages, u16be length of the zlib
// member) is the same encoding graal-3.04-G3D03014/tests/Test304.dpr
// asserts.
//
// PROVISIONAL: the five-byte GINT5(0) in front of each filename. The
// lab note names the two files and does not print those bytes. Test304
// treats them as "no cached mod time". This host copies that. It is
// not a new wire map from a capture read in this pass.

#ifndef HOST304_LOGIN_HPP
#define HOST304_LOGIN_HPP

#include <cstdint>
#include <string>

#include "../../shared/first_frame.hpp"
using HostNet::LoginFrame;
using HostNet::SendStatus;
using HostNet::SendResult;
using HostNet::sendLoginFrame;
using HostNet::hexBytes;
using HostNet::escapeBytes;

// key is 0..127, as the client sends (rand masked to 7 bits).
// language is the raw id-37 body (the folder test uses "English").
bool buildLoginFrame(int key, const std::string &account,
                     const std::string &password, const std::string &language,
                     LoginFrame &out, std::string &error);

// Inflate wire and compare to plain. Used as a boot check.
bool loginFrameRoundTrip(const LoginFrame &frame, std::string &error);



// Connect to loopback only. An empty host means the loopback address.
// A resolved address outside the loopback range is rejected and nothing
// is sent. port is the caller's lab port.


#endif
