import 'dart:math';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/services/inventory_repository.dart';

/// In-memory implementation of [InventoryRepository].
/// Provides rich demo seed data consistent with the existing UI.
/// Replace with an HTTP implementation when connecting a real backend.
class MockInventoryRepository implements InventoryRepository {
  // ── Seed data ──────────────────────────────────────────────────────────────

  final List<Supplier> _suppliers = [
    Supplier(
      id: 's1',
      name: 'Alpha Supply Co.',
      contactEmail: 'john@alpha.com',
      phone: '123-456-7890',
      typicalLeadTimeDays: 5,
    ),
    Supplier(
      id: 's2',
      name: 'Beta Logistics',
      contactEmail: 'jane@beta.com',
      phone: '987-654-3210',
      typicalLeadTimeDays: 14,
    ),
  ];

  final List<Warehouse> _warehouses = [
    Warehouse(
      id: 'w1',
      name: 'Main Warehouse',
      city: 'New York',
      country: 'USA',
      totalStock: 395,
    ),
    Warehouse(
      id: 'w2',
      name: 'West Coast Hub',
      city: 'Los Angeles',
      country: 'USA',
      totalStock: 205,
    ),
  ];

  late final List<Product> _products = [
    Product(
      id: 'p1',
      sku: 'SKU-001',
      name: 'Cotton T-Shirt',
      category: 'Apparel',
      unitCost: 12.50,
      currentStock: 150,
      supplierId: 's1',
      warehouseId: 'w1',
    ),
    Product(
      id: 'p2',
      sku: 'SKU-002',
      name: 'Denim Jeans',
      category: 'Apparel',
      unitCost: 25.00,
      currentStock: 40,
      supplierId: 's2',
      warehouseId: 'w1',
    ),
    Product(
      id: 'p3',
      sku: 'SKU-003',
      name: 'Leather Belt',
      category: 'Accessories',
      unitCost: 15.00,
      currentStock: 200,
      supplierId: 's1',
      warehouseId: 'w2',
    ),
    Product(
      id: 'p4',
      sku: 'SKU-004',
      name: 'Sneakers',
      category: 'Footwear',
      unitCost: 45.00,
      currentStock: 5,
      supplierId: 's2',
      warehouseId: 'w2',
    ),
    Product(
      id: 'p5',
      sku: 'SKU-005',
      name: 'Silk Scarf',
      category: 'Accessories',
      unitCost: 20.00,
      currentStock: 80,
      supplierId: 's1',
      warehouseId: 'w1',
    ),
  ];

  /// Generates 12 months of seeded demand history for each product.
  late final Map<String, List<DomainDemandRecord>> _demandHistory =
      _generateDemandHistory();

  Map<String, List<DomainDemandRecord>> _generateDemandHistory() {
    final rng = Random(42); // fixed seed → deterministic results
    final Map<String, List<DomainDemandRecord>> map = {};

    // Base monthly demand levels per product
    const baseDemand = {'p1': 100, 'p2': 60, 'p3': 40, 'p4': 20, 'p5': 50};

    for (final product in _products) {
      final base = baseDemand[product.id] ?? 50;
      final records = <DomainDemandRecord>[];
      for (int i = 11; i >= 0; i--) {
        final period = DateTime(
          DateTime.now().year,
          DateTime.now().month - i,
          1,
        );
        final qty = (base + rng.nextInt((base * 0.4).toInt()) - base ~/ 5)
            .clamp(1, 9999);
        records.add(
          DomainDemandRecord(
            id: '${product.id}_m$i',
            productId: product.id,
            periodStart: period,
            quantity: qty,
          ),
        );
      }
      map[product.id] = records;
    }
    return map;
  }

  // ── InventoryRepository impl ───────────────────────────────────────────────

  @override
  Future<List<Product>> getProducts() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return List.unmodifiable(_products);
  }

  @override
  Future<List<Warehouse>> getWarehouses() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return List.unmodifiable(_warehouses);
  }

  @override
  Future<List<Supplier>> getSuppliers() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return List.unmodifiable(_suppliers);
  }

  @override
  Future<Map<String, List<DomainDemandRecord>>> getDemandHistory() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return Map.unmodifiable(_demandHistory);
  }

  // ── Mutable helpers (used by Shopify stub) ─────────────────────────────────

  void mergeProducts(List<Product> toMerge) {
    for (final p in toMerge) {
      if (!_products.any((e) => e.id == p.id)) {
        _products.add(p);
      }
    }
  }
}
