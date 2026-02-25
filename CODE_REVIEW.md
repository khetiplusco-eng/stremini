# Code Review Report

## Scope
Reviewed all tracked source/config code in this repository (Flutter/Dart app layer, Android Kotlin integration, and platform scaffolding/config files) excluding generated binary assets.

## Review Method
- Read through Dart application layers under `lib/`.
- Read Android integration/services in `android/app/src/main/kotlin/...`.
- Spot-checked platform manifests and app configuration.
- Ran string/pattern scans for TODOs, direct logging, and hardcoded endpoints.

## Findings

### ✅ Strengths
- App structure is reasonably modular (`core`, `providers`, `services`, `screens`, `widgets`) and easy to navigate.
- Method channel names are mostly centralized and consistent.
- Defensive null checks are generally present around platform channel calls.

### ⚠️ Medium-priority issues
1. **Unbounded polling lifecycle in scanner provider**
   - Previous implementation used an always-true `Future.doWhile` loop without explicit cancellation on notifier disposal.
   - This can keep background work alive unnecessarily and risk updating state after dispose.
   - Fixed by replacing the loop with a cancellable `Timer.periodic` and disposing the timer.

2. **Use of `print` for operational logging in production paths**
   - Several scanner/app lifecycle paths used `print` instead of `debugPrint`.
   - Fixed in updated files to keep logs framework-consistent and less noisy.

### 📝 Lower-priority observations
- There are TODO placeholders in drawer/message input widgets that represent incomplete UX flows.
- Backend base URLs appear duplicated in multiple Dart/Kotlin locations; consider centralizing endpoint config to reduce drift.
- A few file naming inconsistencies/typos exist (e.g. `app_seetings.dart`), which can hurt long-term maintainability.

## Changes applied as part of this review
- `lib/providers/scanner_provider.dart`
  - Replaced `Future.doWhile` polling with cancellable `Timer.periodic`.
  - Added proper `dispose()` cleanup.
  - Replaced `print` with `debugPrint`.
  - Removed unused legacy Riverpod import.
- `lib/main.dart`
  - Replaced scanner handler `print` logs with `debugPrint`.
  - Added default branch in method-call switch.

## Recommended next steps
1. Introduce one source of truth for backend environment configuration.
2. Complete TODO UX handlers or track them explicitly in issues.
3. Add static checks (`dart analyze`, tests) in CI once Flutter SDK is present in the build environment.
