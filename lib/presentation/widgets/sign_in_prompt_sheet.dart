import 'package:flutter/material.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';

/// A bottom-sheet prompt shown to guests when they attempt an action that
/// requires an account. Offers Sign In / Create Account (Sign In opens
/// LoginScreen; Create Account opens LoginScreen with SignUpScreen pushed
/// on top so the back stack reads as Map → Login → Signup) and Cancel.
class SignInPromptSheet extends StatelessWidget {
  final String title;
  final String body;

  const SignInPromptSheet({super.key, required this.title, required this.body});

  void _openLogin(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  void _openSignUp(BuildContext context) {
    Navigator.of(context).pop();
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const LoginScreen(),
    ));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const SignUpScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _openLogin(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _openSignUp(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Create Account'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
