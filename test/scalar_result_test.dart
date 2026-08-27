// test/scalar_result_test.dart
//
// The bug this file exists to prevent:
//
// POST /v1/clinical-notes returns `status` and `score` on every scored note,
// but returns the model's explanation payload (`component_detail`) only when
// the service is configured to include it. The app used to key "was this note
// analysed?" off `result != null`, so a scored note with no payload was stored
// as `analysisFailed` and rendered as an unanalysed DRAFT — telling a clinician
// their assessment had not run when it had, and when its score had already been
// fused into the patient's composite.
//
// So these tests pin the DISTINCTION, not the happy path: scored-with-detail,
// scored-without-detail, submitted-but-not-scored, and transport failure must
// each produce a different state, and only the last two may look like a
// failure.
//
// No network is touched. MockClient is injected into ApiClient, which bypasses
// SecureHttp — correct, because a test double is not a network path.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:r26_ds012_app/data/api/api_client.dart';
import 'package:r26_ds012_app/data/api/gateways.dart';
import 'package:r26_ds012_app/domain/models.dart';

const String _base = 'https://backend.test';

CentralBackendGateway _gatewayReturning(String body, [int status = 200]) =>
    CentralBackendGateway(
      ApiClient(
        _base,
        client: MockClient((_) async => http.Response(body, status)),
        bearer: () => 'test-token',
      ),
    );

Future<ClinicalNoteIngestResult> _submit(CentralBackendGateway g) =>
    g.submitNote(
      subjectId: 'S-abc123',
      noteText: 'Persistent worry over eight months. GAD-7 14.',
      noteType: 'Psychiatry note',
      noteDate: DateTime.utc(2026, 8, 25, 9, 30),
      supportSet: const [],
      visitCount: 3,
      author: 'DR001',
    );

/// A note as it exists on disk before any analysis.
ClinicalNote _draft() => ClinicalNote(
      id: 'n-1',
      patientMrn: 'DEMO-001',
      recordedAt: DateTime.utc(2026, 8, 25, 9, 0),
      text: 'Persistent worry over eight months.',
      noteType: 'Psychiatry note',
      clinicianId: 'DR001',
    );

/// The exact transformation `ChartController.analyseStoredNote` applies to a
/// note once the ingest returns. Mirrored here so the state machine can be
/// tested without a Flutter binding or SharedPreferences.
ClinicalNote _applyIngest(ClinicalNote note, ClinicalNoteIngestResult ingest) {
  final scored = ingest.scored;
  return note.copyWith(
    result: ingest.result,
    clearResult: ingest.result == null,
    score: ingest.score,
    clearScore: ingest.score == null,
    componentStatus: ingest.status,
    scoreProvenance: ingest.scoreProvenance,
    analysedAt: DateTime.utc(2026, 8, 25, 9, 31),
    status: scored
        ? ClinicalNoteStatus.analysed
        : ClinicalNoteStatus.analysisFailed,
    clearAnalysisError: scored,
    lastAnalysisError: scored ? null : 'no usable score',
  );
}

