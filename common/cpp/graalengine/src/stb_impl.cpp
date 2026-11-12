// stb_image's implementation, in its own file: it is third-party code
// (common/cpp/third_party/stb) and is built without -Werror.
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_NO_STDIO
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
