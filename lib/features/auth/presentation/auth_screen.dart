import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/widgets/heart_pin_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  bool _isValidEmail(String email) =>
      RegExp(r'^[^ @]+@[^ @]+[.][^ @]+$').hasMatch(email);

  Future<void> _handlePasswordSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (!_isValidEmail(email)) {
      _showMessage('Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }
    if (_isSignUp && name.isEmpty) {
      _showMessage('Please enter your name.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        final result = await _supabase.auth.signUp(
          email: email, password: password, data: {'name': name},
        );
        if (!mounted) return;
        if (result.session == null) {
          _showMessage('Account created. Check your email to verify your account.');
        } else {
          _showMessage('Account created.');
        }
      } else {
        await _supabase.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF162544);
    const mint = Color(0xFF35D6B4);
    const muted = Color(0xFF657087);
    final maxWidth = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F9),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -120, right: -85,
              child: Container(
                width: 310, height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mint.withOpacity(.10),
                ),
              ),
            ),
            Positioned(
              top: 115, left: -110,
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ink.withOpacity(.035),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HeartPinLogo(size: 78),
                      const SizedBox(height: 13),
                      const Text('spotmate',
                        style: TextStyle(fontSize: 34, letterSpacing: -1.4,
                          color: ink, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('Good places. Great people.',
                        style: TextStyle(color: muted, fontSize: 15)),
                      const SizedBox(height: 32),
                      Container(
                        padding: EdgeInsets.all(maxWidth < 380 ? 22 : 30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: const Color(0xFFE6EBEF)),
                          boxShadow: const [BoxShadow(
                            color: Color(0x100F2942),
                            offset: Offset(0, 15), blurRadius: 35,
                          )],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_isSignUp ? 'Join the good company.' : 'Welcome back.',
                              style: const TextStyle(fontSize: 25, letterSpacing: -.7,
                                fontWeight: FontWeight.w800, color: ink)),
                            const SizedBox(height: 6),
                            Text(_isSignUp
                              ? 'Make real connections at the places you love.'
                              : 'Find your people, wherever you go.',
                              style: const TextStyle(color: muted, fontSize: 13)),
                            const SizedBox(height: 26),
                            if (_isSignUp) ...[
                              const Text('YOUR NAME',
                                style: TextStyle(color: ink, fontWeight: FontWeight.w700,
                                  fontSize: 11, letterSpacing: 1)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'What should we call you?',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                            const Text('EMAIL ADDRESS',
                              style: TextStyle(color: ink, fontWeight: FontWeight.w700,
                                fontSize: 11, letterSpacing: 1)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                hintText: 'you@example.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text('PASSWORD',
                              style: TextStyle(color: ink, fontWeight: FontWeight.w700,
                                fontSize: 11, letterSpacing: 1)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              onSubmitted: (_) => _isLoading ? null : _handlePasswordSubmit(),
                              autofillHints: [_isSignUp ? AutofillHints.newPassword : AutofillHints.password],
                              decoration: InputDecoration(
                                hintText: _isSignUp ? 'At least 6 characters' : 'Enter your password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                                  icon: Icon(_obscurePassword
                                    ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handlePasswordSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ink, foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(width: 19, height: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5, color: Colors.white))
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(_isSignUp ? 'Create my account' : 'Sign in',
                                            style: const TextStyle(
                                              fontSize: 15, fontWeight: FontWeight.w700)),
                                          const SizedBox(width: 10),
                                          const Icon(Icons.arrow_forward_rounded, size: 19),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _isLoading ? null : () => setState(() {
                                _isSignUp = !_isSignUp;
                              }),
                              child: Text(_isSignUp
                                ? 'Already a member? Sign in'
                                : 'New here? Create an account',
                                style: const TextStyle(
                                  color: ink, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 23),
                      const Text('Meet respectfully. Connect on your terms.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
