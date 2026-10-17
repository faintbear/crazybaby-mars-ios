<p align="right">English | <a href="README.zh-CN.md">简体中文</a></p>

# Mars Control for iOS

<img src="MarsControl/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Unofficial Mars Control app icon">

Put Mars back in your hands.

An unofficial, open-source iOS controller for the Mars by crazybaby levitating Bluetooth speaker. Built with SwiftUI and CoreBluetooth, it controls the speaker locally over Bluetooth, without an account or cloud service. This is an independently rebuilt compatible app, not the original official iOS app source code.

![Mars levitating Bluetooth speaker](docs/images/mars-speaker.png)

## About Mars

Mars combines a UFO-shaped, levitating full-range speaker with a cylindrical subwoofer base, Bluetooth audio, and a ring of lights. The floating speaker can also play music away from its base and returns to the base for charging. For a closer look at the product, read Paul Teich’s article for TIRIAS Research: [Mars By Crazybaby Is Bluetooth Audio Magnetism](https://medium.com/@TIRIAS_Research/mars-by-crazybaby-is-bluetooth-audio-magnetism-467e7ad891e).

When the original control app is no longer available, this project offers an iPhone controller you can build, maintain, and improve yourself.

## Features and verification

Verification was performed with one Mars speaker and one iPhone. It does not cover every hardware or firmware version.

| Feature | Current support | Verification completed |
| --- | --- | --- |
| Bluetooth connection | Scan, connect, disconnect, and remember a device | Established a BLE control connection on iPhone and received device responses |
| Device status | Read levitation, light mode, brightness, volume, and EQ | Received actual status values from the speaker |
| Levitation control | Raise and lower using buttons or vertical dragging | Physically observed the speaker lowering and rising again |
| Light modes | Four mode selections (0–3) | Switched modes, read back values, and observed visual changes; individual effects have not all been named |
| Light brightness | Levels 0–15 with a percentage display | Read back settings and observed the lowest brightness and brightness changes |
| Volume control | Range 0–16 and current-level readout | Wrote and read back a low volume setting; confirmed the restored value after reconnecting. Loudness has not been measured at every level |
| EQ presets | Five preset selections (0–4) | Switched 2 → 0 → 2 and confirmed status readback; not every preset has been individually auditioned |
| Device name | Up to 17 UTF-8 bytes, with manual verification after restarting | Successfully changed the name and received user confirmation after a restart; automatic name readback can be truncated |

The dark interface includes a device list, feature pages, connection status, operation feedback, and playback help. Settings are disabled while disconnected or while an operation is in progress. Timed-out settings are not automatically resent.

Physical verification above concerns the control capabilities. Interface interactions such as dragging have not all undergone automated testing. Editing custom EQ bands is not implemented.

## Usage

1. Turn on the Mars floating speaker. To raise or lower it, power on the base and position the speaker correctly.
2. Open the device page in the app, grant Bluetooth permission, and wait for the connection.
3. Choose levitation, lighting, sound, or device-name settings.
4. For music playback, connect Mars in the iPhone’s system Bluetooth settings and use your preferred music app. The audio connection and this app’s BLE control connection work separately.

After renaming, restart the floating speaker, verify its name in system Bluetooth settings, and confirm it in the app. Its BLE advertising name may remain unchanged.

## Build

You need Xcode with support for iOS 17 or later, an iPhone, and Apple development signing. Bluetooth hardware features require a physical device.

```sh
git clone https://github.com/faintbear/crazybaby-mars-ios.git
cd crazybaby-mars-ios
cp Local.xcconfig.example Local.xcconfig
open MarsControl.xcodeproj
```

Set your own `DEVELOPMENT_TEAM` and a unique `MARS_BUNDLE_ID` in `Local.xcconfig`, select your iPhone in Xcode, and run. You can also select your personal team under Signing & Capabilities in Xcode. Personal signing validity and installation limits are determined by Apple.

The Xcode project is included, and there are no third-party runtime dependencies. If you change the project structure, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate --spec project.yml
```

## Scope

The app focuses on the main controls for a single Mars speaker. Firmware updates, automatic volume, Double Up pairing, Multipoint management, and a built-in music player are not provided.

While preparing this project, searches using Crazybaby, Mars, Swift, and Objective-C did not uncover a ready-to-use open-source Mars iOS controller. This is not an exhaustive claim about all public or historical projects.

## License and credits

The project code is available under the [MIT License](LICENSE). Crazybaby and Mars names and trademarks belong to their respective owners. This project is not affiliated with the manufacturer.

The product photograph was supplied by the project initiator to illustrate the speaker. Image rights remain with the original rights holder and are excluded from the code’s MIT license. The product background article is credited through the TIRIAS Research link above.

The app icon is an independently drawn community version: a mint open ring and a floating dot evoke the speaker, while the UNOFFICIAL label distinguishes it from the official app.
