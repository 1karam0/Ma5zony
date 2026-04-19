/// Centralized configuration for Firebase Cloud Function URLs.
///
/// Cloud Functions v2 (2nd gen) deploy to Cloud Run. The URL format is:
///   https://{functionName}-{projectHash}-{region}.a.run.app
///
/// Override the base URL at build time via --dart-define:
///   flutter build web --dart-define=CLOUD_FUNCTIONS_BASE_URL=https://...
///
/// To find your URLs after deploying:
///   firebase deploy --only functions
/// Then check Firebase Console → Functions → each function's trigger URL.
class CloudFunctionConfig {
  CloudFunctionConfig._();

  /// Cloud Run suffix shared by all functions in the same project/region.
  /// This is the hash portion: e.g. "-rjv64oud6a-uc.a.run.app"
  static const String _suffix = String.fromEnvironment(
    'CLOUD_FUNCTIONS_SUFFIX',
    defaultValue: '-rjv64oud6a-uc.a.run.app',
  );

  static String _url(String functionName) =>
      'https://$functionName$_suffix';

  // ── Shopify Integration ──────────────────────────────────────────────

  static String get shopifyGetOAuthUrl =>
      _url('shopifygetoauthurl');

  static String get shopifyOAuthCallback =>
      _url('shopifyoauthcallback');

  static String get shopifyImportProducts =>
      _url('shopifyimportproducts');

  static String get shopifySyncStock =>
      _url('shopifysyncstock');

  static String get shopifyDisconnectStore =>
      _url('shopifydisconnectstore');

  // ── Order Import ─────────────────────────────────────────────────────

  static String get shopifyImportOrders =>
      _url('shopifyimportorders');

  // ── Emails ───────────────────────────────────────────────────────────

  static String get sendSupplierEmails =>
      _url('sendsupplieremails');

  static String get sendFactoryEmails =>
      _url('sendfactoryemails');

  static String get sendManufacturerEmails =>
      _url('sendmanufactureremails');
}
