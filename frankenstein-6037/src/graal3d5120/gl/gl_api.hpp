// The slice of OpenGL 3.2 core the 3D view draws with, loaded at run time.
//
// Nothing here links against a GL library: the context (EGL on Linux and
// other Unix systems, CGL on macOS, WGL on Windows) and every function are
// found with dlopen / LoadLibrary when the renderer starts, so a build
// needs no GL headers or libraries, and a machine without OpenGL 3.2 (a
// Windows VM with only GDI Generic 1.1) falls back to the software
// renderer instead of failing to start. The set is the 3.2 core profile
// subset that macOS (3.2 to 4.1 core, on top of Metal on Apple Silicon),
// Mesa and the Windows drivers all have; no extension is used.
//
// FRANK_GL_LIBRARY names the GL library to load instead of the system's
// (Mesa's opengl32.dll on a Windows VM, a libEGL.so.1 elsewhere).
#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace Frank::gl {

using GLenum = unsigned int;
using GLuint = unsigned int;
using GLint = int;
using GLsizei = int;
using GLboolean = unsigned char;
using GLbitfield = unsigned int;
using GLfloat = float;
using GLchar = char;
using GLubyte = unsigned char;
using GLsizeiptr = std::ptrdiff_t;
using GLintptr = std::ptrdiff_t;

constexpr GLenum NO_ERROR = 0;
constexpr GLenum FALSE_ = 0, TRUE_ = 1;
constexpr GLenum VENDOR = 0x1F00, RENDERER = 0x1F01, VERSION = 0x1F02;
constexpr GLenum DEPTH_BUFFER_BIT = 0x00000100, COLOR_BUFFER_BIT = 0x00004000;
constexpr GLenum TRIANGLES = 0x0004;
constexpr GLenum LESS = 0x0201, LEQUAL = 0x0203;
constexpr GLenum ONE = 1, SRC_ALPHA = 0x0302, ONE_MINUS_SRC_ALPHA = 0x0303;
constexpr GLenum DEPTH_TEST = 0x0B71, BLEND = 0x0BE2, CULL_FACE = 0x0B44;
constexpr GLenum UNPACK_ALIGNMENT = 0x0CF5, PACK_ALIGNMENT = 0x0D05;
constexpr GLenum TEXTURE_2D = 0x0DE1;
constexpr GLenum UNSIGNED_BYTE = 0x1401, UNSIGNED_INT = 0x1405, FLOAT = 0x1406;
constexpr GLenum RED = 0x1903, RGBA = 0x1908;
constexpr GLenum NEAREST = 0x2600, LINEAR = 0x2601;
constexpr GLenum TEXTURE_MAG_FILTER = 0x2800, TEXTURE_MIN_FILTER = 0x2801;
constexpr GLenum TEXTURE_WRAP_S = 0x2802, TEXTURE_WRAP_T = 0x2803;
constexpr GLenum REPEAT = 0x2901, CLAMP_TO_EDGE = 0x812F;
constexpr GLenum RGBA8 = 0x8058, R32F = 0x822E, DEPTH24_STENCIL8 = 0x88F0;
constexpr GLenum TEXTURE0 = 0x84C0;
constexpr GLenum ARRAY_BUFFER = 0x8892, ELEMENT_ARRAY_BUFFER = 0x8893;
constexpr GLenum STATIC_DRAW = 0x88E4, STREAM_DRAW = 0x88E0;
constexpr GLenum FRAGMENT_SHADER = 0x8B30, VERTEX_SHADER = 0x8B31;
constexpr GLenum COMPILE_STATUS = 0x8B81, LINK_STATUS = 0x8B82, INFO_LOG_LENGTH = 0x8B84;
constexpr GLenum FRAMEBUFFER = 0x8D40, RENDERBUFFER = 0x8D41;
constexpr GLenum COLOR_ATTACHMENT0 = 0x8CE0, DEPTH_STENCIL_ATTACHMENT = 0x821A;
constexpr GLenum FRAMEBUFFER_COMPLETE = 0x8CD5;
constexpr GLenum MAX_TEXTURE_SIZE = 0x0D33;

