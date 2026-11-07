# Crumz iOS Student Application (`crumz-ios`)

Native iOS SwiftUI implementation of the **Crumz Student Application**, built as a strict **1:1 functional, visual, behavioral, and Firestore-compatible mirror** of the Android application (`crumz-android`).

---

## 1. Project Overview & Features

- **Exact Brand Theming:**
  - `CrumzDarkBlue` (`#131B3A` / `RGB(19, 27, 58)`)
  - `CrumzDarkBlueLight` (`#1E2B58` / `RGB(30, 43, 88)`)
  - `CrumzGold` (`#D6932C` / `RGB(214, 147, 44)`)
  - `CrumzGoldLight` (`#EAB35E` / `RGB(234, 179, 94)`)
  - Light background (`#F8FAFC`)
- **Global 90-Second Inactivity Auto-Logout (`MainNavigationView.swift`):**
  - Monitors screen touch gestures and keyboard typing across the entire app window via a non-intrusive hit-testing overlay.
  - Automatically signs out of Firebase Auth and resets navigation to `[Login]` after 90 seconds of inactivity on any authenticated screen.
- **Animated Splash Screen (`SplashView.swift`):**
  - Custom vector canvas drawing the 3D-shadowed Dark Blue `'C'` (-45° start, -270° sweep, 60pt stroke).
  - 5 bouncy spring Gold crumbs positioned on the exact 240×240 coordinate grid.
  - Slogan *"Dignity beyond paydays"* fading in at 1.4s (3.0s total timeout).
- **Authentication & Forced Password Change (`LoginView.swift`, `ChangePasswordView.swift`, `AuthViewModel.swift`):**
  - Pulsing `CRUMZ` hero header (White ↔ Gold over 2.0s), `🔒 NCR Registered` & `🎓 Students Only` trust badges.
  - High-contrast, sharp `CrumzDarkBlue` text fields and pure bright white (`#FFFFFF`) ExtraBold `"Sign In →"` button text.
  - First-time login validates `password == temp_password`, creates the Firebase Auth user, marks `used: true` in `approved_students/{studentNumber}`, writes `is_temporary_password: true` to `users/{uid}`, and routes to `ChangePasswordView`.
  - Forced password change updates Firebase Auth password, clears `is_temporary_password = false`, and pops back to Login.
- **Home Dashboard (`MainView.swift`):**
  - Dynamic time-of-day greeting (`Good morning,` / `Good afternoon,` / `Good evening,`) displaying **First Name ONLY**.
  - Responsive top-right circular Logout button.
  - Overlapping `CrumzGold` card with pulsing green status dot, balance (with `-R` negative buffer support), full-to-empty progress bar (`Spent: R...` / `Allocated: R...`), `Buffer limit: R15.00`, bursary cycle, and active status.
  - Quick actions: `Scan & Pay`, `Vendors`, and `History` (wired directly to `HistoryView`).
  - **Strictly max 2 recent transactions** with clickable `"More →"` header button and `"View all transactions (N) →"` link.
- **5-Bubble PIN Pad & QR Code Scanner (`ScanView.swift`):**
  - **Byte-for-byte SHA-256 PIN hashing** (`CryptoKit.SHA256(UTF8(pinSalt + pin))`) matching Android exactly.
  - 5 minimalist animated bubbles (`○ ○ ○ ○ ○` → `● ● ● ● ●`) and 3×4 circular keypad (`1–9`, `CLR`, `0`, `⌫`).
  - **Zero extra steps:** filling the 5th bubble immediately unlocks and launches the camera scanner.
  - Inline 2-step PIN creation flow if student hasn't set a PIN yet, plus `returnToScanAfterPinSetup` loop with Profile.
  - Parses both self-contained offline JSON (`CRUMZ_OFFLINE:{...}`) and online (`CRUMZ_CHARGE:CHG-xxx`) QR codes.
  - Live vendor till bills list with countdown timer (`Expires in Xs`).
  - Read-only bill confirmation dialog with **R15.00 emergency buffer** check and warning banner.
  - Atomic Firestore `runTransaction` enforcing single-use, 2-minute expiration, and `-15.0001` buffer floor.
  - Green `#065F46` `PAYMENT CONFIRMED` receipt card.
- **Partnered Vendors Map & 30-Campus SA Search (`VendorsMapView.swift`, `RouteService.swift`):**
  - Interactive map with custom circular `'C'` vendor pins from live Firestore `vendors`.
  - Top floating search bar with **all 30 South African university campuses (`SA_CAMPUSES`)**, 7 quick preset chips (`UWC`, `UJ`, `Wits`, `UCT`, `UP`, `Campus Square`, `DUT`), real-time autocomplete dropdown, and `CLGeocoder` fallback.
  - Turn-by-turn `Walk` and `Drive` navigation via Google Routes API v2 + native `MKDirections` fallback.
  - Live 3D heading-up compass navigation with distance tracking, step instructions, and automatic off-route re-routing.
