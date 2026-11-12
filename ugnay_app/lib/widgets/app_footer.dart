import 'package:flutter/material.dart';

import '../storage.dart';
import '../screens/home_screen.dart' show logout, membershipTypeLabel, screenForRole;
import '../screens/landing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/pmes_login_screen.dart';
import '../screens/register_screen.dart';

enum AppFooterTab { home, dashboard, account, login, register, pmes }

/// Reusable bottom navigation shown on top-level screens.
/// Guests see Home | Log in | Register | PMES; logged-in users see
/// Home | Dashboard | Account. Session is loaded from secure storage.
class AppFooter extends StatefulWidget {
  final AppFooterTab current;

  const AppFooter({super.key, required this.current});

  @override
  State<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends State<AppFooter> {
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

  void _goHome() {
    if (widget.current == AppFooterTab.home) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
      (route) => false,
    );
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

  void _go(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then(
      (_) => _loadSession(),
    );
  }

  void _goLogin() => _go(const LoginScreen());
  void _goRegister() => _go(const RegisterScreen());
  void _goPmes() => _go(const PmesLoginScreen());

  void _showAccount() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_fullName ?? '', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Chip(label: Text('Role: $_role')),
            if (_role == 'member') ...[
              const SizedBox(height: 8),
              Chip(label: Text(membershipTypeLabel(_membershipType))),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => logout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final tabs = _loggedIn
        ? const [
            (AppFooterTab.home, Icons.home, 'Home'),
            (AppFooterTab.dashboard, Icons.dashboard, 'Dashboard'),
            (AppFooterTab.account, Icons.person, 'Account'),
          ]
        : const [
            (AppFooterTab.home, Icons.home, 'Home'),
            (AppFooterTab.login, Icons.login, 'Log in'),
            (AppFooterTab.register, Icons.app_registration, 'Register'),
            (AppFooterTab.pmes, Icons.assignment, 'PMES'),
          ];
    final selected = tabs.indexWhere((t) => t.$1 == widget.current);
    return NavigationBar(
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: (i) {
        switch (tabs[i].$1) {
          case AppFooterTab.home:
            _goHome();
          case AppFooterTab.dashboard:
            _goDashboard();
          case AppFooterTab.account:
            _showAccount();
          case AppFooterTab.login:
            _goLogin();
          case AppFooterTab.register:
            _goRegister();
          case AppFooterTab.pmes:
            _goPmes();
        }
      },
      destinations: [
        for (final (_, icon, label) in tabs)
          NavigationDestination(icon: Icon(icon), label: label),
      ],
    );
  }
}
