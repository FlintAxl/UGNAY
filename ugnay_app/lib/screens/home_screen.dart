import 'package:flutter/material.dart';

import '../storage.dart';
import '../widgets/app_footer.dart';
import 'admin_dashboard_screen.dart';
import 'landing_screen.dart';
import 'logistics_dashboard_screen.dart';
import 'production_dashboard_screen.dart';

/// Chooses the landing screen for a role. Other roles get a placeholder
/// until their modules are built.
Widget screenForRole(String role, String fullName, {String? membershipType}) {
  if (role == 'admin') return AdminDashboardScreen(fullName: fullName);
  if (role == 'logistics') return LogisticsDashboardScreen(fullName: fullName);
  if (role == 'production') return ProductionDashboardScreen(fullName: fullName);
  return HomeScreen(role: role, fullName: fullName, membershipType: membershipType);
}

String membershipTypeLabel(String? value) => switch (value) {
      'ASSOCIATE' => 'Associate member',
      'FULLY_PLEDGED' => 'Fully pledged member',
      _ => 'Membership not set',
    };

Future<void> logout(BuildContext context) async {
  await TokenStorage.clear();
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const LandingScreen()),
    (route) => false,
  );
}

/// Placeholder landing screen for non-admin roles.
class HomeScreen extends StatelessWidget {
  final String role;
  final String fullName;
  final String? membershipType;

  const HomeScreen({
    super.key,
    required this.role,
    required this.fullName,
    this.membershipType,
  });

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
      bottomNavigationBar: const AppFooter(current: AppFooterTab.dashboard),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome, $fullName', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Chip(label: Text('Role: $role')),
              if (role == 'member') ...[
                const SizedBox(height: 8),
                Chip(label: Text(membershipTypeLabel(membershipType))),
              ],
              const SizedBox(height: 16),
              if (role == 'member')
                const Text(
                  'Welcome to Ugnay. Use the "Apply for PMES" link on the login screen to view or update your PMES application.',
                  textAlign: TextAlign.center,
                )
              else
                const Text('The dashboard for this role is coming soon.'),
            ],
          ),
        ),
      ),
    );
  }
}