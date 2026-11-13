#include "link.hpp"

#include <bzlib.h>
#include <zlib.h>

#include <algorithm>

namespace graal3d {

namespace {

// Out-of-band packet types (udp-session.md §3).
enum : uint8_t {
  kChallengeRequest = 0x1A,
  kChallengeReject = 0x1C,
  kChallengeResponse = 0x1E,
  kConnectRequest = 0x20,
  kConnectReject = 0x22,
  kConnectAccept = 0x24,
  kDisconnect = 0x26,
};

// Data-link packet types (§4).
enum { kData = 0, kPing = 1, kAck = 2 };

constexpr int kMaxInFlight = 30;
constexpr uint32_t kEventWindow = 126;

std::string inflateZlib(const std::string& in) {
  z_stream z{};
  if (inflateInit(&z) != Z_OK) return {};
  std::string out;
  z.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(in.data()));
  z.avail_in = static_cast<uInt>(in.size());
  char buf[4096];
  int rc = Z_OK;
  while (rc == Z_OK) {
    z.next_out = reinterpret_cast<Bytef*>(buf);
    z.avail_out = sizeof buf;
    rc = inflate(&z, Z_NO_FLUSH);
    out.append(buf, sizeof buf - z.avail_out);
    if (rc == Z_BUF_ERROR && z.avail_in == 0) break;
  }
  inflateEnd(&z);
  return out;
}

std::string inflateBzip2(const std::string& in) {
  for (unsigned size = 1u << 14; size <= (1u << 26); size <<= 1) {
    std::string out(size, '\0');
    unsigned len = size;
    const int rc = BZ2_bzBuffToBuffDecompress(&out[0], &len, const_cast<char*>(in.data()),
                                              static_cast<unsigned>(in.size()), 0, 0);
    if (rc == BZ_OK) {
      out.resize(len);
      return out;
    }
    if (rc != BZ_OUTBUFF_FULL) break;
  }
  return {};
}

}  // namespace

int protocolForBuild(const std::string& build) {
  if (build.rfind("5.", 0) == 0) return 24;
  if (build.rfind("4.20", 0) == 0) return 21;
  return 19;
}

Link::Link(LinkLogin login, Callbacks cb) : login_(std::move(login)), cb_(std::move(cb)) {}

void Link::log(const std::string& s) {
  if (cb_.log) cb_.log(s);
}

void Link::fail(const std::string& reason) {
  if (state_ == State::Closed) return;
  state_ = State::Closed;
  log("Graal3D: " + reason);
  if (cb_.error) cb_.error(reason);
}

void Link::setStep(int s) {
  step_ = s;
  if (cb_.loginStep) cb_.loginStep(s);
}

std::vector<std::string> Link::takeOutgoing() {
  std::vector<std::string> v;
  v.swap(out_);
  return v;
}

// ---- Handshake --------------------------------------------------------

void Link::start(uint32_t now) {
  now_ = started_ = lastResend_ = now;
  state_ = State::Challenging;
  sendChallenge();
}

void Link::sendChallenge() {
  BitWriter w;
  w.u8(kChallengeRequest);
  w.u32(login_.connectSequence);
  out_.push_back(w.bytes());
}

void Link::sendConnectRequest() {
  BitWriter w;
  w.u8(kConnectRequest);
  w.u32(login_.connectSequence);
  for (uint32_t d : digest_) w.u32(d);
  w.string("GameConnection");
  w.u32(0);           // net class group: game
  w.u32(0xFFFFFFFFu);  // class CRC: the static table's (torque/wire-by-build.md)
  w.string("Graal3D");
  w.u32(static_cast<uint32_t>(login_.protocol));  // current
  w.u32(static_cast<uint32_t>(login_.protocol));  // minimum
  w.string(login_.password);  // the account password, in clear, as the real clients send it
  w.u32(2);
  w.string(login_.account);
  w.string(login_.nickname);
  out_.push_back(w.bytes());
}

