import 'package:flutter/material.dart';

import '../storage.dart';
import 'admin_dashboard_screen.dart';
import 'logistics_dashboard_screen.dart';
import 'login_screen.dart';

/// Chooses the landing screen for a role. Other roles get a placeholder
/// until their modules are built.
Widget screenForRole(String role, String fullName) {
  if (role == 'admin') return AdminDashboardScreen(fullName: fullName);
  if (role == 'logistics') return LogisticsDashboardScreen(fullName: fullName);
  return HomeScreen(role: role, fullName: fullName);
}

Future<void> logout(BuildContext context) async {
  await TokenStorage.clear();
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

/// Placeholder landing screen for non-admin roles.
class HomeScreen extends StatelessWidget {
  final String role;
  final String fullName;

  const HomeScreen({super.key, required this.role, required this.fullName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ugnay'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome, $fullName', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Chip(label: Text('Role: $role')),
              const SizedBox(height: 16),
              const Text('The dashboard for this role is coming soon.'),
            ],
          ),
        ),
      ),
    );
  }
}