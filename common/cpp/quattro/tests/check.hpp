// Minimal test helpers: no framework, a failed check prints and counts.
#pragma once

#include <cstdio>

inline int g_failures = 0;

#define CHECK(...)                                                     \
  do {                                                                  \
    if (!(__VA_ARGS__)) {                                                      \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #__VA_ARGS__); \
      ++g_failures;                                                     \
    }                                                                   \
  } while (0)

#define TEST_MAIN_END()                                                 \
  do {                                                                  \
    if (g_failures) {                                                   \
      std::fprintf(stderr, "%d check(s) failed\n", g_failures);         \
      return 1;                                                         \
    }                                                                   \
    std::printf("ok\n");                                                \
    return 0;                                                           \
  } while (0)
