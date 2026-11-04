/* Reading the asset pack. This file is linked into bank 0: it maps a pack
   bank at $4000, copies, and maps bank 1 (the game code) back. Nothing in
   here may call code that lives in bank 1. */
#include <gb/gb.h>
#include "pak.h"

#define PACK_BANK  8
#define GAME_BANK  1

static uint8_t dir_bank[PK_ITEMS];
static uint16_t dir_addr[PK_ITEMS];

uint8_t pak_init(void)
{
    const uint8_t *p = (const uint8_t *)0x4000;
    uint8_t i, ok;
    SWITCH_ROM(PACK_BANK);
    ok = p[0] == 'G' && p[1] == 'P' && p[2] == 'A' && p[3] == 'K';
    if (ok) {
        p += 6;
        for (i = 0; i != PK_ITEMS; i++) {
            dir_bank[i] = p[0];
            dir_addr[i] = p[1] | ((uint16_t)p[2] << 8);
            p += 5;
        }
    }
    SWITCH_ROM(GAME_BANK);
    return ok;
}

void pak_read(uint8_t id, uint16_t off, uint8_t *dst, uint16_t len)
{
    const uint8_t *src = (const uint8_t *)(dir_addr[id] + off);
    SWITCH_ROM(dir_bank[id]);
    while (len--)
        *dst++ = *src++;
    SWITCH_ROM(GAME_BANK);
}

uint8_t pak_byte(uint8_t id, uint16_t off)
{
    uint8_t v;
    SWITCH_ROM(dir_bank[id]);
    v = *(const uint8_t *)(dir_addr[id] + off);
    SWITCH_ROM(GAME_BANK);
    return v;
}

uint16_t pak_word(uint8_t id, uint16_t off)
{
    return pak_byte(id, off) | ((uint16_t)pak_byte(id, off + 1) << 8);
}
