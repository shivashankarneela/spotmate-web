import 'package:spotmate/core/account_validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  bool _isResetEmailSending = false;

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

  Future<void> _showForgotPassword() async {
    if (_isLoading || _isResetEmailSending) return;
    var recoveryEmail = _emailController.text.trim();
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset your password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter your account email. We will send you a secure password reset link.'),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: recoveryEmail,
                onChanged: (value) => recoveryEmail = value,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final address = recoveryEmail.trim();
                if (!_isValidEmail(address)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid email address.')),
                  );
                  return;
                }
                if (_isResetEmailSending) return;
                _isResetEmailSending = true;
                try {
                  await _supabase.auth.resetPasswordForEmail(
                    address,
                    // The web app receives the recovery token at its own origin.
                    // Add each preview origin to Supabase Auth redirect allowlist
                    // before testing recovery on that preview.
                    redirectTo: kIsWeb ? '${Uri.base.origin}/' : null,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  _showMessage('If an account exists for that email, check your inbox for a reset link.');
                } on AuthException catch (e) {
                  if (mounted) _showMessage(e.message);
                } catch (_) {
                  if (mounted) _showMessage('Could not send the reset link. Please try again.');
                } finally {
                  _isResetEmailSending = false;
                }
              },
              child: const Text('Send reset link'),
            ),
          ],
        ),
      );
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
                            if (!_isSignUp) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading ? null : _showForgotPassword,
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
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

/// Shown only after Supabase verifies the recovery link and opens a session.
/// Do not ask for the old password or allow normal navigation before reset.
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (_busy) return;
    final newPassword = _password.text;
    if (!isStrongPassword(newPassword)) {
      setState(() => _error = passwordRequirements);
      return;
    }
    if (newPassword != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      // Recovery sessions must not be treated as regular sign-in.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (mounted) widget.onFinished();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to update password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8F5),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_reset_rounded, color: Color(0xFF517C6E), size: 48),
                    const SizedBox(height: 16),
                    const Text('Create a new password', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF20382E))),
                    const SizedBox(height: 8),
                    const Text('Choose a strong password for your HaloBerry account.',
                      textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF728179))),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _password,
                      obscureText: _hidden,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'New password',
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Show password' : 'Hide password',
                          icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirm,
                      obscureText: _hidden,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(labelText: 'Confirm new password'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Color(0xFFAB304D))),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _savePassword,
                      child: _busy
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Update password'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
