import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Cognito public-client authentication. The app client intentionally has no
/// client secret; refresh and ID tokens are stored in the platform's secure
/// storage (Keychain on iOS).
class CognitoAuthService {
  CognitoAuthService._();

  static final CognitoAuthService instance = CognitoAuthService._();

  static const _region = 'us-east-1';
  static const _userPoolId = String.fromEnvironment('AVA_COGNITO_USER_POOL_ID');
  static const _clientId = String.fromEnvironment('AVA_COGNITO_CLIENT_ID');
  static const _idTokenKey = 'ava.cognito.idToken';
  static const _refreshTokenKey = 'ava.cognito.refreshToken';
  static const _storage = FlutterSecureStorage();

  static final Uri _endpoint = Uri.https(
    'cognito-idp.$_region.amazonaws.com',
    '/',
  );

  bool get isConfigured => _userPoolId.isNotEmpty && _clientId.isNotEmpty;

  Future<void> signUp(String email, String password) async {
    _requireConfiguration();
    await _request('SignUp', {
      'ClientId': _clientId,
      'Username': email.trim().toLowerCase(),
      'Password': password,
      'UserAttributes': [
        {'Name': 'email', 'Value': email.trim().toLowerCase()},
      ],
    });
  }

  Future<void> confirmSignUp(String email, String code) async {
    _requireConfiguration();
    await _request('ConfirmSignUp', {
      'ClientId': _clientId,
      'Username': email.trim().toLowerCase(),
      'ConfirmationCode': code.trim(),
    });
  }

  Future<void> resendConfirmationCode(String email) async {
    _requireConfiguration();
    await _request('ResendConfirmationCode', {
      'ClientId': _clientId,
      'Username': email.trim().toLowerCase(),
    });
  }

  Future<void> signIn(String email, String password) async {
    _requireConfiguration();
    final result = await _request('InitiateAuth', {
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'ClientId': _clientId,
      'AuthParameters': {
        'USERNAME': email.trim().toLowerCase(),
        'PASSWORD': password,
      },
    });

    final authentication = result['AuthenticationResult'];
    if (authentication is! Map<String, dynamic> ||
        authentication['IdToken'] is! String ||
        authentication['RefreshToken'] is! String) {
      throw Exception('Cognito did not return a complete sign-in session.');
    }

    await _storage.write(
      key: _idTokenKey,
      value: authentication['IdToken'] as String,
    );
    await _storage.write(
      key: _refreshTokenKey,
      value: authentication['RefreshToken'] as String,
    );
  }

  Future<bool> hasValidSession() async {
    try {
      await _validIdToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> authorizationHeaders() async {
    final token = await _validIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<void> signOut() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    try {
      if (refreshToken != null && isConfigured) {
        await _request('RevokeToken', {
          'ClientId': _clientId,
          'Token': refreshToken,
        });
      }
    } finally {
      await _storage.delete(key: _idTokenKey);
      await _storage.delete(key: _refreshTokenKey);
    }
  }

  Future<String> _validIdToken() async {
    _requireConfiguration();
    final idToken = await _storage.read(key: _idTokenKey);
    if (idToken != null && !_expiresSoon(idToken)) return idToken;

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      throw Exception('Sign in to Ava to use its AWS services.');
    }

    try {
      final result = await _request('InitiateAuth', {
        'AuthFlow': 'REFRESH_TOKEN_AUTH',
        'ClientId': _clientId,
        'AuthParameters': {'REFRESH_TOKEN': refreshToken},
      });
      final authentication = result['AuthenticationResult'];
      if (authentication is! Map<String, dynamic> ||
          authentication['IdToken'] is! String) {
        throw Exception('Cognito did not refresh the sign-in session.');
      }
      final refreshedIdToken = authentication['IdToken'] as String;
      await _storage.write(key: _idTokenKey, value: refreshedIdToken);
      final rotatedRefreshToken = authentication['RefreshToken'];
      if (rotatedRefreshToken is String) {
        await _storage.write(key: _refreshTokenKey, value: rotatedRefreshToken);
      }
      return refreshedIdToken;
    } catch (_) {
      await _storage.delete(key: _idTokenKey);
      await _storage.delete(key: _refreshTokenKey);
      throw Exception('Your Ava session expired. Please sign in again.');
    }
  }

  bool _expiresSoon(String token) {
    try {
      final segments = token.split('.');
      if (segments.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      ) as Map<String, dynamic>;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as num).toInt() * 1000,
      );
      return expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 1)));
    } catch (_) {
      return true;
    }
  }

  Future<Map<String, dynamic>> _request(
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          _endpoint,
          headers: {
            'Content-Type': 'application/x-amz-json-1.1',
            'X-Amz-Target': 'AWSCognitoIdentityProviderService.$operation',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception('Ava received an invalid response from Cognito.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map<String, dynamic> ? decoded : const {};
      final type = (error['__type'] as String? ?? '').split('#').last;
      final message = switch (type) {
        'NotAuthorizedException' => 'The email or password is incorrect.',
        'UserNotFoundException' => 'No Ava account was found for that email.',
        'UserNotConfirmedException' =>
          'Confirm your email address with the code we sent you.',
        'UsernameExistsException' =>
          'An account already exists for that email.',
        'CodeMismatchException' => 'That confirmation code is incorrect.',
        'ExpiredCodeException' => 'That confirmation code has expired.',
        'InvalidPasswordException' => 'Use at least 8 characters, including uppercase, lowercase, and a number.',
        'InvalidParameterException' =>
          error['message'] as String? ?? 'Check the information and try again.',
        'TooManyRequestsException' || 'LimitExceededException' =>
          'Too many attempts. Wait a little and try again.',
        _ => error['message'] as String? ?? 'Cognito request failed.',
      };
      throw Exception(message);
    }

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Ava received an invalid response from Cognito.');
    }
    return decoded;
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw Exception(
        'Ava sign-in is not configured. Rebuild with the Cognito pool and client IDs.',
      );
    }
  }
}
