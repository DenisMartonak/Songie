import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/theme_spec.dart';

/// Real, popular songs from YouTube Music, pinned by video id (looked up
/// 2026-11-11) so a recording never depends on search results.
const demoSongs = <YtmSong>[
  YtmSong(
    videoId: 'h-zuG75Ds-w',
    title: 'Nicole Kidman',
    artists: [YtmArtistRef(name: 'ADÉLA')],
    album: 'PRIMA',
    durationMs: 182000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/mHa1sg5pmlgudnTZ_XOcJ-0VAKuFDodEstxurIF2C6RttpfyyeaqC75FmPQjlc2BQQ5JfvGaFuU69dhs=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'nyNm-dVBMoo',
    title: 'Ain\'t In LA',
    artists: [YtmArtistRef(name: 'ADÉLA')],
    album: 'PRIMA',
    durationMs: 185000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/mHa1sg5pmlgudnTZ_XOcJ-0VAKuFDodEstxurIF2C6RttpfyyeaqC75FmPQjlc2BQQ5JfvGaFuU69dhs=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'kIft-LUHHVA',
    title: 'Espresso',
    artists: [YtmArtistRef(name: 'Sabrina Carpenter')],
    album: 'Short n\' Sweet',
    durationMs: 176000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/bTWlZSenrOAYgH4r6NAzyDraWQR_wLl3OuRexJ_8h3NZUVHEilRSzUmKNa9YMOFSVcF0YtOuzKdXrt2UHg=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'WKZO-CWeOVA',
    title: 'BIRDS OF A FEATHER',
    artists: [YtmArtistRef(name: 'Billie Eilish')],
    album: 'HIT ME HARD AND SOFT',
    durationMs: 211000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/mXJjWX4E6Gpr03CUYl18PdVXlczmoL2Tm-LEBGafIr_8smlHnl8AHniJu0_7Y80e-aeloJxcryQQx0ZJ=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'DiTd771WumE',
    title: 'APT.',
    artists: [YtmArtistRef(name: 'ROSÉ'), YtmArtistRef(name: 'Bruno Mars')],
    album: 'rosie',
    durationMs: 170000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/-MtYkhdYuOvj8YWHA4afh-OUYMYHNpBpkk047QgGAxLJMLE570Pj0-LQjA2PW1ltedqTusKOjzXvuS8=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'VZ-oGLluGAc',
    title: 'Good Luck, Babe!',
    artists: [YtmArtistRef(name: 'Chappell Roan')],
    album: 'Good Luck, Babe!',
    durationMs: 219000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/vB4Sh2i4BvMg5qn9Jt6sy09IsMfX4whFcI2QxDLvYbDIR5jWLJjqM0oyD4U0CiS2ywIj13JQ-U91BaWA=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'J7p4bzqLvCw',
    title: 'Blinding Lights',
    artists: [YtmArtistRef(name: 'The Weeknd')],
    album: 'Blinding Lights',
    durationMs: 202000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/R_cjQK3wwLPEzri1jerx-79zgzGocoKvwGU3NMONaTsaMM0Idd641pfB8r5jgfpn6I8JAoFtf9RBIcI=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'OsfAnsMY21M',
    title: 'Levitating',
    artists: [YtmArtistRef(name: 'Dua Lipa')],
    album: 'Future Nostalgia',
    durationMs: 204000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/UpJ_IhBqyhQV9b2UGcDxxWDm14kRQ2eY1o9S96AGsbE7Ol8isbpbPA0Yefvg8S8ZGAX9L1g4xaj21zVJ=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'nujn6wbr-e8',
    title: 'As It Was',
    artists: [YtmArtistRef(name: 'Harry Styles')],
    album: 'Harry\'s House',
    durationMs: 168000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/F618Qwn2yRlYhCqlMtEMnFHajg4rGZSGeWOF4ro7l3I9R6y7aGfowqqiNQqj6CgVR0yepTK6T5aRSfAF=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'DlFXDl_ROAM',
    title: 'Die With A Smile',
    artists: [YtmArtistRef(name: 'Lady Gaga'), YtmArtistRef(name: 'Bruno Mars')],
    album: 'MAYHEM',
    durationMs: 252000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/RFK4wHeGqwI3DndbARbRJB21IC0TcmqnrlyjxYK7T-nC8wlIVbfxNaCIFKNvSpchDKmYyVLe1RN36w=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'BkSSOGNeWTM',
    title: 'Flowers',
    artists: [YtmArtistRef(name: 'Miley Cyrus')],
    album: 'Flowers',
    durationMs: 201000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/umJNTu_qH_THEHP4XsOb4bMCjKn1nka4c8iz8Vs791pB5aroCWwq4aHC9ds5kCnONrgNUPgPadWnecak=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'phLb_SoPBlA',
    title: 'Not Like Us',
    artists: [YtmArtistRef(name: 'Kendrick Lamar')],
    album: 'Not Like Us',
    durationMs: 275000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/8qk3C_zpd2FXHVN8BpMBFL6h9J5BlKlbcKOlvDMvIgBWBsAblDoTjU98RGbFH9DxtnN1X5zRzc9sSvWr=w544-h544-l90-rj',
  ),
  YtmSong(
    videoId: 'DntZ3-yCaFs',
    title: 'Manchild',
    artists: [YtmArtistRef(name: 'Sabrina Carpenter')],
    album: 'Man’s Best Friend',
    durationMs: 214000,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/pbzBdDb17dzalZDm7YdsYLfUeEr1_mmm9eG4GYU4z8vio13sRpvN9-Q6SF3gatZbpcQRqsZwMiikHHA=w544-h544-l90-rj',
  ),
];

