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
  State<AuthScreen> createState() {
    return _AuthScreenState();
  }
}

class _AuthScreenState extends State<AuthScreen> {
  String _tab = 'login';
  final _loginUsername = TextEditingController();
  final _loginPassword = TextEditingController();
  final _registerUsername = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  String? _loginError;
  String? _registerError;
  bool _busy = false;
  bool _showLoginPassword = false;
  bool _showRegisterPassword = false;

  /// Signs in with the username and password typed in, showing the error if it fails.
  Future<void> _login() async {
    setState(() {
      _busy = true;
      _loginError = null;
    });
    final error = await AppState.I.login(_loginUsername.text.trim(), _loginPassword.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _loginError = error;
    });
  }

  /// Creates an account from the Register form, showing the error if it fails.
  Future<void> _register() async {
    setState(() {
      _busy = true;
      _registerError = null;
    });
    final error = await AppState.I.register(_registerUsername.text.trim(), _registerEmail.text.trim(), _registerPassword.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _registerError = error;
    });
  }

  /// Lets the person pick a board's JSON file, then starts a guest session with that board in
  /// it. A file that isn't valid JSON is handed on as null.
  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Board', extensions: ['json']),
      ],
    );
    if (file == null) {
      return;
    }
    Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } catch (error) {
      json = null;
    }
    AppState.I.setGuest();
    await AppState.I.importBoard(json, asNew: true);
  }

  /// The screen: the logo and name, the three tabs, and the form of the chosen tab, in a glass
  /// panel in the middle.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
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
                            style: TextStyle(fontSize: 26, color: colors.ink, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _tabs(colors),
                      const SizedBox(height: 8),
                      if (_tab == 'login') ..._loginForm(colors),
                      if (_tab == 'register') ..._registerForm(colors),
                      if (_tab == 'guest') ..._guestOptions(colors),
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

  /// The Sign In / Register / Guest switch, with the chosen tab filled in the brand colour.
  Widget _tabs(UwuColors colors) {
    /// One tab button.
    Widget tab(String id, String label) {
      final isSelected = _tab == id;
      Color fillColor;
      Color textColor;
      FontWeight fontWeight;
      if (isSelected) {
        fillColor = colors.brandFill;
        textColor = colors.onBrand;
        fontWeight = FontWeight.w600;
      } else {
        fillColor = Colors.transparent;
        textColor = colors.muted;
        fontWeight = FontWeight.w400;
      }
      return Expanded(
        child: Semantics(
          selected: isSelected,
          button: true,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              setState(() {
                _tab = id;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor, fontWeight: fontWeight),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(children: [tab('login', 'Sign In'), tab('register', 'Register'), tab('guest', 'Guest')]),
    );
  }

  /// A password box with an eye button to show or hide what's typed; Enter submits the form.
  Widget _passwordField(TextEditingController controller, bool showPassword, VoidCallback toggle, String hint, Iterable<String> autofillHints, VoidCallback submit) {
    final colors = UwuColors.of(context);
    String toggleTooltip;
    String toggleIcon;
    if (showPassword) {
      toggleTooltip = 'Hide password';
      toggleIcon = 'eye-off';
    } else {
      toggleTooltip = 'Show password';
      toggleIcon = 'eye';
    }
    return TextField(
      controller: controller,
      obscureText: !showPassword,
      autofillHints: autofillHints,
      onSubmitted: (value) {
        submit();
      },
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: toggleTooltip,
          onPressed: toggle,
          icon: AppIcon(toggleIcon, size: 18, color: colors.muted),
        ),
      ),
    );
  }

  /// The Sign In tab: username, password and the Sign In button (off while busy).
  List<Widget> _loginForm(UwuColors colors) {
    VoidCallback? onSignIn;
    if (_busy) {
      onSignIn = null;
    } else {
      onSignIn = _login;
    }
    return [
      const FieldLabel('Username'),
      TextField(
        controller: _loginUsername,
        autofillHints: const [AutofillHints.username],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(hintText: 'your username'),
      ),
      const FieldLabel('Password'),
      _passwordField(_loginPassword, _showLoginPassword, () {
        setState(() {
          _showLoginPassword = !_showLoginPassword;
        });
      }, '••••••••', const [AutofillHints.password], _login),
      FormError(_loginError),
      const SizedBox(height: 16),
      FilledButton(onPressed: onSignIn, child: const Text('Sign In')),
    ];
  }

  /// The Register tab: username, email, password and the Create Account button (off while
  /// busy).
  List<Widget> _registerForm(UwuColors colors) {
    VoidCallback? onCreateAccount;
    if (_busy) {
      onCreateAccount = null;
    } else {
      onCreateAccount = _register;
    }
    return [
      const FieldLabel('Username'),
      TextField(
        controller: _registerUsername,
        autofillHints: const [AutofillHints.newUsername],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(hintText: 'choose a username'),
      ),
      const FieldLabel('Email'),
      TextField(
        controller: _registerEmail,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(hintText: 'you@example.com'),
      ),
      const FieldLabel('Password'),
      _passwordField(_registerPassword, _showRegisterPassword, () {
        setState(() {
          _showRegisterPassword = !_showRegisterPassword;
        });
      }, 'min 8 characters', const [AutofillHints.newPassword], _register),
      FormError(_registerError),
      const SizedBox(height: 16),
      FilledButton(onPressed: onCreateAccount, child: const Text('Create Account')),
    ];
  }

  /// The Guest tab: carry on without an account, or start from a board file.
  List<Widget> _guestOptions(UwuColors colors) {
    return [
      const SizedBox(height: 12),
      Text(
        'Continue as a guest. Your boards are saved on this device. Export JSON to take them elsewhere.',
        style: TextStyle(color: colors.muted, fontSize: 14, height: 1.4),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: AppState.I.setGuest, child: const Text('Continue as Guest')),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: _importFile,
        icon: AppIcon('file-import', size: 16, color: colors.ink),
        label: const Text('Or start from a board file'),
      ),
    ];
  }
}
