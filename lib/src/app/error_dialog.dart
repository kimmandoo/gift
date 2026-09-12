import 'package:flutter/material.dart';
import 'package:gift/src/app/pixel_theme.dart';

class GiftRecoveryAction {
  const GiftRecoveryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class GiftRecoveryActions extends StatelessWidget {
  const GiftRecoveryActions({super.key, required this.actions});

  final List<GiftRecoveryAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return PixelActionRow(
      key: key,
      children: [
        for (final action in actions)
          OutlinedButton.icon(
            onPressed: action.onPressed,
            icon: Icon(action.icon, size: 18),
            label: Text(action.label),
          ),
      ],
    );
  }
}

Future<void> showGiftErrorDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('error-popup'),
      title: const Row(
        children: [
          Icon(Icons.error_outline),
          SizedBox(width: 8),
          Expanded(child: Text('Error')),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(message, key: const Key('error-popup-message')),
      ),
      actions: [
        FilledButton(
          key: const Key('dismiss-error-popup'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
