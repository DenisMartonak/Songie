import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bug_report/bug_report.dart';
import '../../bug_report/bug_report_sender.dart';
import '../../core/app_version.dart';
import '../../core/log.dart';
import '../../data/settings_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;

/// A picked screenshot: its file name and bytes.
/// [bytes] is null when the file is over [maxScreenshotBytes]: it is not read.
typedef Screenshot = ({String fileName, int size, Uint8List? bytes});

/// Asks the user for one image; null when cancelled. A provider so tests can
/// replace the native dialog.
typedef ScreenshotPicker = Future<Screenshot?> Function();

final screenshotPickerProvider = Provider<ScreenshotPicker>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a screenshot',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = file?.path;
    if (path == null) return null;
    final f = File(path);
    final size = await f.length();
    return (
      fileName: file!.name,
      size: size,
      bytes: size > maxScreenshotBytes ? null : await f.readAsBytes(),
    );
  },
);

/// The shortest description that can be sent.
const int _minDescription = 10;

/// Opens the bug report form: a dialog on wide windows, a full page on narrow
/// ones. The page goes on the root navigator, above the tab bar and mini
/// player, so switching tabs cannot throw away a report being typed.
Future<void> showBugReportForm(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= phoneBreakpoint) {
    return showDialog<void>(
      context: context,
      // Cancel closes it; a stray tap must not drop a report being typed.
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const SingleChildScrollView(child: BugReportForm()),
        ),
      ),
    );
  }
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const Scaffold(
        body: SafeArea(child: SingleChildScrollView(child: BugReportForm())),
      ),
    ),
  );
}

/// [collectLog] on another isolate: the log is big. A top-level function, so
/// the closure holds only these plain values and not a widget.
Future<Uint8List> _collectLogOffThread(String logsPath, List<String> names) =>
    Isolate.run(() => collectLog(Directory(logsPath), deviceNames: names));

/// The form itself: what happened, an optional name and screenshot, and Send.
class BugReportForm extends ConsumerStatefulWidget {
  const BugReportForm({super.key});

  @override
  ConsumerState<BugReportForm> createState() => _BugReportFormState();
}

class _BugReportFormState extends ConsumerState<BugReportForm> {
  final _description = TextEditingController();
  final _name = TextEditingController();
  ({String fileName, Uint8List bytes})? _screenshot;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillName();
  }

  Future<void> _prefillName() async {
    final saved = await ref
        .read(settingsRepositoryProvider)
        .getString(kBugReportName);
    if (!mounted || saved == null || _name.text.isNotEmpty) return;
    _name.text = saved;
  }

  @override
  void dispose() {
    _description.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && _description.text.trim().length >= _minDescription;

  Future<void> _attach() async {
    final islands = Islands.of(context);
    final shot = await ref.read(screenshotPickerProvider)();
    if (!mounted || shot == null) return;
    final bytes = shot.bytes;
    if (bytes == null || shot.size > maxScreenshotBytes) {
      islands.show('That image is too big', kind: IslandKind.failure);
      return;
    }
    setState(() => _screenshot = (fileName: shot.fileName, bytes: bytes));
  }

  Future<void> _send() async {
    if (_sending) return;
    final islands = Islands.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final settings = ref.read(settingsRepositoryProvider);
    final sender = ref.read(bugReportSenderProvider);
    final readDevice = ref.read(deviceSummaryProvider);
    final logsPath = ref.read(appPathsProvider).logs.path;
    final name = _name.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    BugReportSendResult result;
    try {
      await AppLog.flush();
      // Never create an install id for a report: only read one that exists.
      final installId = await settings.getString(kCrashInstallId);
      // Sync peers are named after the host on desktop; keep that out of the log.
      final deviceNames = [
        Platform.localHostname,
        ?await settings.getString(kDeviceName),
      ];
      final report = BugReport(
        description: _description.text.trim(),
        name: name.isEmpty ? null : name,
        device: await readDevice(),
        version: '$appVersion+$appBuild',
        time: DateTime.now().toUtc(),
        installId: installId,
        log: await _collectLogOffThread(logsPath, deviceNames),
        screenshot: _screenshot,
      );
      result = await sender.send(report);
    } catch (e) {
      AppLog.w('Bug report failed: ${e.runtimeType}');
      result = BugReportSendResult.failed;
    }
    if (result == BugReportSendResult.sent) {
      try {
        await settings.setString(kBugReportName, name.isEmpty ? null : name);
      } catch (e) {
        AppLog.w('Bug report name not saved: ${e.runtimeType}');
      }
      islands.show('Bug report sent', kind: IslandKind.success);
      // Only close our own route; never whatever is on top by now.
      if (route != null && route.isCurrent) {
        navigator.pop();
      } else if (route != null && route.isActive) {
        navigator.removeRoute(route);
      } else if (mounted) {
        setState(() => _sending = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = result == BugReportSendResult.tooSoon
          ? 'You just sent one. Try again in a minute.'
          : "Couldn't send. Check your connection and try again.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final shot = _screenshot;
    return PopScope(
      canPop: !_sending,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report a bug', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('bugReport.description'),
              controller: _description,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('bugReport.name'),
              controller: _name,
              enabled: !_sending,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Your name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (shot == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('bugReport.attach'),
                  onPressed: _sending ? null : _attach,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Attach screenshot'),
                ),
              )
            else
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      shot.bytes,
                      key: const Key('bugReport.thumbnail'),
                      cacheWidth: 112,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(shot.fileName, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    key: const Key('bugReport.removeScreenshot'),
                    tooltip: 'Remove screenshot',
                    onPressed: _sending
                        ? null
                        : () => setState(() => _screenshot = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              "Includes the app version, your device and the app's log.",
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('bugReport.error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('bugReport.cancel'),
                  onPressed: _sending
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('bugReport.send'),
                  onPressed: _canSend ? _send : null,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
