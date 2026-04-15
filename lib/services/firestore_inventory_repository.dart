import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:ma5zony/services/inventory_repository.dart';

/// Firestore-backed implementation of [InventoryRepository].
/// All data is scoped under `users/{uid}/`.
class FirestoreInventoryRepository implements InventoryRepository {
  final FirebaseFirestore _db;
  final String uid;

  FirestoreInventoryRepository({required this.uid, FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ── Collection references ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _productsCol =>
      _db.collection('users').doc(uid).collection('products');

  CollectionReference<Map<String, dynamic>> get _suppliersCol =>
      _db.collection('users').doc(uid).collection('suppliers');

  CollectionReference<Map<String, dynamic>> get _warehousesCol =>
      _db.collection('users').doc(uid).collection('warehouses');

  CollectionReference<Map<String, dynamic>> get _demandCol =>
      _db.collection('users').doc(uid).collection('demandRecords');

  // ── Read ─────────────────────────────────────────────────────────────────

  @override
  Future<List<Product>> getProducts() async {
    final snap = await _productsCol.get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return Product.fromJson(data);
    }).toList();
  }

  @override
  Future<List<Warehouse>> getWarehouses() async {
    final snap = await _warehousesCol.get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return Warehouse.fromJson(data);
    }).toList();
  }

  @override
  Future<List<Supplier>> getSuppliers() async {
    final snap = await _suppliersCol.get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return Supplier.fromJson(data);
    }).toList();
  }

  @override
  Future<Map<String, List<DomainDemandRecord>>> getDemandHistory() async {
    final snap = await _demandCol.orderBy('periodStart').get();
    final map = <String, List<DomainDemandRecord>>{};
    for (final d in snap.docs) {
      final data = d.data();
      data['id'] = d.id;
      // Handle Firestore Timestamps
      if (data['periodStart'] is Timestamp) {
        data['periodStart'] =
            (data['periodStart'] as Timestamp).toDate().toIso8601String();
      }
      final record = DomainDemandRecord.fromJson(data);
      map.putIfAbsent(record.productId, () => []).add(record);
    }
    return map;
  }

  // ── Products CRUD ────────────────────────────────────────────────────────

  @override
  Future<Product> addProduct(Product product) async {
    final data = product.toJson();
    data.remove('id'); // let Firestore generate the ID
    final docRef = await _productsCol.add(data);
    return Product.fromJson({...data, 'id': docRef.id});
  }

  @override
  Future<void> updateProduct(Product product) async {
    final data = product.toJson();
    data.remove('id');
    await _productsCol.doc(product.id).update(data);
  }

  @override
  Future<void> deleteProduct(String productId) async {
    await _productsCol.doc(productId).delete();
  }

  // ── Suppliers CRUD ───────────────────────────────────────────────────────

  @override
  Future<Supplier> addSupplier(Supplier supplier) async {
    final data = supplier.toJson();
    data.remove('id');
    final docRef = await _suppliersCol.add(data);
    return Supplier.fromJson({...data, 'id': docRef.id});
  }

  @override
  Future<void> updateSupplier(Supplier supplier) async {
    final data = supplier.toJson();
    data.remove('id');
    await _suppliersCol.doc(supplier.id).update(data);
  }

  @override
  Future<void> deleteSupplier(String supplierId) async {
    await _suppliersCol.doc(supplierId).delete();
  }

  // ── Warehouses CRUD ──────────────────────────────────────────────────────

  @override
  Future<Warehouse> addWarehouse(Warehouse warehouse) async {
    final data = warehouse.toJson();
    data.remove('id');
    final docRef = await _warehousesCol.add(data);
    return Warehouse.fromJson({...data, 'id': docRef.id});
  }

  @override
  Future<void> updateWarehouse(Warehouse warehouse) async {
    final data = warehouse.toJson();
    data.remove('id');
    await _warehousesCol.doc(warehouse.id).update(data);
  }

  @override
  Future<void> deleteWarehouse(String warehouseId) async {
    await _warehousesCol.doc(warehouseId).delete();
  }

  // ── Demand Records ───────────────────────────────────────────────────────

  @override
  Future<DomainDemandRecord> addDemandRecord(DomainDemandRecord record) async {
    final data = record.toJson();
    data.remove('id');
    // Store as Firestore Timestamp for proper ordering
    data['periodStart'] = Timestamp.fromDate(record.periodStart);
    final docRef = await _demandCol.add(data);
    return DomainDemandRecord(
      id: docRef.id,
      productId: record.productId,
      periodStart: record.periodStart,
      quantity: record.quantity,
    );
  }

  @override
  Future<void> deleteDemandRecord(String recordId) async {
    await _demandCol.doc(recordId).delete();
  }

  // ── Raw Materials CRUD ───────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _rawMaterialsCol =>
      _db.collection('users').doc(uid).collection('rawMaterials');

  @override
  Future<List<RawMaterial>> getRawMaterials() async {
    final snap = await _rawMaterialsCol.get();
    return snap.docs
        .map((d) => RawMaterial.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<RawMaterial> addRawMaterial(RawMaterial material) async {
    final data = material.toFirestore();
    final docRef = await _rawMaterialsCol.add(data);
    return RawMaterial.fromFirestore(docRef.id, data);
  }

  @override
  Future<void> updateRawMaterial(RawMaterial material) async {
    await _rawMaterialsCol.doc(material.id).update(material.toFirestore());
  }

  @override
  Future<void> deleteRawMaterial(String materialId) async {
    await _rawMaterialsCol.doc(materialId).delete();
  }

  // ── Bill of Materials CRUD ───────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _bomsCol =>
      _db.collection('users').doc(uid).collection('boms');

  @override
  Future<List<BillOfMaterials>> getBOMs() async {
    final snap = await _bomsCol.get();
    return snap.docs
        .map((d) => BillOfMaterials.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<BillOfMaterials> addBOM(BillOfMaterials bom) async {
    final data = bom.toFirestore();
    final docRef = await _bomsCol.add(data);
    return BillOfMaterials.fromFirestore(docRef.id, data);
  }

  @override
  Future<void> updateBOM(BillOfMaterials bom) async {
    await _bomsCol.doc(bom.id).update(bom.toFirestore());
  }

  @override
  Future<void> deleteBOM(String bomId) async {
    await _bomsCol.doc(bomId).delete();
  }

  // ── Manufacturers CRUD ───────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _manufacturersCol =>
      _db.collection('users').doc(uid).collection('manufacturers');

  @override
  Future<List<Manufacturer>> getManufacturers() async {
    final snap = await _manufacturersCol.get();
    return snap.docs
        .map((d) => Manufacturer.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<Manufacturer> addManufacturer(Manufacturer manufacturer) async {
    final data = manufacturer.toFirestore();
    final docRef = await _manufacturersCol.add(data);
    return Manufacturer.fromFirestore(docRef.id, data);
  }

  @override
  Future<void> updateManufacturer(Manufacturer manufacturer) async {
    await _manufacturersCol
        .doc(manufacturer.id)
        .update(manufacturer.toFirestore());
  }

  @override
  Future<void> deleteManufacturer(String manufacturerId) async {
    await _manufacturersCol.doc(manufacturerId).delete();
  }

  // ── Production Orders ────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _productionOrdersCol =>
      _db.collection('users').doc(uid).collection('productionOrders');

  @override
  Future<List<ProductionOrder>> getProductionOrders() async {
    final snap =
        await _productionOrdersCol.orderBy('createdAt', descending: true).get();
    return snap.docs
        .map((d) => ProductionOrder.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<ProductionOrder> addProductionOrder(ProductionOrder order) async {
    final data = order.toFirestore();
    final docRef = await _productionOrdersCol.add(data);
    return ProductionOrder.fromFirestore(docRef.id, data);
  }

  @override
  Future<void> updateProductionOrder(ProductionOrder order) async {
    await _productionOrdersCol.doc(order.id).update(order.toFirestore());
  }

  @override
  Future<void> deleteProductionOrder(String orderId) async {
    await _productionOrdersCol.doc(orderId).delete();
  }

  // ── Raw Material Orders ──────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _rawMaterialOrdersCol =>
      _db.collection('users').doc(uid).collection('rawMaterialOrders');

  @override
  Future<List<RawMaterialOrder>> getRawMaterialOrders() async {
    final snap = await _rawMaterialOrdersCol
        .orderBy('requestedDate', descending: true)
        .get();
    return snap.docs
        .map((d) => RawMaterialOrder.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<RawMaterialOrder> addRawMaterialOrder(RawMaterialOrder order) async {
    final data = order.toFirestore();
    final docRef = await _rawMaterialOrdersCol.add(data);
    return RawMaterialOrder.fromFirestore(docRef.id, data);
  }

  @override
  Future<void> updateRawMaterialOrder(RawMaterialOrder order) async {
    await _rawMaterialOrdersCol.doc(order.id).update(order.toFirestore());
  }

  // ── Manufacturing Recommendations ────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _mfgRecsCol =>
      _db.collection('users').doc(uid).collection('manufacturingRecommendations');

  @override
  Future<List<ManufacturingRecommendation>>
      getManufacturingRecommendations() async {
    final snap = await _mfgRecsCol.get();
    return snap.docs
        .map((d) => ManufacturingRecommendation.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<void> saveManufacturingRecommendations(
      List<ManufacturingRecommendation> recs) async {
    // Delete existing pending recs, then add new ones
    final existing = await _mfgRecsCol
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
    for (final rec in recs) {
      await _mfgRecsCol.doc(rec.id).set(rec.toFirestore());
    }
  }

  @override
  Future<void> updateManufacturingRecommendation(
      ManufacturingRecommendation rec) async {
    await _mfgRecsCol.doc(rec.id).update(rec.toFirestore());
  }

  // ── Cash Flow Snapshots ──────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _cashFlowCol =>
      _db.collection('users').doc(uid).collection('cashFlowSnapshots');

  @override
  Future<List<CashFlowSnapshot>> getCashFlowSnapshots() async {
    final snap =
        await _cashFlowCol.orderBy('uploadedAt', descending: true).get();
    return snap.docs
        .map((d) => CashFlowSnapshot.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<CashFlowSnapshot> addCashFlowSnapshot(
      CashFlowSnapshot snapshot) async {
    final data = snapshot.toFirestore();
    final docRef = await _cashFlowCol.add(data);
    return CashFlowSnapshot.fromFirestore(docRef.id, data);
  }

  // ── Workflow Logs ────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _workflowLogsCol =>
      _db.collection('users').doc(uid).collection('workflowLogs');

  @override
  Future<List<WorkflowLog>> getWorkflowLogs(
      {String? entityType, String? entityId}) async {
    Query<Map<String, dynamic>> query = _workflowLogsCol;
    if (entityType != null) {
      query = query.where('entityType', isEqualTo: entityType);
    }
    if (entityId != null) {
      query = query.where('entityId', isEqualTo: entityId);
    }
    final snap =
        await query.orderBy('timestamp', descending: true).get();
    return snap.docs
        .map((d) => WorkflowLog.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<void> addWorkflowLog(WorkflowLog log) async {
    await _workflowLogsCol.doc(log.id).set(log.toFirestore());
  }

  // ── Purchase Orders ──────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _ordersCol =>
      _db.collection('users').doc(uid).collection('purchaseOrders');

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders() async {
    final snap = await _ordersCol.orderBy('createdAt', descending: true).get();
    return snap.docs
        .map((d) => PurchaseOrder.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<PurchaseOrder> addPurchaseOrder(PurchaseOrder order) async {
    final data = order.toFirestore();
    final docRef = await _ordersCol.add(data);
    return PurchaseOrder.fromFirestore(docRef.id, data);
  }

  @override
  Future<void> updatePurchaseOrder(PurchaseOrder order) async {
    await _ordersCol.doc(order.id).update(order.toFirestore());
  }

  @override
  Future<void> deletePurchaseOrder(String orderId) async {
    await _ordersCol.doc(orderId).delete();
  }

  // ── Supplier Orders (top-level collection for supplier portal access) ────

  CollectionReference<Map<String, dynamic>> get _supplierOrdersCol =>
      _db.collection('supplierOrders');

  @override
  Future<void> addSupplierOrder(SupplierOrder order) async {
    await _supplierOrdersCol.doc(order.id).set(order.toFirestore());
  }

  @override
  Future<List<SupplierOrder>> getSupplierOrdersForPurchase(
      String purchaseOrderId) async {
    final snap = await _supplierOrdersCol
        .where('purchaseOrderId', isEqualTo: purchaseOrderId)
        .where('ownerUid', isEqualTo: uid)
        .get();
    return snap.docs
        .map((d) => SupplierOrder.fromFirestore(d.id, d.data()))
        .toList();
  }

  @override
  Future<List<SupplierOrder>> getAllSupplierOrders() async {
    final snap = await _supplierOrdersCol
        .where('ownerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((d) => SupplierOrder.fromFirestore(d.id, d.data()))
        .toList();
  }

  // ── Factory Orders (top-level for factory portal access) ─────────────────

  CollectionReference<Map<String, dynamic>> get _factoryOrdersCol =>
      _db.collection('factoryOrders');

  /// Create a factory order document in the top-level collection
  /// so factories can access it via their portal token.
  Future<String> addFactoryOrder(Map<String, dynamic> data) async {
    data['ownerUid'] = uid;
    data['createdAt'] = FieldValue.serverTimestamp();
    final docRef = await _factoryOrdersCol.add(data);
    return docRef.id;
  }

  // ── Manufacturer Orders (top-level for manufacturer portal access) ───────

  CollectionReference<Map<String, dynamic>> get _manufacturerOrdersCol =>
      _db.collection('manufacturerOrders');

  /// Create a manufacturer order document in the top-level collection
  /// so manufacturers can access it via their portal token.
  Future<String> addManufacturerOrder(Map<String, dynamic> data) async {
    data['ownerUid'] = uid;
    data['createdAt'] = FieldValue.serverTimestamp();
    final docRef = await _manufacturerOrdersCol.add(data);
    return docRef.id;
  }
}
