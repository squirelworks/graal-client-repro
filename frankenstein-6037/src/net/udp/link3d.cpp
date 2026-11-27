#include "link3d.hpp"

#include <chrono>
#include <sstream>

namespace Frank {

uint32_t Link3D::now_ms() {
  using namespace std::chrono;
  return static_cast<uint32_t>(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
}

bool Link3D::open(const std::string& host, uint16_t port, const graal3d::LinkLogin& login) {
  close();
  // The client's own UDP port is random; the fixed-port option (14899) is
  // not read, as in the 5.12 repro.
  if (!socket_.open(0) || !socket_.setPeer(host, port)) {
    socket_.close();
    if (cb_.error) cb_.error("The connection to the Graal3D server couldn't be established.");
    return false;
  }
  graal3d::Link::Callbacks lc;
  lc.log = [this](const std::string& s) {
    if (cb_.log) cb_.log(s);
  };
  lc.loginStep = [this](int step) {
    if (cb_.login_step) cb_.login_step(step);
  };
  // The link fails from inside its own calls; the host hears it after
  // they return, once the link is gone (settle()).
  lc.error = [this](const std::string& why) { failed_ = why.empty() ? "Graal3D link closed" : why; };
  lc.text = [this](const graal3d::BigText& t) {
    if (cb_.text) cb_.text(t);
  };
  lc.chat3d = [this](const std::string& account, const std::string& text) {
    if (cb_.chat3d) cb_.chat3d(account, text);
  };
  link_ = std::make_unique<graal3d::Link>(login, lc);
  failed_.clear();
  link_->start(now_ms());
  flush();
  settle();
  return true;
}

void Link3D::settle() {
  if (!link_) return;
  const bool closed = link_->state() == graal3d::Link::State::Closed;
  if (failed_.empty() && !closed) return;
  link_.reset();
  socket_.close();
  std::string why;
  why.swap(failed_);
  if (why.empty()) why = "The Graal3D server closed the connection.";
  if (cb_.error) cb_.error(why);
}

void Link3D::flush() {
  if (!link_) return;
  for (const auto& d : link_->takeOutgoing()) socket_.send(d);
}

void Link3D::pump() {
  if (!link_) return;
  const uint32_t now = now_ms();
  std::string d;
  while (link_ && socket_.receive(d)) link_->receive(d, now);
  if (!link_) return;
  link_->tick(now);
  flush();
  settle();
}

void Link3D::close() {
  if (link_) {
    link_->disconnect("");
    flush();
    link_.reset();
  }
  socket_.close();
}

void Link3D::move_control(const graal3d::Vec3& at) {
  if (!link_) return;
  link_->moveControlTo(at);
  link_->tick(now_ms());
  flush();
  settle();
}

void Link3D::event_lines(const std::string& lines) {
  if (!link_) return;
  std::istringstream in(lines);
  std::string l;
  while (std::getline(in, l)) link_->queueEventLine(l);
  link_->flushEventLines();
  flush();
  settle();
}

}  // namespace Frank
