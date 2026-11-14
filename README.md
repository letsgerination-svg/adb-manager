# ADB Manager

Native iOS app for managing Android devices over a local network.

## Initial milestone
- SwiftUI interface for iPhone.
- Device connection screen and connection state.
- Command console with command history.
- Device/app management modules are being built incrementally.

## Important protocol note
Android 11+ Wireless debugging uses authenticated TLS pairing. The app must implement the ADB pairing and transport protocols; simply opening a TCP socket to port 5555 is not sufficient for modern Wireless debugging. Legacy ADB-over-TCP is supported only when explicitly enabled on the Android device.

## Build
Open `ADBManager.xcodeproj` in Xcode 15+ and build for iOS 17 or later.

The GitHub Actions workflow builds an unsigned app artifact. Installation on a physical iPhone requires signing with an Apple development certificate.
