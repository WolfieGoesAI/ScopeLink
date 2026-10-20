/* Offline tests for the screen decoder and wave parser (no hardware needed). */
#include "../core/utd.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int put_run(uint8_t *p, int color, int run) {
    p[0] = (uint8_t)((color & 0x1F) | ((run & 7) << 5));
    p[1] = (uint8_t)(run >> 3);
    return 2;
}

int main(int argc, char **argv) {
    /* palette: index 1 = (10,20,30) as B,G,R bytes; index 2 = (1,2,3) */
    uint8_t header[0xC0] = {0};
    header[0x40] = 0x55; header[0x41] = 0xAA;
    header[0x44 + 3] = 30; header[0x44 + 4] = 20; header[0x44 + 5] = 10;
    header[0x44 + 6] = 3; header[0x44 + 7] = 2; header[0x44 + 8] = 1;

    /* Column 0: 100 pixels of index 1, then 140 of index 2. Columns 1..319: index 1 (2047-runs). */
    uint8_t rle[4096]; int n = 0;
    n += put_run(rle + n, 1, 100);
    n += put_run(rle + n, 2, 140);
    int left = 319 * 240;
    while (left > 0) { int r = left > 2047 ? 2047 : left; n += put_run(rle + n, 1, r); left -= r; }

    static uint8_t rgb[320 * 240 * 3];
    utd_decode_screen(header, rle, n, rgb, 1);
    /* top-left pixel: index 1 -> RGB (10,20,30) */
    assert(rgb[0] == 10 && rgb[1] == 20 && rgb[2] == 30);
    /* row 150, column 0 -> index 2 -> (1,2,3) */
    uint8_t *p = rgb + 3 * (150 * 320 + 0);
    assert(p[0] == 1 && p[1] == 2 && p[2] == 3);
    /* row 150, column 1 -> index 1 */
    p = rgb + 3 * (150 * 320 + 1);
    assert(p[0] == 10);
    /* bottom-right */
    p = rgb + 3 * (239 * 320 + 319);
    assert(p[0] == 10 && p[2] == 30);
    /* RGB palette mode */
    utd_decode_screen(header, rle, n, rgb, 0);
    assert(rgb[0] == 30 && rgb[2] == 10);
    printf("screen decoder OK (%d token bytes)\n", n);

    if (argc > 1) {
        utd_decode_screen(header, rle, n, rgb, 1);
        assert(utd_write_png(argv[1], rgb, 320, 240) == 0);
        printf("wrote %s\n", argv[1]);
    }

    /* wave: 2-channel reply */
    static uint8_t buf[UTD_WAVE_PARAM_2CH];
    memset(buf, 0, sizeof buf);
    buf[0x40] = 0x55; buf[0x41] = 0xAA;
    for (int k = 0; k < 2; k++) {
        int b = 0x58 + k * 0x2EF4;
        buf[b] = 1;              /* on */
        buf[b + 2] = 7;          /* volts index */
        buf[b + 0x10] = 2;       /* 2 samples per column */
        for (int s = 0; s < 600; s++) buf[b + 0x14 + s] = (uint8_t)(s + k);
    }
    static utd_wave w;
    assert(utd_parse_wave(buf, sizeof buf, &w) == 0);
    assert(w.channels == 2 && w.ch[0].enabled && w.ch[1].count == 600 && w.ch[1].samples[5] == 6);
    assert(w.ch[0].volts_index == 7);
    /* 1-channel reply size */
    assert(utd_parse_wave(buf, UTD_WAVE_PARAM_1CH, &w) == 0);
    assert(w.channels == 1 && w.ch[0].count == 600);
    if (argc > 2) assert(utd_write_wave_csv(argv[2], &w) == 0);
    printf("wave parser OK\n");

    assert(utd_key_from_name("Run") == 0x0C && utd_key_from_name("f4") == 0x1B && utd_key_from_name("nope") == -1);
    printf("key names OK\n");
    return 0;
}
