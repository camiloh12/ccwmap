# CCW Map

A collaborative mobile application for mapping and sharing information about concealed carry weapon (CCW) zones across the United States.

## Features

- Interactive map with color-coded pins (Green = Allowed, Yellow = Uncertain, Red = No Guns)
- Create, edit, and delete pins with detailed restriction information
- Offline-first architecture with local SQLite storage
- User authentication with Supabase
- Real-time location services
- US boundary validation
- Platform support: Android, iOS, and Web

## Current Status

**Iteration 7 Complete** - All local CRUD operations functional
- 74/74 tests passing (100%)
- Ready for Iteration 8: Overpass API Integration

See `IMPLEMENTATION_PLAN.md` for detailed development roadmap.

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Android Studio / Xcode (for mobile development)
- Chrome (for web development)

## Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/camiloh12/ccwmap.git
   cd ccwmap
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure environment variables**

   Create a `.env` file in the project root:
   ```properties
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   MAPTILER_API_KEY=your-maptiler-key  # Optional
   ```

4. **Generate database code**
   ```bash
   flutter pub run build_runner build
   ```

## Running the App

### Web (Development)
```bash
flutter run -d chrome
```
Note: Web uses in-memory database (data resets on page reload)

### Android
```bash
flutter emulators --launch <emulator-id>
flutter run
```

### iOS (macOS only)
```bash
open -a Simulator
flutter run
```

## Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Analyze code
flutter analyze
```

## Architecture

This project follows **Clean Architecture** with three layers:

- **Domain Layer**: Pure Dart business logic (models, repository interfaces)
- **Data Layer**: Repository implementations, database DAOs, API clients
- **Presentation Layer**: Flutter UI, ViewModels using MVVM pattern

See `CLAUDE.md` for detailed architectural guidelines.

## Project Structure

```
lib/
├── domain/           # Business logic and models
│   ├── models/       # Pin, PinStatus, Location, etc.
│   ├── repositories/ # Repository interfaces
│   └── validators/   # US boundary validation
├── data/            # Data layer implementations
│   ├── database/    # Drift database and DAOs
│   ├── repositories/# Repository implementations
│   └── mappers/     # Entity ↔ Domain conversions
├── presentation/    # UI layer
│   ├── screens/     # MapScreen, LoginScreen
│   ├── widgets/     # PinDialog, etc.
│   └── viewmodels/  # MapViewModel, AuthViewModel
└── main.dart        # App entry point
```

## Key Technologies

- **Flutter** - Cross-platform UI framework
- **Drift** - Type-safe SQLite ORM
- **MapLibre GL** - Open-source mapping library
- **Supabase** - Backend-as-a-Service (Auth + PostgreSQL)
- **Provider** - State management
- **Geolocator** - Location services

## Known Issues

- **Web Pin Detection**: Requires dual-detection system (see `BUILD_STATUS.md` section 2)
- **Windows Build**: Requires Visual Studio 2019+ with Desktop development workload
- **Linter Warnings**: 13 style warnings for enum naming (intentional for database consistency)

## Contributing

1. Read `CLAUDE.md` for architectural guidelines
2. Follow Clean Architecture principles
3. Write tests for all new features
4. Ensure `flutter analyze` passes
5. Update documentation as needed

## License

This project is licensed under the MIT License.

## Links

- **Documentation**: See `CLAUDE.md` for development guidelines
- **Implementation Plan**: See `IMPLEMENTATION_PLAN.md` for roadmap
- **Build Status**: See `BUILD_STATUS.md` for current build health
