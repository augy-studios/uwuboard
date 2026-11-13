// The Profile window (the site's #profile-modal) and deleting the account in three steps
// (#delete-account-modal).
import 'package:flutter/material.dart';

import '../../app/files.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/images.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet.dart';

Future<void> openProfile(BuildContext context) {
  if (AppState.I.isGuest) {
    AppNav.toast('Sign in to edit your profile', error: true);
    return Future.value();
  }
  return AppSheet.show(context, id: 'profile', width: 460, builder: (context) => const _Profile());
}

class _Profile extends StatefulWidget {
  const _Profile();

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  late final _name = TextEditingController(text: AppState.I.shownName);
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  String? _avatarData;
  LoadedImage? _preview;
  bool _busy = false;

  Future<void> _pickAvatar() async {
    final files = await pickImages(multiple: false);
    if (files.isEmpty) return;
    final data = resizeToDataUrl(await files.first.readAsBytes(), maxWidth: 200);
    if (data == null) return;
    setState(() {
      _avatarData = data;
      _preview = parseDataUrl(data);
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AppState.I.updateProfile(name: _name.text.trim(), newPassword: _pass.text, confirm: _confirm.text, avatarData: _avatarData);
    if (!mounted) return;
    if (err == null) {
      AppSheet.close(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return SheetFrame(
      title: 'Profile',
      footer: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.error),
          onPressed: () {
            AppSheet.close(context);
            openDeleteAccount(context);
          },
          child: const Text('Delete Account'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save Changes')),
      ],
      children: [
        Center(
          child: Tooltip(
            message: 'Click to change photo',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _pickAvatar,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Avatar(size: 84, preview: _preview),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), shape: BoxShape.circle),
                    child: const Center(child: AppIcon('camera', color: Colors.white, size: 24)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const FieldLabel('Username', note: '(cannot be changed)'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Text(AppState.I.username, style: TextStyle(color: c.muted)),
        ),
        const FieldLabel('Display Name'),
        TextField(
          controller: _name,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'How you appear to yourself', counterText: ''),
        ),
        const FieldLabel('New Password'),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Leave blank to keep current'),
        ),
        const FieldLabel('Confirm Password'),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Retype new password'),
          onSubmitted: (_) => _save(),
        ),
        FormError(_error),
      ],
    );
  }
}

Future<void> openDeleteAccount(BuildContext context) {
  return AppSheet.show(context, id: 'delete-account', width: 420, builder: (context) => const _DeleteAccount());
}

class _DeleteAccount extends StatefulWidget {
  const _DeleteAccount();

  @override
  State<_DeleteAccount> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends State<_DeleteAccount> {
  int _step = 1;
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final danger = FilledButton.styleFrom(backgroundColor: c.errorFill, foregroundColor: c.error);
    final cancel = OutlinedButton(onPressed: () => AppSheet.close(context), child: const Text('Cancel'));
    return switch (_step) {
      1 => SheetFrame(
        title: 'Delete Account',
        footer: [
          cancel,
          FilledButton(style: danger, onPressed: () => setState(() => _step = 2), child: const Text('Yes, delete it')),
        ],
        children: [Text('Are you sure you want to delete your account? This cannot be undone.', style: TextStyle(color: c.ink))],
      ),
      2 => SheetFrame(
        title: 'Are you really sure?',
        footer: [
          cancel,
          FilledButton(style: danger, onPressed: () => setState(() => _step = 3), child: const Text('Yes, I’m really sure')),
        ],
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(color: c.ink),
              children: const [
                TextSpan(text: 'All your boards and data will be '),
                TextSpan(
                  text: 'permanently lost',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '. There is no going back.'),
              ],
            ),
          ),
        ],
      ),
      _ => SheetFrame(
        title: 'Final Confirmation',
        footer: [
          cancel,
          FilledButton(
            style: danger,
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    final err = await AppState.I.deleteAccount(_pass.text);
                    if (!context.mounted) return;
                    if (err == null) {
                      AppSheet.close(context);
                    } else {
                      setState(() {
                        _busy = false;
                        _error = err;
                      });
                    }
                  },
            child: const Text('Delete My Account'),
          ),
        ],
        children: [
          Text('Enter your password to permanently delete your account.', style: TextStyle(color: c.ink)),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Your password'),
          ),
          FormError(_error),
        ],
      ),
    };
  }
}
