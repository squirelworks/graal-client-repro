// The Torque UDP link of a Graal 4.x/5.x 3D session, client side
// (Graal_analysis torque/udp-session.md, graal3d/torque-engine-4x.md,
// torque/4208-g3d.md, torque/5007-g3d.md).
//
// The link knows nothing about sockets or clocks: datagrams go in through
// receive(), come out of takeOutgoing(), and time is the caller's
// millisecond count. The library glue (exports.cpp) puts a UDP socket and
// the engine on either side.
//
// Protocols 24 (5.00r7, 5.12) and 21 (read on the 2006-09-19 Mac build,
// recorded as 4.20r6 but in fact 4.11 Mac; assumed for 4.20) share their packet shapes and
// run the whole start: handshake, packet numbering and acks, guaranteed
// events, the tagged mission commands, ghosts, the control object and the
// login steps 2 to 6. Protocol 19 (4.04r2) is stock TGE past the handshake
// (datablocks, moves) and has never been run past it on a real client, so
// it connects and keeps the link alive but reads no game data.
#pragma once

#include "bits.hpp"
#include "world.hpp"

#include <deque>
#include <functional>
#include <map>
#include <string>
#include <vector>

namespace graal3d {

// The protocol of a launcher build: 19 for 4.04r2 (and 3.153), 21 for the
// 4.20 builds, 24 for 5.00r7 and 5.12 (torque/network.md).
int protocolForBuild(const std::string& build);

struct LinkLogin {
  std::string account, nickname, password;
  int protocol = 24;
  uint32_t connectSequence = 0x400;  // the client's choice; 0x400 in the 5.12 run
};

// A Graal text message over BigData (udp-session.md §7).
struct BigText {
  std::string s1, s2, s3, data;
};

class Link {
 public:
  enum class State { Idle, Challenging, Connecting, Connected, Closed };

  struct Callbacks {
    std::function<void(const std::string&)> log;
    // Login step changes, as onGraal3DLoginStep sees them (2 to 6).
    std::function<void(int)> loginStep;
    // The link failed or timed out; the engine drops the TCP side too.
    std::function<void(const std::string&)> error;
    // Server text: weapons, flags, events (s2 selects the action).
    std::function<void(const BigText&)> text;
  };

  Link(LinkLogin login, Callbacks cb);

  void start(uint32_t now);
  void receive(const std::string& datagram, uint32_t now);
  void tick(uint32_t now);
  // Sends the disconnect (0x26) and closes.
  void disconnect(const std::string& reason);
  std::vector<std::string> takeOutgoing();

  // The client's "events" message to the server: lines `w <weapon>`,
  // `s <name>=<value>`, `t weapon,<name>,<params>` (§7).
  void queueEventLine(const std::string& line);
  void flushEventLines();

  State state() const { return state_; }
  int protocol() const { return login_.protocol; }
  int loginStep() const { return step_; }
  const GhostTable& ghosts() const { return ghosts_; }
  int controlGhost() const { return controlGhost_; }
  uint32_t serverTime() const { return serverTime_; }
  // The class table from the connect accept: server id -> name, by type.
  const std::map<int, std::string>& objectClasses() const { return objectClasses_; }
  const std::map<int, std::string>& eventClasses() const { return eventClasses_; }
  uint32_t sentDataPackets() const { return sendSeq_; }
  const std::vector<std::string>& commandsReceived() const { return commands_; }

  // Timing (ms). The 5.12 client gives up on the handshake after about
  // 15 s (§1); the Seihai server times a link out after 30 s of silence.
  static constexpr uint32_t kResendMs = 500;
  static constexpr uint32_t kConnectTimeoutMs = 15000;
  static constexpr uint32_t kSilenceTimeoutMs = 30000;
  static constexpr uint32_t kKeepAliveMs = 1000;
  static constexpr size_t kPacketBytes = 450;

 private:
  struct OutEvent {
    int classId = 0;  // the server's id for our class name
    BitWriter payload;
    uint32_t seq = 0;
  };
  struct SentPacket {
    uint32_t seq = 0;
    uint32_t recvSeqAtSend = 0;
    std::vector<OutEvent> events;
  };
  struct InEvent {
    std::string className;
    // RemoteCommandEvent: argument codes and values.
    std::vector<std::pair<int, std::string>> args;
    // NetStringEvent
    int tagId = 0;
    std::string text;
    // BigData
    int transfer = 0;
    BigText big;
    uint32_t total = 0;
    int compression = 0;
  };

  void log(const std::string& s);
  void fail(const std::string& reason);
  void setStep(int s);
  void sendChallenge();
  void sendConnectRequest();
  void onAccept(BitReader& r);
  void onDataPacket(BitReader& r, uint32_t now);
  bool readServerGameSection(BitReader& r);
  bool readEvent(BitReader& r, int classId, InEvent& ev);
  void deliver(const InEvent& ev);
  void onCommand(const std::vector<std::string>& args);
  void readGhosts(BitReader& r);
  bool readGhostPayload(BitReader& r, Ghost& g);
  void sendDataPacket();
  void sendAckPacket(int type);
  void writeHeader(BitWriter& w, int type);
  void writeClientGameSection(BitWriter& w);
  void sendCommand(const std::string& name);
  int eventClassId(const std::string& name) const;
  void queueEvent(const std::string& className, BitWriter payload);
  void notify(uint32_t highestAck, uint32_t mask, int maskBits);
  void bigDataDone(int transfer);

  LinkLogin login_;
  Callbacks cb_;
  State state_ = State::Idle;
  std::vector<std::string> out_;
  uint32_t started_ = 0, lastSend_ = 0, lastHeard_ = 0, lastResend_ = 0, now_ = 0;
  uint32_t digest_[4] = {0, 0, 0, 0};

  std::map<int, std::string> objectClasses_, eventClasses_, datablockClasses_;

  // Packet numbering (§4).
  uint32_t sendSeq_ = 0;          // last data sequence sent
  uint32_t highestAckedSeq_ = 0;  // highest of ours the server acked
  uint32_t lastRecvSeq_ = 0;      // last sequence received
  uint32_t recvMask_ = 0;         // bit i = lastRecvSeq_ - i received
  uint32_t lastRecvAckAck_ = 0;   // our acks the server has seen up to
  bool firstDataSent_ = false;
  std::deque<SentPacket> inFlight_;

  // Guaranteed events (§5).
  std::deque<OutEvent> outEvents_;
  uint32_t nextOutEventSeq_ = 0;
  uint32_t nextInEventSeq_ = 0;
  std::map<uint32_t, InEvent> heldEvents_;
  std::string tags_[32];

  // BigData transfers in, by id.
  std::map<int, InEvent> transfers_;
  std::vector<std::string> eventLines_;
  int nextTransfer_ = 0;

  // The world.
  int step_ = 0;
  GhostTable ghosts_;
  int controlGhost_ = -1;
  bool sendOwnState_ = false;
  uint32_t serverTime_ = 0;
  std::vector<std::string> commands_;
};

}  // namespace graal3d