void Link::onAccept(BitReader& r) {
  // Graal's class table, then the protocol (§3). Protocol 19 numbers the
  // types object 0, datablock 1, event 2; 21 and 24 object 0, event 1.
  const bool p19 = login_.protocol == 19;
  objectClasses_.clear();
  eventClasses_.clear();
  datablockClasses_.clear();
  while (r.flag() && !r.overrun()) {
    const int type = static_cast<int>(r.bits(12));
    const int id = static_cast<int>(r.bits(12));
    const std::string name = r.string();
    if (type == 0) objectClasses_[id] = name;
    else if (p19 && type == 1) datablockClasses_[id] = name;
    else if (type == (p19 ? 2 : 1)) eventClasses_[id] = name;
  }
  const uint32_t protocol = r.u32();
  if (r.overrun()) return fail("bad connect accept");
  if (protocol != static_cast<uint32_t>(login_.protocol))
    return fail("the server runs protocol " + std::to_string(protocol) + ", this client " +
                std::to_string(login_.protocol));
  state_ = State::Connected;
  lastHeard_ = now_;
  log("Connection established");
  if (login_.protocol == 19) log("Graal3D: protocol 19 game data is not read yet; keeping the link alive");
  sendDataPacket();
}

// ---- Receiving --------------------------------------------------------

void Link::receive(const std::string& d, uint32_t now) {
  now_ = now;
  if (d.empty() || state_ == State::Idle || state_ == State::Closed) return;
  BitReader r(d);
  if (!(static_cast<uint8_t>(d[0]) & 1)) {
    const uint8_t type = r.u8();
    const uint32_t seq = r.u32();
    if (seq != login_.connectSequence) return;  // another link's packet
    switch (type) {
      case kChallengeResponse:
        if (state_ != State::Challenging) return;
        for (auto& v : digest_) v = r.u32();
        state_ = State::Connecting;
        lastResend_ = now;
        sendConnectRequest();
        return;
      case kConnectAccept:
        if (state_ != State::Connecting) return;
        onAccept(r);
        return;
      case kConnectReject:
      case kChallengeReject: {
        const std::string reason = type == kConnectReject ? r.string() : std::string("challenge rejected");
        if (state_ == State::Connecting || state_ == State::Challenging) fail("connection rejected: " + reason);
        return;
      }
      case kDisconnect: {
        const std::string reason = r.string();
        if (state_ == State::Connected) fail(reason.empty() ? "disconnected by the 3D server" : reason);
        return;
      }
      default:
        return;
    }
  }
  if (state_ != State::Connected) return;
  onDataPacket(r, now);
}

void Link::onDataPacket(BitReader& r, uint32_t now) {
  r.flag();  // the data-link bit
  if (r.bits(1) != (login_.connectSequence & 1)) return;
  uint32_t seq = r.bits(9);
  uint32_t ack = r.bits(9);
  const int type = static_cast<int>(r.bits(2));
  const int ackBytes = static_cast<int>(r.bits(3));
  if (ackBytes > 4) return;
  const uint32_t mask = r.bits(8 * ackBytes);
  if (r.overrun()) return;

  seq |= lastRecvSeq_ & ~0x1FFu;
  if (seq < lastRecvSeq_) seq += 0x200;
  if (seq > lastRecvSeq_ + 31) return;
  ack |= highestAckedSeq_ & ~0x1FFu;
  if (ack < highestAckedSeq_) ack += 0x200;
  if (ack > sendSeq_) return;  // acks a packet we never sent

  lastHeard_ = now;
  notify(ack, mask, 8 * ackBytes);

  const uint32_t advance = seq - lastRecvSeq_;
  if (advance > 0) {
    recvMask_ = advance >= 32 ? 0 : recvMask_ << advance;
    lastRecvSeq_ = seq;
  }
  if (type == kPing) {
    sendAckPacket(kAck);
    return;
  }
  if (type != kData) return;
  if (advance == 0) return;  // a duplicate
  recvMask_ |= 1;

  r.resetStrings();
  if (r.flag()) {  // current rate
    r.bits(10);
    r.bits(10);
  }
  if (r.flag()) {  // max rate
    r.bits(10);
    r.bits(10);
  }
  const size_t controlBefore = static_cast<size_t>(controlGhost_ + 1);
  if (login_.protocol != 19) {
    const bool sectionOk = readServerGameSection(r);
    if (sectionOk) {
      // Unguaranteed events, then guaranteed ones (§5).
      while (r.flag() && !r.overrun()) {
        const int classId = static_cast<int>(r.bits(12));
        InEvent ev;
        if (readEvent(r, classId, ev)) deliver(ev);
      }
      long long prev = -2;
      while (r.flag() && !r.overrun()) {
        long long s;
        if (r.flag()) {
          s = prev + 1;
        } else {
          uint32_t s7 = r.bits(7);
          uint32_t full = (nextInEventSeq_ & ~0x7Fu) | s7;
          if (full < nextInEventSeq_) full += 0x80;
          s = full;
        }
        const int classId = static_cast<int>(r.bits(12));
        InEvent ev;
        const bool ok = readEvent(r, classId, ev);
        if (s >= 0 && ok && static_cast<uint32_t>(s) >= nextInEventSeq_) heldEvents_[static_cast<uint32_t>(s)] = ev;
        prev = s;
      }
      for (auto it = heldEvents_.find(nextInEventSeq_); it != heldEvents_.end();
           it = heldEvents_.find(nextInEventSeq_)) {
        const InEvent ev = it->second;
        heldEvents_.erase(it);
        ++nextInEventSeq_;
        deliver(ev);
        if (state_ != State::Connected) return;
      }
      readGhosts(r);
    }
  }
  if (state_ != State::Connected) return;
  // Every server data packet is answered at once: with our data packet
  // when we have something to say, else with an ack (§4, lab).
  const bool newControl = static_cast<size_t>(controlGhost_ + 1) != controlBefore;
  if (!outEvents_.empty() || newControl) sendDataPacket();
  else sendAckPacket(kAck);
}

