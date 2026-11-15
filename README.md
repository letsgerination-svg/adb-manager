# ADB Manager

Native SwiftUI iOS app for managing Android devices over a local network.

## Implemented
- SwiftUI connection screen and command console.
- ADB packet framing and validation.
- Legacy ADB TCP handshake (CNXN).
- Persistent RSA-2048 key identity stored in iOS Keychain.
- ADB AUTH token signing (RSA PKCS#1 v1.5 with SHA-1).
- Android-compatible RSA public-key serialization for the authorization prompt.
- Basic ADB shell stream using OPEN / OKAY / WRTE / CLSE, with a 1 MB output cap.

## Not implemented / not yet verified
- Android 11+ Wireless debugging pairing over TLS (pairing code and pairing port).
- TLS ADB transport for modern Wireless debugging.
- APK installation, package listing, uninstall/disable tools.
- End-to-end testing against a physical Android device.
- Verified successful Xcode build and signed IPA.

## Protocol compatibility
The current connection flow targets legacy ADB-over-TCP, typically port 5555, when that mode is explicitly enabled on the Android device. Android 11+ Wireless debugging normally uses a separate TLS pairing flow and is not supported yet. A successful TCP connection alone does not mean ADB is authenticated.

## Build
Open `ADBManager.xcodeproj` in Xcode 15+ and build for iOS 17 or later.

GitHub Actions is configured to build an unsigned iOS app artifact. Installing on a physical iPhone requires signing with an Apple development certificate or a supported sideloading workflow.
