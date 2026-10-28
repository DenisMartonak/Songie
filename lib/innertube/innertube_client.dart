import 'dart:async';
import 'dart:io';

import '../core/result.dart';
import '../data/settings_repository.dart';
import '../youtube/yt_models.dart';
import 'clients.dart';
import 'sapisid_hash.dart';
import 'transport.dart';
import 'yt_session.dart';

/// The cause of an HTTP status failure (anything but 2xx and 429).
class InnertubeHttpError implements Exception {
  const InnertubeHttpError(this.status);

  final int status;

  @override
  String toString() => 'HTTP $status';
}

/// The HTTP status a failed [InnertubeClient.call] got, if it got one.
int? httpStatusOf(Failure f) => f.cause is InnertubeHttpError
    ? (f.cause! as InnertubeHttpError).status
    : null;

/// Calls Innertube endpoints as a [ClientIdentity], carrying YouTube's
/// anonymous visitor id and watching for a consent request.
class InnertubeClient {
  InnertubeClient(this._t, this._settings, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final InnertubeTransport _t;
  final SettingsRepository _settings;
  final DateTime Function() _now;
  final _consent = StreamController<bool>.broadcast();

  bool _visitorLoaded = false;
  String? _visitor;
  bool? _consentGiven;

  /// The cookie yt-dlp, ytmusicapi and NewPipe send for "accept all"
  /// (see docs/innertube-notes.md, Consent).
  static const consentCookie = 'SOCS=CAI';

  /// Emits `true` whenever a response asks the user to accept YouTube's
  /// terms (a consent.youtube.com redirect or link, or an FEconsent browse).
  /// Silent once consent was given on this device.
  Stream<bool> get consentRequired => _consent.stream;

  /// Whether the user accepted YouTube's terms on this device.
  Future<bool> consentGiven() async =>
      _consentGiven ??= await _settings.getString(kYtConsentGiven) != null;

  /// Records the user's consent (device-local); every later request sends
  /// the [consentCookie].
  Future<void> acceptConsent() async {
    _consentGiven = true;
    await _settings.setString(kYtConsentGiven, '1');
  }

  /// The stored visitor id, if any.
  Future<String?> visitorData() async {
    if (!_visitorLoaded) {
      _visitor = await _settings.getString(kYtVisitorData);
      _visitorLoaded = true;
    }
    return _visitor;
  }

  /// Forgets the visitor id; the next response's id is stored instead.
  Future<void> resetVisitor() async {
    await _settings.setString(kYtVisitorData, null);
    _visitor = null;
    _visitorLoaded = true;
  }

  /// The origin a signed-in request is made for (the hash covers it).
  static const signedInOrigin = 'https://music.youtube.com';

  /// POSTs [body] to [endpoint] as [c] (with extra URL [query] params).
  /// Never throws: every failure is `Err`.
  ///
  /// With a [session] the request goes out signed in: its cookies (plus the
  /// [consentCookie] once consented) and a SAPISIDHASH `Authorization`
  /// (docs/innertube-notes.md, Signed in). Only Home is sent this way. A
  /// failure then never carries a cookie value or the hash in its message.
  Future<Result<Map<String, Object?>>> call(
    ClientIdentity c,
    String endpoint,
    Map<String, Object?> body, {
    Map<String, String>? query,
    YtSession? session,
  }) async {
    if (session == null) return _call(c, endpoint, body, query, null, null);
    final sapisid = session.sapisid;
    final auth = sapisid == null
        ? null
        : sapisidHash(sapisid, signedInOrigin, _now());
    final res = await _call(c, endpoint, body, query, session, auth);
    if (res is! Err<Map<String, Object?>>) return res;
    final secrets = [
      ?auth,
      for (final v in session.cookies.values)
        if (v.length >= 4) v,
    ];
    String scrub(String text) {
      var out = text.replaceAll(_hashPattern, '<redacted>');
      for (final secret in secrets) {
        out = out.replaceAll(secret, '<redacted>');
      }
      return out;
    }

    final f = res.failure;
    final cause = f.cause;
    final cleanCause =
        cause == null ||
            cause is InnertubeHttpError ||
            scrub('$cause') == '$cause'
        ? cause
        : null;
    return Err(Failure(f.kind, scrub(f.message), cause: cleanCause));
  }

  static final _hashPattern = RegExp(r'SAPISID\w*HASH\s+\S+');

  Future<Result<Map<String, Object?>>> _call(
    ClientIdentity c,
    String endpoint,
    Map<String, Object?> body,
    Map<String, String>? query,
    YtSession? session,
    String? auth,
  ) async {
    try {
      final visitor = await visitorData();
      final consented = await consentGiven();
      final request = <String, Object?>{
        ...body,
        'context': {
          'client': {
            'clientName': c.name,
            'clientVersion': c.version,
            'userAgent': c.userAgent,
            'hl': 'en',
            'utcOffsetMinutes': _now().timeZoneOffset.inMinutes,
            ...c.extraClient,
            'visitorData': ?visitor,
          },
        },
      };
      final headers = {
        'User-Agent': c.userAgent,
        'X-YouTube-Client-Name': '${c.nameId}',
        'X-YouTube-Client-Version': c.version,
        'Origin': 'https://${c.host}',
        'X-Goog-Visitor-Id': ?visitor,
        if (session != null) ...{
          'Cookie': [
            session.cookieHeader(),
            if (consented && !session.cookies.containsKey('SOCS'))
              consentCookie,
          ].join('; '),
          'Authorization': ?auth,
          'X-Goog-AuthUser': '0',
          'X-Origin': signedInOrigin,
        } else if (consented)
          'Cookie': consentCookie,
      };
      final res = await _t.post(c.endpoint(endpoint, query), request, headers);
      return await _handle(c, endpoint, res);
    } on FormatException catch (e) {
      return Err(
        Failure(FailureKind.unknown, _msg(c, endpoint, 'bad JSON'), cause: e),
      );
    } on SocketException catch (e) {
      return Err(_network(c, endpoint, e));
    } on HttpException catch (e) {
      return Err(_network(c, endpoint, e));
    } on TlsException catch (e) {
      return Err(_network(c, endpoint, e));
    } on TimeoutException catch (e) {
      return Err(_network(c, endpoint, e));
    } on Object catch (e) {
      return Err(
        Failure(FailureKind.unknown, _msg(c, endpoint, '$e'), cause: e),
      );
    }
  }

  void dispose() => _consent.close();

  Future<Result<Map<String, Object?>>> _handle(
    ClientIdentity c,
    String endpoint,
    InnertubeResponse res,
  ) async {
    final redirect = res.redirect;
    if (redirect != null && _isConsentHost(redirect)) {
      await _askForConsent();
      return Err(
        Failure(
          FailureKind.network,
          _msg(c, endpoint, 'consent required (HTTP ${res.status})'),
        ),
      );
    }
    if (res.status == 429) {
      return Err(
        ytFailure(YtErrorKind.throttled, _msg(c, endpoint, 'HTTP 429')),
      );
    }
    if (res.status < 200 || res.status >= 300) {
      return Err(
        Failure(
          FailureKind.network,
          _msg(c, endpoint, 'HTTP ${res.status}'),
          cause: InnertubeHttpError(res.status),
        ),
      );
    }
    final json = res.json;
    if (json == null) {
      return Err(
        Failure(
          FailureKind.unknown,
          _msg(c, endpoint, 'response is not a JSON object'),
        ),
      );
    }
    await _storeVisitor(json);
    if (_asksForConsent(json)) await _askForConsent();
    return Ok(json);
  }

  Future<void> _askForConsent() async {
    if (!await consentGiven() && !_consent.isClosed) _consent.add(true);
  }

  /// Stores the first visitor id YouTube hands out; a stored one is kept.
  Future<void> _storeVisitor(Map<String, Object?> json) async {
    if (await visitorData() != null) return;
    final ctx = json['responseContext'];
    final vd = ctx is Map ? ctx['visitorData'] : null;
    if (vd is! String || vd.isEmpty) return;
    // In memory first: a concurrent call must see it before the write ends.
    _visitor = vd;
    await _settings.setString(kYtVisitorData, vd);
  }

  static bool _isConsentHost(Uri u) => u.host == 'consent.youtube.com';

  /// True when a link to consent.youtube.com or an `FEconsent` browse
  /// appears anywhere in the response (the IOS player response, for one,
  /// carries a `startEomFlowCommand` with such a link).
  static bool _asksForConsent(Object? v) {
    if (v is String) {
      return v.startsWith('https://consent.youtube.com/') || v == 'FEconsent';
    }
    if (v is Map) {
      for (final child in v.values) {
        if (_asksForConsent(child)) return true;
      }
    } else if (v is List) {
      for (final child in v) {
        if (_asksForConsent(child)) return true;
      }
    }
    return false;
  }

  static String _msg(ClientIdentity c, String endpoint, String detail) =>
      'innertube ${c.name} $endpoint: $detail';

  static Failure _network(ClientIdentity c, String endpoint, Object e) =>
      Failure(FailureKind.network, _msg(c, endpoint, '$e'), cause: e);
}