bool Link::readServerGameSection(BitReader& r) {
  // §6, server to client.
  if (r.flag() && r.flag()) {
    serverTime_ = r.u32();
    const int idx = static_cast<int>(r.bits(12));
    auto it = ghosts_.find(idx);
    GameObjectState scratch;
    GameObjectState& o = it != ghosts_.end() ? it->second.object : scratch;
    if (!readGameObjectUpdate(r, o)) return false;
    if (it == ghosts_.end() || it->second.className != "GameObject") {
      log("Graal3D: control object " + std::to_string(idx) + " is not a GameObject ghost");
    } else if (controlGhost_ != idx) {
      controlGhost_ = idx;
      sendOwnState_ = true;
      // Step 5 is set by the first control object after the last mission
      // phase; one that comes earlier leaves the client at step 4 (§6).
      if (step_ == 4) {
        log("Initial Control Object");
        setStep(5);
        // Step 6 when no file download is active (torque/5007-g3d.md).
        // This library does not see the engine's TCP downloads yet.
        setStep(6);
      }
    }
  }
  if (r.flag()) {
    const int idx = static_cast<int>(r.bits(12));
    if (r.flag()) {
      auto it = ghosts_.find(idx);
      if (it == ghosts_.end() || it->second.className != "Camera") {
        log("Received unknown camera object");
        return false;  // the rest of the packet is lost, as in the original
      }
      if (!readCameraUpdate(r, it->second.camera)) return false;
    }
  }
  if (r.flag()) r.bits(8);  // field of view
  return !r.overrun();
}

