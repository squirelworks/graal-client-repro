/* Things that are lifted, thrown, dropped and blown up.

   Lifting works on 2x2 map objects whose top two tiles match one of four
   liftable kinds in the pack. Kinds 0 to 2 leave their "lifted" tiles in
   the map; kind 3 (a dropped object) puts the room's own tiles back. The
   object shows where it stood for 10 ticks, then over the carrier's head.
   A thrown object flies about 6 ticks and always breaks into four pieces;
   nothing is written back into the map. */
#include <gb/gb.h>
#include "game.h"
#include "pak.h"

obj_t objs[MAX_OBJ];

static const int8_t dir_dx[4] = { 0, -1, 0, 1 };
static const int8_t dir_dy[4] = { -1, 0, 1, 0 };

#define LIFT_TICKS   10
#define THROW_TICKS  6
#define THROW_SPEED  16
#define PIECE_TICKS  8
#define BOMB_TICKS   55
#define FLASH_TICKS  35
#define BLAST_TICKS  8
#define BOOM_OUT     8
#define BOOM_SPEED   8

void objs_reset(void)
{
    uint8_t i;
    for (i = 0; i != MAX_OBJ; i++)
        objs[i].kind = OB_NONE;
}

static obj_t *obj_new(uint8_t kind)
{
    uint8_t i;
    for (i = 0; i != MAX_OBJ; i++)
        if (objs[i].kind == OB_NONE) {
            objs[i].kind = kind;
            objs[i].timer = 0;
            objs[i].phase = 0;
            return &objs[i];
        }
    return 0;
}

static uint8_t at(int8_t tx, int8_t ty)
{
    if (tx < 0 || ty < 0 || tx > 31 || ty > 31)
        return 0xFE;
    return map[((uint16_t)ty << 5) | (uint8_t)tx];
}

/* Returns 1 when ents[ei] lifted something. */
uint8_t try_lift(uint8_t ei)
{
    ent_t *e = &ents[ei];
    uint8_t lift[28];
    int16_t px = (e->x >> 1) + dir_dx[e->dir] * 12;
    int16_t py = (e->y >> 1) + dir_dy[e->dir] * 12;
    int8_t tx, ty, cx, cy;
    uint8_t k, c;
    obj_t *o;
    if (px < 0 || py < 0 || px > 255 || py > 255)
        return 0;
    tx = px >> 3;
    ty = py >> 3;
    pak_read(PK_LIFT, 0, lift, 28);
    for (c = 0; c != 4; c++) {
        cx = tx - (c & 1);
        cy = ty - (c >> 1);
        for (k = 0; k != 4; k++) {
            if (lift[k] == 0xFF || at(cx, cy) != lift[k] || at(cx + 1, cy) != lift[4 + k])
                continue;
            o = obj_new(OB_LIFTING);
            if (!o)
                return 0;
            if (k < 3) {
                map_set(cx, cy, lift[8 + k * 4]);
                map_set(cx + 1, cy, lift[9 + k * 4]);
                map_set(cx, cy + 1, lift[10 + k * 4]);
                map_set(cx + 1, cy + 1, lift[11 + k * 4]);
            } else {
                room_restore_tile(cx, cy);
                room_restore_tile(cx + 1, cy);
                room_restore_tile(cx, cy + 1);
                room_restore_tile(cx + 1, cy + 1);
            }
            o->look = lift[24 + k];
            o->x = (int16_t)(cx + 1) * TILE_UNITS;
            o->y = (int16_t)(cy + 1) * TILE_UNITS;
            o->owner = ei;
            o->timer = LIFT_TICKS;
            e->state = ST_LIFT;
            e->timer = LIFT_TICKS;
            sfx(SFX_LIFT);
            return 1;
        }
    }
    return 0;
}

void throw_carried(uint8_t ei)
{
    ent_t *e = &ents[ei];
    obj_t *o;
    if (!e->carry)
        return;
    o = obj_new(OB_THROWN);
    if (!o)
        return;
    o->look = e->carry - 1;
    o->x = e->x;
    o->y = e->y - 24;
    o->dir = e->dir;
    o->owner = ei;
    o->timer = THROW_TICKS;
    e->carry = 0;
    sfx(SFX_THROW);
}