- **Transaction History & PDF Statement Generator (`HistoryView.swift`, `PDFStatementGenerator.swift`):**
  - Dedicated screen with Statement Summary Card (`fullName`, `studentNumber`, `N Purchases`, `Allocated Credit`, `Total Spent`, `Available Balance`).
  - Full-width **"Download PDF Statement"** button generating an A4 (`595x842 pt`) multi-page PDF statement via `UIGraphicsPDFRenderer` and presenting the native iOS Share / Save to Files sheet.
  - Filter chips: `All`, `Purchases`, `Credits`.
- **My Profile Screen (`ProfileView.swift`):**
  - Profile photo with initials fallback.
  - **Strictly First Name + Last Name ONLY (NO `Mr`/`Ms` title formalities anywhere)**.
  - 270° rounded arc `CreditScoreGauge` (0–999).
  - Personal Details card (no Title row).
  - Security PIN manager (`Change PIN` / `Set PIN`).
  - Settings menu items (`Security`, `Support`, `Legal`) and full-width red Log Out button.

---

## 2. Directory Structure

```text
crumz-ios/
├── Crumz.xcodeproj/
│   ├── project.pbxproj              # Complete Xcode project file
│   ├── project.xcworkspace/
│   └── xcshareddata/xcschemes/Crumz.xcscheme
├── project.yml                      # XcodeGen specification (optional alternate generator)
├── README.md
├── .github/workflows/ios-build.yml  # Automated macOS CI build workflow
└── Crumz/
    ├── CrumzApp.swift               # @main entry point & FirebaseApp.configure()
    ├── Info.plist                   # iOS permissions (Camera, Location) & GMSApiKey
    ├── GoogleService-Info.plist     # Firebase project configuration (crumz-648fb)
    ├── Assets.xcassets/             # AppIcon & image catalog
    ├── Theme/
    │   └── CrumzTheme.swift         # Colors, SHA-256 crypto, arc math, high-contrast inputs
    ├── Models/
    │   └── CrumzModels.swift        # Data models, SA_CAMPUSES (30 campuses), presets
    ├── Navigation/
    │   └── MainNavigationView.swift # Root stack + 90s inactivity auto-logout
    ├── Services/
    │   ├── PDFStatementGenerator.swift # Multi-page A4 PDF statement generator & Share sheet
    │   ├── QRCodeScannerView.swift     # AVCaptureSession camera scanner & Simulator fallback
    │   └── RouteService.swift          # Google Routes API v2 + MKDirections fallback & GPS/heading
    ├── ViewModels/
    │   └── AuthViewModel.swift      # First-time & returning login, forced password change
    └── Views/
        ├── SplashView.swift         # Animated 3D 'C' arc & 5 bouncy gold crumbs
        ├── LoginView.swift          # Pulsing CRUMZ hero, crisp inputs, white button text
        ├── ChangePasswordView.swift # Temporary password change screen
        ├── MainView.swift           # First-name greeting, card, max-2 txns, bottom tabs
        ├── ScanView.swift           # 5-bubble PIN pad, camera scanner, atomic R15 payment
        ├── VendorsMapView.swift     # Custom 'C' pins, 30-campus search, turn-by-turn navigation
        ├── HistoryView.swift        # Statement summary, PDF download, filter chips
        └── ProfileView.swift        # No-formalities profile, credit gauge, PIN manager
```

---

## 3. How to Open and Run

### On macOS (with Xcode):
1. Double-click `Crumz.xcodeproj` to open it in Xcode.
2. Xcode will automatically resolve the Swift Package Manager dependency `firebase-ios-sdk` (`FirebaseAuth`, `FirebaseFirestore`).
3. Select an iPhone Simulator (e.g., iPhone 15) or a physical device.
4. Press **⌘R** (Run) to build and launch.

### Automated CI / GitHub Actions:
- Push to GitHub to trigger `.github/workflows/ios-build.yml` which builds the project on a `macos-14` runner.

---

## 4. Shared Firebase Configuration

The iOS application connects to the exact same Firebase project as `crumz-android` and `crumz-admin`:
- **Project ID:** `crumz-648fb`
- **Project Number:** `301047804736`
- **Storage Bucket:** `crumz-648fb.firebasestorage.app`
- **Collections:** `approved_students`, `users`, `vendors`, `payment_requests`, `transactions`
