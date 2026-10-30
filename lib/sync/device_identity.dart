import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

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
  /// directory) when missing or unusable.
  static Future<DeviceIdentity> loadOrCreate(Directory syncDir) async {
    final certFile = File('${syncDir.path}/cert.pem');
    final keyFile = File('${syncDir.path}/key.pem');
    if (certFile.existsSync() && keyFile.existsSync()) {
      try {
        final id = DeviceIdentity._(
          certFile.readAsStringSync(),
          keyFile.readAsStringSync(),
        );
        id.serverContext(); // proves the pair parses
        return id;
      } catch (_) {
        // Corrupt files: fall through and make a new identity.
      }
    }
    await syncDir.create(recursive: true);
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
      await certFile.writeAsString(id.certPem);
      // Restrict the key file before the key is written into it.
      await keyFile.writeAsString('');
      if (Platform.isLinux) await Process.run('chmod', ['600', keyFile.path]);
      await keyFile.writeAsString(id.keyPem);
      return id;
    }
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
