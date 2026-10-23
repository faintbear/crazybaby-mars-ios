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
| EQ presets | CrazyEQ, Bass, Indoors, Outdoors; legacy preset 4 | Switched 2 → 0 → 2 and confirmed status readback; not every preset has been individually auditioned |
| Device name | Up to 17 UTF-8 bytes, with manual verification after restarting | Successfully changed the name and received user confirmation after a restart; automatic name readback can be truncated |

The dark interface includes a device list, feature pages, connection status, operation feedback, and playback help. Settings are disabled while disconnected or while an operation is in progress. Timed-out settings are not automatically resent.

Physical verification above concerns the control capabilities. Interface interactions such as dragging have not all undergone automated testing. Editing custom EQ bands is not implemented.

## Auto Volume (1.0.0)

Uses the Android 2.1.0 formula, integer smoothing, and polling cadence: roughly one signal sample every two seconds, with a target calculation after three samples. The original signal query returns zero on the tested speaker’s BLE path, so the default input is now iPhone CoreBluetooth RSSI, which has been physically observed to vary between near/far positions. The alternative “音箱原厂” input is retained for compatible firmware. Different measurement sources do not establish identical behavior to the original app.

1. Open “自动音量”, leave the source as “iPhone BLE”, and start read-only detection.
2. After three valid samples and a valid nonzero speaker volume response, choose an upper volume limit and explicitly enable Auto Volume.
3. The algorithm’s target is applied directly, capped by your limit (default 8/15). It can move several levels in one adjustment. There is no new distance-bin or comfortable-volume-baseline algorithm. It never unmutes the speaker.

Manual device controls, disconnects, timeouts, invalid responses, mismatched setting readbacks, and leaving the foreground stop the feature. It never resumes automatically. An already-sent command may still complete. The separate “BLE 信号测试” page remains read-only and cannot enable automatic volume.

The user-selected volume ceiling is saved between sessions. The recurrence and control framing pass local tests. iPhone BLE signal reception and speaker volume commands have been verified separately; a physical test confirmed that enabling automatic volume lowered the speaker volume. Continuous near/far adjustment still needs physical evaluation. Keep the app in the foreground, test at a low listening level, and choose a suitable ceiling. Phone position is only a proxy for listener position, and constant perceived loudness is not guaranteed.

The Android 3.0.11 Java paths inspected retain the Auto Volume page and request enum, but the full loop was found in Android 2.1.0. Firmware updates are not involved.

### Signal diagnostics in 0.5.1

The app distinguishes received responses from valid samples. A response of `00 00` is shown as a reported value of 0 and keeps automatic volume disabled; it is not a payload-length error. “信号检测详情” shows the latest payload and allows manual export of up to 12 recent signal responses, stored locally without device names or identifiers. Nothing is uploaded automatically. Whether zero depends on the audio connection or the BLE control path is still under investigation.

### Read-only iPhone BLE signal test in 0.5.2

“BLE 信号测试” uses iPhone CoreBluetooth RSSI, separately from the original speaker-returned `0x17` signal. It never feeds either the volume algorithm or the automatic-volume enable condition. Starting this test stops automatic volume.

Keep the app in the foreground, start a new test, and label approximately ten seconds each as Near, Far, and Pocket. The screen shows the raw value, a rolling five-point median, a recent-signal curve, and raw-sample summaries for each label. Body occlusion and walls can change the signal; values are not distances in meters.

Sampling is roughly once per second, with one outstanding read at a time. A timeout stops the test and requires reconnecting before a new attempt. Disconnecting or leaving the foreground also stops sampling. Up to 180 recent samples stay in memory and a local report without device identifiers; export is manual, with no automatic upload. Starting a new test clears the previous session.

## New in 0.4.0: experimental controls

Rebuilt from the Android 3.0.11 control behavior. These additions have passed local protocol checks and compilation, but have not yet been verified on a physical Mars speaker:

- Device information: read the two-byte MCU version; no firmware updates.
- Prompt sounds: separate power and levitation sound switches. Changing one preserves the other setting. A valid current response and MCU revision greater than 25 are required before writing.
- Standby: explicit standby/wake commands with a confirmation before standby. This is not an automatic sleep timer. Standby can disconnect Bluetooth; waking through the app is only possible if the control connection remains available. Otherwise, use the speaker’s power button.
- Connection lists: read currently connected and historical device names, up to 16 entries per list. No disconnect, removal, or audio-source switching commands are sent.
- Named EQ presets: CrazyEQ (0), Bass (1), Indoors (2), Outdoors (3). Preset 4 remains a legacy option, not a custom band editor.

Open “提示音与待机” or “连接设备” and press the read button first. Unsupported or missing responses leave advanced settings unavailable. Controls use the Android version condition as a compatibility guard, not as proof of hardware support. Connection-list refresh clears old entries; incomplete results are shown with their returned total and any read error.

RGB color controls, Wi-Fi grouping, and power-saving controls for other speaker models are not included.

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

The app focuses on the main controls for a single Mars speaker. Firmware updates, Double Up pairing, Multipoint connection management, and a built-in music player are not provided. Connection information is read-only; Proximity Volume is experimental.

While preparing this project, searches using Crazybaby, Mars, Swift, and Objective-C did not uncover a ready-to-use open-source Mars iOS controller. This is not an exhaustive claim about all public or historical projects.

## License and credits

The project code is available under the [MIT License](LICENSE). Crazybaby and Mars names and trademarks belong to their respective owners. This project is not affiliated with the manufacturer.

The product photograph was supplied by the project initiator to illustrate the speaker. Image rights remain with the original rights holder and are excluded from the code’s MIT license. The product background article is credited through the TIRIAS Research link above.

The app icon is an independently drawn community version: a mint open ring and a floating dot evoke the speaker, while the UNOFFICIAL label distinguishes it from the official app.
