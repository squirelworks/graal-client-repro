/* People: the player (entity 0) and the room's NPCs.

   Behaviour follows what the demo does in play (graal_analysis
   client-internals/gameboy-demo.md): the player walks 4 pixels a logic
   tick, keeps walking in place against a wall and slides round corners;
   B swings the sword, A uses the character's A item; a hit only knocks
   back. NPCs stand, wander or patrol inside a box. Flag bit 0 makes one
   turn to the player once lined up; with bit 7 as well it chases and
   fights (the soldiers in room 3). */
#include <gb/gb.h>
#include <gb/cgb.h>
#include <rand.h>
#include "game.h"
#include "pak.h"

ent_t ents[MAX_ENT];
uint8_t player_frozen;

static const int8_t dir_dx[4] = { 0, -1, 0, 1 };
static const int8_t dir_dy[4] = { -1, 0, 1, 0 };

#define PLAYER_SPEED 8      /* half pixels a tick */
#define NPC_SPEED    4
#define CHASE_SPEED  5
#define SWING_TICKS  12

void ents_reset(void)
{
    uint8_t i;
    for (i = 0; i != MAX_ENT; i++) {
        ents[i].active = 0;
        ents[i].carry = 0;
    }
    initarand(0x6C1D);
}

void ent_spawn_npc(uint8_t slot, const uint8_t *rec)
{
    ent_t *e = &ents[slot];
    e->active = 1;
    e->x = (int16_t)rec[0] * TILE_UNITS;
    e->y = (int16_t)rec[1] * TILE_UNITS;
    e->dir = rec[2] & 3;
    e->type = rec[3];
    e->text = rec[6];
    e->mode = rec[7];
    e->xmin = rec[8];
    e->xmax = rec[9];
    e->ymin = rec[10];
    e->ymax = rec[11];
    e->flags = rec[12];
    e->event = rec[14];
    e->evstep = 0;
    e->state = ST_IDLE;
    e->carry = 0;
    e->timer = e->frame = e->blink = e->ktimer = e->cool = 0;
    e->aitimer = 8 + slot * 5;
}

void ent_palette(uint8_t i)
{
    uint8_t pal[8];
    pak_read(PK_CHARS, 1 + (uint16_t)ents[i].type * CHAR_REC + CH_PAL, pal, 8);
    set_sprite_palette(i < 5 ? i : 4, 1, (palette_color_t *)pal);
}

void ents_palettes(void)
{
    uint8_t i, pal[16];
    for (i = 0; i != MAX_ENT; i++)
        if (ents[i].active)
            ent_palette(i);
    pak_read(PK_OBJPAL, 0, pal, 16);
    set_sprite_palette(PAL_OBJ_A, 1, (palette_color_t *)pal);
    set_sprite_palette(PAL_OBJ_B, 1, (palette_color_t *)(pal + 8));
}

/* Is another entity's body at (x, y) within r pixels? Returns its index + 1. */
uint8_t ent_box_hit(int16_t x, int16_t y, uint8_t r, uint8_t skip)
{
    uint8_t i;
    int16_t dx, dy;
    for (i = 0; i != MAX_ENT; i++) {
        if (i == skip || !ents[i].active)
            continue;
        dx = (ents[i].x - x) >> 1;
        dy = (ents[i].y - y) >> 1;
        if (dx < 0) dx = -dx;
        if (dy < 0) dy = -dy;
        if (dx < r && dy < r)
            return i + 1;
    }
    return 0;
}

void knock(ent_t *e, int16_t fx, int16_t fy)
{
    int16_t dx = e->x - fx, dy = e->y - fy;
    int16_t ax = dx < 0 ? -dx : dx, ay = dy < 0 ? -dy : dy;
    e->kx = e->ky = 0;
    if (ax >= ay)
        e->kx = dx < 0 ? -8 : 8;
    else
        e->ky = dy < 0 ? -8 : 8;
    e->ktimer = 4;
    e->blink = 12;
    e->state = ST_KNOCK;
    sfx(SFX_HIT);
}

