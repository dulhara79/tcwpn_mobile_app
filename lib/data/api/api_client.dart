// lib/data/api/api_client.dart
//
// One HTTP client for every service. Replaces the three divergent clients in the
// previous build (one that decoded before checking status, one that swallowed
// every error into a print, one with no auth header at all).
//
// Guarantees:
//   • status is checked before the body is decoded
//   • non-JSON error bodies produce a readable message, not a FormatException
//   • every request carries auth when a token is configured
//   • cold-start retries are bounded and only applied to idempotent reads

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';

enum ApiFailure { offline, timeout, unauthorized, notFound, validation, server, malformed, unknown }

class ApiException implements Exception {
  final ApiFailure kind;
  final int statusCode;
  final String detail;
  final String endpoint;

  const ApiException({
    required this.kind,
    this.statusCode = 0,
    this.detail = '',
    this.endpoint = '',
  });

  /// Written for a clinician, not a developer: what happened and what to do.
  String get message => switch (kind) {
        ApiFailure.offline =>
          'No network connection. The note is saved on this device and can be analysed once you are back online.',
        ApiFailure.timeout =>
          'The model did not respond in time. This usually means the service is starting up — try again in a moment.',
        ApiFailure.unauthorized =>
          'This device is not authorised to reach the model service. Contact the study administrator.',
        ApiFailure.notFound =>
          'The model endpoint could not be found. Check the service address in Settings.',
        ApiFailure.validation => 'The service rejected this request. $detail',
        ApiFailure.server =>
          'The model service reported an internal error. Nothing was saved on the server.',
        ApiFailure.malformed =>
          'The service returned a response this app could not read. Report this with the time it happened.',
        ApiFailure.unknown => detail.isEmpty ? 'Something went wrong.' : detail,
      };

  bool get isRetryable =>
      kind == ApiFailure.timeout ||
      kind == ApiFailure.offline ||
      kind == ApiFailure.server;

  @override
  String toString() => 'ApiException(${kind.name}, $statusCode, $endpoint): $detail';
}

class ApiClient {
  final String baseUrl;
  final http.Client _http;

  ApiClient(this.baseUrl, {http.Client? client})
      : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (Env.hfToken.isNotEmpty) 'Authorization': 'Bearer ${Env.hfToken}',
      };

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) =>
      _send(
        () => _http
            .post(_uri(path), headers: _headers, body: jsonEncode(body))
            .timeout(timeout ?? Env.inferenceTimeout),
        path,
      );

  Future<Map<String, dynamic>> get(
    String path, {
    Duration? timeout,
    int retries = 1,
  }) async {
    ApiException? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _send(
          () => _http
              .get(_uri(path), headers: _headers)
              .timeout(timeout ?? Env.quickTimeout),
          path,
        );
      } on ApiException catch (e) {
        last = e;
        if (!e.isRetryable || attempt == retries) rethrow;
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    throw last!;
  }

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() run,
    String endpoint,
  ) async {
    if (baseUrl.isEmpty) {
      throw ApiException(
        kind: ApiFailure.notFound,
        endpoint: endpoint,
        detail: 'No base URL configured for this service.',
      );
    }

    late http.Response res;
    try {
      res = await run();
    } on TimeoutException {
      throw ApiException(kind: ApiFailure.timeout, endpoint: endpoint);
    } on SocketException {
      throw ApiException(kind: ApiFailure.offline, endpoint: endpoint);
    } on http.ClientException catch (e) {
      throw ApiException(
          kind: ApiFailure.offline, endpoint: endpoint, detail: e.message);
    } catch (e) {
      throw ApiException(
          kind: ApiFailure.unknown, endpoint: endpoint, detail: e.toString());
    }

    // Status first, body second. Always.
    if (res.statusCode >= 400) {
      throw ApiException(
        kind: switch (res.statusCode) {
          401 || 403 => ApiFailure.unauthorized,
          404 => ApiFailure.notFound,
          422 || 400 => ApiFailure.validation,
          >= 500 => ApiFailure.server,
          _ => ApiFailure.unknown,
        },
        statusCode: res.statusCode,
        endpoint: endpoint,
        detail: _extractDetail(res.body),
      );
    }

    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (_) {
      throw ApiException(
        kind: ApiFailure.malformed,
        statusCode: res.statusCode,
        endpoint: endpoint,
        detail: res.body.substring(0, res.body.length.clamp(0, 200)),
      );
    }
  }

  /// FastAPI puts errors under `detail`; some Spaces use `error`. Fall back to
  /// a truncated raw body rather than showing the user a stack trace.
  String _extractDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final d = j['detail'] ?? j['error'] ?? j['message'];
        if (d != null) return d.toString();
      }
    } catch (_) {}
    return body.substring(0, body.length.clamp(0, 200));
  }

  void close() => _http.close();
}
