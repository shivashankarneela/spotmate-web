import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailVerificationTile extends StatefulWidget {
  const EmailVerificationTile({super.key});

  @override
  State<EmailVerificationTile> createState() => _EmailVerificationTileState();
}

class _EmailVerificationTileState extends State<EmailVerificationTile> {
  final _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _auth;
  Timer? _cooldown;
  bool _verified = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _auth = _client.auth.onAuthStateChange.listen((_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final verified = await _client.rpc('spotmate_record_email_verification');
      if (mounted) setState(() => _verified = verified == true);
    } on PostgrestException {
      // The verification service can be retried by reopening Account.
    }
  }

  Future<void> _send() async {
    final email = _client.auth.currentUser?.email;
    if (_sending || _cooldown?.isActive == true || email == null) return;
    setState(() => _sending = true);
    try {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
        emailRedirectTo: kIsWeb ? Uri.base.origin : null,
      );
      if (!mounted) return;
      _cooldown = Timer(const Duration(seconds: 60), () {
        if (mounted) setState(() {});
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check your inbox for the verification link.')),
      );
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _cooldown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email;
    if (email == null) return const SizedBox.shrink();
    return ListTile(
      title: Text(_verified ? 'Email verified' : 'Verify your email'),
      subtitle: Text(email),
      leading: Icon(_verified ? Icons.verified_outlined : Icons.email_outlined),
      trailing: _verified ? null : TextButton(
        onPressed: _sending || _cooldown?.isActive == true ? null : _send,
        child: const Text('Send link'),
      ),
    );
  }
}
