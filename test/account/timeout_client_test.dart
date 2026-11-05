import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:songies/account/account_backend.dart';
import 'package:songies/account/timeout_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A server that never answers.
MockClient _blackHole() => MockClient((_) => Completer<http.Response>().future);

void main() {
  test('the default timeout is 20 s', () {
    expect(kAccountHttpTimeout, const Duration(seconds: 20));
  });

  test('a request with no answer times out', () async {
    final c = TimeoutClient(
      _blackHole(),
      timeout: const Duration(milliseconds: 50),
    );
    addTearDown(c.close);
    await expectLater(
      c.get(Uri.parse('https://example.com/')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a body that stops arriving times out', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final c = TimeoutClient(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(body.stream, 200),
      ),
      timeout: const Duration(milliseconds: 50),
    );
    addTearDown(c.close);
    body.add([1, 2]);
    await expectLater(
      c.get(Uri.parse('https://example.com/')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('an answer in time passes through', () async {
    final c = TimeoutClient(
      MockClient((_) async => http.Response('ok', 201)),
      timeout: const Duration(milliseconds: 500),
    );
    addTearDown(c.close);
    final r = await c.get(Uri.parse('https://example.com/'));
    expect(r.statusCode, 201);
    expect(r.body, 'ok');
  });

  test('auth and database calls that time out count as offline', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      httpClient: TimeoutClient(
        _blackHole(),
        timeout: const Duration(milliseconds: 50),
      ),
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    addTearDown(client.dispose);
    final backend = SupabaseAccountBackend(client);
    Matcher offline() => throwsA(
      isA<AccountException>().having(
        (e) => e.error,
        'error',
        AccountError.offline,
      ),
    );
    await expectLater(backend.logIn('a@b.c', 'password1'), offline());
    await expectLater(backend.usernameAvailable('den'), offline());
  });
}
