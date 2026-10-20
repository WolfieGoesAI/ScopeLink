/* ScopeLink core: see utd.h for the protocol summary. */
#include "utd.h"

#include <libusb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

struct utd_dev {
    libusb_context *ctx;
    libusb_device_handle *h;
    uint8_t bus, addr;
    char product[128];
    char manufacturer[128];
};

static utd_log_fn g_log;
static void *g_log_ctx;

void utd_set_log(utd_log_fn fn, void *ctx) { g_log = fn; g_log_ctx = ctx; }

static void logf_(const char *fmt, ...) {
    if (!g_log) return;
    char line[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    g_log(g_log_ctx, line);
}

const char *utd_strerror(int err) {
    switch (err) {
    case UTD_OK: return "OK";
    case UTD_ERR_NODEV: return "No UNI-T oscilloscope found (USB 5345:1234). Check the cable and that the scope is switched on.";
    case UTD_ERR_OPEN: return "The oscilloscope was found but could not be opened.";
    case UTD_ERR_CONFIG: return "Could not select the oscilloscope's USB configuration.";
    case UTD_ERR_CLAIM: return "Could not claim the oscilloscope's USB interface (is another program using it?).";
    case UTD_ERR_WRITE: return "Sending a command to the oscilloscope failed.";
    case UTD_ERR_READ: return "Reading from the oscilloscope failed or timed out.";
    case UTD_ERR_SYNC: return "The oscilloscope's reply was not in the expected format.";
    case UTD_ERR_ARG: return "Invalid argument.";
    case UTD_ERR_INIT: return "USB could not be initialised.";
    default: return "Unknown error";
    }
}

static const struct { int code; const char *name; const char *alias; } k_keys[] = {
    {UTD_KEY_HORIZONTAL, "horizontal", "horiz"},
    {UTD_KEY_SHIFT, "shift", NULL},
    {UTD_KEY_MEASURE, "measure", "meas"},
    {UTD_KEY_CH1, "ch1", "channel"},
    {UTD_KEY_SELECT, "select", "sel"},
    {UTD_KEY_VOLTS_V, "volts-v", "vup"},
    {UTD_KEY_VOLTS_MV, "volts-mv", "vdown"},
    {UTD_KEY_TIME_S, "time-s", "tup"},
    {UTD_KEY_TIME_NS, "time-ns", "tdown"},
    {UTD_KEY_RUN_STOP, "run", "stop"},
    {UTD_KEY_DISPLAY, "display", "disp"},
    {UTD_KEY_MATH, "math", NULL},
    {UTD_KEY_RECORD, "record", "rec"},
    {UTD_KEY_SINGLE, "single", NULL},
    {UTD_KEY_TRIGGER, "trigger", "trig"},
    {UTD_KEY_UP, "up", NULL},
    {UTD_KEY_DOWN, "down", NULL},
    {UTD_KEY_LEFT, "left", NULL},
    {UTD_KEY_RIGHT, "right", NULL},
    {UTD_KEY_OK, "ok", "enter"},
    {UTD_KEY_AUTO, "auto", NULL},
    {UTD_KEY_F1, "f1", NULL},
    {UTD_KEY_F2, "f2", NULL},
    {UTD_KEY_F3, "f3", NULL},
    {UTD_KEY_F4, "f4", NULL},
    {UTD_KEY_DSO_DMM, "dso", "dmm"},
    {UTD_KEY_ACQUIRE, "acquire", "acq"},
};

const char *utd_key_name(int code) {
    for (size_t i = 0; i < sizeof k_keys / sizeof k_keys[0]; i++)
        if (k_keys[i].code == code) return k_keys[i].name;
    return NULL;
}

int utd_key_from_name(const char *name) {
    if (!name) return -1;
    for (size_t i = 0; i < sizeof k_keys / sizeof k_keys[0]; i++) {
        if (!strcasecmp(name, k_keys[i].name)) return k_keys[i].code;
        if (k_keys[i].alias && !strcasecmp(name, k_keys[i].alias)) return k_keys[i].code;
    }
    char *end;
    long v = strtol(name, &end, 0);
    if (*name && !*end && v >= 0 && v <= 0x1F) return (int)v;
    return -1;
}

static int is_scope(libusb_device *d) {
    struct libusb_device_descriptor desc;
    if (libusb_get_device_descriptor(d, &desc) != 0) return 0;
    return desc.idVendor == UTD_VID && desc.idProduct == UTD_PID;
}

int utd_count_devices(void) {
    libusb_context *ctx;
    if (libusb_init(&ctx) != 0) return UTD_ERR_INIT;
    libusb_device **list;
    ssize_t n = libusb_get_device_list(ctx, &list);
    int count = 0;
    for (ssize_t i = 0; i < n; i++) count += is_scope(list[i]);
    if (n >= 0) libusb_free_device_list(list, 1);
    libusb_exit(ctx);
    return count;
}

int utd_open(utd_dev **out) {
    *out = NULL;
    utd_dev *dev = calloc(1, sizeof *dev);
    if (!dev) return UTD_ERR_INIT;
    if (libusb_init(&dev->ctx) != 0) { free(dev); return UTD_ERR_INIT; }

    libusb_device **list;
    ssize_t n = libusb_get_device_list(dev->ctx, &list);
    libusb_device *found = NULL;
    for (ssize_t i = 0; i < n; i++)
        if (is_scope(list[i])) { found = list[i]; break; }
    int rc = UTD_ERR_NODEV;
    if (found) {
        int r = libusb_open(found, &dev->h);
        if (r != 0) {
            logf_("libusb_open: %s", libusb_error_name(r));
            rc = UTD_ERR_OPEN;
        } else {
            dev->bus = libusb_get_bus_number(found);
            dev->addr = libusb_get_device_address(found);
            struct libusb_device_descriptor desc;
            if (libusb_get_device_descriptor(found, &desc) == 0) {
                if (desc.iProduct)
                    libusb_get_string_descriptor_ascii(dev->h, desc.iProduct, (unsigned char *)dev->product, sizeof dev->product - 1);
                if (desc.iManufacturer)
                    libusb_get_string_descriptor_ascii(dev->h, desc.iManufacturer, (unsigned char *)dev->manufacturer, sizeof dev->manufacturer - 1);
            }
            rc = UTD_OK;
        }
    }
    if (n >= 0) libusb_free_device_list(list, 1);
    if (rc != UTD_OK) { libusb_exit(dev->ctx); free(dev); return rc; }

    /* Same order as the Windows app: set_configuration(1), claim_interface(0). */
    int cfg = 0;
    libusb_get_configuration(dev->h, &cfg);
    if (cfg != 1) {
        int r = libusb_set_configuration(dev->h, 1);
        if (r != 0) {
            logf_("set_configuration(1): %s", libusb_error_name(r));
            /* Not fatal on macOS, where the configuration is usually already active. */
            if (cfg == 0) { libusb_close(dev->h); libusb_exit(dev->ctx); free(dev); return UTD_ERR_CONFIG; }
        }
    }
#ifdef __linux__
    libusb_set_auto_detach_kernel_driver(dev->h, 1);
#endif
    int r = libusb_claim_interface(dev->h, 0);
    if (r != 0) {
        logf_("claim_interface(0): %s", libusb_error_name(r));
        libusb_close(dev->h); libusb_exit(dev->ctx); free(dev);
        return UTD_ERR_CLAIM;
    }
    logf_("Opened oscilloscope on bus %u address %u%s%s", dev->bus, dev->addr,
          dev->product[0] ? ": " : "", dev->product);
    *out = dev;
    return UTD_OK;
}

void utd_close(utd_dev *dev) {
    if (!dev) return;
    if (dev->h) {
        libusb_release_interface(dev->h, 0);
        libusb_close(dev->h);
    }
    if (dev->ctx) libusb_exit(dev->ctx);
    free(dev);
}

void utd_describe(utd_dev *dev, char *buf, size_t len) {
    if (!dev || !len) return;
    snprintf(buf, len, "%s%s%s (USB %04x:%04x, bus %u, address %u)",
             dev->manufacturer, dev->manufacturer[0] && dev->product[0] ? " " : "",
             dev->product[0] || dev->manufacturer[0] ? dev->product : "UNI-T oscilloscope",
             UTD_VID, UTD_PID, dev->bus, dev->addr);
}

int utd_send_command(utd_dev *dev, uint8_t group, uint8_t code, uint32_t param) {
    if (!dev) return UTD_ERR_ARG;
    uint8_t pkt[64];
    memset(pkt, 0, sizeof pkt);
    pkt[0] = 0x55; pkt[1] = 0xAA;
    pkt[2] = group; pkt[3] = code;
    pkt[4] = (uint8_t)param; pkt[5] = (uint8_t)(param >> 8);
    pkt[6] = (uint8_t)(param >> 16); pkt[7] = (uint8_t)(param >> 24);
    int done = 0;
    int r = libusb_bulk_transfer(dev->h, UTD_EP_OUT, pkt, sizeof pkt, &done, UTD_TIMEOUT_MS);
    if (r != 0 || done != (int)sizeof pkt) {
        logf_("write %02X %02X %08X: %s (%d bytes)", group, code, param, libusb_error_name(r), done);
        return UTD_ERR_WRITE;
    }
    return UTD_OK;
}

int utd_read(utd_dev *dev, uint8_t *buf, int len) {
    if (!dev || !buf || len <= 0) return UTD_ERR_ARG;
    int done = 0;
    int r = libusb_bulk_transfer(dev->h, UTD_EP_IN, buf, len, &done, UTD_TIMEOUT_MS);
    if (r == LIBUSB_ERROR_TIMEOUT && done > 0) return done;
    if (r == LIBUSB_ERROR_OVERFLOW && done > 0) return done;
    if (r != 0) {
        logf_("read %d bytes: %s (%d received)", len, libusb_error_name(r), done);
        return UTD_ERR_READ;
    }
    return done;
}

int utd_press_key(utd_dev *dev, int key) {
    if (key < 0 || key > 0x1F) return UTD_ERR_ARG;
    return utd_send_command(dev, UTD_GROUP_KEY, (uint8_t)key, 0);
}

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }

