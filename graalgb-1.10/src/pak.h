/* The asset pack in banks 8 to 15 (tools/gpak.py writes it). */
#ifndef PAK_H
#define PAK_H
#include <stdint.h>

#define PK_TILES0   0
#define PK_TILES1   1
#define PK_FONT     2
#define PK_WALK     3
#define PK_BGPAL    4
#define PK_ANIM     5
#define PK_SPRITES  6
#define PK_CHARS    7
#define PK_HEADS    8
#define PK_LIFT     9
#define PK_START    10
#define PK_SWORDPAL 11
#define PK_OBJPAL   12
#define PK_ROOM0    16
#define PK_ITEMS    23

#define CHAR_REC    48
#define NAME_LEN    18
#define CH_PAL      18   /* three OBJ palettes, 24 bytes */
#define CH_HEAD     42
#define CH_SWORD    43
#define CH_AITEM    44

#define A_NONE      0
#define A_LIFT      1
#define A_BOMB      2
#define A_BOOMERANG 3

/* Returns 0 when banks 8 on hold no pack. */
uint8_t pak_init(void);
void pak_read(uint8_t id, uint16_t off, uint8_t *dst, uint16_t len);
uint8_t pak_byte(uint8_t id, uint16_t off);
uint16_t pak_word(uint8_t id, uint16_t off);

#endif
