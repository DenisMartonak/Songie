/// Why this run might touch the user's real Songies data, or null when it
/// is safe: the app must be pointed (via XDG_DATA_HOME, which
/// lib/core/paths.dart honours on Linux) at a throwaway folder that
/// tool/showcase.sh made with `mktemp -d -t showcase-XXXXXX`.
String? isolationProblem(Map<String, String> env) {
  final data = env['XDG_DATA_HOME'] ?? '';
  if (data.isEmpty) {
    return 'XDG_DATA_HOME is not set, so the app would open your real '
        'library. Run tool/showcase.sh instead.';
  }
  if (!data.startsWith('/')) return 'XDG_DATA_HOME must be an absolute path.';
  final home = env['HOME'];
  if (home != null && data.startsWith('$home/.local/share')) {
    return 'XDG_DATA_HOME points at your real data folder.';
  }
  final name = data.split('/').where((s) => s.isNotEmpty).last;
  if (!name.startsWith('showcase-')) {
    return 'XDG_DATA_HOME must be a showcase-* folder made by tool/showcase.sh.';
  }
  return null;
}

/// Every scene, in recording order.
const allShowcaseScenes = ['themes', 'playlists', 'downloads', 'search'];

/// The scenes to record from SHOWCASE_SCENES: unset or empty means all.
List<String> showcaseScenes(String? value) {
  if (value == null || value.trim().isEmpty) return allShowcaseScenes;
  return value
      .split(',')
      .map((s) => s.trim())
      .where(allShowcaseScenes.contains)
      .toList();
}
