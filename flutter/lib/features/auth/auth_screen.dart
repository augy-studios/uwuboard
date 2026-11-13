// The sign-in screen (the site's #auth-overlay): Sign In, Register, or Guest, with a board file
// to start a guest session from.
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/state.dart';
import '../../widgets/common.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String _tab = 'login';
  final _loginUser = TextEditingController();
  final _loginPass = TextEditingController();
  final _regUser = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  String? _loginError;
  String? _regError;
  bool _busy = false;
  bool _showLoginPass = false;
  bool _showRegPass = false;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _loginError = null;
    });
    final err = await AppState.I.login(_loginUser.text.trim(), _loginPass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _loginError = err;
    });
  }

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _regError = null;
    });
    final err = await AppState.I.register(_regUser.text.trim(), _regEmail.text.trim(), _regPass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _regError = err;
    });
  }

  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Board', extensions: ['json']),
      ],
    );
    if (file == null) return;
    Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } catch (_) {
      json = null;
    }
    AppState.I.setGuest();
    await AppState.I.importBoard(json, asNew: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: GlassPanel(
                strong: true,
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset('assets/images/icon-512.png', width: 36, height: 36, semanticLabel: 'uwuBoard logo'),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'uwuBoard',
                            style: TextStyle(fontSize: 26, color: c.ink, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _tabs(c),
                      const SizedBox(height: 8),
                      if (_tab == 'login') ..._loginForm(c),
                      if (_tab == 'register') ..._registerForm(c),
                      if (_tab == 'guest') ..._guest(c),
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

  Widget _tabs(UwuColors c) {
    Widget tab(String id, String label) {
      final on = _tab == id;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => setState(() => _tab = id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: on ? c.brandFill : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: on ? c.onBrand : c.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [tab('login', 'Sign In'), tab('register', 'Register'), tab('guest', 'Guest')]),
    );
  }

  Widget _pass(TextEditingController ctl, bool show, VoidCallback toggle, String hint, Iterable<String> autofill, VoidCallback submit) {
    final c = UwuColors.of(context);
    return TextField(
      controller: ctl,
      obscureText: !show,
      autofillHints: autofill,
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: show ? 'Hide password' : 'Show password',
          onPressed: toggle,
          icon: AppIcon(show ? 'eye-off' : 'eye', size: 18, color: c.muted),
        ),
      ),
    );
  }

  List<Widget> _loginForm(UwuColors c) => [
    const FieldLabel('Username'),
    TextField(
      controller: _loginUser,
      autofillHints: const [AutofillHints.username],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(hintText: 'your username'),
    ),
    const FieldLabel('Password'),
    _pass(_loginPass, _showLoginPass, () => setState(() => _showLoginPass = !_showLoginPass), '••••••••', const [AutofillHints.password], _login),
    FormError(_loginError),
    const SizedBox(height: 16),
    FilledButton(onPressed: _busy ? null : _login, child: const Text('Sign In')),
  ];

  List<Widget> _registerForm(UwuColors c) => [
    const FieldLabel('Username'),
    TextField(
      controller: _regUser,
      autofillHints: const [AutofillHints.newUsername],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(hintText: 'choose a username'),
    ),
    const FieldLabel('Email'),
    TextField(
      controller: _regEmail,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(hintText: 'you@example.com'),
    ),
    const FieldLabel('Password'),
    _pass(_regPass, _showRegPass, () => setState(() => _showRegPass = !_showRegPass), 'min 8 characters', const [AutofillHints.newPassword], _register),
    FormError(_regError),
    const SizedBox(height: 16),
    FilledButton(onPressed: _busy ? null : _register, child: const Text('Create Account')),
  ];

  List<Widget> _guest(UwuColors c) => [
    const SizedBox(height: 12),
    Text(
      'Continue as a guest. Your boards are saved on this device. Export JSON to take them elsewhere.',
      style: TextStyle(color: c.muted, fontSize: 14, height: 1.4),
    ),
    const SizedBox(height: 16),
    FilledButton(onPressed: AppState.I.setGuest, child: const Text('Continue as Guest')),
    const SizedBox(height: 14),
    OutlinedButton.icon(
      onPressed: _importFile,
      icon: AppIcon('file-import', size: 16, color: c.ink),
      label: const Text('Or start from a board file'),
    ),
  ];
}
