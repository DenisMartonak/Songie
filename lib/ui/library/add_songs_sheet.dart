import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../playlist/playlist_page.dart';
import '../widgets/artwork.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// A searchable multi-select list of the library's songs. "Add (N)" appends
/// the chosen songs to the playlist and closes the sheet.
class AddSongsSheet extends ConsumerStatefulWidget {
  const AddSongsSheet({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<AddSongsSheet> {
  static const _searchLimit = 200;

  /// Chosen track ids in the order they were chosen.
  final Set<String> _selected = {};
  String _query = '';
  late Stream<List<Track>> _tracks = _tracksFor('');

  Stream<List<Track>> _tracksFor(String query) {
    final search = ref.read(searchRepositoryProvider);
    return query.trim().isEmpty
        ? search.allTracks()
        : search.searchTracks(query, limit: _searchLimit);
  }

  Future<void> _add() async {
    final result = await ref
        .read(libraryRepositoryProvider)
        .addTracks(widget.playlistId, _selected.toList());
    if (!mounted) return;
    if (result is Err<void>) {
      Islands.of(context)
          .show("Couldn't add the songs", kind: IslandKind.failure);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add songs',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _selected.isEmpty ? null : _add,
                  child: Text('Add (${_selected.length})'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search your library',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() {
                _query = value;
                _tracks = _tracksFor(value);
              }),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Track>>(
              stream: _tracks,
              builder: (context, snapshot) {
                final tracks = snapshot.data;
                if (tracks == null) return const SizedBox.shrink();
                if (tracks.isEmpty) {
                  return Center(
                    child: Text(
                      _query.trim().isEmpty
                          ? 'No songs yet. Add a music folder in Library.'
                          : 'No songs match "${_query.trim()}"',
                      style: TextStyle(color: colors.mutedText),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final track = tracks[i];
                    final chosen = _selected.contains(track.id);
                    return CheckboxListTile(
                      value: chosen,
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (on) => setState(
                        () => on == true
                            ? _selected.add(track.id)
                            : _selected.remove(track.id),
                      ),
                      secondary: Artwork(
                        track.artworkRef,
                        size: 44,
                        seed: track.id,
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${track.artist} · ${trackDurationText(track.durationMs)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
