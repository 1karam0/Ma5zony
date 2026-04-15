import 'package:ma5zony/models/app_user.dart';

/// Permissions that can be checked against a user's role.
enum Permission {
  viewFinancials,
  viewCosts,
  manageUsers,
  approveOrders,
  editGlobalSettings,
  viewIntegrations,
}

/// Owner-only routes that Inventory Managers cannot access.
const ownerOnlyRoutes = <String>{
  '/financial-analytics',
  '/cash-flow',
};

/// All roles recognised by the system.
abstract class UserRole {
  static const owner = 'SME Owner';
  static const inventoryManager = 'Inventory Manager';
  static const manufacturer = 'Manufacturer';
  static const rawMaterialFactory = 'Raw Material Factory';
}

/// Returns true when [user] holds the given [permission].
bool hasPermission(AppUser? user, Permission permission) {
  if (user == null) return false;

  switch (user.role) {
    case UserRole.owner:
      return true; // Owner has all permissions
    case UserRole.inventoryManager:
      return _inventoryManagerPermissions.contains(permission);
    default:
      return false;
  }
}

/// Returns true when [user] is an SME Owner.
bool isOwner(AppUser? user) => user?.role == UserRole.owner;

/// Returns true when [user] is an Inventory Manager.
bool isInventoryManager(AppUser? user) =>
    user?.role == UserRole.inventoryManager;

/// Permissions granted to Inventory Managers.
const _inventoryManagerPermissions = <Permission>{
  Permission.approveOrders,
  Permission.viewIntegrations,
};
