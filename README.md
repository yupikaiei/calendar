# frelsi_cal

An elegant, offline-first Flutter calendar application with CalDAV synchronization and AI-powered Natural Language Processing (NLP) event creation.

## ✨ Features

- **Offline-First Storage:** Powered by [Drift](https://drift.simonbinder.eu/) (SQLite) for ultra-fast, local interactions.
- **CalDAV Synchronization:** Securely syncs events with personal CalDAV servers (e.g., Radicale, Nextcloud) to keep your calendars up-to-date across devices.
- **Natural Language Parsing:** Uses an on-device MLC LLM runtime with **Llama 3.2 1B** to parse sentences like *"Lunch with Sarah tomorrow at 1pm"* into structured calendar events.
- **Advanced Recurrence (RRULE):** Fully supports complex repeating events and instances generation mapped cleanly onto your timeline.
- **Beautiful Glassmorphic UI:** Modern, deeply atmospheric aesthetics with intuitive scrolling, fading past events, and smart contextual icons.
- **Timezone Aware:** Gracefully handles primary and secondary timezones for global event cordination.

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
