# SonyNotch

Control your Sony headphones from your Mac, right from the menu bar and the notch. No phone app needed.

SonyNotch switches noise cancelling and ambient sound, sets the equalizer and shows the battery of your Sony
Bluetooth headphones. It also turns the MacBook notch into a small player for the music playing in Spotify.

## Install

### With Homebrew

If you use [Homebrew](https://brew.sh), run:

```sh
brew install --cask flotttt/tap/sonynotch
```

That's it. Open SonyNotch from your Applications folder.

### Without Homebrew

1. Download **SonyNotch.zip** from the [latest release](https://github.com/flotttt/SonyNotch/releases/latest)
2. Open the zip and drag **SonyNotch** into your Applications folder
3. Open SonyNotch. The first time, macOS says it can't check the app because it isn't signed with an Apple
   developer account yet. Click Done, then go to System Settings › Privacy & Security, scroll down and click
   **Open Anyway**

### First launch

SonyNotch appears in the menu bar. Allow Bluetooth access when macOS asks, and allow SonyNotch to control
Spotify for the notch player. If your headphones aren't connected to the Mac yet, pair them in System Settings ›
Bluetooth first.

Works on macOS 13 or later, on Apple Silicon and Intel Macs.

## Update

SonyNotch checks once a day for a new version. When one is out, an Update Available item shows up in its menu.

With Homebrew, run `brew upgrade --cask sonynotch`. Without Homebrew, click Update Available to open the
download page, then replace the app in Applications as when you installed it. Your settings are kept, but
macOS may ask for the Bluetooth and Spotify permissions again.

## Uninstall

If you turned on Launch at Login, turn it off first. Then run `brew uninstall --cask sonynotch`, or quit
SonyNotch and move it to the Trash.

## What it does

### Menu bar

Click the headphones icon in the menu bar to:

- switch between Noise Cancelling, Ambient Sound and Off, and set the ambient level and Focus on Voice
- pick an equalizer preset or make your own (read only on the WH-1000XM6 for now)
- turn DSEE, Speak-to-Chat and Adaptive Volume on or off, and set Auto Power-Off, when your model has them
- see the battery level, for each earbud and the case on true wireless models
- see the firmware, codec and Bluetooth address in About the Headphones

The icon shows the current sound mode and follows the NC button on your headphones. SonyNotch connects on its
own when the headphones join the Mac, reconnects if the link drops, and can launch at login. It's available in
English and French.

### Notch

Move the pointer over the notch and it opens into a player with:

- the artwork, title and artist
- a progress bar you can click or drag
- previous, play/pause and next
- a volume button for Spotify's volume
- a headphones button to change the sound mode without opening the menu

When the notch is closed, it shows the album artwork and little bars that move with the music. Hover the bars
to skip to the next track, or to resume the music when it's paused.

To change its size, open the menu and go to SonyNotch Options › Notch Size. You can set the width and height,
the size of the closed notch, the artwork and the text. You see the result live and it's saved. To hide the
notch, turn off Show Notch in the same menu.

The player works with the Spotify app for Mac, without any account or login. On a screen without a notch, it
shows up as a black pill at the top of the screen.

## Supported headphones

| | Models |
|---|---|
| Tested | WH-1000XM6, WH-CH720N, ULT WEAR (WH-ULT900N) |
| Should work | WH-1000XM5, WH-XB910N, WH-CH520 |
| Earbuds, controls work but battery may not | WF-1000XM4, WF-1000XM5, WF-C700N, LinkBuds S |
| Older models, sound modes only | WH-1000XM4, WH-1000XM3, WH-1000XM2, WH-XB900N, MDR-XB950BT |

If you try a model that isn't tested, please [open an issue](https://github.com/flotttt/SonyNotch/issues/new)
and say how it went.

## Troubleshooting

**macOS won't open the app.** Go to System Settings › Privacy & Security and click Open Anyway, as in the
install steps.

**The headphones aren't found.** Connect them in System Settings › Bluetooth, then click Connect in the
SonyNotch menu.

**Nothing happens after opening the app.** Check that SonyNotch is allowed in System Settings › Privacy &
Security › Bluetooth.

**The notch says SonyNotch isn't allowed to control Spotify.** Click Open Settings and turn on Spotify under
Automation › SonyNotch.

**The menu bar icon is missing.** When the menu bar is full, macOS hides icons behind the notch. Quit or hide a
few other menu bar apps.

**The controls stopped responding.** Click Disconnect then Connect in the menu, or turn the headphones off and
on.

## For developers

### Build from source

You need Apple's Command Line Tools (`xcode-select --install`). The full Xcode app isn't required.

```sh
git clone https://github.com/flotttt/SonyNotch.git
cd SonyNotch
make install      # build and install to Applications
make run          # build and launch, add DEBUG=1 to log the Bluetooth traffic
make test         # unit tests and translation check
make release      # universal build zipped in build/SonyNotch.zip
```

Logs go to `~/Library/Logs/SonyNotch/app.log`. Launch the app with `open`, Finder or `make`, not by running the
binary inside the bundle, or macOS closes it when it first uses Bluetooth.

The app is written in Swift with AppKit and SwiftUI, on top of a C++ core for the headphones protocol. The code
is in `Client/`, and the notch is in `Client/macos/Notch` and `Client/macos/Music`.

### Publish a release

Push a version tag. GitHub Actions runs the tests, builds the app with that version number, attaches
SonyNotch.zip to the release and updates the Homebrew cask in
[flotttt/homebrew-tap](https://github.com/flotttt/homebrew-tap).

```sh
git tag v1.1.0
git push origin v1.1.0
```

### How it talks to the headphones

Sony headphones expose a Bluetooth serial (RFCOMM) service and accept small binary frames:

```
<0x3e> escaped( type, sequence, 4-byte length, payload, checksum ) <0x3c>
```

Headphones up to the WH-1000XM4 use a first version of this protocol, newer ones use a second. SonyNotch
detects which one when it connects. The byte layouts were checked against the Sony support in
[Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge).

For the notch, Spotify posts a system notification on every playback change, and SonyNotch asks the app for
the artwork and volume with AppleScript. Nothing is polled while the notch is closed.

## Origins

SonyNotch started as a fork of [AmitRajput-Dev/SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge),
which builds on [SonyHeadphonesClient](https://github.com/Plutoberth/SonyHeadphonesClient) by Plutoberth,
semvis123 and their contributors. It has since been renamed and largely rewritten.

SonyNotch isn't affiliated with or endorsed by Sony. It uses a reverse engineered protocol, so use it at your
own risk.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept as the license requires.
