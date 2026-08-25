// lib/services/central_backend_service.dart
//
// The patient app's ONE client for the R26-DS-012 Central Backend.
//
// WHY THIS FILE EXISTS
// --------------------
// Before this, the patient app talked to the central backend for exactly one
// thing: POST /v1/subjects/pair. Every physiological window went straight to
// the C1 Hugging Face Space (ApiService.sendFeatureData -> $baseUrl/ingest),
// GAD-7 went only to a Google Sheet, and the dashboard tried to call a fusion
// Space directly through a PLACEHOLDER_FUSION_ENDPOINT constant that was never
// filled in.
//
// The consequence was not cosmetic. The backend builds its composite from
// ModalityReading rows it holds itself (main.py::_latest_readings). No
// /v1/ingest/* call ever arrived, so there were no c1_physiological or
// c4_demographic rows, gate.evaluate() blocked, and every fusion returned
// band "GREY". The clinician app was correctly wired and still had nothing to
// show, because nothing upstream was feeding it.
//
// This file closes that gap. Every route and every field name below was read
// out of central_backend/main.py — none of it is inferred.
//
//   POST /v1/subjects/pair              PairRequest        no auth
//   GET  /v1/subjects/resolve           query params       bearer
//   POST /v1/ingest/physiological       PhysiologicalWindow bearer
//   POST /v1/ingest/behavioural         BehaviouralAggregate bearer
//   POST /v1/ingest/contextual          ContextualIntake   bearer
//   GET  /v1/patients/{subject_id}/risk                    no auth
//   GET  /health                                           no auth
//
// AUTH, HONESTLY
// --------------
// main.py::_auth compares the Authorization header against one static
// BACKEND_API_TOKEN. There is no per-user login, no JWT, no refresh token. The
// feedback document's section 3 asks for a clinician authentication contract;
// the backend does not have one. Shipping the shared token in the APK is
// therefore the only way the ingest routes work today, and it is a real
// weakness that belongs in your limitations section, not something to paper
// over. Two ingest routes (pair, patient risk) deliberately need no token,
// which is why a build with an empty token still pairs and still shows the
// patient their band.
//
// WHAT THIS FILE DELIBERATELY DOES NOT DO
// ---------------------------------------
// It does not call the fusion service. It does not call C2. It does not
// compute a composite locally. Fusion is triggered server-side by the ingest
// itself (main.py::_auto_fuse) and read back through the patient risk view.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'participant_identity_service.dart';

/// Outcome of one backend call. `ok` false is never thrown — the patient app
/// runs on a phone in a pocket and a dropped window must not surface as a
/// crash or a scary dialog.
@immutable
class BackendResult {
  final bool ok;
  final Map<String, dynamic> body;
  final String? message;
  final int? statusCode;

  const BackendResult._({
    required this.ok,
    this.body = const {},
    this.message,
    this.statusCode,
  });

  const BackendResult.success(Map<String, dynamic> body)
      : this._(ok: true, body: body);

  const BackendResult.failure(String message, {int? statusCode})
      : this._(ok: false, message: message, statusCode: statusCode);

  /// True when the backend accepted the reading AND ran fusion off the back of
  /// it. A false value here is normal for physiological windows: fusion is
  /// debounced to AUTO_FUSION_DEBOUNCE_MIN (default 5 min) server-side.
  bool get fusionTriggered => body['fusion_triggered'] == true;

  /// The component status the backend recorded for this reading — one of
  /// `ok`, `warming_up`, `poor_signal`, `not_validated`, `error`. Not the same
  /// vocabulary C1 itself uses; the backend maps them in modality_clients.py.
  String? get status => body['status']?.toString();
}

class CentralBackendService {
  CentralBackendService._();

  /// Injected at build time:
  ///   flutter build apk --release \
  ///     --dart-define=BACKEND_BASE=https://... \
  ///     --dart-define=BACKEND_TOKEN=...
  static const String _baseRaw = String.fromEnvironment('BACKEND_BASE');

