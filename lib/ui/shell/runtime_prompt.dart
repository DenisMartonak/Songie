import 'package:flutter/material.dart';

import '../../core/result.dart';

/// Installs the helper, reporting bytes received and the total (if known).
typedef RuntimeInstall = Future<Result<String>> Function(
  void Function(int, int?) onProgress,
);

/// Asks before downloading yt-dlp's JavaScript runtime for an age-restricted
/// song, then installs it with a progress bar. True once it is installed;
/// false for Not now (or the dialog closed).
Future<bool> showRuntimePrompt(
  BuildContext context, {
  required RuntimeInstall install,
}) async {
  final installed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RuntimePrompt(install),
  );
  return installed ?? false;
}

class _RuntimePrompt extends StatefulWidget {
  const _RuntimePrompt(this.install);

  final RuntimeInstall install;

  @override
  State<_RuntimePrompt> createState() => _RuntimePromptState();
}

class _RuntimePromptState extends State<_RuntimePrompt> {
  bool _installing = false;
  double? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _progress = null;
      _error = null;
    });
    final r = await widget.install((received, total) {
      if (!mounted || total == null || total <= 0) return;
      setState(() => _progress = received / total);
    });
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() {
          _installing = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Download a helper?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This song is age-restricted. To play it, Songies needs to '
            'download a small helper (about 45 MB, once).',
          ),
          if (_installing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _installing
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('runtimePrompt.download'),
          onPressed: _installing ? null : _install,
          child: Text(error == null ? 'Download' : 'Retry'),
        ),
      ],
    );
  }
}
