import 'dart:io';

/// AppImage only: makes `songies://` links open this AppImage by writing a
/// desktop entry into [applications] and setting it as the handler. Returns
/// whether it wrote; nothing happens without [appImage] or when the entry
/// already points at it.
Future<bool> registerLinuxLinks({
  required String? appImage,
  required Directory applications,
  required Future<void> Function(List<String> args) xdgMime,
}) async {
  if (appImage == null || appImage.isEmpty) return false;
  const name = 'songies-links.desktop';
  final exec = 'Exec="$appImage" %u';
  final file = File('${applications.path}/$name');
  if (file.existsSync() && file.readAsStringSync().contains('\n$exec\n')) {
    return false;
  }
  await applications.create(recursive: true);
  await file.writeAsString(
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name=Songies\n'
    '$exec\n'
    'Icon=songies\n'
    'Terminal=false\n'
    'NoDisplay=true\n'
    'MimeType=x-scheme-handler/songies;\n',
  );
  await xdgMime(['default', name, 'x-scheme-handler/songies']);
  return true;
}
