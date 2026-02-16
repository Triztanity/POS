import 'package:flutter/material.dart';

class Dialogs {
  /// Shows a centered modal message dialog with an OK button.
  /// This helper centralizes styling so all app dialogs look consistent.
  static Future<void> showMessage(
    BuildContext context,
    String title,
    String message, {
    IconData? icon,
    Color? iconColor,
    bool auth = false,
    bool showSideIcons = false,
  }) {
    // If `auth` is true default to check icon; otherwise default to warning
    final IconData shownIcon =
        auth ? (icon ?? Icons.check_circle) : (icon ?? Icons.warning);
    final Color shownColor =
        auth ? (iconColor ?? Colors.green) : (iconColor ?? Colors.amber);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        elevation: auth ? 10 : 4,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: showSideIcons
            ? Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  CircleAvatar(
                    radius: auth ? 18 : 16,
                    backgroundColor: shownColor.withOpacity(0.12),
                    child: Icon(shownIcon,
                        size: auth ? 18 : 16, color: shownColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: auth ? 18 : 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: auth ? 18 : 16,
                    backgroundColor: shownColor.withOpacity(0.12),
                    child: Icon(shownIcon,
                        size: auth ? 18 : 16, color: shownColor),
                  ),
                ],
              )
            : Center(
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: auth ? 18 : 15),
                ),
              ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
