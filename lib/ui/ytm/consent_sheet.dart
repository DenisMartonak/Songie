import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../innertube/yt_session_store.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/page_snack_bar.dart';

/// The notice shown once when YouTube no longer accepts the sign-in.
const ytSignInExpiredNotice =
    'YouTube sign-in expired — showing the regular feed';

/// Shows [ConsentSheet] the first time YouTube asks for consent (common in
/// the EU), at most once per session and never once accepted on this device.
/// Not now changes nothing: search and playback keep working, and the feed
/// stays generic. Signed in to YouTube, the account's own choice applies, so
/// no sheet opens.
///
/// Also tells the user, once, when the YouTube sign-in expires (the feed
/// fell back to the regular one).
class ConsentListener extends ConsumerStatefulWidget {
  const ConsentListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ConsentListener> createState() => _ConsentListenerState();
}

class _ConsentListenerState extends ConsumerState<ConsentListener> {
  Future<void> _ask() async {
    if (ref.read(ytAuthProvider) is YtSignedIn) return;
    // Marked first, so a burst of asking responses shows one sheet.
    if (ref.read(consentAskedProvider)) return;
    ref.read(consentAskedProvider.notifier).markAsked();
    final client = ref.read(innertubeClientProvider);
    if (await client.consentGiven() || !mounted) return;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => const ConsentSheet(),
    );
    if (accepted != true) return;
    await client.acceptConsent();
    // Retried with the consent cookie.
    if (mounted) ref.invalidate(ytmHomeProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ytConsentRequiredProvider, (_, next) {
      if (next.value ?? false) _ask();
    });
    ref.listen(ytAuthProvider, (prev, next) {
      // Only the signed-in -> expired step, so it shows once per expiry.
      if (prev is YtSignedIn && next is YtExpired) {
        showPageSnackBar(context, content: const Text(ytSignInExpiredNotice));
      }
    });
    return widget.child;
  }
}

/// "YouTube needs you to accept its terms", with Accept and Not now; pops
/// `true` for Accept.
class ConsentSheet extends StatelessWidget {
  const ConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return SingleChildScrollView(
      key: const Key('consent.sheet'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YouTube needs you to accept its terms',
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'In your region YouTube asks before it uses cookies to '
            'personalise recommendations. Search and playback work either '
            'way; without it your Home feed stays generic.',
            style: TextStyle(color: colors.text, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('consent.notNow'),
                style: TextButton.styleFrom(foregroundColor: colors.text),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('consent.accept'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Accept'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
