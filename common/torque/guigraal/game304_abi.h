/* The C interface of the 3.04 game library (graal-3.04-G3D03014/src/
   Game304Lib.lpr). Strings are UTF-8; a returned string stays valid until
   the next call on the same handle. */
#ifndef GAME304_ABI_H
#define GAME304_ABI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*g304_log_fn)(void* ctx, const char* line);

void* g304_create(const char* install_dir);
void g304_free(void* h);
void g304_set_log(void* h, g304_log_fn fn, void* ctx);
const char* g304_error(void* h);
void g304_set_nickname(void* h, const char* nick);
int g304_list_open(void* h, const char* account, const char* password);
int g304_list_poll(void* h);
const char* g304_list_status(void* h);
int g304_list_count(void* h);
const char* g304_list_field(void* h, int index, int field);
int g304_connect(void* h, const char* host, int port, const char* account, const char* password);
int g304_offline(void* h, const char* level, double x, double y);
const char* g304_offline_path(void* h);
void g304_key(void* h, int dir, int down);
/* game keys: 0 A, 1 S, 2 D, 3 Q; a press counts on up to down only */
void g304_action(void* h, int which, int down);
void g304_say(void* h, const char* text);
void g304_toall(void* h, const char* text);
int g304_tick(void* h, int draw);
int g304_state(void* h);
const void* g304_frame(void* h, int* width, int* height);
const char* g304_player(void* h);

#ifdef __cplusplus
}
#endif

#endif
