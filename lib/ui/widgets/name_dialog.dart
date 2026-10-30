import 'package:flutter/material.dart';

/// The longest playlist name the repository accepts.
const int maxPlaylistNameLength = 100;

/// Asks for a playlist name. Returns the trimmed name, or null when cancelled.
/// Save stays disabled while the name is blank.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirmLabel = 'Save',
}) {
  return Navigator.of(context, rootNavigator: true).push(
    playlistNameDialogRoute(
      context,
      title: title,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

/// The route [showPlaylistNameDialog] pushes, for a caller that needs to
/// remove it itself (when its page goes away).
DialogRoute<String> playlistNameDialogRoute(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirmLabel = 'Save',
}) => DialogRoute<String>(
  context: context,
  builder: (_) =>
      _NameDialog(title: title, initial: initial, confirmLabel: confirmLabel),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxPlaylistNameLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
