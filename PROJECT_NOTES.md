# Ma5zony — Project Notes

My notes for working on this project.

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

## Overview

Ma5zony is a Flutter web app for inventory management for SMEs. It handles
demand forecasting, replenishment recommendations, purchase orders, the
manufacturing workflow, and Shopify integration.

### Tech Stack
- Flutter (Dart ^3.11.0) with Material 3 / Google Fonts (Inter)
- State management: Provider (`ChangeNotifier`)
- Routing: GoRouter v13
- Backend: Firebase (Auth, Firestore, Cloud Functions v5 / Node 20)
- Charts: fl_chart
- External: Shopify OAuth via Cloud Functions, optional HTTP backend API

### Directory Layout

```
lib/
  main.dart            # Entry point: Firebase init, MultiProvider setup
  app.dart             # MaterialApp root
  app_router.dart      # All GoRouter routes + portal routes
  features/            # One folder per domain screen
  models/              # Data classes (fromMap/toMap)
  providers/
    app_state.dart     # Central ChangeNotifier
  services/            # Business logic; each service is a plain Dart class
  widgets/
    main_layout.dart   # Responsive sidebar shell for authenticated screens
    shared_widgets.dart
  utils/
    constants.dart     # AppColors, AppTextStyles
    api_config.dart    # BACKEND_URL (env var, dev default: localhost:3000)
    role_guard.dart    # isOwner(), ownerOnlyRoutes list
functions/
  index.js             # Cloud Functions: Shopify OAuth, email, webhooks
```

### State Management

`AppState` (`lib/providers/app_state.dart`) is the single source of truth. It:
- Owns and instantiates all service objects
- Listens to Firebase auth state and loads the user profile + Firestore repo after login
- Exposes domain lists (products, suppliers, orders, etc.) and CRUD methods
- Calls `notifyListeners()` to trigger UI rebuilds

Widgets read state via `context.watch<AppState>()` or `context.read<AppState>()`.

### Service Layer

| Service | Responsibility |
|---|---|
| `FirestoreInventoryRepository` | All Firestore CRUD; implements `InventoryRepository` |
| `FirebaseAuthService` | Wraps Firebase Auth |
| `ForecastingService` | SMA / SES algorithms |
| `ReplenishmentService` | ROP, safety stock, reorder quantity |
| `RawMaterialStockService` | Auto reorder points for raw materials |
| `ManufacturingService` | Production order workflow |
| `CashFlowService` | Cash position from orders |
| `BackendApiService` | HTTP client for optional backend API |
| `FirebaseShopifyService` | Shopify OAuth token management |
| `NotificationService` | In-app notifications |
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

Roles live on the Firestore user document and are checked via `AppUser.role`.
Values: `owner`, `inventoryManager`, `manufacturer`, `rawMaterialFactory`.

`role_guard.dart` defines `ownerOnlyRoutes` — routes that redirect non-owners.
Portals (`/supplier-portal`, `/manufacturer-portal`, `/factory-portal`) are
public and accessed via URL token params.

### Routing

Routes are in `app_router.dart`. The `GoRouter` redirect callback checks
`AppState.isAuthenticated` and the user's role to enforce auth and role guards.
Most routes wrap their screen in `MainLayout`. Portal routes bypass it.

### Cloud Functions

`functions/index.js` handles:
- Shopify OAuth: `shopifyGetOAuthUrl`, `shopifyOAuthCallback`
- Email notifications: `sendManufacturerEmail`, `sendSupplierEmail`
- Shopify webhooks: order/product sync

Function URLs live in `lib/utils/cloud_function_config.dart`.

### Environment / Configuration

- `BACKEND_URL` env var controls the optional backend API base URL (default `http://localhost:3000`)
- Firebase project: `ma5zony`
- Firebase secrets for Cloud Functions: `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET`
- `firebase_options.dart` is auto-generated — do not edit manually
