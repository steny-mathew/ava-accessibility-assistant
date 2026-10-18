import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cognito_auth_service.dart';

class ItemMemoryService {
  static const _apiBaseUrl = String.fromEnvironment('AVA_API_BASE_URL');

  Future<void> remember(String itemName, String location) async {
    await _request({
      'action': 'remember',
      'itemName': itemName.trim(),
      'location': location.trim(),
    });
  }

  Future<Map<String, dynamic>> recall(String itemName) =>
      _request({'action': 'recall', 'itemName': itemName.trim()});

  Future<void> forget(String itemName) async {
    await _request({'action': 'forget', 'itemName': itemName.trim()});
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    if (_apiBaseUrl.isEmpty) {
      throw Exception(
        'Ava is not connected yet. Configure AVA_API_BASE_URL and restart the app.',
      );
    }

    final response = await http
        .post(
          Uri.parse(_apiBaseUrl).resolve('/item-memory'),
          headers: await CognitoAuthService.instance.authorizationHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception('Ava received an invalid response from the service.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String? ?? 'Request failed'
          : 'Request failed';
      throw Exception('$message (${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Ava received an invalid response from the service.');
    }
    return decoded;
  }
}