void use_a_item(uint8_t ei)
{
    ent_t *e = &ents[ei];
    uint8_t item = pak_byte(PK_CHARS, 1 + (uint16_t)e->type * CHAR_REC + CH_AITEM);
    uint8_t i;
    obj_t *o;
    if (item == A_LIFT) {
        try_lift(ei);
        return;
    }
    for (i = 0; i != MAX_OBJ; i++)          /* one bomb or boomerang at a time */
        if (objs[i].owner == ei && (objs[i].kind == OB_BOMB || objs[i].kind == OB_BLAST ||
                                    objs[i].kind == OB_BOOM))
            return;
    if (item == A_BOMB) {
        o = obj_new(OB_BOMB);
        if (!o)
            return;
        o->x = e->x + dir_dx[e->dir] * 24;
        o->y = e->y + dir_dy[e->dir] * 24;
        o->owner = ei;
        o->timer = BOMB_TICKS + FLASH_TICKS;
    } else if (item == A_BOOMERANG) {
        o = obj_new(OB_BOOM);
        if (!o)
            return;
        o->x = e->x;
        o->y = e->y;
        o->dir = e->dir;
        o->owner = ei;
        o->timer = 40;
        sfx(SFX_THROW);
    }
}

static void blast_hits(obj_t *o)
{
    uint8_t i;
    int16_t dx, dy;
    for (i = 0; i != MAX_ENT; i++) {
        ent_t *e = &ents[i];
        if (!e->active || e->ktimer)
            continue;
        dx = (e->x - o->x) >> 1;
        dy = (e->y - o->y) >> 1;
        if (dx < 0) dx = -dx;
        if (dy < 0) dy = -dy;
        if ((dx < 40 && dy < 12) || (dy < 40 && dx < 12))
            knock(e, o->x, o->y);
    }
}

void objs_tick(void)
{
    uint8_t i, h;
    obj_t *o;
    for (i = 0; i != MAX_OBJ; i++) {
        o = &objs[i];
        switch (o->kind) {
        case OB_LIFTING:
            if (!--o->timer) {
                ents[o->owner].carry = o->look + 1;
                o->kind = OB_NONE;
            }
            break;
        case OB_THROWN:
            o->x += dir_dx[o->dir] * THROW_SPEED;
            o->y += dir_dy[o->dir] * THROW_SPEED;
            h = ent_box_hit(o->x, o->y + 24, 10, o->owner);
            if (h && !ents[h - 1].ktimer)
                knock(&ents[h - 1], o->x, o->y);
            if (!--o->timer || h || tile_solid_px(o->x >> 1, (o->y + 24) >> 1)) {
                o->kind = OB_PIECES;
                o->y += 24;
                o->timer = PIECE_TICKS;
                sfx(SFX_BREAK);
            }
            break;
        case OB_PIECES:
            if (!--o->timer)
                o->kind = OB_NONE;
            break;
        case OB_BOMB:
            if (!--o->timer) {
                o->kind = OB_BLAST;
                o->timer = BLAST_TICKS;
                sfx(SFX_BOMB);
                blast_hits(o);
            }
            break;
        case OB_BLAST:
            if (!--o->timer)
                o->kind = OB_NONE;
            break;
        case OB_BOOM: {
            ent_t *e = &ents[o->owner];
            o->phase++;
            if (o->phase <= BOOM_OUT) {
                o->x += dir_dx[o->dir] * BOOM_SPEED;
                o->y += dir_dy[o->dir] * BOOM_SPEED;
            } else {
                int16_t dx = e->x - o->x, dy = e->y - o->y;
                o->x += dx > BOOM_SPEED ? BOOM_SPEED : dx < -BOOM_SPEED ? -BOOM_SPEED : dx;
                o->y += dy > BOOM_SPEED ? BOOM_SPEED : dy < -BOOM_SPEED ? -BOOM_SPEED : dy;
                if ((dx < 16 && dx > -16 && dy < 16 && dy > -16) || !--o->timer) {
                    o->kind = OB_NONE;
                    break;
                }
            }
            h = ent_box_hit(o->x, o->y, 10, o->owner);
            if (h && !ents[h - 1].ktimer)
                knock(&ents[h - 1], o->x, o->y);
            break;
        }
        default:
            break;
        }
    }
}
