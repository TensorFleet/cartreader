# OSCR Companion (Android)

An Android app for the [Open Source Cartridge Reader](https://github.com/sanni/cartreader).
Plug the reader into your phone or tablet with a USB OTG cable, control it from a
touch-friendly serial console, and save everything it sends into your Downloads folder.

## Features

- Talks to the reader over USB OTG using the CH340/CH341 chip found on the OSCR
  (CH9102, CP2102, FTDI and genuine Arduino Mega 2560 are also recognized).
- Serial console with send box — drive the firmware's `SERIAL_MONITOR` menu
  (enter menu numbers, starting letters, etc.). Sends are passed through
  byte-for-byte with no newline appended, matching the firmware's single-byte reads.
- Menus the reader prints (`0)Game Boy`, `1)NES/Famicom`, …) are parsed live and shown
  as tappable buttons, including page up/down and A–Z buttons for letter prompts.
- Built-in **Guide** button with a step-by-step "how to dump a cartridge" walkthrough.
- Selectable baud rate; defaults to 9600, which is what the firmware's
  `SERIAL_MONITOR` mode uses.
- **Capture**: records every byte the reader sends into
  `Downloads/CartReader/oscr_capture_<timestamp>.log` on the phone.
- Opening the port toggles DTR, so the reader resets and prints its menu on connect.

## Using it with the reader

1. Build the firmware with `SERIAL_MONITOR` enabled in `Cart_Reader/Config.h`
   (comment out the `HW#` define, uncomment `SERIAL_MONITOR`). This replaces the
   OLED/LCD interface with a text menu on the USB serial port.
2. Connect the reader to your Android device with a USB OTG adapter.
3. Open the app (it also offers to open automatically when the reader is attached),
   tap **Connect**, and the reader's menu appears in the console.
4. Tap the menu buttons that appear above the text box to navigate (or type the
   number and tap **Send**).
5. Tap **Capture** before starting an operation to record the reader's output to a
   file in `Downloads/CartReader/`.

Note: with the stock firmware, cartridge dumps are written to the reader's **SD card**;
the serial port carries the user interface, progress and log output, which the app can
capture. The stock firmware has no file-transfer protocol for pulling dump files off
the SD card over serial — take out the SD card (or use a USB card reader on the phone)
to copy the ROM files themselves.

## Building

```sh
cd android-app
base64 -d ci-keystore.jks.base64 > ci-keystore.jks   # optional, to sign like CI
gradle assembleRelease
```

Requires JDK 17+, Gradle 8.9+ and the Android SDK (compileSdk 35). The APK is
written to `app/build/outputs/apk/release/`. If you prefer a Gradle wrapper, run
`gradle wrapper --gradle-version 8.10.2` once to generate it locally. Without the
decoded keystore the release APK is built unsigned.

CI builds run in [`.github/workflows/android.yml`](../.github/workflows/android.yml):
every push to `master` that touches `android-app/` (and every manual run of the
workflow) builds the APK and publishes it as a GitHub release tagged `android-v1.0.<n>`.

The release APK is signed with a CI keystore committed to the repo in base64 form
(`ci-keystore.jks.base64`) with a well-known password (`cartreader`). That makes CI builds installable and lets them
update each other, but provides **no authenticity guarantee** — anyone can sign with
this key. Build and sign with your own key if that matters to you.

## Requirements

- Android 8.0 (API 26) or newer
- USB host (OTG) support on the device
