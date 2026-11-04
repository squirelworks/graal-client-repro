/* Graal Game Boy Color rebuild: shared state of the engine. */
#ifndef GAME_H
#define GAME_H
#include <gb/gb.h>
#include <stdint.h>

/* Positions are 16-bit centres in half pixels; a map tile is 16 units. */
#define TILE_UNITS   16
#define ROOM_UNITS   512

#define MAX_ENT      8
#define MAX_OBJ      4

/* directions, as the demo numbers them */
#define D_UP    0
#define D_LEFT  1
#define D_DOWN  2
#define D_RIGHT 3

/* entity states */
#define ST_IDLE   0
#define ST_WALK   1
#define ST_SWORD  3
#define ST_KNOCK  4
#define ST_LIFT   9

/* Field order is fixed: tests/smoke.py reads x, y, type, dir, state, carry
   at offsets 0, 2, 4, 5, 6, 7. */
typedef struct {
    int16_t x, y;
    uint8_t type, dir, state, carry;   /* carry: 0 none, else object look + 1 */
    uint8_t active, text, mode;
    uint8_t xmin, xmax, ymin, ymax;    /* tiles */
    uint8_t flags, event, evstep;
    uint8_t timer, frame, aitimer, blink, cool;
    int8_t kx, ky;
    uint8_t ktimer;
} ent_t;

/* objects that move on their own */
#define OB_NONE    0
#define OB_LIFTING 1
#define OB_THROWN  2
#define OB_PIECES  3
#define OB_BOMB    4
#define OB_BLAST   5
#define OB_BOOM    6

typedef struct {
    uint8_t kind, look, timer, owner, dir, phase;
    int16_t x, y;
} obj_t;

/* sprite tile numbers (VRAM bank 0, 8x16 mode), from the pack's sprite sheet */
#define SPR_BASE      128U
#define SP_DOWN ((uint8_t)(SPR_BASE + 0))
#define SP_UP ((uint8_t)(SPR_BASE + 8))
#define SP_RIGHT ((uint8_t)(SPR_BASE + 16))
#define SP_CARRY ((uint8_t)(SPR_BASE + 24))
#define SP_SWORD_V ((uint8_t)(SPR_BASE + 32))
#define SP_SWORD_H ((uint8_t)(SPR_BASE + 34))
#define SP_SWORD_D ((uint8_t)(SPR_BASE + 38))
#define SP_LOOK0 ((uint8_t)(SPR_BASE + 42))    /* object looks: bush, rock, post */
#define SP_LEAF ((uint8_t)(SPR_BASE + 54))
#define SP_BOMB ((uint8_t)(SPR_BASE + 56))
#define SP_FLASH ((uint8_t)(SPR_BASE + 60))
#define SP_BLAST ((uint8_t)(SPR_BASE + 64))
#define SP_BOOM ((uint8_t)(SPR_BASE + 68))
#define SP_ICONS ((uint8_t)(SPR_BASE + 72))    /* menu icons: sword, lift, bomb, boomerang */
#define SP_MENU_BODY ((uint8_t)(SPR_BASE + 88))
#define SP_HEADS      240U

/* OBJ palettes */
#define PAL_SWORD   6
#define PAL_OBJ_A   5
#define PAL_OBJ_B   7


/* main.c */
extern uint8_t keys, pressed;
extern uint8_t tick;
extern uint8_t scx, scy;
extern uint8_t muted;

/* room.c */
extern uint8_t room_id, room_tileset;
extern uint8_t map[1024];
extern uint8_t attr[1024];
extern uint8_t nlinks, ntexts, nnpcs;
extern uint16_t links_off, texts_off;
extern int16_t warp_room, warp_x, warp_y;
void room_load(uint8_t r, int16_t x, int16_t y);
uint8_t tile_solid_px(int16_t px, int16_t py);
void map_set(uint8_t tx, uint8_t ty, uint8_t t);
void room_restore_tile(uint8_t tx, uint8_t ty);
void anim_step(void);
void links_check(void);
uint8_t text_at(uint8_t tx, uint8_t ty);

/* ent.c */
extern ent_t ents[MAX_ENT];
extern uint8_t player_frozen;
void ents_reset(void);
void ent_spawn_npc(uint8_t slot, const uint8_t *rec);
void ents_tick(void);
void ent_palette(uint8_t i);
void ents_palettes(void);
void knock(ent_t *e, int16_t fx, int16_t fy);
uint8_t ent_box_hit(int16_t x, int16_t y, uint8_t r, uint8_t skip);
void event_text_closed(void);

/* obj.c */
extern obj_t objs[MAX_OBJ];
void objs_reset(void);
uint8_t try_lift(uint8_t ei);
void throw_carried(uint8_t ei);
void use_a_item(uint8_t ei);
void objs_tick(void);

/* draw.c */
void draw_frame(void);
void spr_begin(void);
void spr8(int16_t x, int16_t y, uint8_t tile, uint8_t prop);
void spr16(int16_t x, int16_t y, uint8_t tile, uint8_t prop);
void spr_end(void);

/* ui.c */
extern uint8_t text_open, menu_open, win_y, win_target;
void ui_init(void);
void text_show(uint8_t idx);
void text_input(void);
void menu_toggle(void);
void menu_input(void);
void ui_frame(void);
void menu_sprites(void);

/* sfx.c */
#define SFX_SWORD  0
#define SFX_LIFT   1
#define SFX_THROW  2
#define SFX_BREAK  3
#define SFX_TEXT   4
#define SFX_BOMB   5
#define SFX_HIT    6
#define SFX_MENU   7
void sfx_init(void);
void sfx(uint8_t n);
void music_toggle(void);

#endif
