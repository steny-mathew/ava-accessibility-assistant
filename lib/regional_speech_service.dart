import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cognito_auth_service.dart';

class RegionalSpeechService {
  static const _apiBaseUrl = String.fromEnvironment('AVA_API_BASE_URL');

  Future<Uint8List> synthesize(
    String text, {
    required String languageCode,
  }) async {
    if (_apiBaseUrl.isEmpty) {
      throw Exception('Ava is not connected to its speech service yet.');
    }

    final response = await http
        .post(
          Uri.parse(_apiBaseUrl).resolve('/speak'),
          headers: {
            ...await CognitoAuthService.instance.authorizationHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'text': text, 'languageCode': languageCode}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Regional speech could not be generated.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['error'] is String) {
          message = decoded['error'] as String;
        }
      } on FormatException {
        // Keep the friendly fallback for non-JSON errors from the API.
      }
      throw Exception('$message (${response.statusCode}).');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('audio/wav') || response.bodyBytes.isEmpty) {
      throw Exception('Ava received an invalid audio response.');
    }
    return response.bodyBytes;
  }
}