/* The body is the 16x16 square round the centre. Returns 1 when moved,
   0 when a wall or a person was in the way; *who is the person + 1. */
static uint8_t who;

static uint8_t blocked_px(int16_t px, int16_t py)
{
    return tile_solid_px(px, py);
}

static uint8_t try_move(uint8_t ei, int8_t dx, int8_t dy, uint8_t slide)
{
    ent_t *e = &ents[ei];
    int16_t nx = e->x + dx, ny = e->y + dy;
    int16_t px = nx >> 1, py = ny >> 1;
    uint8_t a, b, c;
    who = 0;
    if (dx > 0) {
        a = blocked_px(px + 7, py - 8);
        b = blocked_px(px + 7, py);
        c = blocked_px(px + 7, py + 7);
    } else if (dx < 0) {
        a = blocked_px(px - 8, py - 8);
        b = blocked_px(px - 8, py);
        c = blocked_px(px - 8, py + 7);
    } else if (dy > 0) {
        a = blocked_px(px - 8, py + 7);
        b = blocked_px(px, py + 7);
        c = blocked_px(px + 7, py + 7);
    } else {
        a = blocked_px(px - 8, py - 8);
        b = blocked_px(px, py - 8);
        c = blocked_px(px + 7, py - 8);
    }
    if (a | b | c) {
        /* Round a corner when only one end is caught: the demo nudges the
           body sideways toward the free end without testing the rest of
           it, so a corner can be cut. */
        if (slide && (a ^ c)) {
            int8_t s = a ? 4 : -4;
            if (dx)
                e->y += s;
            else
                e->x += s;
        }
        return 0;
    }
    who = ent_box_hit(nx, ny, 14, ei);
    if (who)
        return 0;
    e->x = nx;
    e->y = ny;
    return 1;
}

static void start_swing(uint8_t ei)
{
    ent_t *e = &ents[ei];
    uint8_t pal[8];
    uint8_t c = pak_byte(PK_CHARS, 1 + (uint16_t)e->type * CHAR_REC + CH_SWORD);
    pak_read(PK_SWORDPAL, (uint16_t)(c > 2 ? 0 : c) * 8, pal, 8);
    set_sprite_palette(PAL_SWORD, 1, (palette_color_t *)pal);
    e->state = ST_SWORD;
    e->timer = SWING_TICKS;
    sfx(SFX_SWORD);
}

/* the sword's point, for hits, in the second half of the swing */
static void swing_hits(uint8_t ei)
{
    ent_t *e = &ents[ei];
    int16_t x = e->x + dir_dx[e->dir] * 28, y = e->y + dir_dy[e->dir] * 28;
    uint8_t h;
    if (e->timer > 8)
        return;
    h = ent_box_hit(x, y, 12, ei);
    if (h && !ents[h - 1].ktimer && (ei == 0 || h == 1))
        knock(&ents[h - 1], e->x, e->y);
}

static uint8_t knock_tick(uint8_t ei)
{
    ent_t *e = &ents[ei];
    if (e->blink)
        e->blink--;
    if (!e->ktimer)
        return 0;
    if (e->kx)
        try_move(ei, e->kx, 0, 0);
    if (e->ky)
        try_move(ei, 0, e->ky, 0);
    if (!--e->ktimer)
        e->state = ST_IDLE;
    return 1;
}

static void face_toward(ent_t *e, int16_t x, int16_t y)
{
    int16_t dx = x - e->x, dy = y - e->y;
    int16_t ax = dx < 0 ? -dx : dx, ay = dy < 0 ? -dy : dy;
    if (ax > ay)
        e->dir = dx < 0 ? D_LEFT : D_RIGHT;
    else
        e->dir = dy < 0 ? D_UP : D_DOWN;
}

