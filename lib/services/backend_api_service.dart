import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:ma5zony/utils/api_config.dart';

/// HTTP client for the Ma5zony backend API.
///
/// Automatically injects the Firebase Auth ID token on every request.
/// All methods throw [BackendException] on non-2xx responses.
class BackendApiService {
  final String _baseUrl;

  BackendApiService({String? baseUrl})
      : _baseUrl = baseUrl ?? ApiConfig.backendUrl;

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Generic HTTP helpers ───────────────────────────────────────────────

  Future<dynamic> _get(String path) async {
    final res = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
    );
    return _handleResponse(res);
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final res = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(res);
  }

  Future<dynamic> _patch(String path, [Map<String, dynamic>? body]) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(res);
  }

  Future<dynamic> _delete(String path) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
    );
    return _handleResponse(res);
  }

  dynamic _handleResponse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String message;
    try {
      final body = jsonDecode(res.body);
      message = body['error'] ?? body['message'] ?? res.body;
    } catch (_) {
      message = res.body;
    }
    throw BackendException(res.statusCode, message);
  }

  // ── Forecasting ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> runForecast({
    required String productId,
    required String method,
    int? windowSize,
    double? alpha,
  }) async {
    return await _post('/api/forecasts/run', {
      'productId': productId,
      'method': method,
      if (windowSize != null) 'windowSize': windowSize,
      if (alpha != null) 'alpha': alpha,
    });
  }

  // ── Replenishment ──────────────────────────────────────────────────────

  Future<List<dynamic>> runReplenishment({
    required List<String> productIds,
    required double annualDemand,
    required double orderingCost,
    required double holdingCost,
    required double demandStdDev,
    required double zFactor,
  }) async {
    return await _post('/api/replenishment/run', {
      'productIds': productIds,
      'annualDemand': annualDemand,
      'orderingCost': orderingCost,
      'holdingCost': holdingCost,
      'demandStdDev': demandStdDev,
      'zFactor': zFactor,
    });
  }

  // ── Manufacturing Recommendations ──────────────────────────────────────

  Future<List<dynamic>> generateRecommendations() async {
    return await _post('/api/recommendations/generate');
  }

  Future<Map<String, dynamic>> approveRecommendation(
    String recId, {
    String? performedBy,
  }) async {
    return await _patch('/api/recommendations/$recId/approve', {
      if (performedBy != null) 'performedBy': performedBy,
    });
  }

  Future<Map<String, dynamic>> rejectRecommendation(
    String recId, {
    String? performedBy,
  }) async {
    return await _patch('/api/recommendations/$recId/reject', {
      if (performedBy != null) 'performedBy': performedBy,
    });
  }

  // ── Production Orders ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> createProductionOrder({
    required String finalProductId,
    required int quantity,
    required String manufacturerId,
    double estimatedCost = 0,
  }) async {
    return await _post('/api/production-orders', {
      'finalProductId': finalProductId,
      'quantity': quantity,
      'manufacturerId': manufacturerId,
      'estimatedCost': estimatedCost,
    });
  }

  /// Approve a production order and auto-create raw material orders from BOM.
  Future<Map<String, dynamic>> approveProductionOrder(String orderId) async {
    return await _post('/api/production-orders/$orderId/approve');
  }

  Future<Map<String, dynamic>> updateProductionOrderStatus(
    String orderId,
    String status, {
    String? performedBy,
  }) async {
    return await _patch('/api/production-orders/$orderId/status', {
      'status': status,
      if (performedBy != null) 'performedBy': performedBy,
    });
  }

  Future<Map<String, dynamic>> deleteProductionOrder(String orderId) async {
    return await _delete('/api/production-orders/$orderId');
  }

  // ── Raw Material Orders ────────────────────────────────────────────────

  Future<Map<String, dynamic>> updateRawMaterialOrderStatus(
    String orderId,
    String status, {
    String? performedBy,
  }) async {
    return await _patch('/api/raw-material-orders/$orderId/status', {
      'status': status,
      if (performedBy != null) 'performedBy': performedBy,
    });
  }

  // ── Cash Flow ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadCashFlowSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    return await _post('/api/cash-flow', snapshot);
  }

  // ── Health ─────────────────────────────────────────────────────────────

  Future<bool> isHealthy() async {
    try {
      await _get('/');
      return true;
    } catch (_) {
      return false;
    }
  }
}

class BackendException implements Exception {
  final int statusCode;
  final String message;
  BackendException(this.statusCode, this.message);

  @override
  String toString() => 'BackendException($statusCode): $message';
}
