/* graalengine.h: the C interface between a 4.x/5.0 launcher and the
 * rebuilt engine library.
 *
 * Shape (Graal_analysis torque/4208-launcher.md, torque/4208-engine.md,
 * torque/engine-4208.md, torque/5007-launcher.md, torque/engine-5007.md):
 *
 *   - The launcher owns the window and every pixel. The engine library owns
 *     the session, the canvas and the controls, and draws only by calling
 *     back into the launcher.
 *   - The engine exports one `graal_set<Name>` per callback slot. Each one
 *     stores the function pointer it is given. An empty slot is skipped by
 *     the engine (a draw does nothing, a query returns its default).
 *   - The launcher resolves the setters by name, calls every one, then
 *     calls `graal_engineInitialize`. A zero return means the launcher
 *     warns and quits.
 *   - Each frame the launcher calls `renderGraalCanvas`. Keys and mouse go
 *     in through `invokeGraalKeyboardEvent` and `invokeGraalMouseEvent`.
 *
 * The names are the original's. The argument lists are this rebuild's own:
 * the notes do not recover them, and nothing here loads an original
 * library, so they only have to agree between our launcher and our engine.
 * Every function is cdecl. Strings are byte strings in the client's code
 * page (Windows-1252 for the 4.x builds), NUL-terminated. Colours are
 * 0xAARRGGBB. Coordinates are screen pixels, origin top-left.
 *
 * The full slot list, grouped by job and tagged with the builds that
 * register each slot, is graalengine_slots.def. */
#ifndef GRAALENGINE_H
#define GRAALENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  if defined(GRAALENGINE_BUILD)
#    define GE_API __declspec(dllexport)
#  else
#    define GE_API __declspec(dllimport)
#  endif
#  define GE_CALL __cdecl
#else
#  define GE_API __attribute__((visibility("default")))
#  define GE_CALL
#endif

/* An image the engine has loaded. The engine owns it and its pixels; the
 * host may cache its own copy under `host_data` and is told when the image
 * goes away through the FreeGraalTexture slot. Pixels are 0xAARRGGBB, row
 * major, `width * height` of them. */
typedef struct graal_texture {
  const char *name;
  int32_t width;
  int32_t height;
  const uint32_t *pixels;
  void *host_data;
} graal_texture;

/* A 2D affine matrix: x' = a*x + c*y + tx, y' = b*x + d*y + ty. */
typedef struct graal_matrix2d {
  float a, b, c, d, tx, ty;
} graal_matrix2d;

typedef struct graal_point {
  int32_t x, y;
} graal_point;

typedef struct graal_rect {
  int32_t x, y, w, h;
} graal_rect;

/* Text style bits for the text slots. */
enum {
  GRAAL_TEXT_BOLD = 1,
  GRAAL_TEXT_ITALIC = 2,
  GRAAL_TEXT_UNDERLINE = 4
};

/* Modifier bits for invokeGraalKeyboardEvent and invokeGraalMouseEvent. */
enum {
  GRAAL_MOD_SHIFT = 1,
  GRAAL_MOD_CTRL = 2,
  GRAAL_MOD_ALT = 4
};

/* Mouse buttons for invokeGraalMouseEvent: 0 is the left (unnamed) button,
 * 1 `middle`, 2 `right` (torque/4208-engine.md). */
enum {
  GRAAL_MOUSE_LEFT = 0,
  GRAAL_MOUSE_MIDDLE = 1,
  GRAAL_MOUSE_RIGHT = 2
};

/* Mouse actions. */
enum {
  GRAAL_MOUSE_MOVE = 0,
  GRAAL_MOUSE_DOWN = 1,
  GRAAL_MOUSE_UP = 2,
  GRAAL_MOUSE_WHEEL = 3
};

