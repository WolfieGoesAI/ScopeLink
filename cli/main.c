/* scopelink: command-line tool for UNI-T UTD1000-series oscilloscopes. */
#include "../core/utd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>

#ifndef SCOPELINK_VERSION
#define SCOPELINK_VERSION "dev"
#endif

static int verbose;
static void log_line(void *ctx, const char *line) { (void)ctx; if (verbose) fprintf(stderr, "  [usb] %s\n", line); }

static void usage(void) {
    printf(
"scopelink %s - UNI-T UTD1000-series oscilloscope over USB\n"
"\n"
"Usage: scopelink [-v] [--1ch] [--rgb] <command> [arguments]\n"
"\n"
"Commands:\n"
"  info                      Find the oscilloscope and show what it is\n"
"  screen [file.png]         Save a screenshot (default: scope-<date-time>.png)\n"
"  wave [file.csv]           Save the current waveform samples as CSV\n"
"  key <name> [name ...]     Press front-panel keys, e.g.  key auto   key f1 ok\n"
"  keys                      List key names\n"
"  watch [folder] [seconds]  Save a screenshot every N seconds (default 1) until Ctrl-C\n"
"  raw <group> <code> [param] [readlen]\n"
"                            Send any command and hex-dump the reply (for exploring)\n"
"\n"
"Options:\n"
"  -v       show USB details\n"
"  --1ch    single-channel model (UTD1000CL); default is 2-channel (UTD1052DL)\n"
"  --rgb    treat the scope's palette as R,G,B instead of B,G,R (use if colours look swapped)\n"
"\n"
"Firmware upgrade is deliberately not supported.\n", SCOPELINK_VERSION);
}

static int open_or_die(utd_dev **d) {
    int r = utd_open(d);
    if (r) { fprintf(stderr, "error: %s\n", utd_strerror(r)); return 0; }
    return 1;
}

static void stamp(char *buf, size_t n, const char *prefix, const char *ext) {
    time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    snprintf(buf, n, "%s-%04d%02d%02d-%02d%02d%02d.%s", prefix, tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
             tm.tm_hour, tm.tm_min, tm.tm_sec, ext);
}

static void hexdump(const uint8_t *b, int n) {
    for (int i = 0; i < n; i += 16) {
        printf("%06x ", i);
        for (int j = 0; j < 16; j++) { if (i + j < n) printf(" %02x", b[i + j]); else printf("   "); }
        printf("  ");
        for (int j = 0; j < 16 && i + j < n; j++) putchar(b[i + j] >= 32 && b[i + j] < 127 ? b[i + j] : '.');
        putchar('\n');
    }
}

