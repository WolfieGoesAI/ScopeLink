# ScopeLink

A native Mac app for UNI-T UTD1000-series handheld oscilloscopes (UTD1052DL, UTD1000CL and
relatives that show up on USB as `5345:1234`). It replaces UNI-T's Windows-only
"Digital Storage Oscilloscope" software. No drivers, no Homebrew: libusb is built into the app.

- Runs on macOS 10.14.4 (Mojave) or newer, Intel and Apple silicon (one universal app)
- **Live view** of the scope's 320×240 screen
- **Front panel**: every key the Windows app has (Run/Stop, Auto, Single, CH1, Math, Measure,
  Acquire, Display, Trigger, Horizontal, Record, DSO/DMM, Shift, Select, OK, arrows, F1–F4,
  Volts/div and Time/div rockers)
- **Save Screenshot…** as PNG
- **Waveform…**: captures the sample data, plots it and saves it as CSV (raw 8-bit codes plus the
  channel settings the scope reports; conversion to volts is not decoded yet)
- Log window (Window ▸ Log, ⇧⌘L) showing every USB step
- Includes `scopelink`, a command-line tool for the same functions

Firmware upgrade is deliberately left out: if it is interrupted, the scope can be left unusable.

## Getting the app

Every push to `main` is built by GitHub Actions and published on the **Releases** page as
`ScopeLink-mac.zip`. Unzip it, move `ScopeLink.app` to Applications, and the first time
**right-click → Open** (the app is not signed with an Apple developer certificate).

## Using it

1. Connect the scope with its USB cable and switch it on.
2. Start ScopeLink. It connects by itself; the status line shows the scope it found.
3. Tick **Live view** for a running picture, or click any key and the screen updates once.
4. Pick your model in the menu at the top (2-channel UTD1052DL or 1-channel UTD1000CL);
   it sets the size of the waveform request.
5. If the colours look wrong (red and blue swapped), use View ▸ Swap Red/Blue Colours.

## Command-line tool

```
scopelink info                 find the scope, test a waveform read
scopelink screen shot.png      screenshot
scopelink wave wave.csv        waveform samples
scopelink key auto             press keys: run, auto, single, f1..f4, ok, up/down/left/right, ...
scopelink keys                 list key names
scopelink watch ~/Desktop 2    screenshot every 2 seconds
scopelink raw 03 e0            send any command and hex-dump the reply (for exploring)
```

Options: `-v` USB details, `--1ch` single-channel model, `--rgb` alternative colour order.
Inside the app bundle it is at `ScopeLink.app/Contents/MacOS/scopelink`; the zip also has a copy.

## Protocol

Worked out from UNI-T's Windows software (LabWindows/CVI app using libusb-win32):

| | |
|---|---|
| USB | VID `5345` PID `1234`, configuration 1, interface 0, bulk OUT `0x03`, bulk IN `0x81`, 5 s timeout |
| Command | 64 bytes: `55 AA <group> <code> <u32 param LE>` then zeros |
| Keys | group `00`, code = key (see `core/utd.h`) |
| Screen | `01 F1 00030DC0` → 128-byte header (`55 AA` at 0x40, byte count at 0x42, palette at 0x44) + RLE data: 2-byte tokens, 5-bit colour index + 11-bit run, filled column by column |
| Waveform | `01 F2 00005E40` (2 ch) / `00002F00` (1 ch) → header 0x58 bytes, then per channel at `0x58 + k·0x2EF4`: on/off, volts index, position, …, samples per column at +0x10, 300 columns of samples at +0x14 |
| Stored files | group `03` codes `E0`/`E1`/`E2`, groups `05`/`06` (not used yet) |
| Upgrade | group `02` codes `F5`/`F6`/`F7` (not implemented) |

## Building by hand

On a Mac with the Xcode command-line tools: `bash scripts/build.sh` → `dist/ScopeLink-mac.zip`.