  static const String _token = String.fromEnvironment('BACKEND_TOKEN');

  /// Trailing slashes are stripped once here rather than at every call site,
  /// because '.../v1/subjects/pair' with a doubled slash is a 404 that looks
  /// exactly like a missing route.
  static String get baseUrl => _baseRaw.trim().replaceFirst(RegExp(r'/+$'), '');

  static bool get isConfigured => baseUrl.isNotEmpty;

  static const Duration _quick = Duration(seconds: 15);
  static const Duration _slow = Duration(seconds: 45);

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  static Map<String, String> get _openHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ───────────────────────────────────────────────────────────────────────────
  // Transport
  // ───────────────────────────────────────────────────────────────────────────

  static Future<BackendResult> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = _quick,
    bool authenticated = true,
  }) async {
    if (!isConfigured) {
      return const BackendResult.failure(
        'The central backend is not configured in this app build.',
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: authenticated ? _headers : _openHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(response, path);
    } catch (e) {
      debugPrint('[central] POST $path failed: $e');
      return BackendResult.failure('Could not reach the central backend.');
    }
  }

  static Future<BackendResult> _get(
    String path, {
    Duration timeout = _quick,
    bool authenticated = true,
  }) async {
    if (!isConfigured) {
      return const BackendResult.failure(
        'The central backend is not configured in this app build.',
      );
    }
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl$path'),
            headers: authenticated ? _headers : _openHeaders,
          )
          .timeout(timeout);
      return _decode(response, path);
    } catch (e) {
      debugPrint('[central] GET $path failed: $e');
      return BackendResult.failure('Could not reach the central backend.');
    }
  }

  static BackendResult _decode(http.Response response, String path) {
    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) decoded = Map<String, dynamic>.from(parsed);
      } catch (_) {
        // A non-JSON body from an ngrok interstitial or a proxy error page is
        // a transport failure, not a backend response. Say so rather than
        // reporting an empty success.
        return BackendResult.failure(
          'The backend returned an unreadable response (HTTP '
          '${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return BackendResult.success(decoded);
    }

    // FastAPI puts the human-readable reason in `detail`, and for 422 it is a
    // list of field errors rather than a string.
    final detail = decoded['detail'];
    final message = detail is String
        ? detail
        : detail is List && detail.isNotEmpty
            ? detail.first.toString()
            : 'The backend rejected the request (HTTP ${response.statusCode}).';

    debugPrint('[central] $path -> ${response.statusCode}: $message');
    return BackendResult.failure(message, statusCode: response.statusCode);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Identity
  // ───────────────────────────────────────────────────────────────────────────

  /// Redeems the clinician's pairing code, attaching this phone's pseudonymous
  /// participant ID to the subject the clinician enrolled.
  ///
  /// Unauthenticated by design: the short-lived code IS the credential, and the
  /// patient app has no clinician token to present. main.py::pair_subject takes
  /// no Authorization header.
  ///
  /// The returned subject_id is persisted immediately. Every ingest afterwards
  /// sends it, so a code that is redeemed but not stored would leave the phone
  /// silently unable to contribute readings.
  static Future<BackendResult> pair({
    required String participantId,
    required String pairingCode,
  }) async {
    final result = await _post(
      '/v1/subjects/pair',
      {
        'pairing_code': pairingCode.trim().toUpperCase(),
        'app_user_id': participantId,
      },
      authenticated: false,
    );

    if (!result.ok) return result;

    final subjectId = result.body['subject_id']?.toString() ?? '';
    if (subjectId.isEmpty) {
      return const BackendResult.failure(
        'The backend paired this device but returned no subject id.',
      );
    }

    await ParticipantIdentityService.saveCentralSubjectId(subjectId);

    // Tell the backend what id C1 knows this patient by, so the backend's
    // legacy fallback (GET /predict/{user_id}) asks C1 about the participant
    // id C1 actually has a buffer for, not our opaque subject uuid.
    await registerExternalId(
      subjectId: subjectId,
      modality: 'c1_physiological',
      externalId: participantId,
    );
    await registerExternalId(
      subjectId: subjectId,
      modality: 'c2_behavioral',
      externalId: participantId,
    );

    return result;
  }

  /// Maps this patient to the id a component service knows them by.
  ///
  /// Best-effort: a 409 here means that external id already belongs to a
  /// different subject, which is a real cross-patient error, but it must not
  /// abort a pairing that otherwise succeeded. It is logged and surfaced
  /// through the return value instead.
  static Future<BackendResult> registerExternalId({
    required String subjectId,
    required String modality,
    required String externalId,
  }) =>
      _post('/v1/subjects/$subjectId/external-ids', {
        'modality': modality,
        'external_id': externalId,
      });

  /// The subject_id saved at pairing time, or null on an unpaired install.
  static Future<String?> currentSubjectId() =>
      ParticipantIdentityService.getCentralSubjectId();

  /// Recovers a lost subject_id from the participant id. Used when local
  /// preferences were cleared but the backend still holds the pairing.
  static Future<String?> resolveSubjectId(String participantId) async {
    final result = await _get(
      '/v1/subjects/resolve?app_user_id=${Uri.encodeQueryComponent(participantId)}',
    );
    if (!result.ok) return null;
    final id = result.body['subject_id']?.toString();
    if (id != null && id.isNotEmpty) {
      await ParticipantIdentityService.saveCentralSubjectId(id);
    }
    return id;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Ingestion
  // ───────────────────────────────────────────────────────────────────────────

  /// One 60-second physiological window.
  ///
  /// The ten feature keys below are passed through the backend verbatim:
  /// modality_clients._call_c1_target_contract posts
  /// `{"subject_id": ..., **window}` to C1's /predict without renaming
  /// anything. So these must be exactly the keys C1 was trained on, which are
  /// the same ten ApiService.sendFeatureData has always sent.
  ///
  /// `deviceUserId` is the id C1 buffers under. Left null, the backend looks up
  /// the c1_device_id alias registered at pairing and falls back to the
  /// subject_id if none exists.
  static Future<BackendResult> ingestPhysiological({
    required String subjectId,
    required DateTime windowStart,
    required DateTime windowEnd,
    required double meanHr,
    required double meanRr,
    required double sdnn,
    required double rmssd,
    required double meanBr,
    required double stdBr,
    required double meanTemp,
    required double stdTemp,
    required double meanAccMag,
    required double stdAccMag,
    int samplingHz = 1,
    String? deviceUserId,
  }) =>
      _post(
        '/v1/ingest/physiological',
        {
          'subject_id': subjectId,
          if (deviceUserId != null && deviceUserId.isNotEmpty)
            'device_user_id': deviceUserId,
          'window_start': windowStart.toUtc().toIso8601String(),
          'window_end': windowEnd.toUtc().toIso8601String(),
          'sampling_hz': samplingHz,
          'features': {
            'mean_hr': meanHr,
            'mean_rr': meanRr,
            'sdnn': sdnn,
            'rmssd': rmssd,
            'mean_br': meanBr,
            'std_br': stdBr,
            'mean_temp': meanTemp,
            'std_temp': stdTemp,
            'mean_acc_mag': meanAccMag,
            'std_acc_mag': stdAccMag,
          },
        },
        // The backend may have to wake a sleeping C1 Space before it can
        // answer, and COMPONENT_TIMEOUT_S is 60s on its side.
        timeout: _slow,
      );

  /// Demographics plus the seven GAD-7 item responses.
  ///
  /// Send the ITEMS, never a precomputed total. main.py::ingest_contextual
  /// recomputes the total server-side and rejects the call with 422 unless
  /// there are exactly seven values each in 0..3. A client-sent total is
  /// display only and is not read by the backend.
  ///
  /// This is the only route that produces a c4_demographic reading, so without
  /// it the demographic modality is permanently absent from the composite.
  static Future<BackendResult> ingestContextual({
    required String subjectId,
    List<int>? gad7Items,
    String? gender,
    double? age,
    String? edu,
    String? smoke,
    String? drink,
  }) {
    if (gad7Items != null &&
        (gad7Items.length != 7 || gad7Items.any((v) => v < 0 || v > 3))) {
      return Future.value(
        const BackendResult.failure(
          'GAD-7 must be exactly seven answers, each between 0 and 3.',
        ),
      );
    }
    return _post(
      '/v1/ingest/contextual',
      {
        'subject_id': subjectId,
        if (gad7Items != null) 'gad7_items': gad7Items,
        if (gender != null && gender.isNotEmpty) 'gender': gender,
        if (age != null) 'age': age,
        if (edu != null && edu.isNotEmpty) 'edu': edu,
        if (smoke != null && smoke.isNotEmpty) 'smoke': smoke,
        if (drink != null && drink.isNotEmpty) 'drink': drink,
      },
      timeout: _slow,
    );
  }

  /// Behavioural aggregates for C2.
  ///
  /// The backend stores the result with status `not_validated` and excludes it
  /// from the composite by pre-registered rule (gate.EXCLUDED_MODALITIES). It
  /// is sent anyway so the exclusion is auditable rather than invisible, and so
  /// the clinician chart can show the experimental value labelled as excluded.
  /// This call never triggers fusion — main.py deliberately omits _auto_fuse
  /// here, because a modality that cannot change the composite should not add
  /// rows to the trend.
  static Future<BackendResult> ingestBehavioural({
    required String subjectId,
    required Map<String, dynamic> observations,
  }) =>
      _post(
        '/v1/ingest/behavioural',
        {'subject_id': subjectId, 'observations': observations},
        timeout: _slow,
      );

  // ───────────────────────────────────────────────────────────────────────────
  // Egress — the patient view
  // ───────────────────────────────────────────────────────────────────────────

  /// What the patient is allowed to see: composite, band, updated_at.
  ///
  /// Per-modality scores, fusion weights and clinical note content are withheld
  /// by the backend itself (main.py::patient_risk), not by this client. Do not
  /// try to reconstruct them here — showing a patient "your clinical notes
  /// score is 0.81" with no clinician present is a harm, and that judgement is
  /// the backend's to enforce.
  ///
  /// Band is one of GREEN / AMBER / RED / GREY. GREY means the gate blocked
  /// fusion — too few usable modalities — and must be shown as "not enough
  /// data yet", never as low risk.
  static Future<PatientRisk?> patientRisk(String subjectId) async {
    final result = await _get(
      '/v1/patients/$subjectId/risk',
      authenticated: false,
    );
    if (!result.ok) return null;
    return PatientRisk.fromJson(result.body);
  }

  static Future<Map<String, dynamic>?> health() async {
    final result = await _get('/health', timeout: const Duration(seconds: 30));
    return result.ok ? result.body : null;
  }
}

/// The patient-facing risk view. Four fields, because the backend returns four.
@immutable
class PatientRisk {
  /// Null whenever the gate blocked fusion or no assessment has run yet.
  final double? composite;

  /// GREEN | AMBER | RED | GREY
  final String band;

  final String message;
  final DateTime? updatedAt;

  const PatientRisk({
    required this.composite,
    required this.band,
    required this.message,
    required this.updatedAt,
  });

  factory PatientRisk.fromJson(Map<String, dynamic> j) {
    final raw = j['updated_at']?.toString();
    return PatientRisk(
      composite: (j['composite'] as num?)?.toDouble(),
      band: j['band']?.toString() ?? 'GREY',
      message: j['message']?.toString() ?? 'No assessment yet.',
      updatedAt: raw == null ? null : DateTime.tryParse(raw),
    );
  }

  /// True when there is a real composite to show. GREY with a null composite is
  /// the gate-blocked state and must not be rendered as a score of zero.
  bool get hasAssessment => composite != null && band != 'GREY';
}