import 'package:cloud_firestore/cloud_firestore.dart';

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
