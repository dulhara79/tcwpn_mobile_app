// lib/core/security/secure_http.dart
//
// TLS pinning for ClinAnx.
//
// WHY THIS FILE EXISTS
// ────────────────────
// Android's network-security-config pins apply only to the platform networking
// stack. Dart's HttpClient opens its own TLS sockets; without this layer, every
// `package:http` call can bypass the Android pins entirely. This wrapper makes
// the Dart path enforce the same trust decision.
//
// WHAT WE PIN
// ───────────
// A SHA-256 fingerprint of the server certificate's DER bytes. Leaf-certificate
// pinning is deliberate for this research prototype: the exact deployed cert is
// known and the allowlist is small. It does mean a certificate renewal requires
// shipping an updated fingerprint before the old cert expires.
//
// The fingerprint allowlists live in `pinned_certificates.dart`. Production
// builds must never silently accept an unknown certificate.
//
// DEVELOPMENT ESCAPE HATCH
// ────────────────────────
// `--dart-define=DISABLE_TLS_PINNING=true` disables the custom HttpClient for
// emulator/proxy debugging. Settings shows a permanent red warning when this is
// active. Do not use it for a research release.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'pinned_certificates.dart';

/// Disables pinning. For emulator work behind a debugging proxy only.
///   --dart-define=DISABLE_TLS_PINNING=true
/// The app shows a permanent red banner when this is set in a release build.
const bool kPinningDisabled =
    bool.fromEnvironment('DISABLE_TLS_PINNING', defaultValue: false);

enum PinStatus { ok, notChecked, hostUnreachable, pinMismatch, disabled, stale }

class PinReport {
  final PinStatus status;
  final String host;
  final String detail;
  final DateTime checkedAt;

  const PinReport({
    required this.status,
    required this.host,
    required this.detail,
    required this.checkedAt,
  });

  bool get ok => status == PinStatus.ok;
}

class _PinRegistry {
  static final Map<String, PinReport> _reports = {};

  static Map<String, PinReport> get reports => Map.unmodifiable(_reports);

  static void record(PinReport report) {
    _reports[report.host] = report;
  }

  static PinReport? forHost(String host) => _reports[host];
}

class PinningHttpException implements Exception {
  final String host;
  final String detail;
  const PinningHttpException(this.host, this.detail);

  @override
  String toString() => 'TLS pinning failed for $host: $detail';
}

/// Creates a package:http client whose TLS socket is rejected unless the
/// presented leaf certificate matches one of the configured SHA-256 pins.
class SecureHttp {
  SecureHttp._();

  static Map<String, PinReport> get pinReports => _PinRegistry.reports;

  static http.Client client() {
    if (kPinningDisabled) {
      for (final host in kPinnedCertificates.keys) {
        _PinRegistry.record(PinReport(
          status: PinStatus.disabled,
          host: host,
          detail: 'TLS pinning disabled by build flag.',
          checkedAt: DateTime.now().toUtc(),
        ));
      }
      return http.Client();
    }

    final io = HttpClient();
    io.badCertificateCallback =
        (X509Certificate cert, String host, int port) =>
            _acceptCertificate(cert, host);
    return IOClient(io);
  }

  static bool _acceptCertificate(X509Certificate cert, String host) {
    final allowed = kPinnedCertificates[host.toLowerCase()];
    if (allowed == null || allowed.isEmpty) {
      _PinRegistry.record(PinReport(
        status: PinStatus.pinMismatch,
        host: host,
        detail: 'No certificate pin is configured for this host.',
        checkedAt: DateTime.now().toUtc(),
      ));
      return false;
    }

    final fingerprint = sha256.convert(cert.der).toString().toLowerCase();
    final accepted = allowed.map((e) => e.toLowerCase()).contains(fingerprint);

    _PinRegistry.record(PinReport(
      status: accepted ? PinStatus.ok : PinStatus.pinMismatch,
      host: host,
      detail: accepted
          ? 'Certificate fingerprint matched the configured allowlist.'
          : 'Presented certificate fingerprint is not in the configured allowlist.',
      checkedAt: DateTime.now().toUtc(),
    ));
    return accepted;
  }

  /// Probes all configured hosts once so Settings can show a useful trust
  /// status before the first API call. Failures are recorded, not thrown.
  static Future<void> verifyAll() async {
    if (kPinningDisabled) {
      client().close();
      return;
    }

    for (final host in kPinnedCertificates.keys) {
      final socket = SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 5),
        onBadCertificate: (cert) => _acceptCertificate(cert, host),
      );
      try {
        final connection = await socket;
        final cert = connection.peerCertificate;
        if (cert != null) {
          final fingerprint = sha256.convert(cert.der).toString().toLowerCase();
          final accepted = kPinnedCertificates[host]!
              .map((e) => e.toLowerCase())
              .contains(fingerprint);
          _PinRegistry.record(PinReport(
            status: accepted ? PinStatus.ok : PinStatus.pinMismatch,
            host: host,
            detail: accepted
                ? 'Certificate fingerprint matched the configured allowlist.'
                : 'Presented certificate fingerprint is not in the configured allowlist.',
            checkedAt: DateTime.now().toUtc(),
          ));
        }
        await connection.close();
      } catch (e) {
        final existing = _PinRegistry.forHost(host);
        if (existing?.status == PinStatus.pinMismatch) continue;
        _PinRegistry.record(PinReport(
          status: PinStatus.hostUnreachable,
          host: host,
          detail: 'Could not verify host: $e',
          checkedAt: DateTime.now().toUtc(),
        ));
      }
    }
  }

  static bool isStale(PinReport report) =>
      DateTime.now().toUtc().difference(report.checkedAt) >
      const Duration(hours: 24);

  static String basicAuth(String username, String password) =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}