/// Demo playlists: name, cover file (under SHOWCASE_COVERS), video ids.
const demoPlaylists = <(String, String, List<String>)>[
  ('Late night drive', 'late-night-drive.jpg', ['J7p4bzqLvCw', 'h-zuG75Ds-w', 'DlFXDl_ROAM', 'nujn6wbr-e8']),
  ('Gym', 'gym.jpg', ['phLb_SoPBlA', 'OsfAnsMY21M', 'DiTd771WumE', 'kIft-LUHHVA', 'DntZ3-yCaFs']),
  ('Sunday', 'sunday.jpg', ['WKZO-CWeOVA', 'BkSSOGNeWTM', 'VZ-oGLluGAc', 'nyNm-dVBMoo']),
];

/// What [seedDemoLibrary] made.
class DemoLibrary {
  DemoLibrary(this.trackIds, this.playlistIds, this.themeIds);

  /// Track id by video id.
  final Map<String, String> trackIds;

  /// Playlist id by name.
  final Map<String, String> playlistIds;

  /// Saved theme id by name.
  final Map<String, String> themeIds;
}

/// Fills the (throwaway) library: the songs, three playlists with covers and
/// two saved themes.
Future<DemoLibrary> seedDemoLibrary(
  ProviderContainer c, {
  required Directory covers,
}) async {
  final tracks = c.read(ytTrackStoreProvider);
  final library = c.read(libraryRepositoryProvider);
  final art = c.read(artCacheProvider);
  final themes = c.read(themeRepositoryProvider);

  final trackIds = <String, String>{};
  for (final s in demoSongs) {
    trackIds[s.videoId] = _ok(await tracks.upsert(s), s.title).id;
  }

  final playlistIds = <String, String>{};
  for (final (name, cover, ids) in demoPlaylists) {
    final id = _ok(await library.createPlaylist(name), name);
    _ok(await library.addTracks(id, [for (final v in ids) trackIds[v]!]), name);
    final ref = await art.put(
      await File('${covers.path}/$cover').readAsBytes(),
      squareCrop: true,
    );
    _ok(await library.setPlaylistCover(id, ref), name);
    playlistIds[name] = id;
  }

  final themeIds = <String, String>{
    'Songies': _ok(
      await themes.save(null, 'Songies', ThemeSpec.builtInDefault.copyWith(
        base: 'charcoal',
        background: const Color(0xFF140A22),
        surface: const Color(0xFF2A1840),
        accent: const Color(0xFFEC4899),
        cornerRadius: 14,
        fontFamily: 'Outfit',
      )),
      'Songies theme',
    ),
    'Ocean': _ok(
      await themes.save(null, 'Ocean', ThemeSpec.builtInDefault.copyWith(
        background: const Color(0xFF071A24),
        surface: const Color(0xFF12313F),
        accent: const Color(0xFF38D6C4),
        cornerRadius: 10,
      )),
      'Ocean theme',
    ),
  };
  return DemoLibrary(trackIds, playlistIds, themeIds);
}

T _ok<T>(Result<T> r, String what) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('Seeding $what failed: $failure'),
};
