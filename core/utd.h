/*
 * ScopeLink core: USB protocol for UNI-T UTD1000-series handheld oscilloscopes
 * (UTD1052DL, UTD1000CL ...), reverse-engineered from UNI-T's Windows software
 * (UTD1052DL.exe / UTD1000CL(EN).exe, LabWindows/CVI + libusb-win32).
 *
 * Transport: USB VID 0x5345 PID 0x1234, configuration 1, interface 0,
 *            bulk OUT 0x03, bulk IN 0x81, 5 s timeout.
 * Command:   64-byte packet  55 AA <group> <code> <u32 param, little endian> 00...
 */
#ifndef UTD_H
#define UTD_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UTD_VID 0x5345
#define UTD_PID 0x1234
#define UTD_EP_OUT 0x03
#define UTD_EP_IN 0x81
#define UTD_TIMEOUT_MS 5000

#define UTD_SCREEN_W 320
#define UTD_SCREEN_H 240

/* Command groups and codes */
enum {
    UTD_GROUP_KEY = 0x00,      /* front-panel key press, code = key */
    UTD_GROUP_CAPTURE = 0x01,  /* F1 screen, F2 waveform */
    UTD_GROUP_UPGRADE = 0x02,  /* F5/F6/F7 firmware upgrade (not implemented on purpose) */
    UTD_GROUP_STORED = 0x03,   /* E0/E1/E2: stored bitmap / wave / recorded wave on the DSO */
};

/* Front-panel key codes (group 0x00) */
typedef enum {
    UTD_KEY_HORIZONTAL = 0x00,
    UTD_KEY_SHIFT = 0x01,
    UTD_KEY_MEASURE = 0x02,
    UTD_KEY_CH1 = 0x06,
    UTD_KEY_SELECT = 0x07,
    UTD_KEY_VOLTS_V = 0x08,    /* Volts/div rocker, "V" side  */
    UTD_KEY_VOLTS_MV = 0x09,   /* Volts/div rocker, "mV" side */
    UTD_KEY_TIME_S = 0x0A,     /* Time/div rocker, "s" side   */
    UTD_KEY_TIME_NS = 0x0B,    /* Time/div rocker, "ns" side  */
    UTD_KEY_RUN_STOP = 0x0C,
    UTD_KEY_DISPLAY = 0x0D,
    UTD_KEY_MATH = 0x0E,
    UTD_KEY_RECORD = 0x0F,
    UTD_KEY_SINGLE = 0x10,
    UTD_KEY_TRIGGER = 0x11,
    UTD_KEY_UP = 0x12,
    UTD_KEY_DOWN = 0x13,
    UTD_KEY_LEFT = 0x14,
    UTD_KEY_RIGHT = 0x15,
    UTD_KEY_OK = 0x16,
    UTD_KEY_AUTO = 0x17,
    UTD_KEY_F1 = 0x18,
    UTD_KEY_F2 = 0x19,
    UTD_KEY_F3 = 0x1A,
    UTD_KEY_F4 = 0x1B,
    UTD_KEY_DSO_DMM = 0x1C,
    UTD_KEY_ACQUIRE = 0x1D,
} utd_key_t;

typedef enum {
    UTD_MODEL_2CH = 0,  /* UTD1052DL and other 2-channel models: wave reply 0x5E40 bytes */
    UTD_MODEL_1CH = 1,  /* UTD1000CL single-channel models:     wave reply 0x2F00 bytes */
} utd_model_t;

#define UTD_SCREEN_PARAM 0x30DC0u
#define UTD_WAVE_PARAM_2CH 0x5E40u
#define UTD_WAVE_PARAM_1CH 0x2F00u
#define UTD_WAVE_MAX 0x5E80u

/* Errors (negative); 0 = OK */
enum {
    UTD_OK = 0,
    UTD_ERR_NODEV = -1,
    UTD_ERR_OPEN = -2,
    UTD_ERR_CONFIG = -3,
    UTD_ERR_CLAIM = -4,
    UTD_ERR_WRITE = -5,
    UTD_ERR_READ = -6,
    UTD_ERR_SYNC = -7,       /* reply has no 55 AA marker */
    UTD_ERR_ARG = -8,
    UTD_ERR_INIT = -9,
};