void utd_decode_screen(const uint8_t *header, const uint8_t *rle, int n, uint8_t *rgb, int palette_bgr) {
    /* Same algorithm as the Windows app (UTD1052DL.exe 0x40DB0F / 0x40DC6F):
     * each 2-byte token: index = b0 & 0x1F, run = (b0 >> 5) | (b1 << 3).
     * Pixels fill column by column, top to bottom, left to right. */
    const int W = UTD_SCREEN_W, H = UTD_SCREEN_H, total = W * H;
    uint8_t *idx = calloc((size_t)total, 1);
    if (!idx) return;
    int col = 0, pos = 0; /* pos = row*W + col */
    for (int i = 0; i + 1 < n; i += 2) {
        uint8_t b0 = rle[i], b1 = rle[i + 1];
        uint8_t color = b0 & 0x1F;
        int run = (b0 >> 5) | (b1 << 3);
        while (run-- > 0) {
            if (pos >= total) {
                col++;
                if (col >= W) goto done;
                pos = col;
            }
            idx[pos] = color;
            pos += W;
        }
    }
done:
    for (int p = 0; p < total; p++) {
        const uint8_t *e = header + 0x44 + 3 * idx[p];
        uint8_t *o = rgb + 3 * p;
        if (palette_bgr) { o[0] = e[2]; o[1] = e[1]; o[2] = e[0]; }
        else { o[0] = e[0]; o[1] = e[1]; o[2] = e[2]; }
    }
    free(idx);
}

