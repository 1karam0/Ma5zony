import 'package:cloud_firestore/cloud_firestore.dart';

/// One-time onboarding answers that decide which screens, fields, and
/// terminology the rest of the app shows. Persisted alongside the rest of
/// user settings so guards and the sidebar can read it synchronously after
/// login.
///
/// `stockMode`:
///   - 'single'   → one warehouse / location
///   - 'multi'    → multiple warehouses / branches
///   - 'dropship' → no physical stock, fulfilment partner ships
///
/// `sourcing`:
///   - 'buy'  → resell finished goods (purchased)
///   - 'make' → manufacture in-house / via partner (BOM-driven)
///   - 'both' → mix; show every workflow
///
/// `channels`: any subset of {'shopify','instore','wholesale','marketplace'}.
class BusinessProfile {
  final String stockMode;
  final String sourcing;
  final List<String> channels;

  const BusinessProfile({
    required this.stockMode,
    required this.sourcing,
    required this.channels,
  });

  bool get sellsB2c => channels.contains('shopify') ||
      channels.contains('instore') ||
      channels.contains('marketplace');
  bool get sellsWholesale => channels.contains('wholesale');
  bool get isDropship => stockMode == 'dropship';
  bool get isMultiLocation => stockMode == 'multi';
  bool get manufactures => sourcing == 'make' || sourcing == 'both';
  bool get purchases => sourcing == 'buy' || sourcing == 'both';

