/// Centralized configuration for Firebase Cloud Function URLs.
///
/// Update these URLs after each `firebase deploy --only functions` if
/// the function region or project changes.
class CloudFunctionConfig {
  CloudFunctionConfig._();

  /// Firebase project region prefix (from deploy output).
  static const String _baseUrl = 'https://';
  static const String _suffix = '-rjv64oud6a-uc.a.run.app';

  // ── Shopify Integration ──────────────────────────────────────────────

  static const String shopifyGetOAuthUrl =
      '${_baseUrl}shopifygetoauthurl$_suffix';

  static const String shopifyOAuthCallback =
      '${_baseUrl}shopifyoauthcallback$_suffix';

  static const String shopifyImportProducts =
      '${_baseUrl}shopifyimportproducts$_suffix';

  static const String shopifySyncStock =
      '${_baseUrl}shopifysyncstock$_suffix';

  static const String shopifyDisconnectStore =
      '${_baseUrl}shopifydisconnectstore$_suffix';

  // ── Order Import ─────────────────────────────────────────────────────

  static const String shopifyImportOrders =
      '${_baseUrl}shopifyimportorders$_suffix';

  // ── Emails ───────────────────────────────────────────────────────────

  static const String sendSupplierEmails =
      '${_baseUrl}sendsupplieremails$_suffix';

  static const String sendFactoryEmails =
      '${_baseUrl}sendfactoryemails$_suffix';

  static const String sendManufacturerEmails =
      '${_baseUrl}sendmanufactureremails$_suffix';

  /// All Shopify function URLs in a map (for dynamic lookup).
  static const Map<String, String> shopifyFunctions = {
    'shopifyGetOAuthUrl': shopifyGetOAuthUrl,
    'shopifyOAuthCallback': shopifyOAuthCallback,
    'shopifyImportProducts': shopifyImportProducts,
    'shopifySyncStock': shopifySyncStock,
    'shopifyDisconnectStore': shopifyDisconnectStore,
    'shopifyImportOrders': shopifyImportOrders,
  };
}