static int g_screen_fmt = UTD_SCREEN_FMT_AUTO;
static int g_last_fmt = 0;
void utd_set_screen_format(int fmt) { g_screen_fmt = fmt; }
int utd_last_screen_format(void) { return g_last_fmt; }
const char *utd_screen_format_name(int fmt) {
    switch (fmt) {
    case UTD_SCREEN_FMT_1000CL: return "UTD1000CL (16-bit tokens, rows)";
    case UTD_SCREEN_FMT_1052DL: return "UTD1052DL (5/11-bit tokens, columns)";
    default: return "automatic";
    }
}

static long sum_1000cl(const uint8_t *data, int ntok, int datalen) {
    long sum = 0;
    for (int i = 0; i < ntok && 2 * i + 1 < datalen; i++) sum += (rd16(data + 2 * i) >> 4) & 0xFFF;
    return sum;
}
static long sum_1052dl(const uint8_t *data, int nbytes, int datalen) {
    long sum = 0;
    for (int i = 0; i + 1 < nbytes && i + 1 < datalen; i += 2) sum += (data[i] >> 5) | (data[i + 1] << 3);
    return sum;
}

int utd_screen_detect(const uint8_t *header, const uint8_t *data, int datalen) {
    int n = rd16(header + 0x42);
    long total = (long)UTD_SCREEN_W * UTD_SCREEN_H;
    long a = sum_1000cl(data, n, datalen), b = sum_1052dl(data, n, datalen);
    long da = labs(a - total), db = labs(b - total);
    return da <= db ? UTD_SCREEN_FMT_1000CL : UTD_SCREEN_FMT_1052DL;
}

