import 'package:flutter/material.dart';

import 'sign_in_screen.dart';

/// Public entry. Sign in carries both other doors (an invite code, or a setup
/// code for a new church), so the front page is simply Sign in.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) => const SignInScreen();
}