int main(int argc, char **argv) {
    int one_ch = 0, rgb_pal = 0;
    int i = 1;
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (!strcmp(argv[i], "-v")) verbose = 1;
        else if (!strcmp(argv[i], "--1ch")) one_ch = 1;
        else if (!strcmp(argv[i], "--rgb")) rgb_pal = 1;
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(); return 0; }
        else if (!strcmp(argv[i], "--version")) { printf("scopelink %s\n", SCOPELINK_VERSION); return 0; }
        else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
    }
    if (i >= argc) { usage(); return 2; }
    utd_set_log(log_line, NULL);
    const char *cmd = argv[i++];
    utd_dev *d = NULL;

    if (!strcmp(cmd, "keys")) {
        for (int k = 0; k < 0x20; k++) if (utd_key_name(k)) printf("  %-11s (code 0x%02X)\n", utd_key_name(k), k);
        return 0;
    }
    if (!strcmp(cmd, "info")) {
        int n = utd_count_devices();
        printf("Oscilloscopes found: %d\n", n < 0 ? 0 : n);
        if (n <= 0) { fprintf(stderr, "%s\n", utd_strerror(UTD_ERR_NODEV)); return 1; }
        if (!open_or_die(&d)) return 1;
        char desc[256]; utd_describe(d, desc, sizeof desc);
        printf("%s\n", desc);
        utd_wave *w = calloc(1, sizeof *w);
        int r = utd_capture_wave(d, one_ch ? UTD_MODEL_1CH : UTD_MODEL_2CH, w);
        if (r) printf("Waveform test: %s\n", utd_strerror(r));
        else {
            printf("Waveform test: OK, %d bytes, %d channel block(s)\n", w->bytes, w->channels);
            for (int k = 0; k < w->channels; k++)
                printf("  CH%d: %s, volts index %d, %d samples\n", k + 1, w->ch[k].enabled ? "on" : "off",
                       w->ch[k].volts_index, w->ch[k].count);
        }
        free(w);
        utd_close(d);
        return r ? 1 : 0;
    }
    if (!strcmp(cmd, "screen")) {
        char name[256];
        if (i < argc) snprintf(name, sizeof name, "%s", argv[i]); else stamp(name, sizeof name, "scope", "png");
        if (!open_or_die(&d)) return 1;
        static uint8_t rgb[UTD_SCREEN_W * UTD_SCREEN_H * 3];
        int r = utd_capture_screen(d, rgb, !rgb_pal);
        utd_close(d);
        if (r) { fprintf(stderr, "error: %s\n", utd_strerror(r)); return 1; }
        if (utd_write_png(name, rgb, UTD_SCREEN_W, UTD_SCREEN_H)) { fprintf(stderr, "error: cannot write %s\n", name); return 1; }
        printf("Saved %s\n", name);
        return 0;
    }
    if (!strcmp(cmd, "wave")) {
        char name[256];
        if (i < argc) snprintf(name, sizeof name, "%s", argv[i]); else stamp(name, sizeof name, "wave", "csv");
        if (!open_or_die(&d)) return 1;
        utd_wave *w = calloc(1, sizeof *w);
        int r = utd_capture_wave(d, one_ch ? UTD_MODEL_1CH : UTD_MODEL_2CH, w);
        utd_close(d);
        if (r) { fprintf(stderr, "error: %s\n", utd_strerror(r)); free(w); return 1; }
        if (utd_write_wave_csv(name, w)) { fprintf(stderr, "error: cannot write %s\n", name); free(w); return 1; }
        printf("Saved %s (%d channel block(s))\n", name, w->channels);
        free(w);
        return 0;
    }
    if (!strcmp(cmd, "key")) {
        if (i >= argc) { fprintf(stderr, "key: name a key (see 'scopelink keys')\n"); return 2; }
        for (int j = i; j < argc; j++)
            if (utd_key_from_name(argv[j]) < 0) { fprintf(stderr, "unknown key '%s' (see 'scopelink keys')\n", argv[j]); return 2; }
        if (!open_or_die(&d)) return 1;
        int rc = 0;
        for (; i < argc; i++) {
            int k = utd_key_from_name(argv[i]);
            int r = utd_press_key(d, k);
            printf("%s: %s\n", utd_key_name(k) ? utd_key_name(k) : argv[i], r ? utd_strerror(r) : "sent");
            if (r) { rc = 1; break; }
            usleep(150000);
        }
        utd_close(d);
        return rc;
    }
    if (!strcmp(cmd, "watch")) {
        const char *dir = i < argc ? argv[i++] : ".";
        double secs = i < argc ? atof(argv[i]) : 1.0;
        if (secs < 0.1) secs = 0.1;
        if (!open_or_die(&d)) return 1;
        static uint8_t rgb[UTD_SCREEN_W * UTD_SCREEN_H * 3];
        printf("Saving a screenshot every %.1f s to %s (Ctrl-C to stop)\n", secs, dir);
        for (;;) {
            int r = utd_capture_screen(d, rgb, !rgb_pal);
            if (r) { fprintf(stderr, "error: %s\n", utd_strerror(r)); break; }
            char name[200], path[512];
            stamp(name, sizeof name, "scope", "png");
            snprintf(path, sizeof path, "%s/%s", dir, name);
            if (utd_write_png(path, rgb, UTD_SCREEN_W, UTD_SCREEN_H)) { fprintf(stderr, "cannot write %s\n", path); break; }
            printf("%s\n", path); fflush(stdout);
            usleep((useconds_t)(secs * 1e6));
        }
        utd_close(d);
        return 1;
    }
    if (!strcmp(cmd, "raw")) {
        if (argc - i < 2) { fprintf(stderr, "raw <group> <code> [param] [readlen]\n"); return 2; }
        unsigned g = (unsigned)strtoul(argv[i], NULL, 16), c = (unsigned)strtoul(argv[i + 1], NULL, 16);
        uint32_t p = argc - i > 2 ? (uint32_t)strtoul(argv[i + 2], NULL, 16) : 0;
        int rl = argc - i > 3 ? atoi(argv[i + 3]) : 64;
        if (g == UTD_GROUP_UPGRADE) { fprintf(stderr, "refusing: group 02 is the firmware upgrade\n"); return 2; }
        if (!open_or_die(&d)) return 1;
        int r = utd_send_command(d, (uint8_t)g, (uint8_t)c, p);
        if (r) { fprintf(stderr, "error: %s\n", utd_strerror(r)); utd_close(d); return 1; }
        printf("sent 55 AA %02X %02X %08X\n", g, c, p);
        if (rl > 0) {
            uint8_t *b = calloc((size_t)rl, 1);
            int n = utd_read(d, b, rl);
            if (n < 0) printf("no reply: %s\n", utd_strerror(n)); else { printf("reply: %d bytes\n", n); hexdump(b, n); }
            free(b);
        }
        utd_close(d);
        return 0;
    }
    fprintf(stderr, "unknown command '%s'\n\n", cmd);
    usage();
    return 2;
}