/* One typedef and one setter per slot. */
#define GE_SLOT(Name, Ret, Default, Params, Args, Builds) \
  typedef Ret(GE_CALL *graal_##Name##_fn) Params;          \
  GE_API void GE_CALL graal_set##Name(graal_##Name##_fn fn);
#include "graalengine_slots.def"
#undef GE_SLOT

/* Builds a slot can belong to (the Builds column of the slot list). */
enum {
  GRAAL_BUILD_4208 = 1, /* the 4.x launcher: 4.04r2, 4.11 Mac, 4.20r8 */
  GRAAL_BUILD_5007 = 2, /* the 5.0 launcher: 5.00r7, 5.12 */
  GRAAL_BUILD_3D = 4    /* filled by the 3D library, not by a launcher */
};

/* ---- Entry points the launcher calls. ---- */

/* Called once after every setter. `exe_path` is the launcher's own path
 * (the engine finds the install from it). Returns non-zero on success. A
 * second call only resets the script environment. */
GE_API int32_t GE_CALL graal_engineInitialize(const char *exe_path);

/* Builds the canvas and the start menus. Calling it again only rebuilds
 * what the notes say it rebuilds. */
GE_API void GE_CALL loadGraalGui(void);

/* One frame: the adventure timer, then every visible control draws through
 * the slots. */
GE_API void GE_CALL renderGraalCanvas(void);

/* The original exports it and its launcher never calls it. Kept for the
 * name; it runs the timer without drawing. */
GE_API void GE_CALL renderGraal(void);

/* `vk` is the Windows virtual-key code, `ch` the character ToAscii gave
 * (0 for none), `mods` GRAAL_MOD_* bits, `down` non-zero on key-down. */
GE_API void GE_CALL invokeGraalKeyboardEvent(int32_t vk, int32_t ch, int32_t mods,
                                             int32_t down);

/* `action` is GRAAL_MOUSE_*, `button` GRAAL_MOUSE_LEFT/MIDDLE/RIGHT,
 * `clicks` the click count on a press (2 for a double click), `wheel` the
 * wheel delta on GRAAL_MOUSE_WHEEL. */
GE_API void GE_CALL invokeGraalMouseEvent(int32_t x, int32_t y, int32_t action, int32_t button,
                                          int32_t clicks, int32_t mods, int32_t wheel);

GE_API void GE_CALL startOfflineMode(void);
GE_API void GE_CALL connectToGraalServer(const char *name, const char *host, int32_t port);
GE_API void GE_CALL openGraalServerList(void);
GE_API void GE_CALL enableScriptedControls(int32_t enable);

/* Two-step shutdown, as the slot pair names it: prepare, then free. */
GE_API void GE_CALL prepareGraalShutdown(void);
GE_API void GE_CALL shutdownGraalEngine(void);

/* ---- The engine's half of the 3D bridge: the 3D library calls these
 * (graal3d/torque-engine-4x.md, torque/4208-g3d.md). ---- */

/* Non-zero once a `3 ` server was connected with the 3D library loaded. */
GE_API int32_t GE_CALL isGraal3DMode(void);

/* The login the session uses: account, nickname and password, each copied
 * NUL-terminated and cut to its buffer size (the original returns the same
 * three values; no session key). On 5.x an empty account is the built-in
 * guest. */
GE_API void GE_CALL getGraalLoginInfo(char *account, int32_t account_size, char *nickname,
                                      int32_t nickname_size, char *password, int32_t password_size);

/* The 3D link failed or timed out: the engine logs the reason, leaves 3D
 * mode and drops the TCP session too. */
GE_API void GE_CALL setGraal3DConnectionError(const char *reason);

/* ---- Rebuild only: not in the original. ---- */

/* Interface version of this header. Bumped when a slot's arguments
 * change, so a launcher refuses an engine library built from another
 * version. */
#define GRAALENGINE_ABI 1
GE_API int32_t GE_CALL graalengine_abi(void);

/* The launcher's build ("4.04r2", "5.00r7", "5.12"), before
 * graal_engineInitialize: the session's wire row and the GS2 opcode
 * profile. 4.04r2 when never called. Returns 0 for a build the library
 * has no row for (the build is then left as it was). */
GE_API int32_t GE_CALL graalengine_setBuild(const char *label);

/* The build set with graalengine_setBuild (the 3D library picks its
 * protocol from it: 19 for 4.04r2, 21 for 4.20, 24 for 5.x). */
GE_API const char *GE_CALL graalengine_build(void);

/* The 3D library's login step (2 to 6). The engine raises
 * `onGraal3DLoginStep(step)` on the universe; at step 6 the 3D GUI becomes
 * the content: `GUIContainer3D` on 4.x (torque/4208-g3d.md),
 * `GUIContainer` on 5.x (torque/5007-g3d.md). In the original the 3D
 * library does both itself on the engine's objects. */
GE_API void GE_CALL graalengine_graal3DLoginStep(int32_t step);

/* One line to the engine's log: the LogGraalMessage slot, or stderr with
 * GRAALENGINE_LOG set when the launcher has no log slot (5.0). */
GE_API void GE_CALL graalengine_logLine(const char *line);

/* The slot list, for a launcher to check its own list against the
 * library's: the count, then each name (without `graal_set`) and its
 * GRAAL_BUILD_* bits. Out-of-range indexes give NULL and 0. */
GE_API int32_t GE_CALL graalengine_slotCount(void);
GE_API const char *GE_CALL graalengine_slotName(int32_t index);
GE_API int32_t GE_CALL graalengine_slotBuilds(int32_t index);

#ifdef __cplusplus
}
#endif

#endif /* GRAALENGINE_H */
