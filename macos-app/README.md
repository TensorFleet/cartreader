# OSCR Companion for macOS

A native SwiftUI companion for the Open Source Cartridge Reader. It mirrors the
Android companion's serial console, parsed menu buttons, exact single-byte commands,
capture logging, and built-in dumping guide.

## Requirements

- macOS 13 or newer
- Xcode 15 or newer
- The matching OSCR serial-transfer firmware with `SERIAL_MONITOR` enabled

The serial-transfer build is based on V15.6. In `Cart_Reader/Config.h`, comment out
the `HW#` define and enable `#define SERIAL_MONITOR` before compiling and flashing.
This custom build uses 115,200 baud for reliable sustained transfers across macOS
and Android USB hosts.

## Run during development

```sh
cd macos-app
swift run OSCRCompanion
```

## Test and package

```sh
cd macos-app
swift test
make app
open "dist/OSCR Companion.app"
```

With an SNES cartridge inserted, the opt-in test below selects SNES Read ROM and
drives a real reader through a complete dump and CRC-verified serial transfer:

```sh
OSCR_LIVE_PORT=/dev/cu.usbserial-10 swift test --filter LiveSerialTransferTests
```

Set `OSCR_LIVE_EXPECTED_CRC` to a known eight-digit hexadecimal CRC for an
additional cartridge-specific assertion.

`make app` creates an ad-hoc-signed app bundle at
`dist/OSCR Companion.app`. A release distributed to other Macs should be signed
with a Developer ID certificate and notarized.

## Device support

The port picker recognizes the macOS serial devices normally created for CH340/CH341,
CH9102, CP2102, FTDI, and Arduino Mega USB interfaces. It opens the selected port as
8 data bits, no parity, one stop bit, raises DTR/RTS, and supports the same baud-rate
choices as the Android app.

ROM and save dumps remain on the OSCR's SD card. Capture records raw serial output to
`~/Downloads/CartReader`; the matching custom firmware can additionally transfer the
completed ROM over serial.

When a ROM read completes, **Download** saves and verifies the completed SD copy
without launching anything. **Download & Play** requests the same copy over
USB using the `OSCRXFER1` size-framed protocol. The Mac writes a temporary `.part`
file, verifies the firmware CRC32 from the transfer header (or the legacy footer),
moves the verified ROM into `~/Downloads/CartReader/ROMs`, and starts the emulator
configured for that system.
Settings provides per-system choices for RetroArch with an explicit compatible core,
the macOS default application, or a chosen `.app`. **Open from SD…** applies the same
configuration to a ROM on removable storage.
