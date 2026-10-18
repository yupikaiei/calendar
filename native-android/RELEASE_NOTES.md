# Frelsi Cal Native — v1.0.1

A native Kotlin/Jetpack Compose build of Frelsi Cal for Android.

## Sync reliability fixes

- **Actionable CalDAV errors**: authentication (401), permission (403), not-found (404), server errors, DNS failures, timeouts and TLS certificate problems now show a specific message instead of silently reporting a successful or empty sync.
- **Test Connection** in **Settings → CalDAV Server Settings** verifies the URL, credentials and calendar discovery before saving.
- **Smarter server URLs**: the app strips an accidentally included principal or calendar path (for example `http://host:5232/test/work/`) and keeps reverse-proxy prefixes such as `/radicale/` when the server returns paths without them.
- **No false "Sync complete"**: failed calendar discovery, uploads and downloads now fail the sync with the server's reason.
- Servers without a `getctag` property are pulled every sync instead of being skipped.

## Highlights

- Agenda and month views with recurring-event expansion
- Create/edit events with all-day support, recurrence presets and end dates
- Edit or delete a single occurrence without changing the rest of the series
- Local SQLite storage and two-way CalDAV sync
- Multiple calendars, ICS import, and secondary timezone display
- Reminders with recurring-occurrence chaining
- Keystore-encrypted CalDAV password

## Installation

1. Download `frelsi-cal-native-v1.0.1.apk` below.
2. On Android, allow installing apps from your browser/file manager if prompted.
3. Open the APK to install.

Requires **Android 8.0 (API 26) or newer**.

The APK is signed with the Android debug key so it can be installed directly. It is **not Play Store-ready**; a dedicated release keystore will be required before publishing to a store.

## CalDAV setup

Open **Settings → CalDAV Server Settings**, enter the **base** server URL, username and password, then tap **Test Connection** before saving.

Examples:

- `http://192.168.1.10:5232` (Radicale on your LAN)
- `https://calendar.example.com/radicale/` (reverse proxy with a path prefix)

Troubleshooting:

- **Cannot connect**: make sure Radicale listens on all interfaces (`hosts = 0.0.0.0:5232` in `config`), not only `localhost`. Open the same URL in the phone's browser to confirm it is reachable.
- **Authentication failed**: verify the username/password and Radicale's htpasswd file.
- **TLS certificate error**: install the self-signed CA on the phone or use a certificate the phone trusts.
- **Not found (404)**: use the server base URL, not the Radicale web UI or a calendar URL. The app now trims a principal path automatically.

## Notes

- Android 13+ calendar apps with `USE_EXACT_ALARM` receive exact reminder timing automatically. On Android 12, use the **Allow exact alarms** action in Settings if reminders are delayed.
- Self-hosted servers using plain HTTP are supported; HTTPS is recommended.
- This release is built from the `feature/native-android` branch and is marked as a pre-release.

## Verification

SHA-256 checksum: see the attached `.sha256` file.
