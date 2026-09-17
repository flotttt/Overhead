# SonyBridge

**Control your Sony headphones from your Mac's menu bar and notch, without the phone app.**

SonyBridge is a native macOS app for Sony Bluetooth headphones: noise cancelling, ambient sound, equalizer,
battery and more, from a menu bar menu, plus a notch panel that shows the music playing in Spotify and your
headphones' sound mode.

It talks to the headphones directly over Bluetooth, so you don't need Sony's *Sound Connect* phone app.

[Features](#features) · [The notch](#the-notch) · [Install](#install) · [Supported headphones](#supported-headphones) · [Build from source](#build-from-source) · [How it works](#how-it-works) · [Troubleshooting](#troubleshooting)

---

## Features

### In the menu bar

- **Sound modes:** Noise Cancelling, Ambient Sound (level slider and Focus on Voice) and Off. The menu follows
  the headphones' own NC button live.
- **Equalizer:** presets and a Manual mode with one slider per band (5 bands + Clear Bass on older models).
  On the WH-1000XM6 the 10-band equalizer is shown but read-only for now.
- **Other settings**, only when your model has them: DSEE, Speak-to-Chat, Adaptive Volume, Auto Power-Off.
- **Battery:** live percentage, per earbud and case on true-wireless models.
- **About the Headphones:** firmware, codec, protocol version and Bluetooth address.
- **Connection:** connects automatically at launch and when the headphones join the Mac, reconnects if the
  link drops, and can launch at login.
- **Languages:** English and French, following your macOS language.

The menu bar icon shows the current sound mode and dims while disconnected.

### The notch

Hover the notch at the top of a MacBook screen and it unfolds into a small player. On a screen without a
notch, the same panel sits in a black pill at the top centre.

**Closed**, the notch shows what's going on at a glance:

- the album artwork on the left;
- on the right, small bars in the artwork's colour that move while music plays. Hover them for a
  **next track** button, or a **play** button when the music is paused;
- without music, a headphones icon on the left and the current sound mode on the right.

**Open**, it's a music player for the **Spotify** desktop app:

- artwork, title and artist;
- elapsed time, a progress bar you can click or drag to seek, and the track length;
- previous, play/pause, next and shuffle;
- a volume button that swaps the progress bar for Spotify's volume for a few seconds;
- a headphones button that slides to the **headphones page**: Noise Cancelling / Ambient / Off, ambient
  level and Focus on Voice.

It opens and closes with a spring animation and never takes the keyboard from the app you're using.

**Make it yours** under **SonyBridge Options › Notch Size**: open width and height, closed width, artwork
size on the closed notch, and text size. Changes apply live and are remembered; the layout adapts so
nothing overlaps (the artwork grows with the height, text size is capped to what fits). **Show Notch**
turns the whole thing off.

Spotify is controlled locally through macOS automation. No Spotify account or login is involved, and
SonyBridge never opens Spotify by itself.

## Install

You need **macOS 13 or later** and Apple's **Command Line Tools** (the full Xcode app isn't needed):

```sh
xcode-select --install
```

Then build and install:

```sh
git clone https://github.com/flotttt/SonyBridge.git
cd SonyBridge
make install
```

`make install` builds a release version, quits SonyBridge if it's running, and copies it to
`/Applications/SonyBridge.app`. Open it from Spotlight, Launchpad or Finder.

On first launch:

1. Pair and connect your headphones in **System Settings › Bluetooth**.
2. Allow **Bluetooth** access when macOS asks, or SonyBridge can't reach the headphones.
3. With Spotify open, allow SonyBridge to **control Spotify** when macOS asks, for the notch player.

**Update:** `git pull`, then `make install` again.

**Uninstall:** turn off **Launch at Login** if you enabled it, quit SonyBridge, and move
`/Applications/SonyBridge.app` to the Trash.

## Supported headphones

| Status | Models |
|---|---|
| Tested on real hardware | WH-1000XM6, WH-CH720N, Sony ULT WEAR (WH-ULT900N) |
| Expected to work (same protocol) | WH-1000XM5, WH-XB910N, WH-CH520 |
| Earbuds: controls work, battery format differs | WF-1000XM4, WF-1000XM5, WF-C700N, LinkBuds S |
| Older protocol: sound modes only | WH-1000XM4, WH-1000XM3, WH-1000XM2, WH-XB900N, MDR-XB950BT |

Only the first row has been tested. If you try another model, an issue telling how it went is very welcome.

## Build from source

```sh
make              # debug build → build/SonyBridge.app
make run          # build and launch (add DEBUG=1 to log every Bluetooth frame)
make test         # unit tests + translation check
make release      # universal build (Apple Silicon + Intel), zipped to build/SonyBridge.zip
make install      # release build installed to /Applications
make clean        # remove build/
```

The log goes to `~/Library/Logs/SonyBridge/app.log` (`build/app.log` links to it).

Always start the app through `open`, Finder or the `make` targets. Running
`Contents/MacOS/SonyBridge` directly makes macOS's privacy protection close it on its first Bluetooth access.

The app is Swift (AppKit + SwiftUI) on top of a C++ protocol core. The code is in `Client/`: `Client/macos`
holds the app, and the notch lives in `Client/macos/Notch` and `Client/macos/Music`.

## How it works

Sony headphones expose a vendor Bluetooth serial (RFCOMM) service. Every command is a small binary frame:

```
<START 0x3e> ESCAPE( <TYPE> <SEQ> <4-byte big-endian length> <PAYLOAD> <checksum> ) <END 0x3c>
```

There are two generations of this protocol, told apart by their service UUID:

- **v1** (`96CC203E-…`): WH-1000XM4 and older;
- **v2** (`956C7B26-…`): WH-1000XM5/XM6, WH-CH720N, ULT WEAR, WF series, LinkBuds.

SonyBridge looks for v1 first and falls back to v2. The v2 path adds the start-up handshake and the
acknowledgement every frame needs, plus the battery, equalizer and DSEE commands. Byte layouts were
cross-checked against [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge)'s Sony support.

The notch reads Spotify through the notification the Spotify app posts on every playback change and
through AppleScript for artwork, volume and shuffle. Nothing is polled while the notch is closed.

## Troubleshooting

- **SonyBridge doesn't find the headphones:** connect them in macOS Bluetooth settings first, then choose
  **Connect…** in the menu.
- **Nothing happens, no Bluetooth prompt:** check System Settings › Privacy & Security › Bluetooth.
- **The notch shows "SonyBridge isn't allowed to control Spotify":** click **Open Settings** and enable
  Spotify under Automation › SonyBridge.
- **The menu bar icon is missing:** on notched MacBooks a crowded menu bar hides icons; quit or hide a few.
- **Controls stopped responding:** **Disconnect** then **Connect…**, or turn the headphones off and on.
- **The app closes right after opening:** launch it through Finder, Spotlight or `make run`, not the binary.

## Origins

SonyBridge started as a fork of [AmitRajput-Dev/SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge),
itself based on [SonyHeadphonesClient](https://github.com/Plutoberth/SonyHeadphonesClient) (Plutoberth,
semvis123's macOS port and contributors). It has since been reworked into its own app: menu bar interface,
v2 protocol support, automatic connection, the notch and Spotify player.

## Disclaimer

Not affiliated with, endorsed by or connected to Sony. SonyBridge uses a reverse-engineered protocol for
interoperability; use it at your own risk.

## License

[MIT](LICENSE). The original copyright notice is kept as the license requires.
