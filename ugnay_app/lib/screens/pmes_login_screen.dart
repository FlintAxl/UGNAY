import 'package:flutter/material.dart';

import '../api_client.dart';
import '../pmes_api.dart';
import 'pmes_application_screen.dart';

/// Limited login for PMES applicants: email + password, no face check.
/// Pending registrants can use this while waiting for admin approval.
class PmesLoginScreen extends StatefulWidget {
  final String initialEmail;

  const PmesLoginScreen({super.key, this.initialEmail = ''});

  @override
  State<PmesLoginScreen> createState() => _PmesLoginScreenState();
}

class _PmesLoginScreenState extends State<PmesLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await pmesLogin(
        _email.text.trim().toLowerCase(),
        _password.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PmesApplicationScreen(
            pmesToken: result.token,
            email: result.email,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final reason = (e.reason != null && e.reason!.isNotEmpty) ? '\n\nReason: ${e.reason}' : '';
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(e.code == 'INVALID_CREDENTIALS' ? 'Login failed' : 'Cannot apply for PMES'),
          content: Text('${e.message}$reason'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for PMES')),
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
                    const Icon(Icons.school_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'PMES Application',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'For aspiring cooperative members. Use the same email and password you registered with.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('PMES schedule: Saturdays only'),
                            SizedBox(height: 4),
                            Text('Venue: PRIC Cooperative, Barangay Pinagdanlayan, Dolores, Quezon'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter your email' : null,
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
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
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
