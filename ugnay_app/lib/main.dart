import 'package:flutter/material.dart';

import 'api_client.dart';
import 'screens/login_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // If the token can't be refreshed (expired session, suspended account),
  // send the user back to the login screen.
  onSessionExpired = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };
  runApp(const UgnayApp());
}

class UgnayApp extends StatelessWidget {
  const UgnayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ugnay',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}