import 'package:spotmate/core/account_validation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onSignupInProgress});

  final ValueChanged<bool> onSignupInProgress;
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
    if (_isSignUp && !isStrongPassword(password)) {
      _showMessage(passwordRequirements);
      return;
    }
    if (_isSignUp && name.isEmpty) {
      _showMessage('Please enter your name.');
      return;
    }
    final signingUp = _isSignUp;
    if (signingUp) widget.onSignupInProgress(true);
    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        final result = await _supabase.auth.signUp(
          email: email, password: password, data: {'name': name},
        );
        if (result.session != null) {
          await _supabase.auth.signOut(scope: SignOutScope.local);
        }
        if (!mounted) return;
        _passwordController.clear();
        setState(() => _isSignUp = false);
        _showMessage(result.session == null
            ? 'Account created. Please sign in. If prompted, check your inbox.'
            : 'Account created. Please sign in.');
      } else {
        await _supabase.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Something went wrong. Please try again.');
    } finally {
      widget.onSignupInProgress(false);
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
    // Approved HaloBerry identity: airy ivory, mint, forest ink and restrained berry.
    const ink = Color(0xFF20382E);
    const mint = Color(0xFFBCE9D9);
    const muted = Color(0xFF728179);
    final maxWidth = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      body: SafeArea(
        child: Stack(
          children: [
            if (!_isSignUp)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF3FBF6), Color(0xFFFCF8F6), Color(0xFFF9F6F2)],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: -120, right: -85,
              child: Container(
                width: 310, height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mint.withValues(alpha: .55),
                ),
              ),
            ),
            Positioned(
              top: 115, left: -110,
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x185CC3A8),
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
                      // Official HaloBerry artwork, cropped from the uploaded logo.
                      Container(
                        width: 118,
                        height: 118,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: const Color(0xFFEAF8F1),
                          boxShadow: const [
                            BoxShadow(color: Color(0x164A896F), blurRadius: 25, offset: Offset(0, 12)),
                          ],
                        ),
                        child: Image.asset(
                          'assets/branding/haloberry_icon.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          semanticLabel: 'HaloBerry official logo',
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text('HaloBerry',
                        style: TextStyle(fontSize: 36, letterSpacing: -1.3,
                          color: ink, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Find your people. Feel the magic.',
                        style: TextStyle(color: muted, fontSize: 15)),
                      const SizedBox(height: 32),
                      Container(
                        padding: EdgeInsets.all(maxWidth < 380 ? 22 : 30),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDFC),
                          borderRadius: BorderRadius.circular(_isSignUp ? 26 : 30),
                          border: Border.all(
                            color: const Color(0xFFE5E8E2)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x183C544D),
                              offset: const Offset(0, 15), blurRadius: 35,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_isSignUp ? 'Join the good company.' : 'Welcome back.',
                              style: TextStyle(fontSize: 25, letterSpacing: -.7,
                                fontWeight: FontWeight.w800, color: ink)),
                            const SizedBox(height: 6),
                            Text(_isSignUp
                              ? 'Make real connections at the places you love.'
                              : 'Find your people, wherever you go.',
                              style: TextStyle(color: muted, fontSize: 13)),
                            const SizedBox(height: 26),
                            if (_isSignUp) ...[
                              Text('YOUR NAME',
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
                            Text('EMAIL ADDRESS',
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
                            Text('PASSWORD',
                              style: TextStyle(color: ink, fontWeight: FontWeight.w700,
                                fontSize: 11, letterSpacing: 1)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              onSubmitted: (_) => _isLoading ? null : _handlePasswordSubmit(),
                              autofillHints: [_isSignUp ? AutofillHints.newPassword : AutofillHints.password],
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
                                helperText: _isSignUp ? passwordRequirements : null,
                                helperMaxLines: 3,
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
                                  backgroundColor: const Color(0xFF98365E),
                                  foregroundColor: Colors.white,
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
                                style: TextStyle(
                                  color: ink, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 23),
                      Text('Meet respectfully. Connect on your terms.',
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