static void player_tick(void)
{
    ent_t *p = &ents[0];
    uint8_t d = 0xFF, moved;
    if (knock_tick(0))
        return;
    if (p->state == ST_SWORD) {
        swing_hits(0);
        if (--p->timer)
            return;
        p->state = ST_IDLE;
        if ((keys & J_B) && !text_open)
            start_swing(0);
        return;
    }
    if (p->state == ST_LIFT) {
        if (!--p->timer)
            p->state = ST_IDLE;
        return;
    }
    if (text_open || player_frozen)
        return;
    if (pressed & J_A) {
        if (p->carry)
            throw_carried(0);
        else
            use_a_item(0);
        if (p->state == ST_LIFT)
            return;
    }
    if ((keys & J_B) && !p->carry) {
        start_swing(0);
        return;
    }
    if (keys & J_UP) d = D_UP;
    else if (keys & J_DOWN) d = D_DOWN;
    else if (keys & J_LEFT) d = D_LEFT;
    else if (keys & J_RIGHT) d = D_RIGHT;
    if (d == 0xFF) {
        p->state = ST_IDLE;
        return;
    }
    p->dir = d;
    p->state = ST_WALK;
    p->frame++;
    moved = try_move(0, dir_dx[d] * PLAYER_SPEED, dir_dy[d] * PLAYER_SPEED, 1);
    if (moved) {
        links_check();
        return;
    }
    /* walked into someone with something to say */
    if (who && ents[who - 1].text != 0xFF && !(pressed & J_A)) {
        ent_t *n = &ents[who - 1];
        face_toward(n, p->x, p->y);
        n->state = ST_IDLE;
        text_show(n->text);
        if (n->event == 1 && n->evstep == 0)
            n->evstep = 1;
        return;
    }
    /* a sign: facing up, the tile above is a wall */
    if (d == D_UP && tile_solid_px(p->x >> 1, (p->y >> 1) - 9)) {
        uint8_t t = text_at((p->x >> 1) >> 3, ((p->y >> 1) - 9) >> 3);
        if (t != 0xFF)
            text_show(t);
    }
}

/* Event 1, the captive: after the first text closes it walks two tiles
   left, lifts the bush there, turns and throws it, then the second text
   opens. The player waits while it runs. */
void event_text_closed(void)
{
    uint8_t i;
    for (i = 1; i != MAX_ENT; i++)
        if (ents[i].active && ents[i].event == 1 && ents[i].evstep == 1) {
            ents[i].evstep = 2;
            ents[i].timer = 8;
            ents[i].dir = D_LEFT;
            player_frozen = 1;
        } else if (ents[i].active && ents[i].event == 1 && ents[i].evstep == 6) {
            ents[i].evstep = 7;
        }
}

static void event_tick(uint8_t ei)
{
    ent_t *e = &ents[ei];
    switch (e->evstep) {
    case 2:                         /* walk two tiles left */
        e->state = ST_WALK;
        e->frame++;
        try_move(ei, -NPC_SPEED, 0, 0);
        if (!--e->timer) {
            e->state = ST_IDLE;
            e->evstep = 3;
        }
        break;
    case 3:                         /* lift the bush in front */
        e->dir = D_LEFT;
        if (try_lift(ei)) {
            e->evstep = 4;
        } else {
            e->evstep = 5;
            e->timer = 4;
        }
        break;
    case 4:                         /* turn and throw */
        if (e->state == ST_LIFT) {
            if (!--e->timer) {
                e->state = ST_IDLE;
                e->dir = D_RIGHT;       /* turns round and throws it east */
                e->timer = 24;
            }
            break;
        }
        if (!--e->timer) {
            throw_carried(ei);
            e->evstep = 5;
            e->timer = 16;
        }
        break;
    case 5:                         /* wait for the pieces, then the second text */
        if (!--e->timer) {
            e->evstep = 6;
            player_frozen = 0;
            text_show(1);
        }
        break;
    default:
        break;
    }
}

