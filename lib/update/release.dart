/// A three-part app version, `major.minor.patch`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Accepts an optional leading `v` and drops a `+build` suffix. Anything
  /// other than exactly three numeric parts gives null.
  static AppVersion? tryParse(String s) {
    var t = s.trim();
    if (t.startsWith('v')) t = t.substring(1);
    final plus = t.indexOf('+');
    if (plus >= 0) t = t.substring(0, plus);
    final parts = t.split('.');
    if (parts.length != 3) return null;
    final nums = <int>[];
    for (final p in parts) {
      if (!RegExp(r'^\d+$').hasMatch(p)) return null;
      final n = int.tryParse(p);
      if (n == null) return null;
      nums.add(n);
    }
    return AppVersion(nums[0], nums[1], nums[2]);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

enum UpdatePlatform {
  android,
  windows,
  linux;

  /// The release asset this platform installs.
  String assetName(AppVersion v) => switch (this) {
    UpdatePlatform.android => 'songies-$v.apk',
    UpdatePlatform.windows => 'songies-$v-windows-setup.exe',
    UpdatePlatform.linux => 'songies-$v-x86_64.AppImage',
  };
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final Uri url;
  final int size;
}

class Release {
  const Release({
    required this.version,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
  });

  final AppVersion version;
  final String notes;
  final Uri htmlUrl;
  final List<ReleaseAsset> assets;

  /// Reads GitHub's release JSON. Null for drafts, pre-releases or a tag that
  /// is not a three-part version.
  static Release? fromGitHubJson(Map<String, Object?> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;
    final body = json['body'];
    final htmlUrl = Uri.tryParse(json['html_url'] as String? ?? '');
    final assets = <ReleaseAsset>[];
    final raw = json['assets'];
    if (raw is List) {
      for (final a in raw) {
        if (a is! Map) continue;
        final name = a['name'];
        final url = Uri.tryParse(a['browser_download_url'] as String? ?? '');
        if (name is! String || url == null || !url.hasScheme) continue;
        final size = a['size'];
        assets.add(
          ReleaseAsset(name: name, url: url, size: size is int ? size : 0),
        );
      }
    }
    return Release(
      version: version,
      notes: body is String ? body : '',
      htmlUrl: htmlUrl ?? Uri(),
      assets: assets,
    );
  }

  ReleaseAsset? _named(String name) {
    for (final a in assets) {
      if (a.name == name) return a;
    }
    return null;
  }

  ReleaseAsset? pickAsset(UpdatePlatform p) => _named(p.assetName(version));

  ReleaseAsset? get checksums => _named('SHA256SUMS');
}

/// Parses `sha256sum` output (`<hex>  <name>`, or `<hex> *<name>`) into a map
/// of file name to lowercase hex. Blank and malformed lines are ignored.
Map<String, String> parseSha256Sums(String text) {
  final line = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  final out = <String, String>{};
  for (final raw in text.split('\n')) {
    final m = line.firstMatch(raw.trimRight());
    if (m == null) continue;
    out[m.group(2)!] = m.group(1)!.toLowerCase();
  }
  return out;
}
