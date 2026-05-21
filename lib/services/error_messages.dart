/// 4K — Centralised error-message mapping.
///
/// Converts raw Firebase, Dart, and domain exceptions into short, friendly
/// strings suitable for display in SnackBars, AlertBanners, and form errors.
///
/// Usage:
/// ```dart
/// catch (e) {
///   final msg = AppErrors.friendly(e);
///   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
/// }
/// ```
library;

class AppErrors {
  const AppErrors._();

  // ── Firebase Auth codes ─────────────────────────────────────────────────
  static const _auth = <String, String>{
    'user-not-found':            'No account found with that email.',
    'wrong-password':            'Incorrect password.',
    'invalid-email':             'Please enter a valid email address.',
    'email-already-in-use':      'An account with that email already exists.',
    'weak-password':             'Password must be at least 6 characters.',
    'invalid-credential':        'Invalid email or password.',
    'INVALID_LOGIN_CREDENTIALS': 'Invalid email or password.',
    'too-many-requests':         'Too many sign-in attempts. Please wait and try again.',
    'user-disabled':             'This account has been disabled. Contact support.',
    'network-request-failed':    'Network error — check your connection and try again.',
    'popup-closed-by-user':      'Sign-in cancelled.',
    'account-exists-with-different-credential':
        'An account already exists with a different sign-in method.',
  };

  // ── Firebase Firestore / Functions codes ───────────────────────────────
  static const _firestore = <String, String>{
    'permission-denied':         'You don\'t have permission to perform this action.',
    'unavailable':               'Service temporarily unavailable. Please retry.',
    'not-found':                 'The requested item no longer exists.',
    'already-exists':            'This item already exists.',
    'resource-exhausted':        'Quota exceeded. Please try again later.',
    'deadline-exceeded':         'The request timed out. Check your connection.',
    'unauthenticated':           'Your session has expired. Please sign in again.',
    'cancelled':                 'The operation was cancelled.',
  };

  // ── Domain / business-logic messages ──────────────────────────────────
  static const _domain = <String, String>{
    'BomMissingException':  'No Bill of Materials found for this product.',
    'CloudFunctionException':
        'Could not contact the server. Check your connection and try again.',
  };

  /// Returns a user-friendly message for any thrown [error].
  ///
  /// Falls through in order:
  ///   1. Domain exception class name
  ///   2. Firebase auth code
  ///   3. Firebase Firestore/Functions code
  ///   4. Generic fallback
  static String friendly(Object error, {String? context}) {
    final raw = error.toString();
    final type = error.runtimeType.toString();

    // 1. Domain exceptions by type name
    for (final entry in _domain.entries) {
      if (type.contains(entry.key) || raw.contains(entry.key)) {
        return entry.value;
      }
    }

    // 2. Firebase auth codes
    for (final entry in _auth.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }

    // 3. Firebase Firestore / Functions codes
    for (final entry in _firestore.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }

    // 4. Generic fallback with optional context prefix
    final prefix = context != null ? '$context failed. ' : '';
    return '${prefix}Something went wrong. Please try again.';
  }

  // ── Convenience wrappers ────────────────────────────────────────────────

  /// Friendly message specifically for auth operations.
  static String auth(Object error) =>
      friendly(error, context: 'Authentication');

  /// Friendly message for Firestore CRUD operations.
  static String firestore(Object error, {String entity = 'item'}) =>
      friendly(error, context: 'Saving $entity');

  /// Friendly message for network / Cloud Function calls.
  static String cloudFunction(Object error) =>
      friendly(error, context: 'Server request');
}
