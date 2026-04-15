import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/cash_flow_snapshot.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/manufacturer.dart';
import 'package:ma5zony/models/manufacturing_recommendation.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/raw_material_order.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/supplier_order.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/models/workflow_log.dart';

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

  // ── Raw Materials CRUD ───────────────────────────────────────────────────
  Future<List<RawMaterial>> getRawMaterials();
  Future<RawMaterial> addRawMaterial(RawMaterial material);
  Future<void> updateRawMaterial(RawMaterial material);
  Future<void> deleteRawMaterial(String materialId);

  // ── Bill of Materials CRUD ───────────────────────────────────────────────
  Future<List<BillOfMaterials>> getBOMs();
  Future<BillOfMaterials> addBOM(BillOfMaterials bom);
  Future<void> updateBOM(BillOfMaterials bom);
  Future<void> deleteBOM(String bomId);

  // ── Manufacturers CRUD ───────────────────────────────────────────────────
  Future<List<Manufacturer>> getManufacturers();
  Future<Manufacturer> addManufacturer(Manufacturer manufacturer);
  Future<void> updateManufacturer(Manufacturer manufacturer);
  Future<void> deleteManufacturer(String manufacturerId);

  // ── Production Orders ────────────────────────────────────────────────────
  Future<List<ProductionOrder>> getProductionOrders();
  Future<ProductionOrder> addProductionOrder(ProductionOrder order);
  Future<void> updateProductionOrder(ProductionOrder order);
  Future<void> deleteProductionOrder(String orderId);

  // ── Raw Material Orders ──────────────────────────────────────────────────
  Future<List<RawMaterialOrder>> getRawMaterialOrders();
  Future<RawMaterialOrder> addRawMaterialOrder(RawMaterialOrder order);
  Future<void> updateRawMaterialOrder(RawMaterialOrder order);

  // ── Manufacturing Recommendations ────────────────────────────────────────
  Future<List<ManufacturingRecommendation>> getManufacturingRecommendations();
  Future<void> saveManufacturingRecommendations(
      List<ManufacturingRecommendation> recs);
  Future<void> updateManufacturingRecommendation(
      ManufacturingRecommendation rec);

  // ── Cash Flow Snapshots ──────────────────────────────────────────────────
  Future<List<CashFlowSnapshot>> getCashFlowSnapshots();
  Future<CashFlowSnapshot> addCashFlowSnapshot(CashFlowSnapshot snapshot);

  // ── Workflow Logs ────────────────────────────────────────────────────────
  Future<List<WorkflowLog>> getWorkflowLogs({String? entityType, String? entityId});
  Future<void> addWorkflowLog(WorkflowLog log);

  // ── Purchase Orders ──────────────────────────────────────────────────────
  Future<List<PurchaseOrder>> getPurchaseOrders();
  Future<PurchaseOrder> addPurchaseOrder(PurchaseOrder order);
  Future<void> updatePurchaseOrder(PurchaseOrder order);
  Future<void> deletePurchaseOrder(String orderId);

  // ── Supplier Orders ──────────────────────────────────────────────────────
  Future<void> addSupplierOrder(SupplierOrder order);
  Future<List<SupplierOrder>> getSupplierOrdersForPurchase(String purchaseOrderId);
  Future<List<SupplierOrder>> getAllSupplierOrders();
}
