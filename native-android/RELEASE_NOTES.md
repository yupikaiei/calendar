# Frelsi Cal Native — v1.0.0

A native Kotlin/Jetpack Compose build of Frelsi Cal for Android.

## Highlights

- Agenda and month views with recurring-event expansion
- Create/edit events with all-day support, recurrence presets and end dates
- Edit or delete a single occurrence without changing the rest of the series
- Local SQLite storage and two-way CalDAV sync
- Multiple calendars, ICS import, and secondary timezone display
- Reminders with recurring-occurrence chaining
- Keystore-encrypted CalDAV password

## Installation

1. Download `frelsi-cal-native-v1.0.0.apk` below.
2. On Android, allow installing apps from your browser/file manager if prompted.
3. Open the APK to install.

Requires **Android 8.0 (API 26) or newer**.

The APK is signed with the Android debug key so it can be installed directly. It is **not Play Store-ready**; a dedicated release keystore will be required before publishing to a store.

## CalDAV setup

Open **Settings → CalDAV Server Settings** and enter your server URL, username, and password. The app creates a `frelsi` calendar automatically when none exists.

## Notes

- Android 13+ calendar apps with `USE_EXACT_ALARM` receive exact reminder timing automatically. On Android 12, use the **Allow exact alarms** action in Settings if reminders are delayed.
- Self-hosted servers using plain HTTP are supported; HTTPS is recommended.
- This release is built from the `feature/native-android` branch and is marked as a pre-release.

## Verification

SHA-256 checksum: see the attached `.sha256` file.
