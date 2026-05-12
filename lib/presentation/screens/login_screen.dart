import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/screens/forgot_password_screen.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

/// Sign-in screen. Email + password + Sign In, with side links to the
/// forgot-password flow and to signup. Auto-pops when auth state flips.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    // Sign-in does NOT enforce a min-length client-side. Legacy accounts may
    // hold passwords that don't meet current rules; let the server reject.
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    vm.clearError();
    await vm.signIn(_emailController.text.trim(), _passwordController.text);
    // Auto-pop is handled reactively in build(); see the comment there.
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  void _openSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, _) {
        // Auto-pop when auth flips to true. This screen is always pushed on
        // top of MapScreen, so popping reveals the now-authenticated map.
        // Pop runs in addPostFrameCallback to stay out of the build phase;
        // guards make it idempotent across rebuilds.
        //
        // Skip the auto-pop during a password-recovery deep link: the session
        // becomes authenticated, but _AppRoot pushes ResetPasswordScreen on
        // top in the same frame. Popping here pops that screen out from
        // under the user. The recovery screen owns the post-update navigation.
        if (authViewModel.isAuthenticated &&
            authViewModel.error == null &&
            !authViewModel.isLoading &&
            !authViewModel.isInPasswordRecovery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }

        final isLoading = authViewModel.isLoading;
        final errorMessage = authViewModel.error;

        return Scaffold(
          appBar: AppBar(title: const Text('Sign In')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.map,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'CCW Map',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Collaborative mapping of concealed carry zones',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !isLoading,
                        validator: _validateEmail,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        enabled: !isLoading,
                        validator: _validatePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isLoading ? null : _openForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage,
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: isLoading ? null : _handleSignIn,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Sign In'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading ? null : _openSignUp,
                        child: const Text("Don't have an account? Sign up"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
