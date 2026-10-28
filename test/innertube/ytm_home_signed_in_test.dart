// Plan 7: the signed-in Home feed, and the quiet fallback when YouTube no
// longer accepts the session.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_session_store.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';
import 'package:songies/providers.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/fake_network_status.dart';
import '../helpers/fake_ytm.dart';
import '../helpers/test_db.dart';

/// A transport whose next request takes its reply at once, then waits for
/// [gate] (when set) before answering.
class _GatedTransport extends FakeTransport {
  Completer<void>? gate;

  @override
  Future<InnertubeResponse> post(
    Uri url,
    Map<String, Object?> body,
    Map<String, String> headers,
  ) async {
    final g = gate;
    gate = null;
    final reply = super.post(url, body, headers);
    if (g != null) await g.future;
    return reply;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late _GatedTransport transport;
  late InnertubeClient client;
  late FakeYtSessionStore store;
  late ProviderContainer c;
  late List<String> logs;
  DebugPrintCallback? savedPrint;

  final session = YtSession({'SID': 'SIDSECRET', 'SAPISID': 'SAPISECRET'});

  setUp(() async {
    db = testDb();
    settings = SettingsRepository(db);
    transport = _GatedTransport();
    client = InnertubeClient(transport, settings);
    store = FakeYtSessionStore();
    c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        ytSessionStoreProvider.overrideWithValue(store),
        innertubeClientProvider.overrideWithValue(client),
        networkStatusProvider.overrideWithValue(FakeNetworkStatus()),
      ],
    );
    logs = [];
    savedPrint = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
  });
  tearDown(() async {
    debugPrint = savedPrint!;
    c.dispose();
    client.dispose();
    await db.close();
  });

  Future<void> signIn() =>
      c.read(ytAuthProvider.notifier).signIn(session, name: 'N');

  bool authed(FakeRequest r) => r.headers.containsKey('Authorization');

  group('service', () {
    test('the signed-in Home parses into shelves and says signed in', () async {
      transport.reply(fixture('home_signed_in'));
      final ytm = YtmService(client);
      final home = ((await ytm.home(session: session)) as Ok<YtmHome>).value;
      expect(home.signedIn, isTrue);
      expect(home.shelves.length, greaterThanOrEqualTo(3));
      expect(home.shelves[1].title, 'Listen again');
      for (final s in home.shelves) {
        expect(s.items, isNotEmpty);
      }
    });

    test('the signed-out marker parses too, not signed in', () async {
      transport.reply(fixture('home_signed_out_marker'));
      final ytm = YtmService(client);
      final home = ((await ytm.home(session: session)) as Ok<YtmHome>).value;
      expect(home.signedIn, isFalse);
      expect(home.shelves, isNotEmpty);
    });

    test('signedInMarker is three-way: the marker, loggedOut, or null', () {
      expect(signedInMarker(fixture('home_signed_in').json!), isTrue);
      expect(signedInMarker(fixture('home_signed_out_marker').json!), isFalse);
      expect(signedInMarker(fixture('browse_home').json!), isNull);
      expect(signedInMarker(const {}), isNull);
      expect(
        signedInMarker(const {
          'responseContext': {
            'mainAppWebResponseContext': {'loggedOut': true},
          },
        }),
        isFalse,
      );
      expect(
        signedInMarker(const {
          'responseContext': {
            'mainAppWebResponseContext': {'loggedOut': false},
          },
        }),
        isTrue,
      );
    });

    test(
      'a signed-in Home without a marker counts as signed in (R6)',
      () async {
        transport.reply(fixture('browse_home'));
        final ytm = YtmService(client);
        final home = ((await ytm.home(session: session)) as Ok<YtmHome>).value;
        expect(home.signedIn, isTrue);
        expect(home.markerMissing, isTrue);
      },
    );

    test('a Home without a session is never signed in', () async {
      transport.reply(fixture('home_signed_in'));
      final home = ((await YtmService(client).home()) as Ok<YtmHome>).value;
      expect(home.signedIn, isFalse);
    });
  });

  group('provider', () {
    test(
      'signed in: Home goes out signed in, read from the keyring once',
      () async {
        await signIn();
        transport.reply(fixture('home_signed_in'));
        final home = await c.read(ytmHomeProvider.future);
        expect(home.signedIn, isTrue);
        expect(authed(transport.requests.single), isTrue);
        expect(c.read(ytAuthProvider), isA<YtSignedIn>());
      },
    );

    test('marked signed in at startup: the session is read lazily', () async {
      store.stored = session;
      await settings.setBool(kYtSignedIn, true);
      await c.read(ytAuthProvider.notifier).load();
      expect(store.reads, 0);
      transport.reply(fixture('home_signed_in'));
      await c.read(ytmHomeProvider.future);
      expect(store.reads, 1);
      expect(authed(transport.requests.single), isTrue);
    });

    test('signed out: no Authorization', () async {
      transport.reply(fixture('browse_home'));
      await c.read(ytmHomeProvider.future);
      expect(authed(transport.requests.single), isFalse);
      expect(store.reads, 0);
    });

    for (final (what, refusal) in [
      ('a logged_in=0 response', fixture('home_signed_out_marker')),
      ('HTTP 401', const InnertubeResponse(401, null)),
      ('HTTP 403', const InnertubeResponse(403, null)),
    ]) {
      test('$what: one anonymous retry, expired, and no loop', () async {
        await signIn();
        transport
          ..reply(refusal)
          ..reply(fixture('browse_home'));
        final home = await c.read(ytmHomeProvider.future);
        expect(home.shelves, isNotEmpty);
        expect(home.signedIn, isFalse);
        expect(transport.requests.map(authed), [true, false]);
        expect(c.read(ytAuthProvider), isA<YtExpired>());
        // Kept until Sign out or a new sign-in.
        expect(store.stored, session);

        // Opening Home again: signed out, a single request.
        transport.reply(fixture('browse_home'));
        c.invalidate(ytmHomeProvider);
        await c.read(ytmHomeProvider.future);
        expect(transport.requests.map(authed), [true, false, false]);
        expect(c.read(ytAuthProvider), isA<YtExpired>());
      });
    }

    test(
      'no marker: signed in, one log line, no expiry and no retry (R6)',
      () async {
        await signIn();
        transport.reply(fixture('browse_home'));
        final home = await c.read(ytmHomeProvider.future);
        expect(home.signedIn, isTrue);
        expect(transport.requests.map(authed), [true]);
        expect(c.read(ytAuthProvider), isA<YtSignedIn>());
        expect(
          logs.where(
            (l) =>
                l.contains('ytm home: no signed-in marker; assuming signed in'),
          ),
          hasLength(1),
        );
      },
    );

    test('a signed-in network failure is an error, not an expiry', () async {
      await signIn();
      transport.reply(const SocketException('down'));
      await expectLater(
        c.read(ytmHomeProvider.future),
        throwsA(isA<YtmLoadFailed>()),
      );
      expect(transport.requests, hasLength(1));
      expect(c.read(ytAuthProvider), isA<YtSignedIn>());
    });

    group('no secrets in failures or logs', () {
      final hashPrefix = 'SAPISIDHASH';
      void clean(Object error) {
        final text = ['$error', ...logs].join('\n');
        expect(text, isNot(contains('SIDSECRET')));
        expect(text, isNot(contains('SAPISECRET')));
        expect(text, isNot(contains(hashPrefix)));
      }

      for (final (what, reply) in [
        (
          'a socket error',
          SocketException('Cookie: ${session.cookieHeader()} SAPISIDHASH 1_x'),
        ),
        ('bad JSON', const FormatException('SAPISECRET', 'SIDSECRET')),
      ]) {
        test(what, () async {
          await signIn();
          transport.reply(reply);
          Object? error;
          try {
            await c.read(ytmHomeProvider.future);
          } catch (e) {
            error = e;
          }
          expect(error, isA<YtmLoadFailed>());
          expect(logs, isNotEmpty);
          clean(error!);
        });
      }

      test('HTTP 403 (then the regular feed)', () async {
        await signIn();
        transport
          ..reply(const InnertubeResponse(403, null))
          ..reply(fixture('browse_home'));
        await c.read(ytmHomeProvider.future);
        expect(logs, isNotEmpty);
        clean('');
      });
    });

    test('sign out mid-load: the late signed-in feed is never shown', () async {
      await signIn();
      final gate = Completer<void>();
      transport
        ..gate = gate
        ..reply(fixture('home_signed_in'))
        ..reply(fixture('browse_home'));
      final sub = c.listen(ytmHomeProvider, (_, _) {}, fireImmediately: true);
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(transport.requests.map(authed), [true]);

      await c.read(ytAuthProvider.notifier).signOut();
      gate.complete();
      final home = await c.read(ytmHomeProvider.future);
      await pumpEventQueue();
      expect(home.signedIn, isFalse);
      expect(c.read(ytmHomeProvider).value?.signedIn, isFalse);
      expect(c.read(ytAuthProvider), isA<YtSignedOut>());
      expect(store.stored, isNull);
      expect(transport.requests.map(authed), [true, false]);

      // The next open goes out signed out too.
      transport.reply(fixture('browse_home'));
      c.invalidate(ytmHomeProvider);
      await c.read(ytmHomeProvider.future);
      expect(transport.requests.map(authed), [true, false, false]);
    });

    test('signing in reloads Home, signed in', () async {
      transport.reply(fixture('browse_home'));
      final sub = c.listen(ytmHomeProvider, (_, _) {}, fireImmediately: true);
      addTearDown(sub.close);
      await c.read(ytmHomeProvider.future);
      transport.reply(fixture('home_signed_in'));
      await signIn();
      final home = await c.read(ytmHomeProvider.future);
      expect(home.signedIn, isTrue);
      expect(transport.requests.map(authed), [false, true]);
    });
  });
}
