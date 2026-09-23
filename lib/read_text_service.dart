import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

class ReadTextService {
  static const _apiBaseUrl = String.fromEnvironment('AVA_API_BASE_URL');

  Future<String> readImage(XFile image) async {
    if (_apiBaseUrl.isEmpty) {
      throw Exception(
        'Ava is not connected yet. Configure AVA_API_BASE_URL and restart the app.',
      );
    }

    final contentType = _contentType(image.path);
    final baseUri = Uri.parse(_apiBaseUrl);
    final requestHeaders = {'Content-Type': 'application/json'};
    final uploadResponse = await http
        .post(
          baseUri.resolve('/upload-url'),
          headers: requestHeaders,
          body: jsonEncode({'contentType': contentType}),
        )
        .timeout(const Duration(seconds: 20));
    final upload = _decodeResponse(uploadResponse);

    final imageBytes = await image.readAsBytes();
    final putResponse = await http
        .put(
          Uri.parse(upload['uploadUrl'] as String),
          headers: {'Content-Type': contentType},
          body: imageBytes,
        )
        .timeout(const Duration(seconds: 60));
    if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
      throw Exception('Image upload failed (${putResponse.statusCode}).');
    }

    final textResponse = await http
        .post(
          baseUri.resolve('/read-text'),
          headers: requestHeaders,
          body: jsonEncode({'bucket': upload['bucket'], 'key': upload['key']}),
        )
        .timeout(const Duration(seconds: 60));
    final result = _decodeResponse(textResponse);
    return (result['text'] as String?)?.trim() ?? '';
  }

  String _contentType(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
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
