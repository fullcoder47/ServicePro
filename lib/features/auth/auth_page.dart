import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../onboarding/access_page.dart';

/// Kept as a compatibility entry point for older imports.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key, required this.appState});
  final AppState appState;
  @override
  Widget build(BuildContext context) => AccessPage(appState: appState);
}
