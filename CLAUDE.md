# StudyCycleApp - Project Memory

## Project Overview

**StudyCycleApp** is a cross-platform mobile application built with Xamarin.Forms demonstrating MVVM architecture with basic CRUD operations.

## Technology Stack

- **Language:** C# (.NET)
- **Framework:** Xamarin.Forms 5.0.0.2196
- **Target:** .NET Standard 2.0 (shared code)
- **Platforms:** Android (API 13), iOS
- **Dependencies:** Xamarin.Essentials 1.7.0

## Key Features

- Login functionality
- Item browsing with collection view
- Item detail view
- Add new items
- Shell-based navigation with flyout menu

## Architecture

- **Pattern:** MVVM (Model-View-ViewModel)
- **Navigation:** Xamarin.Forms Shell with URI-based routing
- **Data Binding:** Two-way XAML bindings with INotifyPropertyChanged

## Project Structure

```
StudyCycleApp/
├── StudyCycleApp.sln
└── StudyCycleApp/
    ├── StudyCycleApp/              # Shared .NET Standard library
    │   ├── Models/
    │   │   └── Item.cs             # Data model (Id, Text, Description)
    │   ├── Views/
    │   │   ├── LoginPage.xaml      # Login entry
    │   │   ├── AboutPage.xaml      # Flyout menu item
    │   │   ├── ItemsPage.xaml      # Item browser
    │   │   ├── ItemDetailPage.xaml # Detail view
    │   │   └── NewItemPage.xaml    # Add new items
    │   ├── ViewModels/
    │   │   ├── BaseViewModel.cs    # Base INotifyPropertyChanged
    │   │   ├── LoginViewModel.cs
    │   │   ├── ItemsViewModel.cs
    │   │   ├── ItemDetailViewModel.cs
    │   │   ├── NewItemViewModel.cs
    │   │   └── AboutViewModel.cs
    │   ├── Services/
    │   │   ├── IDataStore.cs       # Data persistence interface
    │   │   └── MockDataStore.cs    # In-memory mock data
    │   ├── App.xaml                # Application entry
    │   └── AppShell.xaml           # Shell navigation container
    │
    ├── StudyCycleApp.Android/      # Android platform project
    │   └── StudyCycleApp.Android.csproj
    │
    └── StudyCycleApp.iOS/          # iOS platform project
        └── StudyCycleApp.iOS.csproj
```

## Navigation Structure

**Shell Configuration (AppShell.xaml):**
- Flyout menu with "About" and "Browse" items
- Logout menu item
- Login page as separate tab bar

## Data Layer

Currently uses `MockDataStore` with sample data. Ready to be replaced with:
- REST API calls
- Local database (SQLite)
- Cloud storage

## Styling

- **Primary Color:** Material Design Blue (#2196F3)
- Global Button styling with visual states
- Platform-aware styling in AppShell

## Build Configuration

- **Platforms:** Debug, Release
- **Android:** API level 13, Aapt2 resource compilation
- **iOS:** iPhoneSimulator and iPhone builds

## Development Notes

- Solution uses Visual Studio 2022 (v17.4+)
- Mock data includes 6 sample items
- Item model: simple with Id, Text, and Description properties

---

*This file maintains project context for AI assistance. Last reviewed: 2026-01-19*