bool Link::readEvent(BitReader& r, int classId, InEvent& ev) {
  const uint32_t len = r.bits(14);
  const size_t start = r.pos();
  auto it = eventClasses_.find(classId);
  ev.className = it == eventClasses_.end() ? std::string() : it->second;
  const std::string& c = ev.className;
  if (c == "NetStringEvent") {
    ev.tagId = static_cast<int>(r.bits(5));
    ev.text = r.pstring();
  } else if (c == "RemoteCommandEvent") {
    const int argc = static_cast<int>(r.bits(5));
    for (int i = 0; i < argc && !r.overrun(); ++i) {
      const int code = static_cast<int>(r.bits(2));
      std::string v;
      if (code == 1) {
        v = r.pstring();
      } else if (code == 2) {
        v = std::to_string(r.bits(5));
      } else if (code == 3) {
        const bool neg = r.flag();
        long long n;
        if (r.flag()) n = r.bits(7);
        else if (r.flag()) n = r.bits(15);
        else n = r.bits(31);
        v = std::to_string(neg ? -n : n);
      }
      ev.args.emplace_back(code, v);
    }
  } else if (c == "BigDataStartEvent") {
    ev.transfer = static_cast<int>(r.bits(16));
    ev.big.s1 = r.pstring();
    ev.big.s2 = r.pstring();
    ev.big.s3 = r.pstring();
    ev.total = r.bits(24);
    ev.compression = static_cast<int>(r.bits(3));
  } else if (c == "BigDataChunkEvent") {
    ev.transfer = static_cast<int>(r.bits(16));
    const int n = static_cast<int>(r.bits(8));
    for (int i = 0; i < n; ++i) ev.big.data.push_back(static_cast<char>(r.u8()));
  }
  // Everything else (ConnectionMessageEvent, the terrain events, a class
  // the table did not name) is skipped by its length.
  const bool ok = !r.overrun() && r.pos() <= start + len;
  r.seek(start + len);
  return ok;
}

void Link::deliver(const InEvent& ev) {
  const std::string& c = ev.className;
  if (c == "NetStringEvent") {
    tags_[ev.tagId & 31] = ev.text;
  } else if (c == "RemoteCommandEvent") {
    std::vector<std::string> args;
    for (const auto& [code, v] : ev.args) args.push_back(code == 2 ? tags_[std::stoi(v) & 31] : v);
    onCommand(args);
  } else if (c == "BigDataStartEvent") {
    transfers_[ev.transfer] = ev;
    if (ev.total == 0) bigDataDone(ev.transfer);
  } else if (c == "BigDataChunkEvent") {
    auto it = transfers_.find(ev.transfer);
    if (it == transfers_.end()) return;
    it->second.big.data += ev.big.data;
    if (it->second.big.data.size() >= it->second.total) bigDataDone(ev.transfer);
  }
}

void Link::bigDataDone(int transfer) {
  auto it = transfers_.find(transfer);
  if (it == transfers_.end()) return;
  BigText t = it->second.big;
  if (it->second.compression == 1) t.data = inflateZlib(t.data);
  else if (it->second.compression == 2) t.data = inflateBzip2(t.data);
  transfers_.erase(it);
  if (cb_.text) cb_.text(t);
}

void Link::onCommand(const std::vector<std::string>& args) {
  if (args.empty()) return;
  commands_.push_back(args[0]);
  // The mission start (§7, torque/4208-g3d.md, torque/5007-g3d.md). Any
  // other command name is ignored, as the real clients do.
  if (args[0] == "MissionStartPhase1") {
    log("Phase 1: Download Ghost Objects");
    setStep(2);
    sendCommand("MissionStartPhase1Ack");
  } else if (args[0] == "MissionStartPhase2") {
    log("Phase 2: Mission Lighting");
    setStep(3);
    // No scene lighting to compute yet: lighting is done at once.
    log("Mission lighting done");
    setStep(4);
    sendCommand("MissionStartPhase2Ack");
  }
}

void Link::readGhosts(BitReader& r) {
  // §8.
  if (!r.flag()) return;
  const int width = static_cast<int>(r.bits(4));
  while (r.flag() && !r.overrun()) {
    const int idx = static_cast<int>(r.bits(width));
    if (r.flag()) {
      ghosts_.erase(idx);
      if (controlGhost_ == idx) controlGhost_ = -1;
      continue;
    }
    const int classId = static_cast<int>(r.bits(12));
    const uint32_t len = r.bits(14);
    const size_t start = r.pos();
    auto cls = objectClasses_.find(classId);
    const std::string name = cls == objectClasses_.end() ? std::string("?") : cls->second;
    Ghost& g = ghosts_[idx];
    if (g.className != name) {
      g = Ghost();
      g.className = name;
    }
    readGhostPayload(r, g);
    ++g.updates;
    r.seek(start + len);
  }
}

bool Link::readGhostPayload(BitReader& r, Ghost& g) {
  if (g.className == "GameObject") return readGameObjectUpdate(r, g.object);
  if (g.className == "Camera") return readCameraUpdate(r, g.camera);
  if (g.className == "Sun") return readSunUpdate(r, g.sun);
  if (g.className == "Sky") return readSkyUpdate(r, g.sky);
  return true;  // read by length only
}

