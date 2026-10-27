import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../providers.dart';
import '../../youtube/yt_import_service.dart';
import '../../youtube/yt_models.dart';
import '../widgets/page_snack_bar.dart';

/// Asks for a YouTube playlist link and imports it. On success it opens the
/// playlist and says how it went; errors stay in the dialog.
///
/// [router] defaults to the one above [context] (pass it when [context] is
/// the root navigator's, e.g. for a link shared into the app).
Future<void> showImportDialog(
  BuildContext context, {
  String? initialLink,
  GoRouter? router,
}) {
  final go = router ?? GoRouter.of(context);
  final snacks = PageSnackBars.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) =>
        ImportDialog(initialLink: initialLink, router: go, snacks: snacks),
  );
}

/// What an import did, as its snack bar says it.
String importResultMessage(ImportResult r) {
  final songs = r.added == 1 ? '1 song' : '${r.added} songs';
  return r.alreadyExisted
      ? 'Already in your library — use Sync to update it'
      : 'Imported $songs';
}

/// A new import's page shows skeleton rows until its entries reach it.
void markImportPending(ImportResult r, PendingImports pending) {
  if (!r.alreadyExisted && r.added > 0) pending.add(r.playlistId);
}

class ImportDialog extends ConsumerStatefulWidget {
  const ImportDialog({
    required this.router,
    required this.snacks,
    this.initialLink,
    super.key,
  });

  final String? initialLink;
  final GoRouter router;
  final PageSnackBars snacks;

  @override
  ConsumerState<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<ImportDialog> {
  late final TextEditingController _link = TextEditingController(
    text: widget.initialLink ?? '',
  );
  bool _busy = false;
  String? _error;
  bool _missingBinary = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  static const _failedCopy = 'Something went wrong — try again';

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _missingBinary = false;
    });
    Result<ImportResult> result;
    try {
      result = await ref
          .read(ytImportServiceProvider)
          .importPlaylist(_link.text.trim());
    } catch (e, s) {
      AppLog.w('Import failed', e, s);
      result = Err(Failure(FailureKind.unknown, _failedCopy, cause: e));
    } finally {
      // Whatever happens above, the dialog must not stay stuck busy.
      if (mounted && _busy) setState(() => _busy = false);
    }
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        final pending = ref.read(pendingImportsProvider.notifier);
        Navigator.of(context).pop();
        _open(value, pending);
      case Err(:final failure):
        setState(() {
          _error = ytErrorUserMessage(failure);
          _missingBinary = ytErrorKindOf(failure) == YtErrorKind.missingBinary;
        });
    }
  }

  void _open(ImportResult r, PendingImports pending) {
    markImportPending(r, pending);
    widget.router.go('/library/playlist/${r.playlistId}');
    widget.snacks
      ..clear()
      ..show(content: Text(importResultMessage(r)));
  }

  void _openSettings() {
    Navigator.of(context).pop();
    widget.router.go('/settings');
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Import from YouTube'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _link,
                autofocus: widget.initialLink == null,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'Paste a YouTube Music playlist link',
                  errorText: error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _import(),
              ),
              if (_missingBinary)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _openSettings,
                    child: const Text('Open Settings'),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Importing…'),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _import,
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