  factory BusinessProfile.fromMap(Map<String, dynamic> m) {
    return BusinessProfile(
      stockMode: m['stockMode'] as String? ?? 'single',
      sourcing: m['sourcing'] as String? ?? 'both',
      channels: (m['channels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['shopify'],
    );
  }

  Map<String, dynamic> toMap() => {
        'stockMode': stockMode,
        'sourcing': sourcing,
        'channels': channels,
      };

  BusinessProfile copyWith({
    String? stockMode,
    String? sourcing,
    List<String>? channels,
  }) =>
      BusinessProfile(
        stockMode: stockMode ?? this.stockMode,
        sourcing: sourcing ?? this.sourcing,
        channels: channels ?? this.channels,
      );
}

/// User-level settings persisted in Firestore at `users/{uid}/settings/global`.
class UserSettings {
  final double serviceLevelTarget;
  final int defaultLeadTimeDays;
  final String planningTimeBucket;
  final String defaultAlgorithm;
  final int smaWindow;
  final double sesAlpha;
  final double holtBeta;
  final double holtGamma;
  final int holtWintersSeasonLength;
  final double orderingCost;
  final double holdingRate;
  final bool emailDigest;
  final bool lowStockAlerts;
  final BusinessProfile? businessProfile;
  /// True once the user has seen the welcome tour overlay. Used by
  /// `AppState`/`OwnerDashboardScreen` to decide whether to auto-show the
  /// guided walkthrough on first visit to the dashboard.
  final bool tourCompleted;

  const UserSettings({
    this.serviceLevelTarget = 95,
    this.defaultLeadTimeDays = 7,
    this.planningTimeBucket = 'Daily',
    this.defaultAlgorithm = 'Auto',
    this.smaWindow = 3,
    this.sesAlpha = 0.3,
    this.holtBeta = 0.1,
    this.holtGamma = 0.2,
    this.holtWintersSeasonLength = 12,
    this.orderingCost = 250.0,
    this.holdingRate = 0.20,
    this.emailDigest = true,
    this.lowStockAlerts = true,
    this.businessProfile,
    this.tourCompleted = false,
  });

  factory UserSettings.fromMap(Map<String, dynamic> m) {
    return UserSettings(
      serviceLevelTarget: (m['serviceLevelTarget'] as num?)?.toDouble() ?? 95,
      defaultLeadTimeDays: (m['defaultLeadTimeDays'] as num?)?.toInt() ?? 7,
      planningTimeBucket: m['planningTimeBucket'] as String? ?? 'Daily',
      defaultAlgorithm: m['defaultAlgorithm'] as String? ?? 'Auto',
      smaWindow: (m['smaWindow'] as num?)?.toInt() ?? 3,
      sesAlpha: (m['sesAlpha'] as num?)?.toDouble() ?? 0.3,
      holtBeta: (m['holtBeta'] as num?)?.toDouble() ?? 0.1,
      holtGamma: (m['holtGamma'] as num?)?.toDouble() ?? 0.2,
      holtWintersSeasonLength: (m['holtWintersSeasonLength'] as num?)?.toInt() ?? 12,
      orderingCost: (m['orderingCost'] as num?)?.toDouble() ?? 250.0,
      holdingRate: (m['holdingRate'] as num?)?.toDouble() ?? 0.20,
      emailDigest: m['emailDigest'] as bool? ?? true,
      lowStockAlerts: m['lowStockAlerts'] as bool? ?? true,
      businessProfile: m['businessProfile'] is Map
          ? BusinessProfile.fromMap(
              Map<String, dynamic>.from(m['businessProfile'] as Map))
          : null,
      tourCompleted: m['tourCompleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'serviceLevelTarget': serviceLevelTarget,
        'defaultLeadTimeDays': defaultLeadTimeDays,
        'planningTimeBucket': planningTimeBucket,
        'defaultAlgorithm': defaultAlgorithm,
        'smaWindow': smaWindow,
        'sesAlpha': sesAlpha,
        'holtBeta': holtBeta,
        'holtGamma': holtGamma,
        'holtWintersSeasonLength': holtWintersSeasonLength,
        'orderingCost': orderingCost,
        'holdingRate': holdingRate,
        'emailDigest': emailDigest,
        'lowStockAlerts': lowStockAlerts,
        if (businessProfile != null)
          'businessProfile': businessProfile!.toMap(),
        'tourCompleted': tourCompleted,
      };

  UserSettings copyWith({
    double? serviceLevelTarget,
    int? defaultLeadTimeDays,
    String? planningTimeBucket,
    String? defaultAlgorithm,
    int? smaWindow,
    double? sesAlpha,
    double? holtBeta,
    double? holtGamma,
    int? holtWintersSeasonLength,
    double? orderingCost,
    double? holdingRate,
    bool? emailDigest,
    bool? lowStockAlerts,
    BusinessProfile? businessProfile,
    bool clearBusinessProfile = false,
    bool? tourCompleted,
  }) {
    return UserSettings(
      serviceLevelTarget: serviceLevelTarget ?? this.serviceLevelTarget,
      defaultLeadTimeDays: defaultLeadTimeDays ?? this.defaultLeadTimeDays,
      planningTimeBucket: planningTimeBucket ?? this.planningTimeBucket,
      defaultAlgorithm: defaultAlgorithm ?? this.defaultAlgorithm,
      smaWindow: smaWindow ?? this.smaWindow,
      sesAlpha: sesAlpha ?? this.sesAlpha,
      holtBeta: holtBeta ?? this.holtBeta,
      holtGamma: holtGamma ?? this.holtGamma,
      holtWintersSeasonLength: holtWintersSeasonLength ?? this.holtWintersSeasonLength,
      orderingCost: orderingCost ?? this.orderingCost,
      holdingRate: holdingRate ?? this.holdingRate,
      emailDigest: emailDigest ?? this.emailDigest,
      lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
      businessProfile: clearBusinessProfile
          ? null
          : (businessProfile ?? this.businessProfile),
      tourCompleted: tourCompleted ?? this.tourCompleted,
    );
  }
}

/// Reads / writes [UserSettings] from Firestore.
class SettingsService {
  final FirebaseFirestore _db;
  final String uid;

  SettingsService({required this.uid, FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('users').doc(uid).collection('settings').doc('global');

  Future<UserSettings> load() async {
    final snap = await _doc.get();
    if (snap.exists && snap.data() != null) {
      return UserSettings.fromMap(snap.data()!);
    }
    return const UserSettings();
  }

  Future<void> save(UserSettings settings) async {
    await _doc.set(settings.toMap());
  }
}
