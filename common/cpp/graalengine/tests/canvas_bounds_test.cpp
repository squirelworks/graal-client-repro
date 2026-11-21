// Inert canvas geometry tests: no engine initialization, assets, window or sockets.
#include "canvas.hpp"
#include "host.hpp"
#include <climits>
#include <cstdio>
#include <vector>

namespace graalengine::host {
Table& table() { static Table value; return value; }
void clear() { table() = Table{}; }
}
namespace {
int failures = 0, checks = 0;
#define CHECK(x) do { ++checks; if (!(x)) { ++failures; std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); } } while (0)
struct Probe : graalengine::Control {
  int renders = 0, inputs = 0;
  graal_rect clip{};
  bool consumes = true;
  void onRender(const graal_rect& r) override { ++renders; clip = r; }
  bool onInput(const graalengine::InputEvent&) override { ++inputs; return consumes; }
};
bool same(const graal_rect& a, const graal_rect& b) {
  return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h;
}
graalengine::InputEvent press(int x, int y) {
  graalengine::InputEvent e; e.kind = graalengine::InputEvent::MouseDown; e.x = x; e.y = y; return e;
}
void positive_extent_overflow() {
  graalengine::Canvas canvas;
  auto root = std::make_shared<graalengine::Control>();
  auto child = std::make_shared<Probe>();
  child->rect() = {10, 10, INT_MAX, INT_MAX};
  root->add(child); canvas.setContentControl(root); canvas.renderFrame(true);
  CHECK(child->renders == 1);
  CHECK(same(child->clip, {10, 10, 630, 470}));
  canvas.processInputEvent(press(20, 20)); CHECK(child->inputs == 1);
  canvas.processInputEvent(press(9, 20)); CHECK(child->inputs == 1);
  // Edges outside int32 are still valid mathematical edges; fields stay int32.
  Probe edge; edge.rect() = {INT_MAX - 5, 0, 10, 20};
  edge.renderTree({INT_MAX - 4, 0, 5, 10});
  CHECK(edge.renders == 1); CHECK(same(edge.clip, {INT_MAX - 4, 0, 5, 10}));
  CHECK(edge.dispatch(press(INT_MAX, 1)));
  // Exercise each overflowing axis independently as well.
  for (const graal_rect r : std::vector<graal_rect>{{10, 10, INT_MAX, 50}, {10, 10, 50, INT_MAX}}) {
    Probe axis; axis.rect() = r; axis.renderTree({0, 0, 640, 480});
    CHECK(axis.renders == 1); CHECK(axis.clip.w > 0 && axis.clip.h > 0);
    CHECK(axis.dispatch(press(20, 20)));
  }
}
void empty_and_negative_extents() {
  for (const graal_rect r : std::vector<graal_rect>{{INT_MIN, 10, -1, 20},
       {10, INT_MIN, 20, -1}, {0, 0, 0, 5}, {0, 0, 5, 0}, {5, 5, -5, -5}}) {
    Probe p; p.rect() = r; p.renderTree({0, 0, 640, 480});
    CHECK(p.renders == 0); CHECK(!p.dispatch(press(20, 20))); CHECK(p.inputs == 0);
    // Containment is a mouse rule; preserve existing keyboard delivery.
    graalengine::InputEvent key; key.kind = graalengine::InputEvent::KeyDown;
    CHECK(p.dispatch(key)); CHECK(p.inputs == 1);
  }
  Probe p; p.rect() = {0, 0, 10, 10}; p.renderTree({INT_MIN, 0, -1, 10});
  CHECK(p.renders == 0);
}
void ordinary_boundaries_and_routing() {
  Probe p; p.rect() = {-10, -5, 20, 15}; p.renderTree({0, 0, 640, 480});
  CHECK(same(p.clip, {0, 0, 10, 10}));
  CHECK(p.dispatch(press(-10, -5))); CHECK(p.dispatch(press(9, 9)));
  CHECK(!p.dispatch(press(10, 9))); CHECK(!p.dispatch(press(9, 10)));
  Probe touching; touching.rect() = {10, 0, 10, 10}; touching.renderTree({0, 0, 10, 10});
  CHECK(touching.renders == 0); CHECK(!touching.dispatch(press(9, 0)));
  p.rect() = {INT_MIN, 0, INT_MAX, 2}; p.renderTree({-20, 0, 30, 20});
  CHECK(same(p.clip, {-20, 0, 19, 2}));
  CHECK(p.dispatch(press(-2, 1))); CHECK(!p.dispatch(press(-1, 1)));
  graalengine::Canvas c; auto root = std::make_shared<graalengine::Control>();
  auto back = std::make_shared<Probe>(); auto front = std::make_shared<Probe>();
  back->rect() = {0, 0, 100, 100}; front->rect() = {10, 10, INT_MAX, 50};
  root->add(back); root->add(front); c.setContentControl(root);
  c.processInputEvent(press(20, 20)); CHECK(front->inputs == 1); CHECK(back->inputs == 0);
  auto dialog = std::make_shared<Probe>(); c.pushDialog(dialog);
  c.processInputEvent(press(20, 20)); CHECK(dialog->inputs == 1); CHECK(front->inputs == 1);
  CHECK(c.popDialog(dialog.get())); front->setVisible(false);
  c.processInputEvent(press(20, 20)); CHECK(back->inputs == 1); CHECK(front->inputs == 1);
}
}
int main() {
  positive_extent_overflow(); empty_and_negative_extents(); ordinary_boundaries_and_routing();
  std::printf("canvas-bounds-test: %d checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
