import 'package:flutter/material.dart';

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
