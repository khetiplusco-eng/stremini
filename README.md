# Stremini AI

## Project Overview
Stremini AI is a cross‑platform keyboard application that integrates AI‑powered assistance directly into the typing experience. It works on Android, iOS, Web, Linux, macOS, and Windows, providing a custom Input Method (IME), a floating chat overlay, screen‑reader support, QR/barcode scanning, and robust permission handling.

## Key Features
- **AI‑driven chat overlay** – Real‑time suggestions, answers, and actions while typing.
- **Custom Input Method (IME)** – Fully functional keyboard with dynamic layouts and shortcuts.
- **Screen Reader Service** – Reads on‑screen content for accessibility.
- **Scanner Provider** – QR and barcode scanning integrated into the keyboard.
- **Permission Management** – Automatic handling of runtime permissions (camera, microphone, etc.).
- **Cross‑platform support** – Android, iOS, Web, Linux, macOS, Windows.
- **Provider‑based state management** – ChatProvider, ScannerProvider, ChatWindowStateProvider.
- **Theming & UI** – Gradient rings, feature cards, permission cards, customizable app drawer.
- **Session Lifecycle** – Automatic handling of background tasks and app lifecycle events.
- **System Overlay Control** – Manages system UI overlays for optimal visibility.

## Architecture
The project follows a modular architecture with a clear separation between Flutter UI and native platform code.

### Flutter Layer (`lib/`)
- **Controllers** – Home navigation logic.
- **Core** – Constants, theme definitions, shared widgets.
- **Models** – Data models such as `MessageModel`.
- **Providers** – State management for chat, scanner, and UI.
- **Services** – API, Keyboard, Overlay, Permission services.
- **Utils** – Helper functions, session lifecycle manager, system overlay controller.
- **Widgets** – Reusable UI components (chat bubbles, floating chatbot, etc.).

### Native Android Layer (`android/app/`)
- Kotlin services:
  - `ChatOverlayService.kt` – Manages the floating chat overlay.
  - `ScreenReaderService.kt` – Provides screen‑reading capabilities.
  - `KeyboardSettingsActivity.kt` – Settings UI for the IME.
  - `StreminiIME.kt` – Core Input Method implementation.
- ProGuard rules (`proguard-rules.pro`) for code obfuscation.
- Gradle configuration (`build.gradle.kts`) for Android build settings.

### Native iOS Layer (`ios/Runner/`)
- Swift bridging header (`Runner-Bridging-Header.h`) for native interop.
- Generated plugin registration (`GeneratedPluginRegistrant.swift`).

### Desktop & Web
- Platform‑specific CMake files and Flutter engine integration for Linux, macOS, and Windows.
- Web build output in `build/web`.

## Getting Started

### Prerequisites
- Flutter SDK (>= 3.10.0)
- Android Studio or Xcode (for native builds)
- Java JDK 11 (Android) or Apple clang (iOS)
- Git

### Clone the repository
$ git clone https://github.com/983111/Streminiai-.git
$ cd Streminiai-

### Install dependencies
$ flutter pub get

### Run the app
$ flutter run
Select the target device (Android emulator, iOS simulator, web, or desktop).

## Platform Specific Build Instructions

### Android
1. Ensure `android/gradle.properties` has the correct `android.useAndroidX` and `android.enableJetifier` flags.
2. Build with Gradle:
   $ cd android
   $ ./gradlew assembleRelease
3. The APK will be located at `android/app/build/outputs/apk/release/app-release.apk`.

### iOS
1. Open the Xcode workspace:
   $ open ios/Runner.xcodeproj
2. Select a simulator or a physical device and press **Run**.
3. Ensure the `Runner-Bridging-Header.h` includes any required native headers.

### Web
$ flutter build web
Deploy the generated `build/web` folder to any static web host.

### Desktop (Linux, macOS, Windows)
$ flutter build linux   # or macos, windows
For Windows, you may need to run `flutter build windows` and then package the `.msi` or `.exe` using the provided `Runner.rc`.

## Configuration
- **`pubspec.yaml`** – Lists Flutter dependencies and assets.
- **`analysis_options.yaml`** – Linting rules and code style.
- **`devtools_options.yaml`** – Configuration for Flutter DevTools.
- **`android/app/proguard-rules.pro`** – ProGuard rules for native code obfuscation.
- **`android/app/build.gradle.kts`** – Android build settings (minSdk, compileSdk, etc.).
- **`ios/Runner.xcodeproj`** – iOS project settings.

## Usage

### Enabling the Keyboard
1. Install the app from the generated APK/IPA or from the Play Store/App Store.
2. Open **Settings → General → Keyboard → Keyboards → Add New Keyboard** and select **Stremini AI**.
3. Grant required permissions (camera, microphone, etc.) when prompted.

### Using the Chat Overlay
- While typing, tap the floating chat icon to open the overlay.
- Ask questions, request actions, or get suggestions directly from the AI.
- The overlay can be dragged to any screen location.

### Scanning QR/Barcodes
- Press the scanner button on the keyboard or invoke the overlay’s scan command.
- Point the device camera at the QR code or barcode; the result is returned instantly.

### Screen Reader
- Activate the screen reader from the keyboard settings.
- The service reads highlighted text and UI elements as you navigate.

## Contributing
We welcome contributions! Please follow these steps:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/awesome-feature`).
3. Make your changes and ensure all tests pass (`flutter test`).
4. Update documentation if needed.
5. Submit a pull request with a clear description.

### Code Style
- Run `dart format` on Dart files.
- Follow the linting rules defined in `analysis_options.yaml`.
- Keep Kotlin code idiomatic; consider using `ktlint` for formatting.

### Testing
- Unit tests: `flutter test`.
- Integration tests: `flutter drive --target=test_driver/integration_test.dart`.

## License
This project is licensed under the **MIT License** – see the `LICENSE` file for details.

## Contact
- **Maintainer**: StreminiAI developers.
- **GitHub**: https://github.com/983111/Streminiai-

## Roadmap
- Add voice input support.
- Implement offline AI inference.
- Expand scanner capabilities (NFC, RFID).
- Improve multi‑language support for the keyboard layout.

## Acknowledgements
- Thanks to the Flutter community for the excellent framework.
- Thanks to the contributors of the AI API used for chat suggestions.