void utd_decode_screen_fmt(const uint8_t *header, const uint8_t *data, int datalen, uint8_t *rgb, int palette_bgr, int fmt) {
    int n = rd16(header + 0x42);
    if (fmt == UTD_SCREEN_FMT_AUTO) fmt = utd_screen_detect(header, data, datalen);
    if (fmt == UTD_SCREEN_FMT_1052DL) {
        utd_decode_screen(header, data, n < datalen ? n : datalen, rgb, palette_bgr);
        return;
    }
    const int total = UTD_SCREEN_W * UTD_SCREEN_H;
    uint8_t *idx = calloc((size_t)total, 1);
    if (!idx) return;
    int pos = 0;
    for (int i = 0; i < n && 2 * i + 1 < datalen && pos < total; i++) {
        uint16_t w = rd16(data + 2 * i);
        int color = w & 0x0F, run = (w >> 4) & 0xFFF;
        if (run > total - pos) run = total - pos;
        memset(idx + pos, color, (size_t)run);
        pos += run;
    }
    for (int p = 0; p < total; p++) {
        const uint8_t *e = header + 0x44 + 3 * idx[p];
        uint8_t *o = rgb + 3 * p;
        if (palette_bgr) { o[0] = e[2]; o[1] = e[1]; o[2] = e[0]; }
        else { o[0] = e[0]; o[1] = e[1]; o[2] = e[2]; }
    }
    free(idx);
}

/* Sends 01 F1 and reads header + data. Caller frees *data. */
static int capture_screen_bytes(utd_dev *dev, uint8_t header[0xC0], uint8_t **data, int *datalen) {
    *data = NULL; *datalen = 0;
    int r = utd_send_command(dev, UTD_GROUP_CAPTURE, 0xF1, UTD_SCREEN_PARAM);
    if (r) return r;
    memset(header, 0, 0xC0);
    r = utd_read(dev, header, 0x80);
    if (r < 0) return r;
    if (rd16(header + 0x40) != 0xAA55) {
        logf_("screen: no sync in reply (%d bytes, got %02X %02X at 0x40)", r, header[0x40], header[0x41]);
        return UTD_ERR_SYNC;
    }
    int n = rd16(header + 0x42);
    int want = ((n << 2) / 64 + 1) * 64; /* exactly what the Windows apps request */
    uint8_t *buf = calloc((size_t)want, 1);
    if (!buf) return UTD_ERR_ARG;
    r = utd_read(dev, buf, want);
    if (r < 0) { free(buf); return r; }
    *data = buf; *datalen = r;
    return UTD_OK;
}

int utd_capture_screen(utd_dev *dev, uint8_t *rgb, int palette_bgr) {
    uint8_t header[0xC0];
    uint8_t *data; int len;
    int r = capture_screen_bytes(dev, header, &data, &len);
    if (r) return r;
    int fmt = g_screen_fmt == UTD_SCREEN_FMT_AUTO ? utd_screen_detect(header, data, len) : g_screen_fmt;
    if (fmt != g_last_fmt) {
        int n = rd16(header + 0x42);
        logf_("screen: %d bytes, count %d; format %s (runs: 1000CL %ld, 1052DL %ld, need %d)", len, n,
              utd_screen_format_name(fmt), sum_1000cl(data, n, len), sum_1052dl(data, n, len), UTD_SCREEN_W * UTD_SCREEN_H);
        g_last_fmt = fmt;
    }
    utd_decode_screen_fmt(header, data, len, rgb, palette_bgr, fmt);
    free(data);
    return UTD_OK;
}

int utd_capture_screen_raw(utd_dev *dev, const char *path) {
    uint8_t header[0xC0];
    uint8_t *data; int len;
    int r = capture_screen_bytes(dev, header, &data, &len);
    if (r) return r;
    FILE *f = fopen(path, "wb");
    if (!f) { free(data); return UTD_ERR_ARG; }
    fwrite(header, 1, sizeof header, f);
    fwrite(data, 1, (size_t)len, f);
    fclose(f);
    free(data);
    return UTD_OK;
}

int utd_parse_wave(const uint8_t *buf, int len, utd_wave *out) {
    memset(out, 0, sizeof *out);
    out->bytes = len;
    if (len < 0x58 + 0x14) return UTD_ERR_SYNC;
    if (rd16(buf + 0x40) != 0xAA55) return UTD_ERR_SYNC;
    memcpy(out->header, buf, 0x58);
    /* Channel block k starts at 0x58 + k*0x2EF4:
     *   +0x00 on/off, +0x02 volts index, +0x06 position, +0x0A invert flag,
     *   +0x10 samples per column (max 40), +0x14 samples (300 columns). */
    for (int k = 0; k < 2; k++) {
        int base = 0x58 + k * 0x2EF4;
        if (base + 0x14 > len) break;
        utd_channel *c = &out->ch[k];
        c->present = 1;
        for (int w = 0; w < 10; w++) c->raw_header[w] = rd16(buf + base + 2 * w);
        c->enabled = rd16(buf + base + 0x00) == 1;
        c->volts_index = (int16_t)rd16(buf + base + 0x02);
        c->position = (int16_t)rd16(buf + base + 0x06);
        c->inverted = (int16_t)rd16(buf + base + 0x0A);
        int per = (int16_t)rd16(buf + base + 0x10);
        if (per < 1) per = 1;
        if (per > 40) per = 40;
        c->per_column = per;
        int count = 300 * per;
        int avail = len - (base + 0x14);
        if (count > avail) count = avail;
        if (count < 0) count = 0;
        c->count = count;
        memcpy(c->samples, buf + base + 0x14, (size_t)count);
        out->channels = k + 1;
    }
    return UTD_OK;
}

