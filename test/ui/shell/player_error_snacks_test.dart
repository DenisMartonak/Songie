import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/shell/player_error_snacks.dart';

void main() {
  test('ytdlp-prefixed errors use the yt user copy', () {
    expect(
      playerErrorMessage('ytdlp:extractor:boom'),
      'YouTube changed something — try Settings → Update yt-dlp',
    );
  });

  test('network messages and others show as is', () {
    expect(playerErrorMessage("You're offline"), "You're offline");
  });
}
