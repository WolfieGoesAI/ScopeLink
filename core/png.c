/* Minimal PNG writer (RGB, 8-bit) using the system zlib. */
#include "utd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static void put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = (uint8_t)v; }

static int chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len) {
    uint8_t b[4];
    put32(b, len);
    if (fwrite(b, 1, 4, f) != 4 || fwrite(type, 1, 4, f) != 4) return -1;
    if (len && fwrite(data, 1, len, f) != len) return -1;
    uLong crc = crc32(0, (const Bytef *)type, 4);
    if (len) crc = crc32(crc, data, len);
    put32(b, (uint32_t)crc);
    return fwrite(b, 1, 4, f) == 4 ? 0 : -1;
}

int utd_write_png(const char *path, const uint8_t *rgb, int w, int h) {
    size_t raw_len = (size_t)h * (1 + 3 * (size_t)w);
    uint8_t *raw = malloc(raw_len);
    if (!raw) return UTD_ERR_ARG;
    for (int y = 0; y < h; y++) {
        raw[y * (1 + 3 * w)] = 0;
        memcpy(raw + y * (1 + 3 * w) + 1, rgb + (size_t)y * w * 3, (size_t)w * 3);
    }
    uLongf zlen = compressBound(raw_len);
    uint8_t *z = malloc(zlen);
    if (!z || compress2(z, &zlen, raw, raw_len, 9) != Z_OK) { free(raw); free(z); return UTD_ERR_ARG; }
    free(raw);
    FILE *f = fopen(path, "wb");
    if (!f) { free(z); return UTD_ERR_ARG; }
    static const uint8_t sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};
    uint8_t ihdr[13];
    put32(ihdr, (uint32_t)w); put32(ihdr + 4, (uint32_t)h);
    ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
    int ok = fwrite(sig, 1, 8, f) == 8 && !chunk(f, "IHDR", ihdr, 13) &&
             !chunk(f, "IDAT", z, (uint32_t)zlen) && !chunk(f, "IEND", NULL, 0);
    free(z);
    if (fclose(f) != 0) ok = 0;
    return ok ? UTD_OK : UTD_ERR_ARG;
}
