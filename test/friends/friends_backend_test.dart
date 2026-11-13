import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/friends/friends_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_friends_backend.dart';

void main() {
  test('escapeLike escapes wildcards', () {
    expect(escapeLike(r'a_b%c\'), r'a\_b\%c\\');
    expect(escapeLike('den'), 'den');
  });

  test('a search pattern keeps only username letters', () {
    expect(usernameSearchPattern('De'), 'de%');
    expect(usernameSearchPattern('  a_b.c '), r'a\_b.c%');
    // `*` is a wildcard to the server: it never reaches it.
    expect(usernameSearchPattern('**'), isNull);
    expect(usernameSearchPattern('a*'), isNull);
    expect(usernameSearchPattern('d*e%n'), 'den%');
  });

  test('unexpected failures become FriendsExceptions', () async {
    final answers = <Object? Function()>[
      () => throw const HandshakeException('captive portal'),
      () => throw const FormatException('<html>502'),
    ];
    final b = SupabaseFriendsBackend.withRpc(
      (fn, params) async => answers.removeAt(0)(),
    );
    for (final want in [FriendsError.offline, FriendsError.other]) {
      await expectLater(
        b.accept('u2'),
        throwsA(isA<FriendsException>().having((e) => e.error, 'error', want)),
      );
    }
  });

  test('send maps pending and accepted; server errors map', () async {
    final answers = <Object? Function()>[
      () => 'pending',
      () => 'accepted',
      () => throw const PostgrestException(message: 'self_request'),
      () => throw const PostgrestException(message: 'unknown_user'),
      () => throw const SocketException('down'),
    ];
    final calls = <(String, Map<String, Object?>)>[];
    final b = SupabaseFriendsBackend.withRpc((fn, params) async {
      calls.add((fn, params));
      return answers.removeAt(0)();
    });
    expect(await b.send('u2'), FriendLink.outgoing);
    expect(calls.single.$1, 'send_friend_request');
    expect(calls.single.$2, {'p_other': 'u2'});
    expect(await b.send('u2'), FriendLink.friend);
    for (final want in [
      FriendsError.selfRequest,
      FriendsError.unknownUser,
      FriendsError.offline,
    ]) {
      await expectLater(
        b.send('u2'),
        throwsA(isA<FriendsException>().having((e) => e.error, 'error', want)),
      );
    }
  });

  test('accept and remove call their functions', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final b = SupabaseFriendsBackend.withRpc((fn, params) async {
      calls.add((fn, params));
      if (fn == 'accept_friend_request' && calls.length > 1) {
        throw const PostgrestException(message: 'not_requested');
      }
      return null;
    });
    await b.accept('u2');
    await expectLater(
      b.accept('u3'),
      throwsA(
        isA<FriendsException>().having(
          (e) => e.error,
          'error',
          FriendsError.notRequested,
        ),
      ),
    );
    await b.remove('u2');
    expect(calls.map((c) => c.$1), [
      'accept_friend_request',
      'accept_friend_request',
      'remove_friend',
    ]);
    expect(calls.last.$2, {'p_other': 'u2'});
  });

  test('the fake follows the server rules', () async {
    final f = FakeFriendsBackend()
      ..addUser('a', 'ann')
      ..addUser('b', 'ben');
    f.me = 'a';
    expect(await f.send('b'), FriendLink.outgoing);
    f.me = 'b';
    expect((await f.load('b')).single.link, FriendLink.incoming);
    // Crossed: B asking A accepts A's request.
    expect(await f.send('a'), FriendLink.friend);
    expect((await f.load('a')).single.link, FriendLink.friend);
    expect((await f.load('b')).single.link, FriendLink.friend);
    f.me = 'a';
    await expectLater(
      f.send('a'),
      throwsA(
        isA<FriendsException>().having(
          (e) => e.error,
          'error',
          FriendsError.selfRequest,
        ),
      ),
    );
  });
}
