import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:songies/account/account_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _user = {
  'id': 'u1',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'a@b.c',
  'app_metadata': <String, Object?>{},
  'user_metadata': <String, Object?>{},
  'created_at': '2026-11-05T00:00:00Z',
};

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);

/// A real [SupabaseAccountBackend] on a client whose HTTP is [handler].
(SupabaseAccountBackend, SupabaseClient, List<String>) _backend(
  http.Response Function(http.Request) handler,
) {
  final seen = <String>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'key',
    httpClient: MockClient((r) async {
      seen.add('${r.method} ${r.url.path}');
      return handler(r);
    }),
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
  );
  return (SupabaseAccountBackend(client), client, seen);
}

Matcher _throwsAccount(AccountError e) =>
    throwsA(isA<AccountException>().having((x) => x.error, 'error', e));

void main() {
  test(
    'sign up answering a user with no identities gives emailTaken',
    () async {
      final (backend, client, _) = _backend(
        (r) => _json(200, {..._user, 'identities': <Object>[]}),
      );
      addTearDown(client.dispose);
      await expectLater(
        backend.signUp('a@b.c', 'password1', 'den'),
        _throwsAccount(AccountError.emailTaken),
      );
    },
  );

  test('sign up of a new user needs the code', () async {
    final (backend, client, _) = _backend(
      (r) => _json(200, {
        ..._user,
        'identities': [
          {'id': 'i1', 'user_id': 'u1', 'provider': 'email'},
        ],
      }),
    );
    addTearDown(client.dispose);
    expect(await backend.signUp('a@b.c', 'password1', 'den'), isNull);
  });

  test(
    'a refused new password drops the recovery session and never reports it',
    () async {
      final (backend, client, seen) = _backend((r) {
        if (r.url.path.endsWith('/verify')) {
          return _json(200, {
            'access_token': 'at',
            'refresh_token': 'rt',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': _user,
          });
        }
        if (r.url.path.endsWith('/user')) {
          return _json(422, {'code': 'same_password', 'msg': 'same'});
        }
        return http.Response('', 204);
      });
      addTearDown(client.dispose);
      final ids = <String?>[];
      final sub = backend.userIdChanges.listen(ids.add);
      addTearDown(sub.cancel);

      await expectLater(
        backend.resetPassword('a@b.c', '123456', 'password1'),
        _throwsAccount(AccountError.samePassword),
      );
      await pumpEventQueue();
      expect(client.auth.currentSession, isNull);
      expect(ids.whereType<String>(), isEmpty);
      expect(seen, contains('POST /auth/v1/logout'));
    },
  );
}
