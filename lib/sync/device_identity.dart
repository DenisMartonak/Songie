import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import '../core/log.dart';

/// This device's TLS identity for sync: a self-signed EC P-256 certificate
/// and its key, created once and kept in the sync directory. Peers pin the
/// [fingerprint] when pairing; no certificate authority is involved.
class DeviceIdentity {
  DeviceIdentity._(this.certPem, this.keyPem)
    : fingerprint = _fingerprintOfDer(
        CryptoUtils.getBytesFromPEMString(certPem),
      );

  final String certPem;
  final String keyPem;

  /// Lowercase hex SHA-256 of the certificate DER.
  final String fingerprint;

  static const _validDays = 7300;

  /// Loads `cert.pem` and `key.pem` from [syncDir], creating them (and the
  /// directory) when missing. Files that exist but cannot be parsed are
  /// moved to `*.bak` and replaced (which breaks existing pairings, so it is
  /// logged). An I/O error while reading is rethrown and nothing is touched.
  static Future<DeviceIdentity> loadOrCreate(Directory syncDir) async {
    final certFile = File('${syncDir.path}/cert.pem');
    final keyFile = File('${syncDir.path}/key.pem');
    final hasCert = certFile.existsSync();
    final hasKey = keyFile.existsSync();
    if (hasCert && hasKey) {
      // Read errors propagate: a transient failure must not cost the identity.
      final cert = certFile.readAsStringSync();
      final key = keyFile.readAsStringSync();
      try {
        final id = DeviceIdentity._(cert, key);
        id.serverContext(); // proves the pair parses
        return id;
      } catch (e) {
        AppLog.w(
          'Device identity files are unusable (${e.runtimeType}); '
          'regenerating. Paired devices must pair again.',
        );
      }
    } else if (hasCert || hasKey) {
      AppLog.w(
        'Device identity is incomplete; regenerating. '
        'Paired devices must pair again.',
      );
    }
    await syncDir.create(recursive: true);
    for (final f in [certFile, keyFile]) {
      if (f.existsSync()) await f.rename('${f.path}.bak');
    }
    // A generated key can, rarely, encode a leading-zero scalar in a form
    // the TLS stack rejects; retry until the pair loads.
    for (var attempt = 0; ; attempt++) {
      final id = _generate();
      try {
        id.serverContext();
      } catch (_) {
        if (attempt >= 8) rethrow;
        continue;
      }
      // Key first: a crash in between leaves no certificate without its key.
      await _writeAtomic(keyFile, id.keyPem, private: true);
      await _writeAtomic(certFile, id.certPem);
      return id;
    }
  }

  /// Writes [content] to a temp file beside [target], then renames it over.
  /// A private file is restricted (Linux) before its bytes are written.
  static Future<void> _writeAtomic(
    File target,
    String content, {
    bool private = false,
  }) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString('');
    if (private && Platform.isLinux) {
      final r = await Process.run('chmod', ['600', tmp.path]);
      if (r.exitCode != 0) {
        AppLog.w(
          'Could not restrict the device key file (chmod ${r.exitCode})',
        );
      }
    }
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  static DeviceIdentity _generate() {
    final pair = CryptoUtils.generateEcKeyPair();
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem({'CN': 'Songies'}, priv, pub);
    final cert = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      _validDays,
      serialNumber: '${DateTime.now().microsecondsSinceEpoch}',
    );
    return DeviceIdentity._(cert, CryptoUtils.encodeEcPrivateKeyToPem(priv));
  }

  /// A context that serves this certificate.
  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChainBytes(certPem.codeUnits)
    ..usePrivateKeyBytes(keyPem.codeUnits);

  static String fingerprintOf(X509Certificate c) => _fingerprintOfDer(c.der);

  static String _fingerprintOfDer(List<int> der) =>
      sha256.convert(der).toString();
}
