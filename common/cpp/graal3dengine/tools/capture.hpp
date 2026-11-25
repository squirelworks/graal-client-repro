// Reading a recorded 3D session back: the UDP datagrams of a packet
// capture (pcap or pcapng), and a Link fed with the server's side of them.
//
// A capture taken next to a real client holds the server's packets
// exactly as that client got them. Feeding them to a Link in replay mode
// (LinkLogin::replay) rebuilds the ghost table the client built, which the
// renderer can then draw. The tool g3d-replay (g3d_replay.cpp) is the
// command-line front end; nothing here is part of the library.
#pragma once

#include "link.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace graal3d::capture {

struct Datagram {
  double time = 0;  // seconds since the capture's first packet
  uint32_t srcIp = 0, dstIp = 0;  // host order, a.b.c.d = a << 24 | ...
  uint16_t srcPort = 0, dstPort = 0;
  bool udp = true;  // false: a TCP segment's payload (not reassembled)
  std::string payload;
};

struct CaptureStats {
  size_t frames = 0, udp = 0, tcp = 0, skipped = 0, fragments = 0;
};

// IPv4 UDP datagrams and TCP segment payloads, in capture order. Link
// types: Ethernet (with VLAN tags), Linux cooked v1 and v2, raw IP, BSD
// loopback. False with `error` when the file is not a capture this reads.
bool readCapture(const std::string& bytes, std::vector<Datagram>& out, CaptureStats& stats, std::string& error);

std::string ipText(uint32_t ip);

struct ReplayOptions {
  int protocol = 24;
  // Stop before the first server packet later than this (seconds after
  // the challenge); negative for the whole capture.
  double stopAt = -1;
  // The server's UDP port; 0 takes it from the first challenge request.
  uint16_t serverPort = 0;
};

struct ReplayEvent {
  double time = 0;
  std::string what;  // a log line, "step N", "text ..." or "error ..."
};

struct ReplayResult {
  bool found = false;  // a challenge request was in the capture
  uint32_t sequence = 0;
  uint32_t serverIp = 0, clientIp = 0;
  uint16_t serverPort = 0, clientPort = 0;
  size_t serverPackets = 0, clientPackets = 0;
  double lastTime = 0;  // of the last server packet fed, after the challenge
  std::vector<ReplayEvent> events;
  std::vector<BigText> texts;
};

// Makes `link` (protocol, the session's connect sequence, replay mode)
// and feeds it the server's side of the first session in `datagrams`,
// starting it at the client's challenge request.
ReplayResult replay(const std::vector<Datagram>& datagrams, const ReplayOptions& options,
                    std::unique_ptr<Link>& link);

}  // namespace graal3d::capture
