// Runs scripts compiled by Seihai's GS2 compiler (seihai-core) on the
// machine, under every opcode profile. The sources and the bytes the
// compiler wrote for them are in tests/seihai (README there). This checks
// that the clients run what a Seihai server sends; it does not check the
// compiler's bytes against the official compiler (seihai-core does that).

#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "../engine_commands.hpp"
#include "../gs2.hpp"

static int failures = 0;
#define CHECK(cond)                                                                 \
  do {                                                                              \
    if (!(cond)) {                                                                  \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                                   \
    }                                                                               \
  } while (0)

static std::string dir = "tests/seihai/";

static std::string readFile(const std::string& name) {
  std::ifstream f(dir + name, std::ios::binary);
  if (!f) {
    std::fprintf(stderr, "cannot open %s%s\n", dir.c_str(), name.c_str());
    ++failures;
    return {};
  }
  return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

struct Run {
  std::vector<std::string> lines;
  std::vector<std::string> errors;
};

// Loads `file` on a fresh machine (with `classes` added first), lets
// `created` run, then runs `passes` 2D passes (0.05 s each).
static Run run(gs2::Profile p, const std::string& file, const std::vector<std::string>& classes, int passes) {
  Run r;
  gs2::Machine m(p);
  gs2::EngineHost h;
  h.log = [&r](const std::string& s) { r.lines.push_back(s); };
  gs2::addEngineCommands(m, h);
  for (const auto& c : classes) {
    std::string err;
    if (!m.addClassScript(c, readFile(c + ".gs2bc"), &err)) r.errors.push_back("class " + c + ": " + err);
  }
  auto v = m.newVar("npc");
  std::string err;
  if (!m.setScript(v, readFile(file), &err)) r.errors.push_back("load: " + err);
  for (int i = 0; i < passes; ++i) m.runScripts();
  for (const auto& e : m.errors()) r.errors.push_back(e);
  return r;
}

static void expectLines(const Run& r, const std::vector<std::string>& want, const char* profile) {
  for (const auto& e : r.errors) std::fprintf(stderr, "[%s] script error: %s\n", profile, e.c_str());
  CHECK(r.errors.empty());
  if (r.lines != want) {
    std::fprintf(stderr, "[%s] got:\n", profile);
    for (const auto& l : r.lines) std::fprintf(stderr, "  %s\n", l.c_str());
    ++failures;
  }
}

static const gs2::Profile kProfiles[] = {gs2::Profile::Engine42, gs2::Profile::Engine50, gs2::Profile::Engine600};

// Every opcode the compiler wrote is one the profile has and the machine runs.
static void testEveryOpcodeRuns() {
  for (const char* f : {"semantics.gs2bc", "lambdas.gs2bc", "helper.gs2bc", "joiner.gs2bc"}) {
    const std::string bytes = readFile(f);
    for (gs2::Profile p : kProfiles) {
      auto r = gs2::load(bytes, p);
      CHECK(r.ok());
      if (!r.ok()) continue;
      for (const auto& in : r.script->code) {
        if (!gs2::opcodeInProfile(in.op, p) || !gs2::opcodeImplemented(in.op)) {
          std::fprintf(stderr, "%s [%s]: opcode %d (%s)\n", f, gs2::profileName(p), in.op,
                       gs2::opcodeName(in.op).c_str());
          ++failures;
        }
      }
    }
  }
}

static void testSemantics() {
  const std::vector<std::string> want = {
      "add 7",   "pow 1024",  "cat x3",     "for 10",    "foreach 6",     "in 11",
      "sw 3",    "call 10",   "fmt 7-q",    "null 1",    "and ok",        "label 3",
      "member 15", "obj hi",  "params 3",   "str 2 ell 2", "tern big",    "while 12",
      "link 5",  "done",
  };
  expectLines(run(gs2::Profile::Engine600, "semantics.gs2bc", {}, 2), want, "6.00");
}

// The compiler keeps a name used five times or in a loop in a frame slot:
// `var "echo"`, 47 (makeprop), 45 (setreg). The 6.00 loader folds 47 + 45
// into 242, which stores the name itself, so a later call through the slot
// finds the command. The 4.2 and 5.0 loaders have no 242 (Graal_analysis
// client-internals/gs2-vm-quirks-by-version.md: an official body that
// assumes fold 242 needs a 6.x loader), so 47 runs and the slot holds a
// variable, which the call does not find. A Seihai server must not send
// cached call names to a 4.x or 5.x client.
static void testCachedCallsNeed600() {
  const std::string bytes = readFile("semantics.gs2bc");
  auto loaded = gs2::load(bytes, gs2::Profile::Engine600);
  CHECK(loaded.ok());
  bool cachesEcho = false;
  if (loaded.ok()) {
    const auto& c = loaded.script->code;
    for (std::size_t i = 0; i + 1 < c.size(); ++i)
      if (c[i].kind == gs2::Instruction::Kind::String && c[i].str == "echo" && c[i + 1].op == 242) cachesEcho = true;
  }
  CHECK(cachesEcho);
  for (gs2::Profile p : {gs2::Profile::Engine42, gs2::Profile::Engine50}) {
    Run r = run(p, "semantics.gs2bc", {}, 2);
    CHECK(r.lines.empty());
    CHECK(!r.errors.empty());
  }
}

// Function values: a `function () { ... }` kept in a variable, a named
// function passed as `this.f`, a lambda passed inline, and functions set as
// members of an object, where `this` is that object (the idiom real weapon
// scripts use to build their own object types).
static void testFunctionValues() {
  const std::vector<std::string> want = {"plain hello 15", "named 12", "passed 2 36", "method 10 10", "member 3", "done"};
  expectLines(run(gs2::Profile::Engine600, "lambdas.gs2bc", {}, 2), want, "6.00");  // echo is cached: 6.00 only
}

// join, a public function from a class, setTimer and scheduleevent.
static void testClassesAndTimers() {
  const std::vector<std::string> want = {"joined 8 hi bob", "timer 3", "later x"};
  for (gs2::Profile p : kProfiles) expectLines(run(p, "joiner.gs2bc", {"helper"}, 20), want, gs2::profileName(p));
}

int main(int argc, char** argv) {
  if (argc > 1) dir = std::string(argv[1]) + "/";
  testEveryOpcodeRuns();
  testSemantics();
  testCachedCallsNeed600();
  testFunctionValues();
  testClassesAndTimers();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("seihai compiler output tests passed\n");
  return 0;
}
