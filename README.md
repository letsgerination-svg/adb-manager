# ADB Manager

Native SwiftUI iOS app for managing Android devices over a local network.

## Implemented in the current source

- SwiftUI connection screen and ADB command console.
- ADB packet framing and validation.
- Legacy ADB TCP handshake (CNXN).
- Persistent RSA-2048 identity stored in iOS Keychain.
- ADB AUTH token signing (RSA PKCS#1 v1.5 with SHA-1).
- Android-compatible RSA public-key serialization for the authorization prompt.
- Basic ADB shell stream using OPEN / OKAY / WRTE / CLSE, with a 1 MB output cap.
- Shell commands for device properties and package listing.
- Package actions: uninstall for user 0, disable for user 0, and enable.
- APK transfer code using ADB SYNC v1 followed by `pm install -r`.
- Confirmation dialog before package-changing actions.

## Implemented but not yet verified on physical hardware

- End-to-end RSA authorization against a real Android device.
- Shell command execution over a live ADB transport.
- APK transfer and installation using the SYNC v1 implementation.
- Package actions and their device-specific output.
- Reconnection and long-running command behavior.

These features compile and have protocol/helper smoke tests where applicable, but a successful CI build does not prove device interoperability.

## Not implemented

- Android 11+ Wireless Debugging pairing over TLS (pairing code and pairing port).
- TLS ADB transport for modern Wireless Debugging.
- mDNS discovery of pairing/connect services.
- Signed IPA and installation verification on a physical iPhone.

## Protocol compatibility

The current connection flow targets legacy ADB-over-TCP, typically port 5555, when that mode is explicitly enabled on the Android device. Android 11+ Wireless Debugging normally uses a separate TLS pairing flow and is not supported yet. A successful TCP connection alone does not mean ADB is authenticated.

The Android 11+ pairing and TLS requirements are documented in [docs/WIRELESS_DEBUGGING.md](docs/WIRELESS_DEBUGGING.md).

## Build

Open `ADBManager.xcodeproj` in Xcode 15+ and build for iOS 17 or later.

GitHub Actions builds an unsigned iOS app artifact. Installing on a physical iPhone requires signing with an Apple development certificate or a supported sideloading workflow.
