import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../storage.dart';
import 'face_capture_screen.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  // Errors where the user can simply retake the photo.
  static const _retryableFaceCodes = {
    'FACE_MISMATCH', 'NO_FACE', 'MULTIPLE_FACES', 'FACE_TOO_SMALL',
    'LOW_QUALITY', 'INVALID_IMAGE',
  };

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _showMessage(String title, String message) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _askRetry(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Face verification failed'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Try again')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    String faceToken;
    try {
      faceToken = await login(_email.text.trim().toLowerCase(), _password.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      switch (e.code) {
        case 'ACCOUNT_PENDING':
          await _showMessage(
            'Pending review',
            'Your account is still waiting for admin approval. Please try again later.',
          );
        case 'ACCOUNT_REJECTED':
          final reason = (e.reason != null && e.reason!.isNotEmpty) ? e.reason! : 'No reason given.';
          await _showMessage('Registration rejected', 'Your registration was rejected.\n\nReason: $reason');
        case 'ACCOUNT_SUSPENDED':
          await _showMessage('Account suspended', 'Your account has been suspended. Contact an administrator.');
        default:
          await _showMessage('Login failed', e.message);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    await _verifyFaceLoop(faceToken);
  }

  /// Opens the camera, verifies, and lets the user retry while the
  /// face_token is still valid (5 minutes).
  Future<void> _verifyFaceLoop(String faceToken) async {
    while (true) {
      final bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => const FaceCaptureScreen(title: 'Verify your face'),
        ),
      );
      if (bytes == null || !mounted) return; // user went back

      setState(() => _loading = true);
      try {
        final session = await verifyFace(faceToken: faceToken, image: bytes);
        await TokenStorage.save(session);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => screenForRole(session.role, session.fullName),
          ),
          (route) => false,
        );
        return;
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        if (_retryableFaceCodes.contains(e.code)) {
          if (!await _askRetry(e.message)) return;
          if (!mounted) return;
          continue;
        }
        if (e.code == 'TOKEN_EXPIRED') {
          await _showMessage('Session expired', 'Too much time passed. Please log in again.');
        } else {
          await _showMessage('Login failed', e.message);
        }
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ugnay',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('Cooperative management', textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Log in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegisterScreen()),
                              ),
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}