// ---- Acks -------------------------------------------------------------

void Link::notify(uint32_t highestAck, uint32_t mask, int maskBits) {
  for (uint32_t s = highestAckedSeq_ + 1; s <= highestAck; ++s) {
    const uint32_t back = highestAck - s;
    const bool delivered = static_cast<int>(back) < maskBits && ((mask >> back) & 1);
    while (!inFlight_.empty() && inFlight_.front().seq < s) inFlight_.pop_front();
    if (inFlight_.empty() || inFlight_.front().seq != s) continue;
    SentPacket p = std::move(inFlight_.front());
    inFlight_.pop_front();
    if (delivered) {
      lastRecvAckAck_ = std::max(lastRecvAckAck_, p.recvSeqAtSend);
    } else {
      // A lost packet's events go out again, in order (§5).
      for (auto it = p.events.rbegin(); it != p.events.rend(); ++it) outEvents_.push_front(std::move(*it));
    }
  }
  if (highestAck > highestAckedSeq_) highestAckedSeq_ = highestAck;
}

// ---- Sending ----------------------------------------------------------

void Link::writeHeader(BitWriter& w, int type) {
  w.flag(true);
  w.bits(login_.connectSequence & 1, 1);
  w.bits(sendSeq_ & 0x1FF, 9);
  w.bits(lastRecvSeq_ & 0x1FF, 9);
  w.bits(static_cast<uint32_t>(type), 2);
  const uint32_t ackBytes = std::min<uint32_t>(4, (lastRecvSeq_ - lastRecvAckAck_ + 7) / 8);
  w.bits(ackBytes, 3);
  for (uint32_t i = 0; i < ackBytes; ++i) w.bits((recvMask_ >> (8 * i)) & 0xFF, 8);
}

void Link::sendAckPacket(int type) {
  BitWriter w;
  writeHeader(w, type);
  out_.push_back(w.bytes());
  lastSend_ = now_;
}

void Link::writeClientGameSection(BitWriter& w) {
  // §6, client to server (protocols 21 and 24: no moves).
  w.flag(true);  // first person
  const auto it = ghosts_.find(controlGhost_);
  const GameObjectState* o = controlGhost_ >= 0 && it != ghosts_.end() ? &it->second.object : nullptr;
  w.f32(o ? o->position.x : 0);
  w.f32(o ? o->position.y : 0);
  w.f32(o ? o->position.z : 0);
  if (w.flag(o != nullptr)) w.bits(static_cast<uint32_t>(controlGhost_), 12);
  if (login_.protocol == 19) {
    // Stock TGE: the client sends moves (none).
    w.flag(false);
    w.bits(0, 32);
    w.bits(0, 5);
  } else if (w.flag(o != nullptr)) {
    GameObjectState back = *o;
    // A zero rotation goes back as axis (1, 0, 0), angle 0 (lab).
    if (back.angle == 0) back.axis = {1, 0, 0};
    // The first packet after the control object carries its shape,
    // transform and flags back; later ones an empty update.
    writeGameObjectUpdate(w, back, sendOwnState_ ? ((1u << 2) | (1u << 4) | (1u << 12)) : 0);
    sendOwnState_ = false;
  }
  w.flag(false);  // field of view
}