// The functions, filled by Context::open. Named as in GL without the
// "gl" prefix.
struct Api {
#define FRANK_GL_FUNCTIONS(X)                                                                      \
  X(const GLubyte*, GetString, (GLenum))                                                           \
  X(GLenum, GetError, ())                                                                          \
  X(void, GetIntegerv, (GLenum, GLint*))                                                           \
  X(void, Viewport, (GLint, GLint, GLsizei, GLsizei))                                              \
  X(void, ClearColor, (GLfloat, GLfloat, GLfloat, GLfloat))                                        \
  X(void, ClearDepth, (double))                                                                    \
  X(void, Clear, (GLbitfield))                                                                     \
  X(void, Enable, (GLenum))                                                                        \
  X(void, Disable, (GLenum))                                                                       \
  X(void, DepthFunc, (GLenum))                                                                     \
  X(void, DepthMask, (GLboolean))                                                                  \
  X(void, ColorMask, (GLboolean, GLboolean, GLboolean, GLboolean))                                 \
  X(void, BlendFunc, (GLenum, GLenum))                                                             \
  X(void, PixelStorei, (GLenum, GLint))                                                            \
  X(void, ReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*))                     \
  X(void, Finish, ())                                                                              \
  X(void, GenTextures, (GLsizei, GLuint*))                                                         \
  X(void, DeleteTextures, (GLsizei, const GLuint*))                                                \
  X(void, BindTexture, (GLenum, GLuint))                                                           \
  X(void, TexImage2D, (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*)) \
  X(void, TexParameteri, (GLenum, GLenum, GLint))                                                  \
  X(void, ActiveTexture, (GLenum))                                                                 \
  X(void, GenBuffers, (GLsizei, GLuint*))                                                          \
  X(void, DeleteBuffers, (GLsizei, const GLuint*))                                                 \
  X(void, BindBuffer, (GLenum, GLuint))                                                            \
  X(void, BufferData, (GLenum, GLsizeiptr, const void*, GLenum))                                   \
  X(void, GenVertexArrays, (GLsizei, GLuint*))                                                     \
  X(void, DeleteVertexArrays, (GLsizei, const GLuint*))                                            \
  X(void, BindVertexArray, (GLuint))                                                               \
  X(void, EnableVertexAttribArray, (GLuint))                                                       \
  X(void, DisableVertexAttribArray, (GLuint))                                                      \
  X(void, VertexAttribPointer, (GLuint, GLint, GLenum, GLboolean, GLsizei, const void*))           \
  X(void, VertexAttrib2f, (GLuint, GLfloat, GLfloat))                                              \
  X(void, DrawArrays, (GLenum, GLint, GLsizei))                                                    \
  X(void, DrawElements, (GLenum, GLsizei, GLenum, const void*))                                    \
  X(GLuint, CreateShader, (GLenum))                                                                \
  X(void, DeleteShader, (GLuint))                                                                  \
  X(void, ShaderSource, (GLuint, GLsizei, const GLchar* const*, const GLint*))                     \
  X(void, CompileShader, (GLuint))                                                                 \
  X(void, GetShaderiv, (GLuint, GLenum, GLint*))                                                   \
  X(void, GetShaderInfoLog, (GLuint, GLsizei, GLsizei*, GLchar*))                                  \
  X(GLuint, CreateProgram, ())                                                                     \
  X(void, DeleteProgram, (GLuint))                                                                 \
  X(void, AttachShader, (GLuint, GLuint))                                                          \
  X(void, BindAttribLocation, (GLuint, GLuint, const GLchar*))                                     \
  X(void, BindFragDataLocation, (GLuint, GLuint, const GLchar*))                                   \
  X(void, LinkProgram, (GLuint))                                                                   \
  X(void, GetProgramiv, (GLuint, GLenum, GLint*))                                                  \
  X(void, GetProgramInfoLog, (GLuint, GLsizei, GLsizei*, GLchar*))                                 \
  X(void, UseProgram, (GLuint))                                                                    \
  X(GLint, GetUniformLocation, (GLuint, const GLchar*))                                            \
  X(void, Uniform1i, (GLint, GLint))                                                               \
  X(void, Uniform1f, (GLint, GLfloat))                                                             \
  X(void, Uniform3f, (GLint, GLfloat, GLfloat, GLfloat))                                           \
  X(void, Uniform4f, (GLint, GLfloat, GLfloat, GLfloat, GLfloat))                                  \
  X(void, UniformMatrix3fv, (GLint, GLsizei, GLboolean, const GLfloat*))                           \
  X(void, UniformMatrix4fv, (GLint, GLsizei, GLboolean, const GLfloat*))                           \
  X(void, GenFramebuffers, (GLsizei, GLuint*))                                                     \
  X(void, DeleteFramebuffers, (GLsizei, const GLuint*))                                            \
  X(void, BindFramebuffer, (GLenum, GLuint))                                                       \
  X(void, FramebufferRenderbuffer, (GLenum, GLenum, GLenum, GLuint))                               \
  X(GLenum, CheckFramebufferStatus, (GLenum))                                                      \
  X(void, GenRenderbuffers, (GLsizei, GLuint*))                                                    \
  X(void, DeleteRenderbuffers, (GLsizei, const GLuint*))                                           \
  X(void, BindRenderbuffer, (GLenum, GLuint))                                                      \
  X(void, RenderbufferStorage, (GLenum, GLenum, GLsizei, GLsizei))
#if defined(_WIN32)
#define FRANK_GL_CALL __stdcall
#else
#define FRANK_GL_CALL
#endif
#define FRANK_GL_MEMBER(ret, name, args) ret(FRANK_GL_CALL* name) args = nullptr;
  FRANK_GL_FUNCTIONS(FRANK_GL_MEMBER)
#undef FRANK_GL_MEMBER
};

// An offscreen OpenGL 3.2 core context, current on the thread that opened
// it. Drawing goes to a framebuffer object of the renderer's; the context
// has no window of its own.
class Context {
 public:
  virtual ~Context() = default;
  virtual void make_current() = 0;
  const Api& api() const { return api_; }
  // "OpenGL <version> (<renderer>, <vendor>)".
  const std::string& description() const { return description_; }

  // A new context, or null with `why` saying what was missing.
  static std::unique_ptr<Context> open(std::string& why);

 protected:
  Api api_;
  std::string description_;
};

}  // namespace Frank::gl
