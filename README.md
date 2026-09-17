# SonyNotch

Control your Sony headphones from your Mac, right from the menu bar and the notch. No phone app needed.

SonyNotch is a native macOS app for Sony Bluetooth headphones. It switches noise cancelling and ambient sound,
sets the equalizer and shows the battery from a menu bar menu. It also turns the MacBook notch into a small
player for the music playing in Spotify.

It talks to the headphones directly over Bluetooth, so Sony's Sound Connect app isn't needed.

## Features

### Menu bar

- Noise Cancelling, Ambient Sound and Off, with the ambient level and Focus on Voice
- Follows the NC button on the headphones in real time
- Equalizer presets and a manual mode (read only on the WH-1000XM6 for now)
- DSEE, Speak-to-Chat, Adaptive Volume and Auto Power-Off when your model has them
- Battery level, per earbud and case on true wireless models
- Firmware, codec and Bluetooth address in About the Headphones
- Connects by itself when the headphones join the Mac and reconnects if the link drops
- Optional launch at login
- English and French

The menu bar icon shows the current sound mode and dims when the headphones are disconnected.

### Notch

Move the pointer over the notch and it opens into a player. On a screen without a notch it appears as a black
pill at the top of the screen.

When the notch is closed you see the album artwork on the left and little bars on the right that move with the
music, in the colour of the artwork. Hover the bars to skip to the next track, or to resume the music when
it's paused. Without music, the notch shows your headphones and their current sound mode instead.

When it's open you get:

- the artwork, title and artist
- a progress bar you can click or drag
- previous, play/pause, next and shuffle
- a volume button that shows Spotify's volume for a few seconds
- a headphones button that opens the headphones controls (sound mode, ambient level, Focus on Voice)

You can resize everything in SonyNotch Options › Notch Size: open width and height, closed width, artwork
size and text size. Changes show live on the notch and are saved. Show Notch turns the notch off completely.

The player works with the Spotify desktop app. It uses macOS automation, so no Spotify account or login is
involved, and SonyNotch never opens Spotify on its own.

## Install

You need macOS 13 or later.

1. Download `SonyNotch.zip` from the [latest release](https://github.com/flotttt/SonyNotch/releases/latest).
2. Unzip it and move `SonyNotch.app` to your Applications folder.
3. Open it. The app isn't signed with an Apple developer account yet, so macOS blocks it the first time.
   Go to System Settings › Privacy & Security, scroll down and click Open Anyway.

Then pair your headphones in System Settings › Bluetooth if they aren't already. SonyNotch asks for Bluetooth
access on first launch, and for permission to control Spotify the first time Spotify is open. Allow both.

To update, download the new release and replace the app. To uninstall, turn off Launch at Login if you
enabled it, quit SonyNotch and move it to the Trash.

## Supported headphones

| | Models |
|---|---|
| Tested | WH-1000XM6, WH-CH720N, ULT WEAR (WH-ULT900N) |
| Should work | WH-1000XM5, WH-XB910N, WH-CH520 |
| Earbuds, controls work but battery may not | WF-1000XM4, WF-1000XM5, WF-C700N, LinkBuds S |
| Older protocol, sound modes only | WH-1000XM4, WH-1000XM3, WH-1000XM2, WH-XB900N, MDR-XB950BT |

If you try a model that isn't tested, please open an issue and say how it went.

## Build from source

You need Apple's Command Line Tools. The full Xcode app isn't required.

```sh
xcode-select --install
git clone https://github.com/flotttt/SonyNotch.git
cd SonyNotch
make install
```

`make install` builds the app and copies it to Applications. Other commands:

```sh
make              # debug build in build/SonyNotch.app
make run          # build and launch, add DEBUG=1 to log the Bluetooth traffic
make test         # unit tests and translation check
make release      # universal build zipped in build/SonyNotch.zip
make clean        # delete build/
```

Logs go to `~/Library/Logs/SonyNotch/app.log`. Always launch the app with `open`, Finder or `make`. Running the
binary inside the app bundle directly gets it closed by macOS when it first uses Bluetooth.

The app is written in Swift with AppKit and SwiftUI, on top of a C++ core that handles the headphones
protocol. Everything lives in `Client/`, with the notch in `Client/macos/Notch` and `Client/macos/Music`.

To publish a release, push a version tag. GitHub Actions tests and builds the app and attaches the zip to the
release.

```sh
git tag v1.0.0
git push origin v1.0.0
```

## How it works

Sony headphones expose a Bluetooth serial (RFCOMM) service and accept small binary frames:

```
<0x3e> escaped( type, sequence, 4-byte length, payload, checksum ) <0x3c>
```

There are two versions of this protocol. Older headphones up to the WH-1000XM4 use the first one, newer ones
like the WH-1000XM5 and XM6, the WF series and LinkBuds use the second. SonyNotch detects which one the
headphones speak when it connects. The byte layouts were checked against the Sony support in
[Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge).

For the notch, Spotify announces every playback change with a system notification, and SonyNotch asks the
app for the artwork, volume and shuffle state with AppleScript. Nothing is polled while the notch is closed.

## Troubleshooting

**The headphones aren't found.** Connect them in the macOS Bluetooth settings first, then click Connect in the
menu.

**No Bluetooth prompt appeared.** Check System Settings › Privacy & Security › Bluetooth.

**The notch says SonyNotch isn't allowed to control Spotify.** Click Open Settings and turn on Spotify under
Automation › SonyNotch.

**The menu bar icon is missing.** A crowded menu bar hides icons behind the notch. Quit or hide a few others.

**The controls stopped responding.** Disconnect and connect again from the menu, or turn the headphones off
and on.

## Origins

SonyNotch started as a fork of [AmitRajput-Dev/SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge),
which builds on [SonyHeadphonesClient](https://github.com/Plutoberth/SonyHeadphonesClient) by Plutoberth,
semvis123 and their contributors. It has since been renamed and largely rewritten.

## Disclaimer

SonyNotch isn't affiliated with or endorsed by Sony. It uses a reverse engineered protocol. Use it at your own
risk.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept as the license requires.
