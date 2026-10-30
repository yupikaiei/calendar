# Frelsi Cal Native — v1.0.7

A native Kotlin/Jetpack Compose build of Frelsi Cal for Android.

## Choose Frelsi Cal as your calendar handler

- Frelsi Cal now answers **"open calendar" requests** (`CATEGORY_APP_CALENDAR`), so Android can offer it as the default when another app or launcher asks for the calendar. Pick Frelsi Cal and **Always** in the chooser.
- Combined with the new-event support added in 1.0.6, that same choice also routes `ACTION_INSERT` requests to Frelsi Cal.
- Android has no global "default calendar app" setting, and apps that write directly to `content://com.android.calendar` still target the system calendar provider.

## Add events from other apps

- **Other apps can now open the new-event editor pre-filled**, following the Android calendar contract (`ACTION_INSERT` / `ACTION_INSERT_OR_EDIT` with `vnd.android.cursor.dir/event`). Title, description, location, start and end time, the all-day flag and the recurrence rule are carried over.
- **`.ics` files opened or shared with the app** (`ACTION_VIEW` / `ACTION_SEND` with `text/calendar`) now import through the same path as **Settings → Import .ics**, including calendars shared as plain text.
- Incoming events are **never written silently**: they open in the editor and are stored only after you tap **Save**.
- All-day requests use the platform's UTC-midnight convention and land on the correct local date.

## Agenda opens on today

- The agenda now starts on **today** instead of the earliest day with events. The view is positioned once the first database read finishes, and the app returns to today when you reopen it on a later day.
- Your scroll position is kept while you stay in the agenda, and the **Today** shortcut still jumps back at any time.
- The sync icon only animates while a sync is running.

## Calmer syncing

- Automatic syncs are now silent: opening the app no longer flashes the progress bar with every resume.
- Automatic syncs run at most every **5 minutes**, backing off to **15 minutes** after a failure; the last attempt is remembered across app restarts, so a failing server is no longer retried on every launch.
- Syncs are skipped while CalDAV is not configured or the device has no network. Manual sync (the refresh button) always runs and still shows its progress and result.
- Renaming, recoloring or creating a calendar can no longer start a second sync alongside the automatic one.

## All-day events from CalDAV and existing imports

- **CalDAV sync now applies the same midnight-UTC detection as ICS import.** Birthday calendars stored on Radicale/Nextcloud with events like `DTSTART:20230514T220000Z` / `DTEND:20230515T220000Z` are shown as all-day after the next sync.
- **Existing events are repaired once on first launch.** The app converts already-stored midnight-like whole-day events to all-day, so you do not need to delete or re-import your `Aniversários` calendar.
- Events now show **“All day”** instead of `00:00 - 00:00` and stay on the intended calendar date.
- Multi-day spans and EXDATEs are preserved. Afternoon and short timed events are unchanged.
- The About section now shows the real installed version instead of a hard-coded `1.0.0`.

## Sync reliability (v1.0.2)

- Every CalDAV request is time-bounded (30 s per call) and cancellable; a 5-minute sync cap stops the spinner with an explanatory message.
- Only changed events are uploaded; unchanged events are no longer re-uploaded on every sync.
- Sync progress is shown under the app bar.
- Actionable 401/403/404/5xx, DNS, timeout and TLS errors.
- **Test Connection** in Settings and smarter server URL handling.

## Highlights

- Agenda and month views with recurring-event expansion
- Create/edit events with all-day support, recurrence presets and end dates
- Edit or delete a single occurrence without changing the rest of the series
- Local SQLite storage and two-way CalDAV sync
- Multiple calendars, ICS import, and secondary timezone display
- Events added from other apps through the Android calendar contract
- Reminders with recurring-occurrence chaining
- Keystore-encrypted CalDAV password

## Installation

1. Download `frelsi-cal-native-v1.0.7.apk` below.
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

- **Cannot connect**: make sure Radicale listens on all interfaces (`hosts = 0.0.0.0:5232` in `config`), not only `localhost`.
- **Authentication failed**: verify the username/password and Radicale's htpasswd file.
- **TLS certificate error**: install the self-signed CA on the phone or use a certificate the phone trusts.
- **Not found (404)**: use the server base URL, not the Radicale web UI or a calendar URL.
- **Sync timed out**: the server accepted the connection but did not answer within 30 seconds. Check the URL, proxy and firewall.

## Adding events from other apps

Other apps can open the editor with a pre-filled event:

```kotlin
val intent = Intent(Intent.ACTION_INSERT).apply {
    type = "vnd.android.cursor.dir/event"
    putExtra(CalendarContract.Events.TITLE, "Dentist")
    putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMillis)
    putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis)
}
startActivity(intent)
```

The app does not implement the `CalendarContract` content provider, so apps that write to `content://com.android.calendar` directly instead of launching the insert intent are not supported.

## Notes

- Android 13+ calendar apps with `USE_EXACT_ALARM` receive exact reminder timing automatically. On Android 12, use the **Allow exact alarms** action in Settings if reminders are delayed.
- Self-hosted servers using plain HTTP are supported; HTTPS is recommended.
- This release is built from the `feature/native-android` branch and is marked as a pre-release.

## Verification

SHA-256 checksum: see the attached `.sha256` file.
