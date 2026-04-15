import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:ma5zony/models/cash_flow_snapshot.dart';
import 'package:ma5zony/services/inventory_repository.dart';

/// Handles cash-flow snapshot creation from parsed spreadsheet rows
/// and persists them via the repository.
class CashFlowService {
  final InventoryRepository repo;
  CashFlowService({required this.repo});

  /// Build and persist a [CashFlowSnapshot] from parsed spreadsheet rows.
  /// Each row should have: category, amount, date, and optionally notes.
  Future<CashFlowSnapshot> importFromRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final entries = rows.map((r) {
      return CashFlowEntry(
        category: r['category'] as String? ?? '',
        amount: (r['amount'] as num?)?.toDouble() ?? 0,
        date: r['date'] is DateTime
            ? r['date'] as DateTime
            : DateTime.tryParse(r['date']?.toString() ?? '') ?? DateTime.now(),
        notes: r['notes'] as String?,
      );
    }).toList();

    final income = entries
        .where((e) => e.amount > 0)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final expenses = entries
        .where((e) => e.amount < 0)
        .fold<double>(0, (sum, e) => sum + e.amount.abs());

    final snapshot = CashFlowSnapshot(
      id: '', // Firestore will assign
      uploadedAt: DateTime.now(),
      totalAvailable: income - expenses,
      entries: entries,
    );

    return repo.addCashFlowSnapshot(snapshot);
  }

  /// Parse an Excel (.xlsx) file and import its rows as a cash-flow snapshot.
  /// Expected columns: Category, Amount, Date (optional), Notes (optional).
  Future<CashFlowSnapshot> importFromExcelBytes(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null || sheet.rows.length < 2) {
      throw Exception('Excel file is empty or has no data rows');
    }

    // Read header row to find column indices
    final headers = sheet.rows.first
        .map((cell) => cell?.value?.toString().trim().toLowerCase() ?? '')
        .toList();

    int colCategory = headers.indexOf('category');
    int colAmount = headers.indexOf('amount');
    int colDate = headers.indexOf('date');
    int colNotes = headers.indexOf('notes');

    // Fallback: use first 4 columns in order
    if (colCategory == -1) colCategory = 0;
    if (colAmount == -1) colAmount = headers.length > 1 ? 1 : -1;

    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final category = row.length > colCategory
          ? row[colCategory]?.value?.toString().trim() ?? ''
          : '';
      final amountStr = colAmount >= 0 && row.length > colAmount
          ? row[colAmount]?.value?.toString().trim() ?? '0'
          : '0';
      final dateStr = colDate >= 0 && row.length > colDate
          ? row[colDate]?.value?.toString().trim() ?? ''
          : '';
      final notes = colNotes >= 0 && row.length > colNotes
          ? row[colNotes]?.value?.toString().trim()
          : null;

      if (category.isEmpty && amountStr == '0') continue; // skip empty rows

      rows.add({
        'category': category,
        'amount': double.tryParse(amountStr) ?? 0,
        'date': dateStr.isNotEmpty ? dateStr : DateTime.now().toIso8601String(),
        'notes': notes,
      });
    }

    if (rows.isEmpty) {
      throw Exception('No valid data rows found in the Excel file');
    }

    return importFromRows(rows);
  }

  /// Get the most recent cash-flow snapshot, or null if none exists.
  Future<CashFlowSnapshot?> getLatest() async {
    final all = await repo.getCashFlowSnapshots();
    if (all.isEmpty) return null;
    return all.first; // already ordered descending by uploadedAt
  }
}
