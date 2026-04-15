import 'package:cloud_firestore/cloud_firestore.dart';

class CashFlowEntry {
  final String category;
  final double amount;
  final DateTime date;
  final String? notes;

  CashFlowEntry({
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
  });

  factory CashFlowEntry.fromJson(Map<String, dynamic> json) {
    return CashFlowEntry(
      category: json['category'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: json['date'] is Timestamp
          ? (json['date'] as Timestamp).toDate()
          : DateTime.parse(json['date'] as String),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'amount': amount,
        'date': Timestamp.fromDate(date),
        if (notes != null) 'notes': notes,
      };
}

class CashFlowSnapshot {
  final String id;
  final DateTime uploadedAt;
  final double totalAvailable;
  final double allocatedToProduction;
  final List<CashFlowEntry> entries;

  CashFlowSnapshot({
    required this.id,
    required this.uploadedAt,
    required this.totalAvailable,
    this.allocatedToProduction = 0,
    required this.entries,
  });

  double get remainingBudget => totalAvailable - allocatedToProduction;

  factory CashFlowSnapshot.fromFirestore(
      String id, Map<String, dynamic> data) {
    final entriesList = (data['entries'] as List<dynamic>?)
            ?.map((e) => CashFlowEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return CashFlowSnapshot(
      id: id,
      uploadedAt: data['uploadedAt'] is Timestamp
          ? (data['uploadedAt'] as Timestamp).toDate()
          : DateTime.parse(data['uploadedAt'] as String),
      totalAvailable: (data['totalAvailable'] as num?)?.toDouble() ?? 0,
      allocatedToProduction:
          (data['allocatedToProduction'] as num?)?.toDouble() ?? 0,
      entries: entriesList,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'totalAvailable': totalAvailable,
      'allocatedToProduction': allocatedToProduction,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }
}
