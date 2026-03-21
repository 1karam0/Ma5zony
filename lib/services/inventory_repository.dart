import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/warehouse.dart';

/// Abstract repository contract for inventory domain data.
/// Swap [MockInventoryRepository] for [FirestoreInventoryRepository] when ready.
abstract class InventoryRepository {
  // ── Read ─────────────────────────────────────────────────────────────────
  Future<List<Product>> getProducts();
  Future<List<Warehouse>> getWarehouses();
  Future<List<Supplier>> getSuppliers();

  /// Returns demand history keyed by productId,
  /// each list sorted ascending by [DomainDemandRecord.periodStart].
  Future<Map<String, List<DomainDemandRecord>>> getDemandHistory();

  // ── Products CRUD ────────────────────────────────────────────────────────
  Future<Product> addProduct(Product product);
  Future<void> updateProduct(Product product);
  Future<void> deleteProduct(String productId);

  // ── Suppliers CRUD ───────────────────────────────────────────────────────
  Future<Supplier> addSupplier(Supplier supplier);
  Future<void> updateSupplier(Supplier supplier);
  Future<void> deleteSupplier(String supplierId);

  // ── Warehouses CRUD ──────────────────────────────────────────────────────
  Future<Warehouse> addWarehouse(Warehouse warehouse);
  Future<void> updateWarehouse(Warehouse warehouse);
  Future<void> deleteWarehouse(String warehouseId);

  // ── Demand Records ───────────────────────────────────────────────────────
  Future<DomainDemandRecord> addDemandRecord(DomainDemandRecord record);
  Future<void> deleteDemandRecord(String recordId);
}
