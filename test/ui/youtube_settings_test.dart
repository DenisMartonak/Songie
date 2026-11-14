import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_session_store.dart';
import 'package:songies/innertube/yt_sign_in.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/settings/settings_categories.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/settings/youtube_settings.dart';
import 'package:songies/youtube/deno_installer.dart';
import 'package:songies/youtube/js_runtime.dart';

import '../helpers/ui_harness.dart';

/// A sign-in route that answers what the test sets, without a web view.
class _FakeRoute implements YtSignInRoute {
  _FakeRoute(this.result, {this.label = 'Sign in to YouTube'});
  YtSignInResult? result;
  int runs = 0;

  @override
  final String label;

  @override
  Future<bool> supported() async => true;

  @override
  Future<YtSignInResult?> signIn(BuildContext context) async {
    runs++;
    return result;
  }

  int forgets = 0;
  bool forgetThrows = false;

  @override
  Future<void> forget() async {
    forgets++;
    if (forgetThrows) throw StateError('web data locked');
  }
}

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpSection(
    WidgetTester tester, {
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        extraOverrides: extraOverrides,
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => Scaffold(
              body: ListView(children: const [YouTubeSettingsSection()]),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<bool?> stored(WidgetTester tester, String key) =>
      real(tester, () async {
        final v = await SettingsRepository(h.db).getString(key);
        return v == null ? null : v == '1';
      });

  uiTest('Settings has a YouTube section', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
        ],
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(
              body: SettingsPage(category: SettingsCategory.youtube),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.byType(YouTubeSettingsSection), findsOneWidget);
    expect(find.text('yt-dlp version: 2026.10.21'), findsOneWidget);
  });

  uiTest('shows the installed version and offers Update', (tester) async {
    await pumpSection(tester);
    expect(find.text('yt-dlp version: 2026.10.21'), findsOneWidget);
    expect(find.text('Update yt-dlp'), findsOneWidget);
    expect(find.text('Install yt-dlp'), findsNothing);
  });

  group('age-restricted helper', () {
    uiTest("Songies' Deno shows as installed, with Remove", (tester) async {
      final deno = _FakeDeno();
      h
        ..denoInstaller = deno
        ..jsRuntime = const JsRuntime(JsRuntimeKind.songiesDeno, []);
      await pumpSection(tester);
      expect(
        find.text('Helper for age-restricted songs: installed'),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(deno.removed, 1);
    });

    uiTest('Node on the system is used, no Remove', (tester) async {
      h
        ..denoInstaller = _FakeDeno()
        ..jsRuntime = const JsRuntime(JsRuntimeKind.systemNode, []);
      await pumpSection(tester);
      expect(
        find.text('Helper for age-restricted songs: using Node.js'),
        findsOneWidget,
      );
      expect(find.text('Remove'), findsNothing);
    });

    uiTest('none installed offers Install', (tester) async {
      h.denoInstaller = _FakeDeno();
      await pumpSection(tester);
      expect(
        find.text('Helper for age-restricted songs: not installed'),
        findsOneWidget,
      );
      expect(find.text('Install helper'), findsOneWidget);
    });

    uiTest('hidden without an installer (Android)', (tester) async {
      await pumpSection(tester);
      expect(find.textContaining('Helper for age-restricted'), findsNothing);
    });
  });

  uiTest('desktop without yt-dlp offers Install', (tester) async {
    h.ytRunner.versionResult = null;
    await pumpSection(tester);
    expect(find.text('yt-dlp version: not installed'), findsOneWidget);
    expect(find.text('Install yt-dlp'), findsOneWidget);
  });

  uiTest('Android only ever offers Update', (tester) async {
    h.isAndroid = true;
    h.ytRunner.versionResult = null;
    await pumpSection(tester);
    expect(find.text('Update yt-dlp'), findsOneWidget);
    expect(find.text('Install yt-dlp'), findsNothing);
  });

  uiTest('Update reports the new version', (tester) async {
    await pumpSection(tester);
    h.ytRunner.versionResult = '2026.11.01';
    await tester.tap(find.text('Update yt-dlp'));
    await settle(tester);

    expect(h.ytRunner.updateCalls, 1);
    expect(find.text('yt-dlp updated to 2026.11.01'), findsOneWidget);
    expect(find.text('yt-dlp version: 2026.11.01'), findsOneWidget);
  });

  uiTest('a failed update shows the error', (tester) async {
    h.ytRunner.updateResult = const Err(
      Failure(FailureKind.network, 'Could not download yt-dlp'),
    );
    await pumpSection(tester);
    await tester.tap(find.text('Update yt-dlp'));
    await settle(tester);

    expect(find.text('Could not download yt-dlp'), findsOneWidget);
  });

  uiTest('Wi-Fi only moved to the Downloads section', (tester) async {
    await pumpSection(tester);
    expect(find.textContaining('Wi-Fi only'), findsNothing);
  });

  uiTest('the system yt-dlp toggle is hidden off Linux', (tester) async {
    await pumpSection(tester);
    expect(find.text('Use system yt-dlp'), findsNothing);
  });

  uiTest('on Linux the system yt-dlp toggle writes its setting', (
    tester,
  ) async {
    h.isLinux = true;
    await pumpSection(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Use system yt-dlp');
    expect(tile, findsOneWidget);
    expect(find.text('Takes effect after restart'), findsOneWidget);

    await tester.tap(tile);
    await settle(tester);
    expect(await stored(tester, kYtdlpUseSystem), isTrue);
  });

  group('YouTube sign-in', () {
    final session = YtSession({'SAPISID': 'SECRET', 'SID': 'S2'});

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(YouTubeSettingsSection)),
        );

    Future<_FakeRoute> pumpWithRoute(
      WidgetTester tester,
      YtSignInResult? result, {
      List<Override> extra = const [],
    }) async {
      final route = _FakeRoute(result);
      h.ytSignInRoutes = [route];
      await pumpSection(tester, extraOverrides: extra);
      return route;
    }

    uiTest('signed out offers Sign in; signing in shows the account', (
      tester,
    ) async {
      final route = await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
      );
      expect(find.text('Sign in to YouTube'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);

      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);

      expect(route.runs, 1);
      expect(h.ytSessions.stored?.cookies, session.cookies);
      expect(find.text('Signed in as Name'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign in to YouTube'), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
    });

    uiTest('without an account name it says Signed in', (tester) async {
      await pumpWithRoute(tester, YtSignInResult(session: session));
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);
      expect(find.text('Signed in'), findsOneWidget);
    });

    uiTest('closing the page leaves the user signed out, no error', (
      tester,
    ) async {
      final route = await pumpWithRoute(tester, null);
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);

      expect(route.runs, 1);
      expect(h.ytSessions.stored, isNull);
      expect(find.text('Sign in to YouTube'), findsOneWidget);
      expect(find.byKey(const Key('island')), findsNothing);
      expect(containerOf(tester).read(ytAuthProvider), isA<YtSignedOut>());
    });

    uiTest('Sign out asks, clears, offers Sign in again and reloads Home', (
      tester,
    ) async {
      var homeBuilds = 0;
      await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
        extra: [
          ytmHomeProvider.overrideWith((ref) async {
            homeBuilds++;
            return const YtmHome([], null);
          }),
        ],
      );
      final c = containerOf(tester);
      final sub = c.listen(ytmHomeProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);
      final before = homeBuilds;

      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.text('Sign out of YouTube?'), findsOneWidget);
      // Cancel keeps the sign-in.
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(h.ytSessions.stored, isNotNull);
      expect(find.text('Signed in as Name'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings.ytSignOut.confirm')));
      await settle(tester);

      expect(h.ytSessions.stored, isNull);
      expect(c.read(ytAuthProvider), isA<YtSignedOut>());
      expect(find.text('Sign in to YouTube'), findsOneWidget);
      expect(find.text('Signed in as Name'), findsNothing);
      expect(homeBuilds, greaterThan(before));
    });

    Future<void> confirmSignOut(WidgetTester tester) async {
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings.ytSignOut.confirm')));
      await settle(tester);
    }

    uiTest('Sign out asks every route to forget its web data', (tester) async {
      final route = await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
      );
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);
      expect(route.forgets, 0);

      await confirmSignOut(tester);
      expect(route.forgets, 1);
    });

    uiTest('a route that fails to forget does not break Sign out', (
      tester,
    ) async {
      final route = await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
      );
      route.forgetThrows = true;
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);

      await confirmSignOut(tester);
      expect(route.forgets, 1);
      expect(h.ytSessions.stored, isNull);
      expect(containerOf(tester).read(ytAuthProvider), isA<YtSignedOut>());
      expect(find.text('Sign in to YouTube'), findsOneWidget);
      expect(find.byKey(const Key('island')), findsNothing);
    });

    uiTest('a keyring that fails to clear still signs out', (tester) async {
      var homeBuilds = 0;
      await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
        extra: [
          ytmHomeProvider.overrideWith((ref) async {
            homeBuilds++;
            return const YtmHome([], null);
          }),
        ],
      );
      final c = containerOf(tester);
      final sub = c.listen(ytmHomeProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);
      final before = homeBuilds;
      h.ytSessions.clearThrows = true;

      await confirmSignOut(tester);

      expect(
        find.text("Signed out, but the keyring couldn't be cleared"),
        findsOneWidget,
      );
      expect(c.read(ytAuthProvider), isA<YtSignedOut>());
      expect(
        await real(
          tester,
          () => SettingsRepository(h.db).getBool(kYtSignedIn, fallback: true),
        ),
        isFalse,
      );
      expect(homeBuilds, greaterThan(before));
    });

    uiTest('a keyring that fails to save says so and stays signed out', (
      tester,
    ) async {
      h.ytSessions.writeThrows = true;
      await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
      );
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);

      expect(find.text("Couldn't save the YouTube sign-in"), findsOneWidget);
      expect(find.textContaining('keyring write failed'), findsNothing);
      expect(
        containerOf(tester).read(ytAuthProvider),
        isNot(isA<YtSignedIn>()),
      );
      expect(find.text('Signed in as Name'), findsNothing);
    });

    uiTest('no keyring but still marked signed in: Sign out stays', (
      tester,
    ) async {
      await real(
        tester,
        () => SettingsRepository(h.db).setBool(kYtSignedIn, true),
      );
      h.ytSessions.isAvailable = false;
      final route = await pumpWithRoute(tester, null);
      expect(
        find.text(
          'Sign-in needs a keyring (KWallet or GNOME Keyring), '
          "which isn't available",
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in to YouTube'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);

      await confirmSignOut(tester);
      expect(route.forgets, 1);
      expect(
        await real(
          tester,
          () => SettingsRepository(h.db).getBool(kYtSignedIn, fallback: true),
        ),
        isFalse,
      );
      expect(find.text('Sign out'), findsNothing);
      expect(
        containerOf(tester).read(ytAuthProvider),
        isA<YtAuthUnavailable>(),
      );
    });

    uiTest('an expired sign-in offers Sign in again', (tester) async {
      final route = await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
      );
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);
      containerOf(tester).read(ytAuthProvider.notifier).markExpired();
      await settle(tester);

      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('Sign in to YouTube'), findsNothing);

      await tester.tap(find.text('Sign in again'));
      await settle(tester);
      expect(route.runs, 2);
      expect(find.text('Signed in as Name'), findsOneWidget);
    });

    uiTest('an expired sign-in offers every route again', (tester) async {
      final page = _FakeRoute(YtSignInResult(session: session, name: 'Name'));
      final browser = _FakeRoute(
        YtSignInResult(session: session, name: 'Name'),
        label: 'Use the YouTube sign-in from my browser',
      );
      h.ytSignInRoutes = [page, browser];
      await pumpSection(tester);
      await tester.tap(find.text('Sign in to YouTube'));
      await settle(tester);
      containerOf(tester).read(ytAuthProvider.notifier).markExpired();
      await settle(tester);

      expect(find.text('Sign in again'), findsOneWidget);
      expect(
        find.text('Use the YouTube sign-in from my browser'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use the YouTube sign-in from my browser'));
      await settle(tester);
      expect(browser.runs, 1);
      expect(find.text('Signed in as Name'), findsOneWidget);
    });

    uiTest('no keyring: explains why and offers no sign-in', (tester) async {
      h.ytSessions.isAvailable = false;
      await pumpWithRoute(
        tester,
        YtSignInResult(session: session, name: 'Name'),
      );
      expect(
        find.text(
          'Sign-in needs a keyring (KWallet or GNOME Keyring), '
          "which isn't available",
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in to YouTube'), findsNothing);
      // The rest of the section still works.
      expect(find.text('Update yt-dlp'), findsOneWidget);
    });

    uiTest('no sign-in routes (Linux for now): no sign-in row', (tester) async {
      h.ytSignInRoutes = const [];
      await pumpSection(tester);
      expect(find.text('Sign in to YouTube'), findsNothing);
    });
  });
}

class _FakeDeno extends DenoInstaller {
  _FakeDeno()
    : super(
        Directory.systemTemp,
        download: (uri, {onProgress}) async => [],
        isWindows: false,
      );

  int removed = 0;

  @override
  Future<void> remove() async => removed++;
}