typedef struct utd_dev utd_dev;

const char *utd_strerror(int err);
const char *utd_key_name(int code);   /* NULL if unknown */
int utd_key_from_name(const char *name); /* -1 if unknown; case-insensitive, e.g. "run", "f1", "auto" */

/* Logging hook (optional): receives one line of text without trailing newline. */
typedef void (*utd_log_fn)(void *ctx, const char *line);
void utd_set_log(utd_log_fn fn, void *ctx);

/* Count matching devices currently attached (no open). <0 on error. */
int utd_count_devices(void);

int utd_open(utd_dev **out);
void utd_close(utd_dev *dev);
/* USB bus/address and product strings of the open device (may be empty). */
void utd_describe(utd_dev *dev, char *buf, size_t len);

/* Low level */
int utd_send_command(utd_dev *dev, uint8_t group, uint8_t code, uint32_t param);
/* Reads up to len bytes; returns bytes read (>=0) or error. A timeout after some data
 * counts as success with the bytes received. */
int utd_read(utd_dev *dev, uint8_t *buf, int len);

int utd_press_key(utd_dev *dev, int key);

/*
 * Screen capture. Fills rgb (UTD_SCREEN_W*UTD_SCREEN_H*3 bytes, row-major, top row first,
 * R,G,B order). The scope sends a 5-bit indexed, run-length encoded image with its palette.
 * palette_bgr != 0 treats palette entries as B,G,R (what the Windows app's 24-bit bitmap
 * expects); 0 treats them as R,G,B.
 */
int utd_capture_screen(utd_dev *dev, uint8_t *rgb, int palette_bgr);

/* Decoder used by utd_capture_screen; exposed for tests.
 * header: the 0xC0-byte reply header (palette at 0x44); rle: n bytes of 2-byte tokens. */
void utd_decode_screen(const uint8_t *header, const uint8_t *rle, int n, uint8_t *rgb, int palette_bgr);

/* Waveform capture */
#ifdef UTD_OPAQUE_TYPES
typedef struct utd_wave utd_wave; /* Swift sees an opaque pointer */
#else
typedef struct utd_channel {
    int present;            /* channel block exists in the reply */
    int enabled;            /* channel switched on */
    int volts_index;        /* raw Volts/div setting index from the scope */
    int position;           /* raw vertical position field */
    int inverted;           /* raw invert flag field (the Windows app flips samples when 0) */
    int per_column;         /* samples per screen column (1..40) */
    int count;              /* number of samples in samples[] (300 * per_column) */
    uint8_t samples[12000]; /* raw 8-bit codes as sent by the scope */
    uint16_t raw_header[10];/* the 20-byte channel header as little-endian words */
} utd_channel;

typedef struct utd_wave {
    int bytes;              /* reply size */
    int channels;           /* 1 or 2 */
    uint8_t header[0x58];   /* reply header, raw */
    utd_channel ch[2];
} utd_wave;
#endif

int utd_capture_wave(utd_dev *dev, utd_model_t model, utd_wave *out);
/* Parser used by utd_capture_wave; exposed for tests. */
int utd_parse_wave(const uint8_t *buf, int len, utd_wave *out);

/* Heap-allocated wave + accessors (for Swift, which imports large C arrays awkwardly) */
utd_wave *utd_wave_new(void);
void utd_wave_free(utd_wave *w);
int utd_wave_channels(const utd_wave *w);
int utd_wave_enabled(const utd_wave *w, int ch);
int utd_wave_volts_index(const utd_wave *w, int ch);
int utd_wave_count(const utd_wave *w, int ch);
int utd_wave_per_column(const utd_wave *w, int ch);
const uint8_t *utd_wave_samples(const utd_wave *w, int ch);
int utd_wave_bytes(const utd_wave *w);

/* Small helpers for front ends */
int utd_write_png(const char *path, const uint8_t *rgb, int w, int h);
int utd_write_wave_csv(const char *path, const utd_wave *w);

#ifdef __cplusplus
}
#endif
#endif
