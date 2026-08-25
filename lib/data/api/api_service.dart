// lib/services/api_service.dart
//
// REPLACES the existing file.
//
// WHAT CHANGED AND WHY
// ====================
//
// 1. sendToFusionModel() IS DELETED.
//    It posted to a constant literally named PLACEHOLDER_FUSION_ENDPOINT and
//    short-circuited to {'success': false} on every call, so it had never once
//    reached a fusion service. Worse, it hardcoded a fusion URL into the
//    patient APK, which is exactly the coupling section 2 of the feedback rules
//    out. Fusion is not the phone's job: the backend runs it automatically
//    after each ingest (main.py::_auto_fuse) and the phone reads the result
//    back from /v1/patients/{subject_id}/risk. See dashboard_page patch.
//
// 2. sendFeatureData() NOW DUAL-WRITES.
//    Read this part carefully, because the obvious reading of the feedback
//    document gets it wrong.
//
//    The document says the app should only know CENTRAL_BACKEND_BASE_URL. For
//    the clinician app that is already true and correct. For the patient app it
//    is not yet achievable, and doing it naively would BREAK C1.
//
//    Here is the actual dependency. The backend's target contract posts the
//    window to C1's POST /predict. C1 has not shipped that route — it serves
//    POST /ingest plus GET /predict/{user_id}. modality_clients.call_c1 handles
//    this: on 404 it falls back to _call_c1_legacy, which does
//    GET /predict/{user_id} and reads whatever is in C1's OWN rolling buffer.
//    That buffer is fed by POST /ingest, from this app.
//
//    So if the phone stops posting to C1 /ingest and posts only to the backend,
//    C1's buffer starves, the legacy fallback returns status 'buffering'
//    forever, the backend maps that to 'warming_up', the gate finds no usable
//    physiological reading, and every fusion goes GREY. Routing "properly"
//    would produce a system that looks correct and computes nothing.
//
//    The honest transitional design is therefore two writes from one call site:
//      • POST {C1}/ingest                    keeps C1's buffer alive
//      • POST {backend}/v1/ingest/physiological   records the reading, fuses
//
//    This is a documented transition, not the end state. THE MOMENT C1 SHIPS
//    POST /predict, delete the C1 leg: the backend's target-contract path stops
//    404ing and the phone needs only the backend. That single deletion is the
//    whole remaining distance to the document's architecture, and it is one
//    function call, not a refactor.
//
// 3. pairWithCentralBackend() DELEGATES to CentralBackendService.
//    The old version parsed the response but never stored the subject_id and
//    never registered the C1/C2 external ids, so the backend had no way to know
//    which C1 user this subject was. That mapping is what makes the legacy
//    fallback ask C1 about the right person.
//
// The C1 calls that remain (calibration, forecast, history, feedback) are
// patient-facing features C1 owns and the backend does not proxy. They stay.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'central_backend_service.dart';

class ApiService {
  /// Component 1 — the physiological Space. Still called directly for the
  /// patient's own forecast, calibration and history, none of which the central
  /// backend proxies.
  static const String baseUrl = String.fromEnvironment(
    'C1_BASE',
    defaultValue: 'https://dewdu-physiological-anxiety-escalation.hf.space',
  );

  /// Kept as a re-export so existing call sites keep compiling. New code should
  /// read CentralBackendService.baseUrl.
  static String get centralBackendBaseUrl => CentralBackendService.baseUrl;

  // ───────────────────────────────────────────────────────────────────────────
  // Physiological ingest — dual write, see header note 2
  // ───────────────────────────────────────────────────────────────────────────

