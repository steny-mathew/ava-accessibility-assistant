import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cognito_auth_service.dart';
import 'ava_theme.dart';

class AuthGate extends StatefulWidget {
  final Widget Function(VoidCallback onSignOut) signedInBuilder;

  const AuthGate({super.key, required this.signedInBuilder});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checkingSession = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final signedIn = await CognitoAuthService.instance.hasValidSession();
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _checkingSession = false;
    });
  }

  void _onSignedIn() => setState(() => _signedIn = true);

  Future<void> _onSignOut() async {
    try {
      await CognitoAuthService.instance.signOut();
    } finally {
      if (mounted) setState(() => _signedIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_signedIn) {
      return widget.signedInBuilder(_onSignOut);
    }
    return AuthScreen(onAuthenticated: _onSignedIn);
  }
}

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeController = TextEditingController();
  final _confirmationCodeFocusNode = FocusNode();

  bool _creatingAccount = false;
  bool _awaitingConfirmation = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    _confirmationCodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final auth = CognitoAuthService.instance;

      if (_awaitingConfirmation) {
        final code = _codeController.text.trim();
        if (code.isEmpty) {
          throw Exception('Enter the confirmation code from your email.');
        }
        if (!RegExp(r'^\d{6}$').hasMatch(code)) {
          throw Exception('Enter the 6-digit code from your email.');
        }
        await auth.confirmSignUp(email, code);
        if (!mounted) return;
        setState(() {
          _awaitingConfirmation = false;
          _creatingAccount = false;
          _codeController.clear();
          _info = 'Email confirmed. Signing in…';
        });
        try {
          await auth.signIn(email, password);
        } on CognitoAuthException catch (error) {
          if (error.code == 'NotAuthorizedException') {
            throw Exception(
              'Your email is confirmed. Sign in with the password you originally chose.',
            );
          }
          rethrow;
        }
        widget.onAuthenticated();
      } else if (_creatingAccount) {
        if (password != _confirmPasswordController.text) {
          throw Exception('The passwords do not match.');
        }
        final result = await auth.signUpOrResumeConfirmation(email, password);
        if (!mounted) return;
        switch (result) {
          case CognitoSignUpResult.confirmationSent:
            _showConfirmationStep(
              'Enter the confirmation code Cognito emailed to you.',
            );
          case CognitoSignUpResult.confirmationResent:
            _showConfirmationStep(
              'An unverified account already exists. We sent a fresh code. '
              'After confirming, sign in with the password you originally chose.',
            );
          case CognitoSignUpResult.alreadyConfirmed:
            setState(() {
              _creatingAccount = false;
              _awaitingConfirmation = false;
              _confirmPasswordController.clear();
              _info = 'This email is already verified. Sign in with your existing password.';
            });
        }
      } else {
        await auth.signIn(email, password);
        widget.onAuthenticated();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showConfirmationStep(String message) {
    setState(() {
      _awaitingConfirmation = true;
      _info = message;
      _error = null;
      _codeController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _confirmationCodeFocusNode.requestFocus();
    });
  }

  Future<void> _resendCode() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await CognitoAuthService.instance.resendConfirmationCode(
        _emailController.text.trim(),
      );
      if (mounted) {
        setState(() => _info = 'A new confirmation code was sent.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _creatingAccount = !_creatingAccount;
      _awaitingConfirmation = false;
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _awaitingConfirmation;
    final title = confirming
        ? 'Check your email'
        : _creatingAccount
        ? 'Create your Ava account'
        : 'Welcome to Ava';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AvaColors.sage,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.spa_outlined,
                      color: AvaColors.primary,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AvaColors.ink,
                    fontSize: 29,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  confirming
                      ? 'We sent a one-time code to ${_emailController.text.trim()}.'
                      : 'Sign in securely to use Ava’s AWS accessibility tools.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AvaColors.muted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _emailController,
                  enabled: !_busy && !confirming,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                if (!confirming) ...[
                  TextField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: _hidePassword,
                    autofillHints: _creatingAccount
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_creatingAccount) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'At least 8 characters, with uppercase, lowercase, and a number.',
                      style: TextStyle(color: AvaColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmPasswordController,
                      enabled: !_busy,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ] else ...[
                  TextField(
                    controller: _codeController,
                    focusNode: _confirmationCodeFocusNode,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType:
                        kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.macOS ||
                                defaultTargetPlatform ==
                                    TargetPlatform.windows ||
                                defaultTargetPlatform == TargetPlatform.linux)
                        ? TextInputType.text
                        : TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    maxLength: 6,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Email confirmation code',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: AvaColors.danger),
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _info!,
                    style: const TextStyle(color: AvaColors.primary),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          confirming
                              ? 'Confirm email and continue'
                              : _creatingAccount
                              ? 'Create account'
                              : 'Sign in',
                        ),
                ),
                if (confirming)
                  TextButton(
                    onPressed: _busy ? null : _resendCode,
                    child: const Text('Resend confirmation code'),
                  )
                else
                  TextButton(
                    onPressed: _busy ? null : _toggleMode,
                    child: Text(
                      _creatingAccount
                          ? 'Already have an account? Sign in'
                          : 'New to Ava? Create an account',
                    ),
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Your password is sent securely to Amazon Cognito. Ava keeps your sign-in session on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AvaColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
