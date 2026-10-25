/// One of YouTube's own app clients, impersonated on Innertube requests.
///
/// The values come from yt-dlp's `INNERTUBE_CLIENTS` and were verified live;
/// see docs/innertube-notes.md for when and what each returned.
class ClientIdentity {
  const ClientIdentity({
    required this.name,
    required this.version,
    required this.nameId,
    required this.userAgent,
    required this.host,
    this.extraClient = const {},
  });

  /// `context.client.clientName`.
  final String name;

  /// `context.client.clientVersion`.
  final String version;

  /// The numeric client id sent as `X-YouTube-Client-Name`.
  final int nameId;
  final String userAgent;

  /// The API host, e.g. `www.youtube.com` or `music.youtube.com`.
  final String host;

  /// Further `context.client` fields (device, OS).
  final Map<String, Object?> extraClient;

  Uri endpoint(String name) =>
      Uri.https(host, '/youtubei/v1/$name', const {'prettyPrint': 'false'});
}

const _visionOs = ClientIdentity(
  name: 'VISIONOS',
  version: '1.02',
  nameId: 101,
  userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  host: 'www.youtube.com',
  extraClient: {
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice17,1',
    'osName': 'visionOS',
    'osVersion': '26.5.23O471',
  },
);

const _androidVr = ClientIdentity(
  name: 'ANDROID_VR',
  version: '1.65.10',
  nameId: 28,
  userAgent:
      'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; '
      'Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
  host: 'www.youtube.com',
  extraClient: {
    'deviceMake': 'Oculus',
    'deviceModel': 'Quest 3',
    'androidSdkVersion': 32,
    'osName': 'Android',
    'osVersion': '12L',
  },
);

/// Clients for the `player` endpoint, tried in order. Both returned plain
/// `url` audio formats (no `signatureCipher`, no PO token) on 2026-10-25;
/// TVHTML5 (UNPLAYABLE) and IOS (SABR only) did not, so they are left out.
const List<ClientIdentity> kPlayerClients = [_visionOs, _androidVr];

/// The YouTube Music web client, for `search`, `browse` and `next`.
const ClientIdentity kWebRemix = ClientIdentity(
  name: 'WEB_REMIX',
  version: '1.20260707.12.00',
  nameId: 67,
  userAgent:
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
  host: 'music.youtube.com',
);
