// Offscreen OpenGL 3.2 core contexts: CGL on macOS, WGL on Windows, EGL
// elsewhere. Everything is loaded at run time (gl_api.hpp).
#include "gl_api.hpp"

#include <cstdlib>
#include <cstring>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace Frank::gl {

namespace {

const char* library_override() {
  const char* v = std::getenv("FRANK_GL_LIBRARY");
  return v && *v ? v : nullptr;
}

// Fills every function in `api` with `find`; false (and `why` naming the
// first one missing) when one is not there.
template <class Find>
bool load_api(Api& api, Find find, std::string& why) {
#define FRANK_GL_LOAD(ret, name, args)                                         \
  api.name = reinterpret_cast<ret(FRANK_GL_CALL*) args>(find("gl" #name)); \
  if (!api.name) {                                                             \
    why = "no gl" #name;                                                       \
    return false;                                                              \
  }
  FRANK_GL_FUNCTIONS(FRANK_GL_LOAD)
#undef FRANK_GL_LOAD
  return true;
}

// The context must be at least 3.2: some drivers hand out a lower one
// whatever was asked for.
bool check_version(const Api& api, std::string& description, std::string& why) {
  const char* version = reinterpret_cast<const char*>(api.GetString(VERSION));
  const char* renderer = reinterpret_cast<const char*>(api.GetString(RENDERER));
  const char* vendor = reinterpret_cast<const char*>(api.GetString(VENDOR));
  if (!version) {
    why = "no GL version";
    return false;
  }
  int major = 0, minor = 0;
  const char* p = version;
  while (*p && (*p < '0' || *p > '9')) ++p;  // "OpenGL ES 3.2" style prefixes
  major = std::atoi(p);
  while (*p >= '0' && *p <= '9') ++p;
  if (*p == '.') minor = std::atoi(p + 1);
  description = std::string("OpenGL ") + version + " (" + (renderer ? renderer : "?") + ", " +
                (vendor ? vendor : "?") + ")";
  if (major < 3 || (major == 3 && minor < 2)) {
    why = "OpenGL " + std::string(version) + " is below 3.2";
    return false;
  }
  return true;
}

}  // namespace

#if defined(__APPLE__)

// macOS: CGL with the 3.2 core profile (macOS gives 4.1 core under it). No
// accelerated renderer is required, so the Apple software renderer of a
// VM without a GPU also serves.
namespace {
using CGLPixelFormatObj = void*;
using CGLContextObj = void*;
using CGLError = int;
constexpr int kCGLPFAColorSize = 8, kCGLPFADepthSize = 12, kCGLPFAAllowOfflineRenderers = 96,
              kCGLPFAOpenGLProfile = 99, kCGLOGLPVersion_3_2_Core = 0x3200;

class CglContext : public Context {
 public:
  ~CglContext() override {
    if (ctx_ && destroy_) {
      if (set_current_) set_current_(nullptr);
      destroy_(ctx_);
    }
    // The framework stays loaded: it cannot be unloaded safely.
  }
  bool open(std::string& why) {
    lib_ = dlopen(library_override() ? library_override() : "/System/Library/Frameworks/OpenGL.framework/OpenGL",
                  RTLD_LAZY | RTLD_LOCAL);
    if (!lib_) {
      why = "no OpenGL framework";
      return false;
    }
    auto choose = reinterpret_cast<CGLError (*)(const int*, CGLPixelFormatObj*, int*)>(
        dlsym(lib_, "CGLChoosePixelFormat"));
    auto create =
        reinterpret_cast<CGLError (*)(CGLPixelFormatObj, CGLContextObj, CGLContextObj*)>(dlsym(lib_, "CGLCreateContext"));
    auto destroy_pf = reinterpret_cast<CGLError (*)(CGLPixelFormatObj)>(dlsym(lib_, "CGLDestroyPixelFormat"));
    set_current_ = reinterpret_cast<CGLError (*)(CGLContextObj)>(dlsym(lib_, "CGLSetCurrentContext"));
    destroy_ = reinterpret_cast<CGLError (*)(CGLContextObj)>(dlsym(lib_, "CGLDestroyContext"));
    if (!choose || !create || !destroy_pf || !set_current_ || !destroy_) {
      why = "no CGL";
      return false;
    }
    const int attrs[] = {kCGLPFAOpenGLProfile, kCGLOGLPVersion_3_2_Core, kCGLPFAColorSize, 24, kCGLPFADepthSize, 24,
                         kCGLPFAAllowOfflineRenderers, 0};
    CGLPixelFormatObj pf = nullptr;
    int n = 0;
    if (choose(attrs, &pf, &n) != 0 || !pf) {
      why = "no OpenGL 3.2 core pixel format";
      return false;
    }
    const CGLError e = create(pf, nullptr, &ctx_);
    destroy_pf(pf);
    if (e != 0 || !ctx_) {
      why = "CGLCreateContext failed";
      return false;
    }
    make_current();
    void* lib = lib_;
    return load_api(api_, [lib](const char* name) { return dlsym(lib, name); }, why) &&
           check_version(api_, description_, why);
  }
  void make_current() override { set_current_(ctx_); }

 private:
  void* lib_ = nullptr;
  CGLContextObj ctx_ = nullptr;
  CGLError (*set_current_)(CGLContextObj) = nullptr;
  CGLError (*destroy_)(CGLContextObj) = nullptr;
};
}  // namespace

std::unique_ptr<Context> Context::open(std::string& why) {
  auto c = std::make_unique<CglContext>();
  if (!c->open(why)) return nullptr;
  return c;
}

#elif defined(_WIN32)

// Windows: WGL on a hidden window, then wglCreateContextAttribsARB for a
// 3.2 core context. GDI Generic (OpenGL 1.1, a VM without a GPU driver)
// has no such function and is refused; Mesa's opengl32.dll beside the
// program, or named by FRANK_GL_LIBRARY, serves instead.
namespace {
// A function from GetProcAddress as the type it is (through void*, so the
// compiler does not warn about the cast between function types).
template <class T>
T proc(FARPROC p) {
  return reinterpret_cast<T>(reinterpret_cast<void*>(p));
}
constexpr int WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091, WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092,
              WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126, WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x0001;

class WglContext : public Context {
 public:
  ~WglContext() override {
    if (make_current_fn_) make_current_fn_(nullptr, nullptr);
    if (ctx_ && delete_) delete_(ctx_);
    if (dc_ && wnd_) ReleaseDC(wnd_, dc_);
    if (wnd_) DestroyWindow(wnd_);
  }
  bool open(std::string& why) {
    const char* path = library_override();
    lib_ = path ? LoadLibraryExA(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH) : LoadLibraryA("opengl32.dll");
    if (!lib_) {
      why = "no opengl32.dll";
      return false;
    }
    auto create = proc<HGLRC(WINAPI*)(HDC)>(GetProcAddress(lib_, "wglCreateContext"));
    delete_ = proc<BOOL(WINAPI*)(HGLRC)>(GetProcAddress(lib_, "wglDeleteContext"));
    make_current_fn_ = proc<BOOL(WINAPI*)(HDC, HGLRC)>(GetProcAddress(lib_, "wglMakeCurrent"));
    get_proc_ = proc<PROC(WINAPI*)(LPCSTR)>(GetProcAddress(lib_, "wglGetProcAddress"));
    if (!create || !delete_ || !make_current_fn_ || !get_proc_) {
      why = "no WGL";
      return false;
    }
    WNDCLASSA wc{};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(nullptr);
    wc.lpszClassName = "Frankenstein6037GL";
    RegisterClassA(&wc);  // fails harmlessly when already registered
    wnd_ = CreateWindowExA(0, wc.lpszClassName, "gl", WS_OVERLAPPEDWINDOW, 0, 0, 16, 16, nullptr, nullptr,
                           wc.hInstance, nullptr);
    if (!wnd_ || !(dc_ = GetDC(wnd_))) {
      why = "no window for WGL";
      return false;
    }
    PIXELFORMATDESCRIPTOR pfd{};
    pfd.nSize = sizeof pfd;
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    const int format = ChoosePixelFormat(dc_, &pfd);
    if (!format || !SetPixelFormat(dc_, format, &pfd)) {
      why = "no WGL pixel format";
      return false;
    }
    HGLRC legacy = create(dc_);
    if (!legacy || !make_current_fn_(dc_, legacy)) {
      if (legacy) delete_(legacy);
      why = "wglCreateContext failed";
      return false;
    }
    auto create_attribs = proc<HGLRC(WINAPI*)(HDC, HGLRC, const int*)>(
        reinterpret_cast<FARPROC>(get_proc_("wglCreateContextAttribsARB")));
    if (!create_attribs) {
      make_current_fn_(nullptr, nullptr);
      delete_(legacy);
      why = "no wglCreateContextAttribsARB (OpenGL below 3.2, such as GDI Generic)";
      return false;
    }
    const int attrs[] = {WGL_CONTEXT_MAJOR_VERSION_ARB, 3, WGL_CONTEXT_MINOR_VERSION_ARB, 2,
                         WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB, 0};
    ctx_ = create_attribs(dc_, nullptr, attrs);
    make_current_fn_(nullptr, nullptr);
    delete_(legacy);
    if (!ctx_) {
      why = "no OpenGL 3.2 core context";
      return false;
    }
    make_current();
    HMODULE lib = lib_;
    auto get_proc = get_proc_;
    auto find = [lib, get_proc](const char* name) -> void* {
      void* p = reinterpret_cast<void*>(get_proc(name));
      const auto v = reinterpret_cast<intptr_t>(p);
      if (v == 0 || v == 1 || v == 2 || v == 3 || v == -1)
        p = reinterpret_cast<void*>(GetProcAddress(lib, name));  // the 1.1 entry points
      return p;
    };
    return load_api(api_, find, why) && check_version(api_, description_, why);
  }
  void make_current() override { make_current_fn_(dc_, ctx_); }

 private:
  HMODULE lib_ = nullptr;
  HWND wnd_ = nullptr;
  HDC dc_ = nullptr;
  HGLRC ctx_ = nullptr;
  BOOL(WINAPI* delete_)(HGLRC) = nullptr;
  BOOL(WINAPI* make_current_fn_)(HDC, HGLRC) = nullptr;
  PROC(WINAPI* get_proc_)(LPCSTR) = nullptr;
};
}  // namespace

std::unique_ptr<Context> Context::open(std::string& why) {
  auto c = std::make_unique<WglContext>();
  if (!c->open(why)) return nullptr;
  return c;
}

#else

// Linux and other Unix systems: EGL, surfaceless where Mesa offers it (a
// headless VM needs no X server), else the default display with a 1 x 1
// pbuffer.
namespace {
using EGLDisplay = void*;
using EGLConfig = void*;
using EGLContext = void*;
using EGLSurface = void*;
using EGLint = int32_t;
using EGLBoolean = unsigned int;
using EGLenum = unsigned int;
constexpr EGLint EGL_NONE = 0x3038, EGL_RENDERABLE_TYPE = 0x3040, EGL_OPENGL_BIT = 0x0008,
                 EGL_SURFACE_TYPE = 0x3033, EGL_PBUFFER_BIT = 0x0001, EGL_DONT_CARE = -1,
                 EGL_RED_SIZE = 0x3024, EGL_GREEN_SIZE = 0x3023, EGL_BLUE_SIZE = 0x3022,
                 EGL_CONTEXT_MAJOR_VERSION = 0x3098, EGL_CONTEXT_MINOR_VERSION = 0x30FB,
                 EGL_CONTEXT_OPENGL_PROFILE_MASK = 0x30FD, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT = 0x1,
                 EGL_WIDTH = 0x3057, EGL_HEIGHT = 0x3056;
constexpr EGLenum EGL_OPENGL_API = 0x30A2, EGL_PLATFORM_SURFACELESS_MESA = 0x31DD;

class EglContext : public Context {
 public:
  ~EglContext() override {
    if (display_ && make_current_) make_current_(display_, nullptr, nullptr, nullptr);
    if (display_ && surface_ && destroy_surface_) destroy_surface_(display_, surface_);
    if (display_ && ctx_ && destroy_) destroy_(display_, ctx_);
    if (display_ && terminate_) terminate_(display_);
    // libEGL stays loaded: Mesa's drivers register exit handlers.
  }
  bool open(std::string& why) {
    lib_ = dlopen(library_override() ? library_override() : "libEGL.so.1", RTLD_LAZY | RTLD_LOCAL);
    if (!lib_) {
      why = "no libEGL.so.1";
      return false;
    }
    auto sym = [this](const char* n) { return dlsym(lib_, n); };
    get_proc_ = reinterpret_cast<void* (*)(const char*)>(sym("eglGetProcAddress"));
    auto get_display = reinterpret_cast<EGLDisplay (*)(void*)>(sym("eglGetDisplay"));
    auto initialize = reinterpret_cast<EGLBoolean (*)(EGLDisplay, EGLint*, EGLint*)>(sym("eglInitialize"));
    auto bind_api = reinterpret_cast<EGLBoolean (*)(EGLenum)>(sym("eglBindAPI"));
    auto choose = reinterpret_cast<EGLBoolean (*)(EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*)>(
        sym("eglChooseConfig"));
    auto create = reinterpret_cast<EGLContext (*)(EGLDisplay, EGLConfig, EGLContext, const EGLint*)>(
        sym("eglCreateContext"));
    auto pbuffer = reinterpret_cast<EGLSurface (*)(EGLDisplay, EGLConfig, const EGLint*)>(
        sym("eglCreatePbufferSurface"));
    make_current_ = reinterpret_cast<EGLBoolean (*)(EGLDisplay, EGLSurface, EGLSurface, EGLContext)>(
        sym("eglMakeCurrent"));
    destroy_ = reinterpret_cast<EGLBoolean (*)(EGLDisplay, EGLContext)>(sym("eglDestroyContext"));
    destroy_surface_ = reinterpret_cast<EGLBoolean (*)(EGLDisplay, EGLSurface)>(sym("eglDestroySurface"));
    terminate_ = reinterpret_cast<EGLBoolean (*)(EGLDisplay)>(sym("eglTerminate"));
    if (!get_proc_ || !get_display || !initialize || !bind_api || !choose || !create || !pbuffer || !make_current_ ||
        !destroy_ || !destroy_surface_ || !terminate_) {
      why = "incomplete libEGL";
      return false;
    }
    auto platform_display = reinterpret_cast<EGLDisplay (*)(EGLenum, void*, const intptr_t*)>(
        sym("eglGetPlatformDisplay"));
    using PlatformExt = EGLDisplay (*)(EGLenum, void*, const EGLint*);
    auto platform_display_ext = reinterpret_cast<PlatformExt>(get_proc_("eglGetPlatformDisplayEXT"));
    // Surfaceless first: no display server needed.
    EGLDisplay candidates[3] = {
        platform_display ? platform_display(EGL_PLATFORM_SURFACELESS_MESA, nullptr, nullptr) : nullptr,
        platform_display_ext ? platform_display_ext(EGL_PLATFORM_SURFACELESS_MESA, nullptr, nullptr) : nullptr,
        get_display(nullptr)};
    for (EGLDisplay d : candidates) {
      EGLint major = 0, minor = 0;
      if (!d || !initialize(d, &major, &minor)) continue;
      if (!bind_api(EGL_OPENGL_API)) {
        terminate_(d);
        continue;
      }
      EGLConfig config = nullptr;
      EGLint n = 0;
      const EGLint surface_types[2] = {EGL_PBUFFER_BIT, EGL_DONT_CARE};
      for (EGLint st : surface_types) {
        const EGLint attrs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_SURFACE_TYPE, st, EGL_RED_SIZE, 8,
                                EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE};
        if (choose(d, attrs, &config, 1, &n) && n > 0) break;
        n = 0;
      }
      if (n <= 0) {
        terminate_(d);
        continue;
      }
      const EGLint ctx_attrs[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 2,
                                  EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE};
      EGLContext ctx = create(d, config, nullptr, ctx_attrs);
      if (!ctx) {
        terminate_(d);
        continue;
      }
      EGLSurface surface = nullptr;
      if (!make_current_(d, nullptr, nullptr, ctx)) {
        const EGLint pb[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
        surface = pbuffer(d, config, pb);
        if (!surface || !make_current_(d, surface, surface, ctx)) {
          if (surface) destroy_surface_(d, surface);
          destroy_(d, ctx);
          terminate_(d);
          continue;
        }
      }
      display_ = d;
      ctx_ = ctx;
      surface_ = surface;
      break;
    }
    if (!display_) {
      why = "no EGL display with an OpenGL 3.2 core context";
      return false;
    }
    // eglGetProcAddress gives every core function on Mesa and glvnd; the
    // GL library itself is the fallback.
    void* gl = dlopen("libOpenGL.so.0", RTLD_LAZY | RTLD_LOCAL);
    if (!gl) gl = dlopen("libGL.so.1", RTLD_LAZY | RTLD_LOCAL);
    auto get_proc = get_proc_;
    auto find = [get_proc, gl](const char* name) -> void* {
      void* p = get_proc(name);
      if (!p && gl) p = dlsym(gl, name);
      return p;
    };
    return load_api(api_, find, why) && check_version(api_, description_, why);
  }
  void make_current() override { make_current_(display_, surface_, surface_, ctx_); }

 private:
  void* lib_ = nullptr;
  EGLDisplay display_ = nullptr;
  EGLContext ctx_ = nullptr;
  EGLSurface surface_ = nullptr;
  void* (*get_proc_)(const char*) = nullptr;
  EGLBoolean (*make_current_)(EGLDisplay, EGLSurface, EGLSurface, EGLContext) = nullptr;
  EGLBoolean (*destroy_)(EGLDisplay, EGLContext) = nullptr;
  EGLBoolean (*destroy_surface_)(EGLDisplay, EGLSurface) = nullptr;
  EGLBoolean (*terminate_)(EGLDisplay) = nullptr;
};
}  // namespace

std::unique_ptr<Context> Context::open(std::string& why) {
  auto c = std::make_unique<EglContext>();
  if (!c->open(why)) return nullptr;
  return c;
}

#endif

}  // namespace Frank::gl