static void npc_tick(uint8_t ei)
{
    ent_t *e = &ents[ei];
    ent_t *p = &ents[0];
    int16_t dx, dy;
    uint8_t d;
    if (knock_tick(ei))
        return;
    if (e->state == ST_SWORD) {
        swing_hits(ei);
        if (!--e->timer)
            e->state = ST_IDLE;
        return;
    }
    if (e->event == 1 && e->evstep >= 2 && e->evstep <= 5) {
        event_tick(ei);
        return;
    }
    if (e->state == ST_LIFT) {
        if (!--e->timer)
            e->state = ST_IDLE;
        return;
    }
    if (text_open)
        return;
    if (e->cool)
        e->cool--;
    dx = p->x - e->x;
    dy = p->y - e->y;
    if ((e->flags & 0x81) == 0x01) {
        /* bit 0 alone: turn to watch the player once lined up */
        if ((dx > -16 && dx < 16) || (dy > -16 && dy < 16))
            face_toward(e, p->x, p->y);
    } else if (e->flags & 1) {
        if (dx > -16 && dx < 16 && dy > -160 && dy < 160) {
            e->mode = 0x80 | e->mode;           /* lined up: chase from now on */
        } else if (dy > -16 && dy < 16 && dx > -160 && dx < 160) {
            e->mode = 0x80 | e->mode;
        }
        if (e->mode & 0x80) {
            face_toward(e, p->x, p->y);
            if (dx > -44 && dx < 44 && dy > -44 && dy < 44) {
                if (!e->cool) {
                    start_swing(ei);
                    e->cool = 20;
                }
                e->state = ST_IDLE;
                return;
            }
            e->state = ST_WALK;
            e->frame++;
            d = e->dir;
            if (!try_move(ei, dir_dx[d] * CHASE_SPEED, dir_dy[d] * CHASE_SPEED, 1)) {
                /* blocked along the long axis: try the other one */
                if (d == D_LEFT || d == D_RIGHT)
                    try_move(ei, 0, dy < 0 ? -CHASE_SPEED : CHASE_SPEED, 0);
                else
                    try_move(ei, dx < 0 ? -CHASE_SPEED : CHASE_SPEED, 0, 0);
            }
            return;
        }
    }
    switch (e->mode & 0x7F) {
    case 1:                         /* wander */
    case 4:
        if (!e->aitimer) {
            d = arand() & 7;
            e->state = d < 4 ? ST_WALK : ST_IDLE;
            if (d < 4)
                e->dir = d;
            e->aitimer = 12 + (arand() & 31);
        }
        e->aitimer--;
        if (e->state != ST_WALK)
            return;
        break;
    case 2:                         /* patrol left and right */
        if (e->dir != D_LEFT && e->dir != D_RIGHT)
            e->dir = D_RIGHT;
        e->state = ST_WALK;
        break;
    case 3:                         /* patrol up and down */
        if (e->dir != D_UP && e->dir != D_DOWN)
            e->dir = D_DOWN;
        e->state = ST_WALK;
        break;
    default:
        e->state = ST_IDLE;
        return;
    }
    d = e->dir;
    {
        int16_t nx = e->x + dir_dx[d] * NPC_SPEED, ny = e->y + dir_dy[d] * NPC_SPEED;
        uint8_t tx = (uint8_t)(nx >> 4), ty = (uint8_t)(ny >> 4);
        if (nx < 0 || ny < 0 || tx < e->xmin || tx > e->xmax || ty < e->ymin || ty > e->ymax ||
            !try_move(ei, dir_dx[d] * NPC_SPEED, dir_dy[d] * NPC_SPEED, 0)) {
            e->dir = d ^ 2;             /* turn round */
            if ((e->mode & 0x7F) == 1 || (e->mode & 0x7F) == 4) {
                e->state = ST_IDLE;
                e->aitimer = 10;
            }
            return;
        }
        e->frame++;
    }
}

void ents_tick(void)
{
    uint8_t i;
    if (ents[0].active)
        player_tick();
    for (i = 1; i != MAX_ENT; i++)
        if (ents[i].active)
            npc_tick(i);
}