void main() {
  // ── Case A — rich result ──────────────────────────────────────────────────
  group('A: the service returns the full explanation payload', () {
    const body = '''
{"subject_id":"S-abc123","reading_id":41,"status":"ok","score":0.72,
 "note":"used calibrated_probability",
 "component_detail":{"prediction":"ANXIETY","risk_score":0.72,
   "calibrated_probability":0.68,"confidence":0.81,"entropy":0.44,
   "threshold":0.5,"support_k":12},
 "fusion_triggered":true,
 "fusion":{"composite":0.61,"tier":"Medium","band":"AMBER","reason":"3 modalities"}}''';

    test('the rich result is parsed and the note is analysed', () async {
      final ingest = await _submit(_gatewayReturning(body));

      expect(ingest.scored, isTrue);
      expect(ingest.hasRichDetail, isTrue);
      expect(ingest.result!.supportK, 12);

      final note = _applyIngest(_draft(), ingest);
      expect(note.status, ClinicalNoteStatus.analysed);
      expect(note.hasRichResult, isTrue);
      expect(note.hasScalarResultOnly, isFalse);
      expect(note.hasBeenAnalysed, isTrue);
      expect(note.isDraft, isFalse);
    });

    test('the fusion summary is read as sent, never recomputed', () async {
      final ingest = await _submit(_gatewayReturning(body));
      expect(ingest.hasFusionSummary, isTrue);
      expect(ingest.fusionComposite, 0.61);
      expect(ingest.fusionTier, 'Medium');
      expect(ingest.fusionBand, 'AMBER');
      expect(ingest.fusionReason, '3 modalities');
    });
  });

  // ── Case B — scalar only. THE REGRESSION. ─────────────────────────────────
  group('B: the service scores the note but returns no explanation payload',
      () {
    // Exactly what c4_final/central_backend/main.py returns today.
    const body = '''
{"subject_id":"S-abc123","reading_id":42,"status":"ok","score":0.72,
 "note":"used risk_score (no calibrated_probability returned)",
 "fusion_triggered":true,
 "fusion":{"composite":0.55,"tier":"Medium","band":"AMBER","reason":"2 modalities"}}''';

    test('scored is true even though the rich result is absent', () async {
      final ingest = await _submit(_gatewayReturning(body));
      expect(ingest.scored, isTrue, reason: 'status ok + score present');
      expect(ingest.hasRichDetail, isFalse);
      expect(ingest.result, isNull);
      expect(ingest.score, 0.72);
    });

    test('the note is ANALYSED, not a draft and not a failure', () async {
      final note =
          _applyIngest(_draft(), await _submit(_gatewayReturning(body)));

      expect(note.status, ClinicalNoteStatus.analysed);
      expect(note.isDraft, isFalse);
      expect(note.analysisFailed, isFalse);
      expect(note.lastAnalysisError, isNull);
    });

    test('the scalar score is retained and reaches the reduced UI state',
        () async {
      final note =
          _applyIngest(_draft(), await _submit(_gatewayReturning(body)));

      // This combination is what TcwpnResultScreen routes to _scalarOnly on.
      expect(note.result, isNull);
      expect(note.score, 0.72);
      expect(note.hasScalarResultOnly, isTrue);
      expect(note.hasBeenAnalysed, isTrue,
          reason: 'a null result must no longer read as "not analysed"');
      expect(note.componentStatus, 'ok');
      expect(note.scoreProvenance, contains('risk_score'));
    });

    test('the scalar assessment survives a save/load round trip', () async {
      final note =
          _applyIngest(_draft(), await _submit(_gatewayReturning(body)));
      final reloaded =
          ClinicalNote.fromJson(jsonDecode(jsonEncode(note.toJson())));

      expect(reloaded.score, 0.72);
      expect(reloaded.status, ClinicalNoteStatus.analysed);
      expect(reloaded.hasScalarResultOnly, isTrue);
      expect(reloaded.componentStatus, 'ok');
    });

    test('editing the note clears the whole assessment, both halves', () async {
      final note =
          _applyIngest(_draft(), await _submit(_gatewayReturning(body)));
      final edited = note.copyWith(
        text: 'Rewritten.',
        clearResult: true,
        clearScore: true,
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(edited.score, isNull);
      expect(edited.result, isNull);
      expect(edited.analysedAt, isNull,
          reason: 'no assessment remains, so its timestamp is meaningless');
      expect(edited.hasBeenAnalysed, isFalse);
    });

    test('a re-analysis never keeps the previous run\'s rich result', () async {
      final rich = _applyIngest(
        _draft(),
        await _submit(_gatewayReturning(
            '{"subject_id":"S-abc123","status":"ok","score":0.9,'
            '"component_detail":{"risk_score":0.9,"threshold":0.5}}')),
      );
      expect(rich.hasRichResult, isTrue);

      // Same note, analysed again against a service that returns no payload.
      final again = _applyIngest(rich, await _submit(_gatewayReturning(body)));
      expect(again.result, isNull,
          reason: "one run's attention weights must not sit beside another "
              "run's score");
      expect(again.score, 0.72);
      expect(again.status, ClinicalNoteStatus.analysed);
    });
  });

  // ── Case C — submitted, not scored ────────────────────────────────────────
  group('C: the request succeeds but the model returns no score', () {
    test('no_support_set is a failure state with an honest reason', () async {
      final ingest = await _submit(_gatewayReturning(
        '{"subject_id":"S-abc123","reading_id":43,"status":"no_support_set",'
        '"score":null,"note":"no labelled examples for this subject"}',
      ));

      expect(ingest.scored, isFalse);
      expect(ingest.needsSupportSet, isTrue);

      final note = _applyIngest(_draft(), ingest);
      expect(note.status, ClinicalNoteStatus.analysisFailed);
      expect(note.score, isNull);
      expect(note.hasBeenAnalysed, isFalse);
      expect(note.lastAnalysisError, isNotNull);
    });

    test('status ok with a null score is still not scored', () async {
      final ingest = await _submit(_gatewayReturning(
        '{"subject_id":"S-abc123","status":"ok","score":null}',
      ));
      expect(ingest.scored, isFalse,
          reason: 'scored requires BOTH status ok and a score');
      expect(_applyIngest(_draft(), ingest).status,
          ClinicalNoteStatus.analysisFailed);
    });

    test('a component error is not silently downgraded to a draft', () async {
      final ingest = await _submit(_gatewayReturning(
        '{"subject_id":"S-abc123","status":"error","score":null,'
        '"note":"support bank unusable"}',
      ));
      final note = _applyIngest(_draft(), ingest);

      expect(note.analysisFailed, isTrue);
      expect(note.isDraft, isFalse,
          reason: 'a failed analysis is a distinct state from never trying');
    });
  });

  // ── Case D — transport failure ────────────────────────────────────────────
  group('D: the request itself fails', () {
    test('401 still throws, and is still an auth failure', () async {
      await expectLater(
        _submit(_gatewayReturning('{"detail":"invalid token"}', 401)),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiFailure.unauthorized)),
      );
    });

    test('500 throws rather than producing an unscored note', () async {
      await expectLater(
        _submit(_gatewayReturning('{"detail":"boom"}', 500)),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiFailure.server)),
      );
    });

    test('a non-JSON body is malformed, never an empty assessment', () async {
      await expectLater(
        _submit(_gatewayReturning('<html>gateway</html>')),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiFailure.malformed)),
      );
    });
  });
}
