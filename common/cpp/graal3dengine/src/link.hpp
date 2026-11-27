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
  // Replaying a recorded session (tools/g3d_replay.cpp): the server's acks
  // name the recorded client's packets, not ours, so they are not checked
  // against what this link sent and resend nothing.
  bool replay = false;
  // The Seihai `seihai3d` extension (Graal_analysis torque/seihai3d-ext-v1.md,
  // seihai-core protocol::three_d_ext): when set, the connect request
  // carries a third argument `seihai3d/<version>/<caps hex>`. A real 5.12
  // never sends one, so a server answers only us; one that does not
  // answer leaves the link a plain 5.12.
  bool seihai3dHello = false;
  uint32_t seihai3dCaps = 0;
};

// seihai3d v1 (EXT_VERSION and the capability bits in seihai-core).
namespace seihai3d {
constexpr int kVersion = 1;
constexpr uint32_t kFrameStats = 1u << 0;
constexpr uint32_t kChat3d = 1u << 1;
constexpr uint32_t kKnownV1 = 0xFF;
// The hello argument, `seihai3d/1/00000003`.
std::string helloArg(int version, uint32_t caps);
}  // namespace seihai3d

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
    // seihai3d chat_3d: a chat line from the server (`seihai3dChat`).
    std::function<void(const std::string& account, const std::string& text)> chat3d;
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
  // seihai3d: the version and capabilities the server agreed to (0 and 0
  // on a server without the extension, or before its reply).
  int extVersion() const { return extVersion_; }
  uint32_t extCaps() const { return extCaps_; }
  bool extHas(uint32_t cap) const { return (extCaps_ & cap) == cap && cap; }
  // frame_stats: `seihai3dStats <fps> <frame ms p95> <ghosts> <draw ms>`
  // once agreed; nothing otherwise.
  void sendFrameStats(double fps, double p95Ms, int ghosts, double drawMs);
  int protocol() const { return login_.protocol; }
  int loginStep() const { return step_; }
  const GhostTable& ghosts() const { return ghosts_; }
  // The latest zlib stream of each terrain chunk (index y * 16 + x) the
  // server sent once a TerrainBlock was there, and how many arrived.
  const std::map<int, std::string>& terrainChunks() const { return terrainChunks_; }
  int terrainChunkCount() const { return terrainChunkCount_; }
  int controlGhost() const { return controlGhost_; }
  // The ghost the server last named as the camera (-1 before any), and the
  // last field of view it sent in degrees (0 before any).
  int cameraGhost() const { return cameraGhost_; }
  int fieldOfView() const { return fov_; }
  uint32_t serverTime() const { return serverTime_; }
  // Where the control object is: while it has a movement object, where
  // its movement has taken it; otherwise its transform's position.
  Vec3 controlPosition() const;
  // Moves the client's own GameObject control object to `at` at once, and
  // sends its transform in the next data packet (the server reads the
  // position at the head of the client game section, and the transform
  // section). For a host whose player moves its own object: a script
  // setting player.position, or keys. Nothing without a GameObject
  // control object.
  void moveControlTo(const Vec3& at);
  // The movetype of the control object's movement object ("" for none).
  const std::string& controlMovetype() const { return move_.type; }
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
    // TerrainChunkEvent (the stream in big.data)
    int chunkX = 0, chunkY = 0;
    // GhostAlwaysObjectEvent
    int ghostIndex = -1;
    bool hasGhost = false;
    Ghost ghost;
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
  void requestTerrainOnce();
  void deliver(const InEvent& ev);
  void onCommand(const std::vector<std::string>& args);
  void readGhosts(BitReader& r);
  bool readGhostPayload(BitReader& r, Ghost& g, uint32_t* sections = nullptr);
  void serverMovedControl(int ghost, uint32_t sections);
  void sendDataPacket();
  void sendAckPacket(int type);
  void writeHeader(BitWriter& w, int type);
  void writeClientGameSection(BitWriter& w);
  void sendCommand(const std::string& name, const std::vector<std::string>& args = {});
  int eventClassId(const std::string& name) const;
  void queueEvent(const std::string& className, BitWriter payload);
  void notify(uint32_t highestAck, uint32_t mask, int maskBits);
  void bigDataDone(int transfer);
  void updateOwnMovement();
  void advanceOwnMovement();

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
  bool sendCameraState_ = false;  // a Camera control object's first update is due
  std::map<int, std::string> terrainChunks_;
  int terrainChunkCount_ = 0;
  bool terrainRequested_ = false;
  int cameraGhost_ = -1;
  int fov_ = 0;
  bool sendOwnState_ = false;
  bool sendOwnTransform_ = false;  // moveControlTo() since the last data packet

  // The control object's movement object (E#505): a server moves the
  // player by giving its control object a movetype and movement data; the
  // client moves the object itself and reports where it is. `list` jumps
  // onto each position; `interpolate` and `rigid` glide to each target.
  // The glide time is the rebuild's own: the time between the last two
  // targets (1 s for the first), which gives the 0.25 to 0.5 unit lag the
  // lab saw with a target 0.5 units further each second.
  struct OwnMovement {
    int ghost = -1;
    std::string type;
    uint32_t serial = 0;
    Vec3 from, to, current;
    uint32_t startMs = 0, lastTargetMs = 0, durationMs = 1000;
    bool haveTarget = false;
    bool announce = false;  // sections 3, 5, 6 and 13 once
  };
  OwnMovement move_;
  uint32_t serverTime_ = 0;
  std::vector<std::string> commands_;
  int extVersion_ = 0;
  uint32_t extCaps_ = 0;
  bool phase1Seen_ = false;
};

}  // namespace graal3d
