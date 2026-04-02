import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/supplier_order.dart';
import 'package:ma5zony/models/warehouse.dart';
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

  // ── Purchase Orders ──────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _ordersCol =>
      _db.collection('users').doc(uid).collection('purchaseOrders');

  Future<List<PurchaseOrder>> getPurchaseOrders() async {
    final snap = await _ordersCol.orderBy('createdAt', descending: true).get();
    return snap.docs
        .map((d) => PurchaseOrder.fromFirestore(d.id, d.data()))
        .toList();
  }

  Future<PurchaseOrder> addPurchaseOrder(PurchaseOrder order) async {
    final data = order.toFirestore();
    final docRef = await _ordersCol.add(data);
    return PurchaseOrder.fromFirestore(docRef.id, data);
  }

  Future<void> updatePurchaseOrder(PurchaseOrder order) async {
    await _ordersCol.doc(order.id).update(order.toFirestore());
  }

  Future<void> deletePurchaseOrder(String orderId) async {
    await _ordersCol.doc(orderId).delete();
  }

  // ── Supplier Orders (top-level collection for supplier portal access) ────

  CollectionReference<Map<String, dynamic>> get _supplierOrdersCol =>
      _db.collection('supplierOrders');

  Future<void> addSupplierOrder(SupplierOrder order) async {
    await _supplierOrdersCol.doc(order.id).set(order.toFirestore());
  }

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

  Future<List<SupplierOrder>> getAllSupplierOrders() async {
    final snap = await _supplierOrdersCol
        .where('ownerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((d) => SupplierOrder.fromFirestore(d.id, d.data()))
        .toList();
  }
}
