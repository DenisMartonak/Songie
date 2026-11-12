import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:songies/sync/cloud/cloud_remote.dart';
import 'package:songies/sync/sync_row.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SyncRow _row() => SyncRow(SyncTable.themes, {
  'id': 'th1',
  'clock': '1800000000000-00000-dev',
  'originDevice': 'dev',
  'deleted': false,
  'localSeq': 3,
  'name': 'N',
  'specJson': '{}',
});

void main() {
  SupabaseCloudRemote remoteOn(
    MockClient http, {
    Duration timeout = kCloudCallTimeout,
  }) {
    final client = SupabaseClient(
      'http://localhost:54321',
      'anon',
      httpClient: http,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    return SupabaseCloudRemote(() => client, timeout: timeout);
  }

  test('push sends the rows to push_rows without the local seq', () async {
    late Map<String, dynamic> body;
    final remote = remoteOn(
      MockClient((r) async {
        expect(r.url.path, '/rest/v1/rpc/push_rows');
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('1', 200, request: r);
      }),
    );
    expect(await remote.push([_row()]), 1);
    final sent = (body['rows'] as List).single as Map<String, dynamic>;
    expect(sent['tbl'], 'themes');
    expect(sent['origin_device'], 'dev');
    expect((sent['data'] as Map).containsKey('localSeq'), isFalse);
  });

  test("the server's row refusals become CloudRejected; others stay", () async {
    Future<Object?> refusal(String message, {String code = 'P0001'}) async {
      final remote = remoteOn(
        MockClient(
          (r) async => http.Response(
            jsonEncode({'code': code, 'message': message}),
            400,
            request: r,
          ),
        ),
      );
      try {
        await remote.push([_row()]);
        return null;
      } catch (e) {
        return e;
      }
    }

    expect(
      await refusal('clock more than a day in the future'),
      isA<CloudRejected>().having(
        (e) => e.reason,
        'reason',
        CloudRejection.clockAhead,
      ),
    );
    expect(
      await refusal('row data over 256 KB'),
      isA<CloudRejected>().having(
        (e) => e.reason,
        'reason',
        CloudRejection.tooBig,
      ),
    );
    expect(
      await refusal(
        'invalid row in push (tbl, id, clock, origin_device, '
        'deleted or data)',
      ),
      isA<CloudRejected>().having(
        (e) => e.reason,
        'reason',
        CloudRejection.invalidRow,
      ),
    );
    // Postgres data exceptions (class 22): a value it can't store.
    for (final code in ['22P05', '22021']) {
      expect(
        await refusal('unsupported Unicode escape sequence', code: code),
        isA<CloudRejected>().having(
          (e) => e.reason,
          'reason',
          CloudRejection.badData,
        ),
      );
    }
    expect(await refusal('not signed in'), isA<PostgrestException>());
    expect(
      await refusal('JWT expired', code: 'PGRST301'),
      isA<PostgrestException>(),
    );
  });

  test('a call that hangs counts as offline after the timeout', () async {
    final remote = remoteOn(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(remote.pull(0), throwsA(isA<CloudOffline>()));
    await expectLater(remote.push([_row()]), throwsA(isA<CloudOffline>()));
  });

  test('pull maps rows, the stamp columns winning over data', () async {
    final remote = remoteOn(
      MockClient(
        (r) async => http.Response(
          jsonEncode([
            {
              'tbl': 'themes',
              'id': 'th1',
              'clock': '1800000000001-00000-x',
              'origin_device': 'x',
              'deleted': true,
              'server_seq': 42,
              'data': {
                'id': 'th1',
                'clock': 'stale',
                'name': 'N',
                'specJson': '{}',
              },
            },
          ]),
          200,
          request: r,
        ),
      ),
    );
    final pulled = (await remote.pull(0)).single;
    expect(pulled.serverSeq, 42);
    // A row from before formats were recorded counts as the first one.
    expect(pulled.fmt, kRowFormat);
    final row = pulled.row!;
    expect(row.table, SyncTable.themes);
    expect(row.clock, '1800000000001-00000-x');
    expect(row.deleted, isTrue);
  });

  test('push sends the row format and escapes NUL in strings', () async {
    late Map<String, dynamic> body;
    final remote = remoteOn(
      MockClient((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('1', 200, request: r);
      }),
    );
    final row = SyncRow(SyncTable.lyrics, {
      'id': 't1',
      'clock': '1800000000000-00000-dev',
      'originDevice': 'dev',
      'deleted': false,
      'localSeq': 3,
      'kind': 'plain',
      'body': 'la\n\u0000credit:X \uE000 end',
      'source': 'youtube',
      'fetchedAt': 5,
    });
    await remote.push([row]);
    final sent = (body['rows'] as List).single as Map<String, dynamic>;
    expect(sent['fmt'], kRowFormat);
    final data = sent['data'] as Map<String, dynamic>;
    expect(data['body'], isNot(contains('\u0000')));
    expect(data['source'], 'youtube');
  });

  test('rowFromServer undoes the NUL escaping of rowToServer', () {
    final row = SyncRow(SyncTable.lyrics, {
      'id': 't1',
      'clock': '1800000000000-00000-dev',
      'originDevice': 'dev',
      'deleted': false,
      'localSeq': 3,
      'kind': 'plain',
      'body': '\u0000a\uE000\uE0000\u0000\u0000\uE000E\uE000',
      'source': null,
      'fetchedAt': 5,
    });
    final wire =
        jsonDecode(jsonEncode(rowToServer(row))) as Map<String, dynamic>;
    expect(jsonEncode(wire), isNot(contains(r'\u0000')));
    final back = rowFromServer({...wire, 'server_seq': 1});
    expect(back.row!.data['body'], row.data['body']);
    expect(back.row!.data['source'], isNull);
    expect(back.row!.data['fetchedAt'], 5);
  });

  test('pull leaves out rows this app cannot read, keeping their seq', () {
    Map<String, dynamic> theme(
      int seq, {
      int? fmt,
      Map<String, dynamic>? data,
    }) => {
      'tbl': 'themes',
      'id': 'th$seq',
      'clock': '1800000000001-00000-x',
      'origin_device': 'x',
      'deleted': false,
      'server_seq': seq,
      'fmt': ?fmt,
      'data': data ?? {'name': 'N', 'specJson': '{}'},
    };
    final ok = rowFromServer(theme(1, fmt: kRowFormat));
    expect(ok.row, isNotNull);
    final newer = rowFromServer(theme(2, fmt: kRowFormat + 1));
    expect((newer.serverSeq, newer.fmt, newer.row), (2, kRowFormat + 1, null));
    // A required column missing.
    final broken = rowFromServer(theme(3, data: {'name': 'N'}));
    expect((broken.serverSeq, broken.row), (3, null));
    final unknownTable = rowFromServer({...theme(4), 'tbl': 'moods'});
    expect((unknownTable.serverSeq, unknownTable.row), (4, null));
  });

  test('rowFromServer reads a saved_artists row with fmt 11 and parks fmt 12', () {
    Map<String, dynamic> artist(int fmt) => {
      'tbl': 'saved_artists',
      'id': 'artist:UC1',
      'clock': '1800000000001-00000-x',
      'origin_device': 'x',
      'deleted': false,
      'server_seq': 5,
      'fmt': fmt,
      'data': {'browseId': 'UC1', 'name': 'N', 'savedAt': 1700000000000},
    };
    final ok = rowFromServer(artist(11));
    expect(ok.row!.table, SyncTable.savedArtists);
    expect(ok.row!.data['browseId'], 'UC1');
    final newer = rowFromServer(artist(12));
    expect((newer.serverSeq, newer.fmt, newer.row), (5, 12, null));
  });

  test('broadcastSeq reads the server seq of a changed message', () {
    expect(broadcastSeq({'server_seq': 7}), 7);
    expect(
      broadcastSeq({
        'type': 'broadcast',
        'event': 'changed',
        'payload': {'server_seq': 8},
      }),
      8,
    );
    expect(broadcastSeq({'event': 'changed'}), isNull);
  });
}
