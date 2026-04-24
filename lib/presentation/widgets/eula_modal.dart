import 'package:flutter/material.dart';

enum EulaModalMode { passiveFirstLaunch, retroactiveBlocking }

/// Surfaces the Terms of Use and Community Guidelines acceptance UX.
///
/// - [EulaModalMode.passiveFirstLaunch]: shown once per install to
///   everyone (guest or authenticated). Dismissible. "Got it" calls
///   [onAccept]; "Read full terms" calls [onReadTerms].
/// - [EulaModalMode.retroactiveBlocking]: shown on app-start to
///   already-authenticated users who have never accepted the current
///   version. Non-dismissible: the only exits are "I Agree" (calls
///   [onAccept]) and "Sign Out" (calls [onSignOut]).
class EulaModal extends StatelessWidget {
  final EulaModalMode mode;
  final VoidCallback onAccept;
  final VoidCallback onReadTerms;
  final VoidCallback? onSignOut;

  EulaModal({
    super.key,
    required this.mode,
    required this.onAccept,
    required this.onReadTerms,
    this.onSignOut,
  }) : assert(
          mode != EulaModalMode.retroactiveBlocking || onSignOut != null,
          'onSignOut is required for retroactiveBlocking mode',
        );

  @override
  Widget build(BuildContext context) {
    final isRetroactive = mode == EulaModalMode.retroactiveBlocking;

    return AlertDialog(
      title: const Text('Community Guidelines'),
      content: const SingleChildScrollView(
        child: Text(
          'By using CCW Map, you agree to the Terms of Use and Community '
          'Guidelines. Objectionable content and abusive behavior are not '
          'tolerated and may result in account suspension.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: onReadTerms,
          child: const Text('Read full terms'),
        ),
        if (isRetroactive) ...[
          OutlinedButton(
            onPressed: onSignOut,
            child: const Text('Sign Out'),
          ),
          ElevatedButton(
            onPressed: onAccept,
            child: const Text('I Agree'),
          ),
        ] else
          ElevatedButton(
            onPressed: onAccept,
            child: const Text('Got it'),
          ),
      ],
    );
  }
}
