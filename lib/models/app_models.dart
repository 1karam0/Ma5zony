class User {
  final String id;
  final String name;
  final String email;
  final String role; // 'SME Owner', 'Inventory Manager'

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });
}

class Product {
  final String id;
  final String sku;
  final String name;
  final String category;
  final String uom;
  final double standardCost;
  final double orderingCost;
  final double holdingCost;
  final double targetServiceLevel;
  final String defaultSupplierId;

  // Inventory logic
  int currentStock;
  int reorderPoint;
  int safetyStock;
  int eoq;

  Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.uom,
    required this.standardCost,
    this.orderingCost = 50.0,
    this.holdingCost = 10.0,
    this.targetServiceLevel = 0.95,
    required this.defaultSupplierId,
    this.currentStock = 0,
    this.reorderPoint = 10,
    this.safetyStock = 5,
    this.eoq = 50,
  });

  String get status {
    if (currentStock == 0) return 'Critical';
    if (currentStock <= reorderPoint) return 'Low';
    return 'OK';
  }
}

class Supplier {
  final String id;
  final String name;
  final String contactPerson;
  final String email;
  final String phone;
  final int leadTimeDays;
  final String notes;

  Supplier({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.email,
    required this.phone,
    required this.leadTimeDays,
    this.notes = '',
  });
}

class Warehouse {
  final String id;
  final String name;
  final String location;
  final String status; // 'Active', 'Inactive'

  Warehouse({
    required this.id,
    required this.name,
    required this.location,
    this.status = 'Active',
  });
}

class DemandRecord {
  final String id;
  final String productId;
  final DateTime date;
  final int quantity;
  final String source; // 'Imported', 'Manual'

  DemandRecord({
    required this.id,
    required this.productId,
    required this.date,
    required this.quantity,
    required this.source,
  });
}

class ForecastRecord {
  final DateTime period;
  final int actual; // 0 if future
  final int forecast;
  final double error; // |A - F|

  ForecastRecord({
    required this.period,
    required this.actual,
    required this.forecast,
    required this.error,
  });
}
