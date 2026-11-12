import 'package:flutter/material.dart';

import '../storage.dart';
import '../widgets/app_footer.dart';
import 'home_screen.dart' show screenForRole;
import 'login_screen.dart';
import 'pmes_login_screen.dart';
import 'register_screen.dart';

const _amber = Color(0xFFE8A317);
const _heroBg = Color(0xFF263238);
const _pageBg = Color(0xFFF2F4F7);

/// Public landing page shown on app start, whether logged in or not.
/// All data is placeholder for now.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  String? _role;
  String? _fullName;
  String? _membershipType;
  bool _loaded = false;

  bool get _loggedIn => _role != null;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final token = await TokenStorage.accessToken();
    final role = await TokenStorage.role();
    final name = await TokenStorage.fullName();
    final membership = await TokenStorage.membershipType();
    if (!mounted) return;
    setState(() {
      _role = (token != null && role != null) ? role : null;
      _fullName = _role != null ? name : null;
      _membershipType = _role != null ? membership : null;
      _loaded = true;
    });
  }

  void _goLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    ).then((_) => _loadSession());
  }

  void _goRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    ).then((_) => _loadSession());
  }

  void _goPmes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PmesLoginScreen()),
    ).then((_) => _loadSession());
  }

  void _goDashboard() {
    if (!_loggedIn) return _goLogin();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => screenForRole(
          _role!,
          _fullName ?? '',
          membershipType: _membershipType,
        ),
      ),
      (route) => false,
    );
  }

  void _comingSoon() {
    if (!_loggedIn) return _goLogin();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        leading: const Icon(Icons.location_on_outlined),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PRIC Main Branch', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text('Delivering to your location', style: TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _comingSoon,
          ),
          IconButton(
            tooltip: 'Cart',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: _comingSoon,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loggedIn) ...[
            Text('Welcome, ${_fullName ?? ''}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Chip(label: Text('Role: $_role')),
            const SizedBox(height: 12),
          ],
          _heroCard(),
          const SizedBox(height: 12),
          if (_loggedIn)
            FilledButton.icon(
              onPressed: _goDashboard,
              icon: const Icon(Icons.dashboard),
              label: const Text('Go to Dashboard'),
            )
          else ...[
            FilledButton(onPressed: _goLogin, child: const Text('Log in')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _goRegister, child: const Text('Create account')),
            TextButton(onPressed: _goPmes, child: const Text('Apply for PMES')),
          ],
        ],
      ),
      bottomNavigationBar: const AppFooter(current: AppFooterTab.home),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _heroBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Amount to Pay', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                const Text(
                  '₱1,500.00',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const Text('Due on Nov 15', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _comingSoon,
                      style: ElevatedButton.styleFrom(backgroundColor: _amber),
                      child: const Text('Pay Now'),
                    ),
                    OutlinedButton(
                      onPressed: _comingSoon,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('View Details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.local_shipping_outlined, size: 72, color: _amber),
        ],
      ),
    );
  }
}
