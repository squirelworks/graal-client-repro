/* graal3dengine.h: the rebuilt 3D library of the 4.x/5.0 split clients
 * (plan Track C4), beside the engine library (common/cpp/graalengine).
 *
 * The original `Graal3DEngine.dll` is a cut-down Torque world the launcher
 * loads on demand, the first time the player picks a server whose list
 * name starts with `3 ` (graal3d/torque-engine-4x.md). It exports three
 * calls: load (a command line), run (one frame) and end; the 5.0 build
 * adds `resizeGraal3DWindow` and has `toggleGraal3DFullScreen`
 * (torque/g3d-5007.md). Loading registers the library's 3D callbacks on
 * the engine's `graal_set` slots and calls `graal_engineInitialize` again,
 * which only resets the script environment.
 *
 * The names are the original's; the argument lists are this rebuild's own,
 * as in graalengine.h. */
#ifndef GRAAL3DENGINE_H
#define GRAAL3DENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  if defined(GRAAL3DENGINE_BUILD)
#    define G3D_API __declspec(dllexport)
#  else
#    define G3D_API __declspec(dllimport)
#  endif
#  define G3D_CALL __cdecl
#else
#  define G3D_API __attribute__((visibility("default")))
#  define G3D_CALL
#endif

/* `cmdline`: `-connect <server>` names a server to connect to at once;
 * a `graal://` or `graal3://` word is kept as the protocol string
 * (torque/5007-g3d.md). Registers the 3D slots on the engine library and
 * removes the launcher's StartGraal3D callback. Non-zero on success. */
G3D_API int32_t G3D_CALL loadGraal3DEngine(const char *cmdline);

/* One frame: the UDP link (datagrams in, timers, datagrams out). */
G3D_API void G3D_CALL runGraal3DEngine(void);

/* Sends the disconnect, closes the link and clears the 3D slots. */
G3D_API void G3D_CALL endGraal3DEngine(void);

/* The 3D view's size and the full-screen toggle. Kept for the names; the
 * host gives the size to graal3dengine_renderFrame. */
G3D_API void G3D_CALL resizeGraal3DWindow(int32_t width, int32_t height);
G3D_API void G3D_CALL toggleGraal3DFullScreen(void);

/* ---- Rebuild only: not in the original. ---- */

#define GRAAL3DENGINE_ABI 1
G3D_API int32_t G3D_CALL graal3dengine_abi(void);

/* The link's login step (0 before the first mission phase, 2 to 6 after)
 * and state (0 idle, 1 challenging, 2 connecting, 3 connected, 4 closed). */
G3D_API int32_t G3D_CALL graal3dengine_loginStep(void);
G3D_API int32_t G3D_CALL graal3dengine_state(void);
/* Ghosts the server has sent that are still alive. */
G3D_API int32_t G3D_CALL graal3dengine_ghostCount(void);

/* The connect sequence of the next link (the client's choice; the real
 * 5.12 lab run used 0x400). 0 picks one from the clock. For tests. */
G3D_API void G3D_CALL graal3dengine_setConnectSequence(uint32_t sequence);

/* The world renderer (render/). Draws the current 3D world into `pixels`
 * (32-bit, red in the lowest byte, `stride` pixels per row): the sky box,
 * then each object's shape seen from the server's Camera, lit by the Sun.
 * Black with no Camera, as the 5.x client. Returns the number of objects
 * drawn. In the original the 3D view is GraalControl3D in Torque's canvas;
 * this export is the rebuild's own, for the hosts to present. */
G3D_API int32_t G3D_CALL graal3dengine_renderFrame(uint32_t *pixels, int32_t width, int32_t height, int32_t stride);
/* A folder the renderer finds shapes and textures in (searched with its
 * subfolders). Without one, `levels3d` in the working folder is used. */
G3D_API void G3D_CALL graal3dengine_addResourceFolder(const char *folder);
/* Looks for files again, after downloads have landed. */
G3D_API void G3D_CALL graal3dengine_rescanResources(void);
/* The player's draw distance, visibledistance3D in game_config.txt
 * (default 1000): nothing farther from the camera is drawn. Clamped to
 * 2400 as the 5.12 clamps it; returns the value used. */
G3D_API float G3D_CALL graal3dengine_setVisibleDistance(float distance);

/* The name tags and chat lines of the last renderFrame, for the host to
 * draw over the frame with its own font (the renderer has none): farthest
 * first. Each is centred on (x, y), its baseline at y, in the frame's
 * pixels; `rgba` red in the lowest byte; `kind` 0 a nickname, 1 chat.
 * `text` gets at most textSize - 1 bytes and a NUL. Returns the text's
 * full length, or -1 for an index out of range. Placement is the
 * rebuild's own until a lab shot. */
G3D_API int32_t G3D_CALL graal3dengine_labelCount(void);
G3D_API int32_t G3D_CALL graal3dengine_label(int32_t index, float *x, float *y, uint32_t *rgba, int32_t *kind,
                                             char *text, int32_t textSize);

#ifdef __cplusplus
}
#endif

#endif /* GRAAL3DENGINE_H */