void Link::sendDataPacket() {
  if (inFlight_.size() >= kMaxInFlight) {
    sendAckPacket(kAck);
    return;
  }
  ++sendSeq_;
  BitWriter w;
  writeHeader(w, kData);
  w.flag(false);  // current rate unchanged
  if (w.flag(!firstDataSent_)) {
    // The real client's first data packet: 32 ms, 450 bytes (§4).
    w.bits(32, 10);
    w.bits(static_cast<uint32_t>(kPacketBytes), 10);
  }
  firstDataSent_ = true;
  writeClientGameSection(w);
  SentPacket p;
  p.seq = sendSeq_;
  p.recvSeqAtSend = lastRecvSeq_;
  w.flag(false);  // no unguaranteed events
  long long prev = -2;
  const uint32_t oldest = outEvents_.empty() ? 0 : outEvents_.front().seq;
  while (!outEvents_.empty()) {
    OutEvent& ev = outEvents_.front();
    if (ev.seq - oldest >= kEventWindow) break;
    if (w.pos() + 40 + ev.payload.pos() > (kPacketBytes - 50) * 8 && !p.events.empty()) break;
    w.flag(true);
    if (!w.flag(static_cast<long long>(ev.seq) == prev + 1)) w.bits(ev.seq & 0x7F, 7);
    w.bits(static_cast<uint32_t>(ev.classId), 12);
    w.bits(static_cast<uint32_t>(ev.payload.pos()), 14);
    w.append(ev.payload);
    prev = ev.seq;
    p.events.push_back(std::move(ev));
    outEvents_.pop_front();
  }
  w.flag(false);  // end of guaranteed events
  w.flag(false);  // the client ghosts nothing
  inFlight_.push_back(std::move(p));
  out_.push_back(w.bytes());
  lastSend_ = now_;
}

int Link::eventClassId(const std::string& name) const {
  for (const auto& [id, n] : eventClasses_)
    if (n == name) return id;
  return -1;
}

void Link::queueEvent(const std::string& className, BitWriter payload) {
  const int id = eventClassId(className);
  if (id < 0) {
    log("Graal3D: the server named no " + className + "; not sent");
    return;
  }
  OutEvent ev;
  ev.classId = id;
  ev.payload = std::move(payload);
  ev.seq = nextOutEventSeq_++;
  outEvents_.push_back(std::move(ev));
}

void Link::sendCommand(const std::string& name) {
  // The real client answers with the name as a plain string, not a tag (§5).
  BitWriter p;
  p.bits(1, 5);
  p.bits(1, 2);
  p.pstring(name);
  queueEvent("RemoteCommandEvent", std::move(p));
}

void Link::queueEventLine(const std::string& line) {
  if (!line.empty()) eventLines_.push_back(line);
}

void Link::flushEventLines() {
  if (eventLines_.empty() || state_ != State::Connected) return;
  std::string text;
  for (const auto& l : eventLines_) text += l + "\n";
  eventLines_.clear();
  // One `events` message: a start event, then chunks of up to 191 bytes.
  // Sent uncompressed (the real client zips over 49 bytes; the reader
  // takes all three forms).
  const int id = nextTransfer_++ & 0xFFFF;
  BitWriter start;
  start.bits(static_cast<uint32_t>(id), 16);
  start.pstring("");
  start.pstring("events");
  start.pstring("");
  start.bits(static_cast<uint32_t>(text.size()), 24);
  start.bits(0, 3);
  queueEvent("BigDataStartEvent", std::move(start));
  for (size_t at = 0; at < text.size(); at += 191) {
    const std::string part = text.substr(at, 191);
    BitWriter chunk;
    chunk.bits(static_cast<uint32_t>(id), 16);
    chunk.bits(static_cast<uint32_t>(part.size()), 8);
    for (unsigned char c : part) chunk.u8(c);
    queueEvent("BigDataChunkEvent", std::move(chunk));
  }
}

void Link::disconnect(const std::string& reason) {
  if (state_ == State::Connected || state_ == State::Connecting) {
    BitWriter w;
    w.u8(kDisconnect);
    w.u32(login_.connectSequence);
    w.string(reason);
    out_.push_back(w.bytes());
  }
  state_ = State::Closed;
}

void Link::tick(uint32_t now) {
  now_ = now;
  switch (state_) {
    case State::Challenging:
    case State::Connecting:
      if (now - started_ > kConnectTimeoutMs) {
        fail("The connection to the Graal3D server couldn't be established.");
      } else if (now - lastResend_ >= kResendMs) {
        lastResend_ = now;
        if (state_ == State::Challenging) sendChallenge();
        else sendConnectRequest();
      }
      return;
    case State::Connected:
      if (now - lastHeard_ > kSilenceTimeoutMs) {
        fail("The 3D server connection has timed out");
        return;
      }
      if (!outEvents_.empty() || now - lastSend_ >= kKeepAliveMs) sendDataPacket();
      return;
    default:
      return;
  }
}

}  // namespace graal3d
