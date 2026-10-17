# Frelsi Cal — Native Android

A native Kotlin/Jetpack Compose implementation of Frelsi Cal. It preserves the Flutter app's offline-first behavior and visual language while running directly on the Android platform.

## Features

- **Agenda view** listing event days, with past events dimmed and a "Today" shortcut.
- **Month view** with per-calendar color dots and a day agenda underneath.
- **Event editor**: title, calendar, all-day toggle, start/end date and time, preset recurrence (daily/weekly/monthly/yearly) with an optional end date, reminders, location, description, and deletion.
- **Recurrence expansion** driven by [lib-recur](https://github.com/dmfs/lib-recur), covering `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, and other RFC 5545 parts. Local wall-clock times and all-day dates are preserved across DST changes.
- **Per-occurrence edits and deletes**: edit or remove one instance without touching the series. Exclusions are stored as `EXDATE` and round-trip through CalDAV.
- **Unbounded navigation**: the agenda loads earlier/more event days on demand, and month navigation extends the expansion window automatically instead of stopping at a fixed cutoff.
- **Offline-first SQLite storage** mirroring the Flutter schema (`events`, `calendars`, `reminders`, `deleted_events`).
- **Two-way CalDAV sync** against Radicale/Nextcloud-style servers: calendar discovery, automatic `frelsi` calendar creation, event upload, tombstone propagation, and ctag-based downloads.
- **Reminders** scheduled through `AlarmManager`, with `USE_EXACT_ALARM` on Android 13+ and a direct grant shortcut on Android 12. Recurring events schedule the next occurrence and chain each following occurrence after an alert fires; reminders are rescheduled after reboot/app updates.
- **Multiple calendars** with create, rename, recolor, and delete.
- **ICS import** from the system file picker.
- **Secondary timezone** display in event cards.
- **Password encryption** using an AES/GCM key stored in the Android Keystore.

## Requirements

- JDK 17+
- Android SDK Platform 36 and Build Tools 36
- `ANDROID_HOME` set, or a `local.properties` file containing `sdk.dir=/path/to/Android/sdk`

The project uses the Gradle wrapper (`8.14.3`), Android Gradle Plugin `8.13.2`, Kotlin `2.3.20`, and Compose BOM `2026.03.01`.

## Build and test

```bash
cd native-android
./gradlew testDebugUnitTest    # JVM unit tests (ICS, recurrence, WebDAV XML)
./gradlew lintDebug            # Android lint
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
```

Install on a connected device or emulator:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.frelsical.nativeapp/.MainActivity
```

The native app uses a separate application id (`com.frelsical.nativeapp`) and database, so it can be installed alongside the Flutter build.

## Project layout

```
app/src/main/java/com/frelsical/nativeapp/
├── data/        SQLite database, models, repository, ICS import
├── ical/        ICS parser/writer, RRULE helpers and expansion
├── network/     CalDAV client and WebDAV multistatus parser
├── notify/      AlarmManager scheduler, notification/boot receivers
├── settings/    SharedPreferences settings and Keystore-backed secrets
├── sync/        Two-way CalDAV sync manager
├── ui/          Compose screens, editor, theme
├── FrelsiApplication.kt
└── MainActivity.kt
```

## Configuration

Settings → **CalDAV Server Settings** stores the server URL, username, and password. The password is encrypted with an Android Keystore key; the URL and username live in private `SharedPreferences`.

Self-hosted servers often use plain HTTP. The manifest enables cleartext traffic for that case; use HTTPS whenever possible.

### CalDAV expectations

- The user path is `/<username>/`.
- If no calendars exist, the app creates `/<username>/frelsi/`.
- Local events without a calendar are uploaded to the `frelsi` calendar (or the first available calendar) on sync.
- Deleted remote events are queued in `deleted_events` and retried until the server confirms deletion.
- Imported calendars use a `/local/...` path and are never uploaded.

## Permissions

| Permission | Why |
|---|---|
| `INTERNET` | CalDAV sync |
| `POST_NOTIFICATIONS` | Event reminders (Android 13+) |
| `SCHEDULE_EXACT_ALARM` | On-time reminders on Android 12 and user-granted access |
| `USE_EXACT_ALARM` | Exact reminders without a prompt for qualifying calendar apps on Android 13+ |
| `RECEIVE_BOOT_COMPLETED` | Re-register alarms after reboot |

## Notable differences from the Flutter app

- All-day events are stored with an explicit flag and exported as `VALUE=DATE`, so they do not shift across timezones.
- Calendar colors are written as CalDAV's `#RRGGBBAA` format (the Flutter app writes `#AARRGGBB`).
- Events without a calendar are uploaded to a single default calendar instead of every calendar.
- Deleting a calendar cancels its pending reminder alarms.
- Custom RRULEs (for example `FREQ=WEEKLY;BYDAY=MO`) are shown as "Custom" in the editor instead of crashing the repeat selector.
- Single-occurrence edits create a standalone event and add an `EXDATE` to the series; deleting the standalone later does not resurrect the original occurrence.
- If the base recurrence rule changes, stale occurrence exclusions are discarded.
