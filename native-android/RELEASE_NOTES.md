# Frelsi Cal Native — v1.0.2

A native Kotlin/Jetpack Compose build of Frelsi Cal for Android.

## Sync no longer spins forever

- **Every CalDAV request is time-bounded** (30 s per call, including DNS and TLS) and is cancelled when the sync is cancelled.
- **A 5-minute sync cap** stops the spinner and shows `Sync timed out. Check that the server is reachable and try again.` Remaining changes are uploaded on the next sync.
- **Sync progress** is shown under the app bar (`Finding calendars…`, `Uploading 3 event(s)…`, `Downloading events…`).
- **Only changed events are uploaded.** A new `dirty` flag marks locally created/edited events; unchanged events are no longer re-uploaded on every sync. The first sync after upgrading uploads existing events once.
- **Auto-sync on app resume is debounced** to once per minute and no longer starts a new long sync every time the app returns to the foreground.

## Previous v1.0.1 fixes

- Actionable 401/403/404/5xx, DNS, timeout and TLS errors instead of false “Sync complete” messages.
- **Test Connection** in Settings.
- Smarter server URLs: trims principal/calendar paths and keeps reverse-proxy prefixes such as `/radicale/`.
- Calendars without `getctag` are pulled instead of skipped.

## Highlights

- Agenda and month views with recurring-event expansion
- Create/edit events with all-day support, recurrence presets and end dates
- Edit or delete a single occurrence without changing the rest of the series
- Local SQLite storage and two-way CalDAV sync
- Multiple calendars, ICS import, and secondary timezone display
- Reminders with recurring-occurrence chaining
- Keystore-encrypted CalDAV password

## Installation

1. Download `frelsi-cal-native-v1.0.2.apk` below.
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
- **Not found (404)**: use the server base URL, not the Radicale web UI or a calendar URL.
- **Sync timed out**: the server accepted the connection but did not answer within 30 seconds. Check the URL, proxy and firewall.

## Notes

- Android 13+ calendar apps with `USE_EXACT_ALARM` receive exact reminder timing automatically. On Android 12, use the **Allow exact alarms** action in Settings if reminders are delayed.
- Self-hosted servers using plain HTTP are supported; HTTPS is recommended.
- This release is built from the `feature/native-android` branch and is marked as a pre-release.

## Verification

SHA-256 checksum: see the attached `.sha256` file.
