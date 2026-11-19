// stb_image's implementation, in its own file: it is third-party code
// (common/cpp/third_party/stb) and is built without -Werror.
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_NO_STDIO
// No thread-local flip flags: a DLL that Windows XP loads with LoadLibrary
// gets no slot for its own thread-locals, so stb read a stray flip flag
// there and drew JPEG/BMP/GIF pictures upside down (the XP lab, run 3).
#define STBI_NO_THREAD_LOCALS
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
