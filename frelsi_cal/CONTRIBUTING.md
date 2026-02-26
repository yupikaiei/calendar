# Contributing to `frelsi_cal`

Thank you for your interest in contributing to our Flutter calendar app! The open-source community thrives on contributions from engineers, designers, and enthusiasts like you.

## Getting Started

1. **Fork the Repository:** Create your own fork by clicking the "Fork" button on the top right of this page.
2. **Clone:** Clone your local copy:
   ```bash
   git clone git@github.com:YOUR_USERNAME/frelsi_cal.git
   cd frelsi_cal
   ```
3. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

## Development Workflow

### Database Architecture
`frelsi_cal` uses [Drift](https://drift.simonbinder.eu/) for its local SQLite implementation. If you change any files inside `lib/core/db/` or any annotations (`@UseDao`, `@DataClassName`), you **must** run the build runner to generate the updated part files (`*.g.dart`):

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Running Tests
To ensure the integrity of your changes, please write and run tests:

```bash
flutter test
```

### Coding Standards
We use standard Dart formatting. Before committing your code, please ensure it conforms to `flutter format`:

```bash
dart format .
flutter analyze
```

## Submitting a Pull Request

1. **Create a branch:** Create a feature branch off of `main` (`git checkout -b feature/awesome-new-feature` or `bugfix/issue-description`).
2. **Commit your changes:** Write clear and concise commit messages.
3. **Push to your fork:** `git push origin YOUR_BRANCH_NAME`.
4. **Open a PR:** Go to the original repository and click "New Pull Request." Fill out the PR template as thoroughly as possible.

We look forward to reviewing your PR!