  /// Sends one averaged 60-second feature window to C1 and to the central
  /// backend.
  ///
  /// Returns true when C1 accepted the window, preserving the old contract that
  /// sensor_manager already branches on. Backend failure is logged but does not
  /// flip the result: a backend outage must not make the app discard readings
  /// that C1 accepted and that still drive the patient's live forecast.
  static Future<bool> sendFeatureData({
    required String userId,
    required bool isWorn,
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
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    final end = windowEnd ?? DateTime.now().toUtc();
    final start = windowStart ?? end.subtract(const Duration(seconds: 60));

    final c1Ok = await _sendToC1(
      userId: userId,
      isWorn: isWorn,
      meanHr: meanHr,
      meanRr: meanRr,
      sdnn: sdnn,
      rmssd: rmssd,
      meanBr: meanBr,
      stdBr: stdBr,
      meanTemp: meanTemp,
      stdTemp: stdTemp,
      meanAccMag: meanAccMag,
      stdAccMag: stdAccMag,
    );

    // An off-body window is deliberately NOT forwarded to the backend. C1's
    // data-quality guard rejects it anyway, and a rejected window recorded as a
    // ModalityReading would age the subject's freshness clock while carrying no
    // signal — the reading would look recent and mean nothing.
    if (isWorn) {
      await _sendWindowToBackend(
        userId: userId,
        windowStart: start,
        windowEnd: end,
        meanHr: meanHr,
        meanRr: meanRr,
        sdnn: sdnn,
        rmssd: rmssd,
        meanBr: meanBr,
        stdBr: stdBr,
        meanTemp: meanTemp,
        stdTemp: stdTemp,
        meanAccMag: meanAccMag,
        stdAccMag: stdAccMag,
      );
    }

    return c1Ok;
  }

  static Future<bool> _sendToC1({
    required String userId,
    required bool isWorn,
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
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/ingest'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'is_worn': isWorn,
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
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return true;
      debugPrint(
        '[C1] data-quality guard rejected the window: '
        '${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[C1] network exception during feature ingest: $e');
      return false;
    }
  }

  static Future<void> _sendWindowToBackend({
    required String userId,
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
  }) async {
    final subjectId = await CentralBackendService.currentSubjectId();
    if (subjectId == null || subjectId.isEmpty) {
      // Unpaired install. Normal for a participant who has not yet redeemed a
      // clinician's code — not an error, and not worth a log line every minute.
      return;
    }

    final result = await CentralBackendService.ingestPhysiological(
      subjectId: subjectId,
      deviceUserId: userId,
      windowStart: windowStart,
      windowEnd: windowEnd,
      meanHr: meanHr,
      meanRr: meanRr,
      sdnn: sdnn,
      rmssd: rmssd,
      meanBr: meanBr,
      stdBr: stdBr,
      meanTemp: meanTemp,
      stdTemp: stdTemp,
      meanAccMag: meanAccMag,
      stdAccMag: stdAccMag,
    );

    if (!result.ok) {
      debugPrint('[central] physiological ingest failed: ${result.message}');
    } else if (result.fusionTriggered) {
      debugPrint('[central] window accepted; fusion re-ran');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Pairing
  // ───────────────────────────────────────────────────────────────────────────

  /// Links this app's pseudonymous participant ID to the subject the clinician
  /// enrolled, persists the returned subject_id, and registers the component
  /// external-id aliases.
  ///
  /// Return shape is unchanged so share_participant_id_page keeps working.
  static Future<Map<String, dynamic>> pairWithCentralBackend({
    required String participantId,
    required String pairingCode,
  }) async {
    final result = await CentralBackendService.pair(
      participantId: participantId,
      pairingCode: pairingCode,
    );

    if (result.ok) {
      return {
        'success': true,
        'subject_id': result.body['subject_id']?.toString() ?? '',
      };
    }
    return {
      'success': false,
      'message':
          result.message ?? 'The central backend rejected the pairing request.',
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Component 1 patient-facing features — unchanged
  // ───────────────────────────────────────────────────────────────────────────

  static Future<bool> setNormalizationParams({
    required String userId,
    required List<double> bMean,
    required List<double> bStd,
    required List<List<double>> baselineWindows,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/set_norm_params/$userId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'b_mean': bMean,
              'b_std': bStd,
              'baseline_windows': baselineWindows,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return true;
      debugPrint('[C1] calibration failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('[C1] network exception during calibration: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getEscalationForecast(
    String userId,
  ) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/predict/$userId'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('[C1] prediction pipeline failed: ${response.body}');
      return {'status': 'error', 'message': 'Forecast unavailable right now.'};
    } catch (e) {
      debugPrint('[C1] network exception during prediction: $e');
      return {'status': 'error', 'message': 'No internet connection.'};
    }
  }

  static Future<Map<String, dynamic>> getPhysiologicalHistory(
    String userId, {
    int days = 30,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/history/$userId?days=$days'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        'status': 'error',
        'message': response.statusCode == 404
            ? 'Your history is not available yet.'
            : 'Could not load your history.',
      };
    } catch (_) {
      return {'status': 'error', 'message': 'Could not load your history.'};
    }
  }

  static Future<bool> sendAnxietyFeedback(Map<String, dynamic> feedback) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/feedback/anxiety'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(feedback),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[C1] anxiety feedback upload failed: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getWeeklyFeedbackSummary(
    String userId,
  ) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/feedback/weekly/$userId'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error'};
    } catch (_) {
      return {'status': 'error'};
    }
  }
}