import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign in with a 6-digit code sent by email.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The email's sign-in link opens the app (dumpbox://login-callback); a 6-digit code also works when the email shows one.
      await _auth.signInWithOtp(email: email, shouldCreateUser: true, emailRedirectTo: 'dumpbox://login-callback');
      setState(() => _codeSent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.statusCode == '429' ? 'Too many requests. Wait a minute and try again.' : e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyOTP(email: _email.text.trim(), token: _code.text.trim(), type: OtpType.email);
    } on AuthException {
      setState(() => _error = 'That code is not right or has expired.');
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(16)),
                      alignment: Alignment.center,
                      child: Text('D', style: TextStyle(color: c.onPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('DumpBox', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Dump anything in one tap. Find it in one search.', textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  if (!_codeSent) ...[
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _busy ? null : _send(),
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? 'Sending…' : 'Email me a sign-in link')),
                  ] else ...[
                    Text('Check ${_email.text.trim()}: tap the sign-in link on this phone, or type the 6-digit code if the email shows one. It expires in 10 minutes.', style: TextStyle(color: c.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8),
                      onChanged: (v) {
                        if (v.length == 6 && !_busy) _verify();
                      },
                      decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _busy ? null : _verify, child: Text(_busy ? 'Checking…' : 'Sign in')),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(onPressed: () => setState(() => _codeSent = false), child: const Text('Change email')),
                        TextButton(onPressed: _busy ? null : _send, child: const Text('Send a new code')),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: c.error), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