int utd_capture_wave(utd_dev *dev, utd_model_t model, utd_wave *out) {
    uint32_t param = model == UTD_MODEL_1CH ? UTD_WAVE_PARAM_1CH : UTD_WAVE_PARAM_2CH;
    int r = utd_send_command(dev, UTD_GROUP_CAPTURE, 0xF2, param);
    if (r) return r;
    uint8_t *buf = calloc(UTD_WAVE_MAX, 1);
    if (!buf) return UTD_ERR_ARG;
    r = utd_read(dev, buf, (int)param);
    if (r < 0) { free(buf); return r; }
    int len = r;
    r = utd_parse_wave(buf, len, out);
    if (r) logf_("wave: no sync in %d-byte reply", len);
    free(buf);
    return r;
}

int utd_write_wave_csv(const char *path, const utd_wave *w) {
    FILE *f = fopen(path, "w");
    if (!f) return UTD_ERR_ARG;
    fprintf(f, "# ScopeLink waveform export (raw 8-bit codes as sent by the oscilloscope)\n");
    fprintf(f, "# reply_bytes,%d\n", w->bytes);
    for (int k = 0; k < w->channels; k++) {
        const utd_channel *c = &w->ch[k];
        fprintf(f, "# ch%d,enabled=%d,volts_index=%d,position=%d,field_0a=%d,samples_per_column=%d,samples=%d,header=",
                k + 1, c->enabled, c->volts_index, c->position, c->inverted, c->per_column, c->count);
        for (int i = 0; i < 10; i++) fprintf(f, "%04X%s", c->raw_header[i], i < 9 ? " " : "\n");
    }
    fprintf(f, "# reply_header=");
    for (int i = 0; i < 0x58; i++) fprintf(f, "%02X", w->header[i]);
    fprintf(f, "\n");
    int maxn = 0;
    for (int k = 0; k < w->channels; k++) if (w->ch[k].count > maxn) maxn = w->ch[k].count;
    fprintf(f, "index,column");
    for (int k = 0; k < w->channels; k++) fprintf(f, ",ch%d", k + 1);
    fprintf(f, "\n");
    int per = w->channels ? w->ch[0].per_column : 1;
    for (int i = 0; i < maxn; i++) {
        fprintf(f, "%d,%d", i, i / (per ? per : 1));
        for (int k = 0; k < w->channels; k++) {
            if (i < w->ch[k].count) fprintf(f, ",%u", w->ch[k].samples[i]);
            else fprintf(f, ",");
        }
        fprintf(f, "\n");
    }
    fclose(f);
    return UTD_OK;
}

utd_wave *utd_wave_new(void) { return calloc(1, sizeof(utd_wave)); }
void utd_wave_free(utd_wave *w) { free(w); }
int utd_wave_channels(const utd_wave *w) { return w ? w->channels : 0; }
static const utd_channel *chan(const utd_wave *w, int ch) { return (w && ch >= 0 && ch < w->channels) ? &w->ch[ch] : NULL; }
int utd_wave_enabled(const utd_wave *w, int ch) { const utd_channel *c = chan(w, ch); return c ? c->enabled : 0; }
int utd_wave_volts_index(const utd_wave *w, int ch) { const utd_channel *c = chan(w, ch); return c ? c->volts_index : 0; }
int utd_wave_count(const utd_wave *w, int ch) { const utd_channel *c = chan(w, ch); return c ? c->count : 0; }
int utd_wave_per_column(const utd_wave *w, int ch) { const utd_channel *c = chan(w, ch); return c ? c->per_column : 1; }
const uint8_t *utd_wave_samples(const utd_wave *w, int ch) { const utd_channel *c = chan(w, ch); return c ? c->samples : NULL; }
int utd_wave_bytes(const utd_wave *w) { return w ? w->bytes : 0; }
