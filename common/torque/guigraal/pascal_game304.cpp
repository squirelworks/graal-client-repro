// PascalGame304: Game304 over the g304_* functions of Game304Lib.

#include "pascal_game304.hpp"

#include <cfenv>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#include "game304_abi.h"

namespace Torque {
namespace {

struct Api {
#define G304_FN(name) decltype(&::name) name = nullptr;
  G304_FN(g304_create) G304_FN(g304_free) G304_FN(g304_set_log) G304_FN(g304_error)
  G304_FN(g304_set_nickname) G304_FN(g304_list_open) G304_FN(g304_list_poll)
  G304_FN(g304_list_status) G304_FN(g304_list_count) G304_FN(g304_list_field)
  G304_FN(g304_connect) G304_FN(g304_offline) G304_FN(g304_offline_path) G304_FN(g304_key)
  G304_FN(g304_action)
  G304_FN(g304_say) G304_FN(g304_toall) G304_FN(g304_tick) G304_FN(g304_state)
  G304_FN(g304_frame) G304_FN(g304_player)
#undef G304_FN
};

// The Pascal runtime sets its own floating-point environment; the C++ side
// keeps its own around every call.
struct FenvGuard {
  std::fenv_t saved;
  FenvGuard() { std::fegetenv(&saved); }
  ~FenvGuard() { std::fesetenv(&saved); }
};

std::string text(const char* s) { return s ? std::string(s) : std::string(); }

class PascalGame304 : public Game304 {
 public:
  PascalGame304(void* lib, const Api& api, void* handle) : lib_(lib), api_(api), h_(handle) {
    FenvGuard g;
    api_.g304_set_log(h_, &PascalGame304::log_thunk, this);
  }
  ~PascalGame304() override {
    {
      FenvGuard g;
      api_.g304_free(h_);
    }
    // The library stays loaded: unloading a Pascal runtime is not safe.
    (void)lib_;
  }

  std::string error() override { FenvGuard g; return text(api_.g304_error(h_)); }
  void set_nickname(const std::string& n) override { FenvGuard g; api_.g304_set_nickname(h_, n.c_str()); }
  bool list_open(const std::string& a, const std::string& p) override {
    FenvGuard g;
    return api_.g304_list_open(h_, a.c_str(), p.c_str()) == 1;
  }
  int list_poll() override { FenvGuard g; return api_.g304_list_poll(h_); }
  std::string list_status() override { FenvGuard g; return text(api_.g304_list_status(h_)); }
  int list_count() override { FenvGuard g; return api_.g304_list_count(h_); }
  ListServerEntry list_entry(int index) override {
    FenvGuard g;
    ListServerEntry e;
    for (int f = 0; f < 8; ++f) e.fields[f] = text(api_.g304_list_field(h_, index, f));
    return e;
  }
  bool connect(const std::string& host, int port, const std::string& a, const std::string& p) override {
    FenvGuard g;
    return api_.g304_connect(h_, host.c_str(), port, a.c_str(), p.c_str()) == 1;
  }
  bool offline(const std::string& level, double x, double y) override {
    FenvGuard g;
    return api_.g304_offline(h_, level.c_str(), x, y) == 1;
  }
  std::string offline_path() override { FenvGuard g; return text(api_.g304_offline_path(h_)); }
  void key(int dir, bool down) override { FenvGuard g; api_.g304_key(h_, dir, down ? 1 : 0); }
  void action(int which, bool down) override {
    FenvGuard g;
    api_.g304_action(h_, which, down ? 1 : 0);
  }
  void say(const std::string& t) override { FenvGuard g; api_.g304_say(h_, t.c_str()); }
  void to_all(const std::string& t) override { FenvGuard g; api_.g304_toall(h_, t.c_str()); }
  bool tick(bool draw) override { FenvGuard g; return api_.g304_tick(h_, draw ? 1 : 0) != 0; }
  int state() override { FenvGuard g; return api_.g304_state(h_); }
  const std::uint32_t* frame(int& w, int& h) override {
    FenvGuard g;
    return static_cast<const std::uint32_t*>(api_.g304_frame(h_, &w, &h));
  }
  std::string player() override { FenvGuard g; return text(api_.g304_player(h_)); }

 private:
  static void log_thunk(void* ctx, const char* line) {
    auto* self = static_cast<PascalGame304*>(ctx);
    if (self->on_log) self->on_log(text(line));
  }
  void* lib_;
  Api api_;
  void* h_;
};

void* open_lib(const std::string& path, std::string& error) {
#ifdef _WIN32
  HMODULE m = LoadLibraryA(path.c_str());
  if (!m) error = "cannot load " + path;
  return reinterpret_cast<void*>(m);
#else
  void* m = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (!m) error = text(dlerror());
  return m;
#endif
}

void* symbol(void* lib, const char* name) {
#ifdef _WIN32
  return reinterpret_cast<void*>(GetProcAddress(reinterpret_cast<HMODULE>(lib), name));
#else
  return dlsym(lib, name);
#endif
}

} // namespace

std::unique_ptr<Game304> load_pascal_game304(const std::string& lib_path, const std::string& install_dir,
                                             std::string& error) {
  void* lib = nullptr;
  {
    FenvGuard g;
    lib = open_lib(lib_path, error);
  }
  if (!lib) return nullptr;
  Api api;
  bool ok = true;
#define G304_LOAD(name)                                                       \
  api.name = reinterpret_cast<decltype(api.name)>(symbol(lib, #name));       \
  if (!api.name) { error = "missing " #name " in " + lib_path; ok = false; }
  G304_LOAD(g304_create) G304_LOAD(g304_free) G304_LOAD(g304_set_log) G304_LOAD(g304_error)
  G304_LOAD(g304_set_nickname) G304_LOAD(g304_list_open) G304_LOAD(g304_list_poll)
  G304_LOAD(g304_list_status) G304_LOAD(g304_list_count) G304_LOAD(g304_list_field)
  G304_LOAD(g304_connect) G304_LOAD(g304_offline) G304_LOAD(g304_offline_path) G304_LOAD(g304_key)
  G304_LOAD(g304_action)
  G304_LOAD(g304_say) G304_LOAD(g304_toall) G304_LOAD(g304_tick) G304_LOAD(g304_state)
  G304_LOAD(g304_frame) G304_LOAD(g304_player)
#undef G304_LOAD
  if (!ok) return nullptr;
  void* h = nullptr;
  {
    FenvGuard g;
    h = api.g304_create(install_dir.c_str());
  }
  if (!h) {
    error = "the game library could not open " + install_dir;
    return nullptr;
  }
  return std::make_unique<PascalGame304>(lib, api, h);
}

} // namespace Torque
