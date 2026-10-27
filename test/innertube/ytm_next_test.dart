import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late FakeTransport transport;
  late InnertubeClient client;
  late YtmService ytm;

  setUp(() async {
    db = testDb();
    transport = FakeTransport();
    client = InnertubeClient(transport, SettingsRepository(db));
    ytm = YtmService(client);
  });
  tearDown(() async {
    client.dispose();
    await db.close();
  });

  test('radio: songs without the seed, rich current, continuation', () async {
    transport.reply(fixture('next_radio'));
    final res = await ytm.radio('4D7u5KF7SP8');
    final radio = (res as Ok<YtmRadio>).value;
    expect(radio.songs.length, greaterThanOrEqualTo(20));
    expect(radio.songs.any((s) => s.videoId == '4D7u5KF7SP8'), isFalse);
    expect(radio.current?.videoId, '4D7u5KF7SP8');
    expect(radio.current?.album, 'Random Access Memories');
    expect(radio.current?.albumBrowseId, 'MPREb_K8qWMWVqXGi');
    expect(radio.current?.durationMs, (6 * 60 + 10) * 1000);
    expect(radio.current?.thumbnailUrl, endsWith('=w544-h544-l90-rj'));
    expect(radio.current?.artists.first.browseId, startsWith('UC'));
    for (final s in radio.songs) {
      expect(s.title, isNotEmpty);
      expect(s.artists, isNotEmpty);
    }
    expect(radio.continuation, isNotNull);

    final body = transport.requests.single.body;
    expect(body['videoId'], '4D7u5KF7SP8');
    expect(body['playlistId'], 'RDAMVM4D7u5KF7SP8');
    expect(body['params'], 'wAEB');
    expect(body['isAudioOnly'], true);
    expect(body['enablePersistentPlaylistPanel'], true);
    expect(body['tunerSettingValue'], 'AUTOMIX_SETTING_NORMAL');
    expect(transport.requests.single.url.path, endsWith('/next'));
  });

  test('radio continuation sends the token and parses more songs', () async {
    final rows =
        ((((((((fixture('next_radio').json!['contents']!
                                            as Map)['singleColumnMusicWatchNextResultsRenderer']!
                                        as Map)['tabbedRenderer']!
                                    as Map)['watchNextTabbedResultsRenderer']!
                                as Map)['tabs']!
                            as List)[0]
                        as Map)['tabRenderer']!
                    as Map)['content']!
                as Map)['musicQueueRenderer']!
            as Map;
    final contents =
        ((rows['content']! as Map)['playlistPanelRenderer']!
                as Map)['contents']!
            as List;
    transport.reply(
      InnertubeResponse(200, {
        'continuationContents': {
          'playlistPanelContinuation': {
            'contents': contents.sublist(1, 4),
            'continuations': [
              {
                'nextRadioContinuationData': {'continuation': 'NEXT'},
              },
            ],
          },
        },
      }),
    );
    final res = await ytm.radio('4D7u5KF7SP8', continuation: 'TOK');
    final radio = (res as Ok<YtmRadio>).value;
    expect(transport.requests.single.body['continuation'], 'TOK');
    expect(radio.songs, hasLength(3));
    expect(radio.current, isNull);
    expect(radio.continuation, 'NEXT');
  });

  test('a transport error is passed through', () async {
    transport.reply(InnertubeResponse(403, null));
    final res = await ytm.radio('4D7u5KF7SP8');
    expect(res, isA<Err<YtmRadio>>());
    expect((res as Err).failure.message, contains('HTTP 403'));
  });
}
