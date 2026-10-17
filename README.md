# frelsi_cal

An elegant, offline-first calendar application with CalDAV synchronization and advanced recurrence support. The repository ships both the original Flutter app and a native Android app.

## ✨ Features

- **Offline-First Storage:** Powered by SQLite for ultra-fast, local interactions (Drift in the Flutter app, `SQLiteOpenHelper` in the native app).
- **CalDAV Synchronization:** Securely syncs events with personal CalDAV servers (e.g., Radicale, Nextcloud) to keep your calendars up-to-date across devices.
- **Advanced Recurrence (RRULE):** Fully supports complex repeating events and instance generation mapped cleanly onto your timeline.
- **Local Reminders:** Schedules notifications for upcoming events, with exact-alarm support on Android.
- **Beautiful Glassmorphic UI:** Modern, deeply atmospheric aesthetics with intuitive scrolling, fading past events, and smart contextual icons.
- **Timezone Aware:** Gracefully handles primary and secondary timezones for global event coordination.

## 📱 Native Android app

A native Kotlin/Jetpack Compose implementation lives in [`native-android/`](native-android/README.md). It mirrors the Flutter feature set — agenda and month views, event editing with recurrence, reminders, CalDAV sync, multiple calendars, ICS import, and a secondary timezone — without a Flutter runtime.

```bash
cd native-android
./gradlew assembleDebug
```

See [`native-android/README.md`](native-android/README.md) for requirements, architecture, and testing details.

## 🚀 Getting Started

### Prerequisites

Ensure you have the Flutter SDK installed on your system.
For more info, check the [Flutter Installation Guide](https://docs.flutter.dev/get-started/install).

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/frelsi_cal.git
   cd frelsi_cal
   ```

2. Get the dependencies:
   ```bash
   flutter pub get
   ```

3. (Optional) Run the `build_runner` to generate SQLite data models if you plan to modify the database schema:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. Run the app:
   ```bash
   flutter run
   ```

## 🤝 Contributing

We welcome contributions! Please see our [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to set up your development environment, run tests, and open Pull Requests.

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

## 📄 License

This project is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License (**CC BY-NC 4.0**) - see the [LICENSE](LICENSE) file for details. This explicitly restricts the use of this project for commercial purposes.

## 🙏 Acknowledgements
Built natively with [Flutter](https://flutter.dev/). Uses standard CalDAV and iCalendar protocols.
