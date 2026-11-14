import 'dart:async';
import 'dart:convert';

import '../data/settings_repository.dart';
import 'stats_models.dart';

/// An artist's YouTube Music page and photo (null when it has none).
typedef ArtistPhoto = ({String browseId, String? photoUrl});

/// Finds and remembers artist photos for the stats. A saved artist's photo
/// is used as is; others are looked up through their most-played track.
/// Answers are kept on the device; failed lookups are not, so they are
/// asked again. Lookups run one at a time, at most once an hour.
class ArtistPhotos {
  ArtistPhotos({
    required this.settings,
    required this.saved,
    required this.browseIdForTrack,
    required this.artist,
    this.now = DateTime.now,
  });

  static const every = Duration(hours: 1);

  final SettingsRepository settings;
  final Future<Map<String, ArtistPhoto>> Function() saved;
  final Future<String?> Function(String trackId) browseIdForTrack;
  final Future<ArtistPhoto?> Function(String browseId) artist;
  final DateTime Function() now;

  final _photos = <String, ArtistPhoto>{};
  final _changes = StreamController<void>.broadcast();
  DateTime? _lastPass;
  Future<void>? _running;

  ArtistPhoto? of(String name) => _photos[name];

  Stream<void> get changes => _changes.stream;

  /// Reads the kept photos.
  Future<void> load() async {
    try {
      final raw = await settings.getString(kArtistPhotos);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final v = e.value as Map<String, dynamic>;
        final b = v['b'];
        if (b is! String) continue;
        _photos.putIfAbsent(
          e.key,
          () => (browseId: b, photoUrl: v['p'] as String?),
        );
      }
    } catch (_) {
      // A damaged cache is just a cold one.
    }
  }

  /// Looks up photos missing for [artists]. Skipped when a pass ran less
  /// than [every] ago, unless [force].
  Future<void> fill(List<ArtistStat> artists, {bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final last = _lastPass;
    if (!force && last != null && now().difference(last) < every) {
      return Future.value();
    }
    _lastPass = now();
    return _running = _pass(artists).whenComplete(() => _running = null);
  }

  Future<void> _pass(List<ArtistStat> artists) async {
    var changed = false;
    Map<String, ArtistPhoto> savedNow = const {};
    try {
      savedNow = await saved();
    } catch (_) {}
    for (final a in artists) {
      final s = savedNow[a.name];
      if (s != null) {
        if (_photos[a.name] != s) {
          _photos[a.name] = s;
          changed = true;
        }
        continue;
      }
      if (_photos.containsKey(a.name)) continue;
      final track = a.sampleTrackId;
      if (track == null) continue;
      try {
        final id = await browseIdForTrack(track);
        if (id == null) continue;
        final found = await artist(id);
        if (found == null) continue;
        _photos[a.name] = found;
        changed = true;
      } catch (_) {
        // Not kept; the next pass asks again.
      }
    }
    if (!changed) return;
    try {
      await settings.setString(
        kArtistPhotos,
        jsonEncode({
          for (final e in _photos.entries)
            e.key: {'b': e.value.browseId, 'p': e.value.photoUrl},
        }),
      );
    } catch (_) {}
    _changes.add(null);
  }

  /// [artists] with the known photos and pages filled in.
  List<ArtistStat> apply(List<ArtistStat> artists) => [
    for (final a in artists)
      switch (_photos[a.name]) {
        final p? => a.copyWith(photoUrl: p.photoUrl, browseId: p.browseId),
        null => a,
      },
  ];
}
