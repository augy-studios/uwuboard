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

/// Opens the Profile window; a guest has no profile, so they are told to sign in instead.
Future<void> openProfile(BuildContext context) {
  if (AppState.I.isGuest) {
    AppNav.toast('Sign in to edit your profile', error: true);
    return Future.value();
  }
  return AppSheet.show(
    context,
    id: 'profile',
    width: 460,
    builder: (context) {
      return const _Profile();
    },
  );
}

class _Profile extends StatefulWidget {
  const _Profile();

  @override
  State<_Profile> createState() {
    return _ProfileState();
  }
}

class _ProfileState extends State<_Profile> {
  late final _displayName = TextEditingController(text: AppState.I.shownName);
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _error;
  String? _avatarData;
  LoadedImage? _preview;
  bool _busy = false;

  /// Lets the person pick a photo, shrinks it to 200 pixels wide and shows it as the new
  /// avatar (saved only when they press Save Changes).
  Future<void> _pickAvatar() async {
    final files = await pickImages(multiple: false);
    if (files.isEmpty) {
      return;
    }
    final data = resizeToDataUrl(await files.first.readAsBytes(), maxWidth: 200);
    if (data == null) {
      return;
    }
    setState(() {
      _avatarData = data;
      _preview = parseDataUrl(data);
    });
  }

  /// Saves the name, password and avatar; closes the window when it works, or shows the error.
  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await AppState.I.updateProfile(name: _displayName.text.trim(), newPassword: _newPassword.text, confirm: _confirmPassword.text, avatarData: _avatarData);
    if (!mounted) {
      return;
    }
    if (error == null) {
      AppSheet.close(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  /// The window: the avatar to click and change, the username (fixed), the display name and a
  /// new password, with Delete Account and Save Changes at the bottom.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    VoidCallback? onSave;
    if (_busy) {
      onSave = null;
    } else {
      onSave = _save;
    }
    return SheetFrame(
      title: 'Profile',
      footer: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.error),
          onPressed: () {
            AppSheet.close(context);
            openDeleteAccount(context);
          },
          child: const Text('Delete Account'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Save Changes')),
      ],
      children: [
        Center(
          child: Tooltip(
            message: 'Click to change photo',
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
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
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Text(AppState.I.username, style: TextStyle(color: colors.muted)),
        ),
        const FieldLabel('Display Name'),
        TextField(
          controller: _displayName,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'How you appear to yourself', counterText: ''),
        ),
        const FieldLabel('New Password'),
        TextField(
          controller: _newPassword,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Leave blank to keep current'),
        ),
        const FieldLabel('Confirm Password'),
        TextField(
          controller: _confirmPassword,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Retype new password'),
          onSubmitted: (value) {
            _save();
          },
        ),
        FormError(_error),
      ],
    );
  }
}

/// Opens the first of the three steps of deleting the account.
Future<void> openDeleteAccount(BuildContext context) {
  return AppSheet.show(
    context,
    id: 'delete-account',
    width: 420,
    builder: (context) {
      return const _DeleteAccount();
    },
  );
}

class _DeleteAccount extends StatefulWidget {
  const _DeleteAccount();

  @override
  State<_DeleteAccount> createState() {
    return _DeleteAccountState();
  }
}

class _DeleteAccountState extends State<_DeleteAccount> {
  int _step = 1;
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  /// Deleting the account takes three steps: "Are you sure?", "Are you really sure?", and then
  /// the password to confirm. Each step is its own window contents.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final dangerStyle = FilledButton.styleFrom(backgroundColor: colors.errorFill, foregroundColor: colors.error);
    final cancelButton = OutlinedButton(
      onPressed: () {
        AppSheet.close(context);
      },
      child: const Text('Cancel'),
    );
    if (_step == 1) {
      return SheetFrame(
        title: 'Delete Account',
        footer: [
          cancelButton,
          FilledButton(
            style: dangerStyle,
            onPressed: () {
              setState(() {
                _step = 2;
              });
            },
            child: const Text('Yes, delete it'),
          ),
        ],
        children: [Text('Are you sure you want to delete your account? This cannot be undone.', style: TextStyle(color: colors.ink))],
      );
    } else if (_step == 2) {
      return SheetFrame(
        title: 'Are you really sure?',
        footer: [
          cancelButton,
          FilledButton(
            style: dangerStyle,
            onPressed: () {
              setState(() {
                _step = 3;
              });
            },
            child: const Text('Yes, I’m really sure'),
          ),
        ],
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(color: colors.ink),
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
      );
    } else {
      // The last step: the password, then the account is deleted. Off while it's being done.
      VoidCallback? onDelete;
      if (_busy) {
        onDelete = null;
      } else {
        onDelete = () async {
          setState(() {
            _busy = true;
            _error = null;
          });
          final error = await AppState.I.deleteAccount(_password.text);
          if (!context.mounted) {
            return;
          }
          if (error == null) {
            AppSheet.close(context);
          } else {
            setState(() {
              _busy = false;
              _error = error;
            });
          }
        };
      }
      return SheetFrame(
        title: 'Final Confirmation',
        footer: [
          cancelButton,
          FilledButton(
            style: dangerStyle,
            onPressed: onDelete,
            child: const Text('Delete My Account'),
          ),
        ],
        children: [
          Text('Enter your password to permanently delete your account.', style: TextStyle(color: colors.ink)),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Your password'),
          ),
          FormError(_error),
        ],
      );
    }
  }
}
