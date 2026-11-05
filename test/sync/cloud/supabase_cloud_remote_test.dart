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
    final (seq, row) = (await remote.pull(0)).single;
    expect(seq, 42);
    expect(row.table, SyncTable.themes);
    expect(row.clock, '1800000000001-00000-x');
    expect(row.deleted, isTrue);
  });
}
