import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/warehouse.dart';

/// Abstract repository contract for inventory domain data.
/// Swap [MockInventoryRepository] for a real HTTP implementation when ready.
abstract class InventoryRepository {
  Future<List<Product>> getProducts();
  Future<List<Warehouse>> getWarehouses();
  Future<List<Supplier>> getSuppliers();

  /// Returns demand history keyed by productId,
  /// each list sorted ascending by [DomainDemandRecord.periodStart].
  Future<Map<String, List<DomainDemandRecord>>> getDemandHistory();
}
