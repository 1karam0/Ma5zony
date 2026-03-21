import 'package:cloud_firestore/cloud_firestore.dart';

/// User-level settings persisted in Firestore at `users/{uid}/settings/global`.
class UserSettings {
  final double serviceLevelTarget;
  final int defaultLeadTimeDays;
  final String planningTimeBucket;
  final String defaultAlgorithm;
  final int smaWindow;
  final double sesAlpha;

  const UserSettings({
    this.serviceLevelTarget = 95,
    this.defaultLeadTimeDays = 7,
    this.planningTimeBucket = 'Daily',
    this.defaultAlgorithm = 'SMA',
    this.smaWindow = 3,
    this.sesAlpha = 0.3,
  });

  factory UserSettings.fromMap(Map<String, dynamic> m) {
    return UserSettings(
      serviceLevelTarget: (m['serviceLevelTarget'] as num?)?.toDouble() ?? 95,
      defaultLeadTimeDays: (m['defaultLeadTimeDays'] as num?)?.toInt() ?? 7,
      planningTimeBucket: m['planningTimeBucket'] as String? ?? 'Daily',
      defaultAlgorithm: m['defaultAlgorithm'] as String? ?? 'SMA',
      smaWindow: (m['smaWindow'] as num?)?.toInt() ?? 3,
      sesAlpha: (m['sesAlpha'] as num?)?.toDouble() ?? 0.3,
    );
  }

  Map<String, dynamic> toMap() => {
        'serviceLevelTarget': serviceLevelTarget,
        'defaultLeadTimeDays': defaultLeadTimeDays,
        'planningTimeBucket': planningTimeBucket,
        'defaultAlgorithm': defaultAlgorithm,
        'smaWindow': smaWindow,
        'sesAlpha': sesAlpha,
      };

  UserSettings copyWith({
    double? serviceLevelTarget,
    int? defaultLeadTimeDays,
    String? planningTimeBucket,
    String? defaultAlgorithm,
    int? smaWindow,
    double? sesAlpha,
  }) {
    return UserSettings(
      serviceLevelTarget: serviceLevelTarget ?? this.serviceLevelTarget,
      defaultLeadTimeDays: defaultLeadTimeDays ?? this.defaultLeadTimeDays,
      planningTimeBucket: planningTimeBucket ?? this.planningTimeBucket,
      defaultAlgorithm: defaultAlgorithm ?? this.defaultAlgorithm,
      smaWindow: smaWindow ?? this.smaWindow,
      sesAlpha: sesAlpha ?? this.sesAlpha,
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
