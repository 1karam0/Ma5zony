/// Base URL for the Ma5zony backend API.
///
/// In development, point to localhost. In production, this should be the
/// Cloud Run URL (e.g. https://ma5zony-backend-xxxxx-uc.a.run.app).
///
/// Override via the `BACKEND_URL` compile-time constant:
///   flutter build web --dart-define=BACKEND_URL=https://...
class ApiConfig {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );
}
