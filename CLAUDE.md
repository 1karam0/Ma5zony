# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app (web)
flutter run -d chrome

# Build for web (production)
flutter build web --release

# Analyze & lint
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Deploy Firebase Cloud Functions
cd functions && npm install
firebase deploy --only functions

# Deploy everything (hosting + Firestore rules + functions)
firebase deploy
```

## Architecture Overview

**Ma5zony** is a Flutter-based inventory management system for SMEs. It handles demand forecasting, replenishment recommendations, purchase orders, manufacturing workflow, and Shopify integration. Supports Web, iOS, macOS, and Windows.

### Tech Stack
- **Flutter** (Dart ^3.11.0) with Material 3 / Google Fonts (Inter)
- **State management**: Provider (`ChangeNotifier`)
- **Routing**: GoRouter v13
- **Backend**: Firebase (Auth, Firestore, Cloud Functions v5 / Node 20)
- **Charts**: fl_chart
- **External**: Shopify OAuth via Cloud Functions, optional HTTP backend API

### Directory Layout

```
lib/
  main.dart            # Entry point: Firebase init, MultiProvider setup
  app.dart             # MaterialApp root
  app_router.dart      # All 19+ GoRouter routes + portal routes
  features/            # One folder per domain screen (see below)
  models/              # 19 Dart data classes (plain objects, fromMap/toMap)
  providers/
    app_state.dart     # Single central ChangeNotifier (~1100 lines)
  services/            # Business logic; each service is a plain Dart class
  widgets/
    main_layout.dart   # Responsive sidebar shell used by all authenticated screens
    shared_widgets.dart
  utils/
    constants.dart     # AppColors, AppTextStyles
    api_config.dart    # BACKEND_URL (env var, dev default: localhost:3000)
    role_guard.dart    # isOwner(), ownerOnlyRoutes list
functions/
  index.js             # Firebase Cloud Functions: Shopify OAuth, email, webhooks
```

### State Management

`AppState` (`lib/providers/app_state.dart`) is the single source of truth. It:
- Owns and instantiates all service objects
- Listens to Firebase auth state and loads user profile + Firestore repo after login
- Exposes domain lists (products, suppliers, orders, etc.) and CRUD methods
- Calls `notifyListeners()` to trigger UI rebuilds

Widgets read state via `context.watch<AppState>()` or `context.read<AppState>()`.

### Service Layer

| Service | Responsibility |
|---|---|
| `FirestoreInventoryRepository` | All Firestore CRUD; implements `InventoryRepository` interface |
| `FirebaseAuthService` | Wraps Firebase Auth (sign in, register, sign out) |
| `ForecastingService` | Pure Dart SMA / SES algorithms |
| `ReplenishmentService` | ROP, safety stock, reorder quantity calculations |
| `ManufacturingService` | Production order workflow and status transitions |
| `CashFlowService` | Cash position aggregation from orders |
| `BackendApiService` | HTTP client for optional backend API (forecasts, replenishment) |
| `FirebaseShopifyService` | Shopify OAuth token management via Cloud Functions |
| `NotificationService` | In-app notifications (Firestore-backed) |
| `WorkflowService` | Audit trail / workflow logs |

### Firestore Data Model

All data is user-scoped under `users/{uid}/`:

```
users/{uid}/
  products/            purchaseOrders/      forecastResults/
  suppliers/           rawMaterials/        replenishmentRecommendations/
  warehouses/          rawMaterialOrders/   manufacturingRecommendations/
  demandRecords/       productionOrders/    approvals/
  billOfMaterials/     manufacturers/       notifications/
  settings/            workflowLogs/        shopifyConnections/
```

Security rules in `firestore.rules` enforce user-scoped access and role checks.

### Authentication & Roles

Roles are stored on the Firestore user document and checked via `AppUser.role`. Role values: `owner`, `inventoryManager`, `manufacturer`, `rawMaterialFactory`.

`role_guard.dart` defines `ownerOnlyRoutes` — routes that redirect non-owners. Portals (`/supplier-portal`, `/manufacturer-portal`, `/factory-portal`) are fully public (no auth required) and accessed via URL token params.

### Routing

Routes are defined in `app_router.dart`. The `GoRouter` uses a redirect callback that checks `AppState.isAuthenticated` and `AppState.currentUser.role` to enforce auth and role guards. Most routes wrap their screen in `MainLayout` (the sidebar shell). Portal routes bypass `MainLayout` entirely.

### Cloud Functions

`functions/index.js` handles:
- **Shopify OAuth**: `shopifyGetOAuthUrl`, `shopifyOAuthCallback` (stores access token in Firestore)
- **Email notifications**: `sendManufacturerEmail`, `sendSupplierEmail` (via Nodemailer)
- **Shopify webhooks**: order/product sync

Function URLs are configured in `lib/utils/cloud_function_config.dart`.

### Environment / Configuration

- `BACKEND_URL` env var controls the optional backend API base URL (defaults to `http://localhost:3000`)
- Firebase project: `ma5zony`
- Firebase secrets for Cloud Functions: `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET`
- `firebase_options.dart` is auto-generated — do not edit manually
