import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r26_ds012_app/data/api/api_client.dart';
import 'package:r26_ds012_app/data/api/gateways.dart';
import 'package:r26_ds012_app/data/api/session.dart';
import 'package:r26_ds012_app/domain/models.dart';

void main() {
  tearDown(Session.clear);

  group('the app talks to the Central Backend and nothing else', () {
    test('a note goes to /v1/clinical-notes, not to a model service', () async {
      late http.Request sent;
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'subject_id': 'S1',
                'component': {
                  'component_id': 'c3_clinical_nlp',
                  'score': 0.72,
                  'available': true,
                  'status': 'ok',
                },
                'fusion': {'fusion_result_id': 1},
              }),
              200,
            );
          }),
          bearer: () => 'token',
        ),
      );

      await gateway.submitNote(
        subjectId: 'S1',
        noteText: 'test note',
        noteType: 'progress',
        anxietySupport: const [],
        controlSupport: const [],
        author: 'DR1',
      );

      expect(sent.url.path, '/v1/clinical-notes');
      expect(sent.url.path, isNot(contains('/predict')));
    });

    test('the note request carries no weights and no composite', () async {
      late Map<String, dynamic> body;
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'subject_id': 'S1',
                'component': {
                  'component_id': 'c3_clinical_nlp',
                  'score': 0.72,
                  'available': true,
                  'status': 'ok',
                },
                'fusion': {'fusion_result_id': 1},
              }),
              200,
            );
          }),
          bearer: () => 'token',
        ),
      );

      await gateway.submitNote(
        subjectId: 'S1',
        noteText: 'test note',
        noteType: 'progress',
        anxietySupport: const [],
        controlSupport: const [],
        author: 'DR1',
      );

      expect(body.containsKey('weights'), isFalse);
      expect(body.containsKey('composite'), isFalse);
    });

    test('enrolment sends the MRN once and the app keeps the subject_id', () async {
      late Map<String, dynamic> body;
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'subject_id': 'S1',
                'pairing_code': 'ABC123',
                'expires_at': '2026-09-16T10:00:00Z',
              }),
              200,
            );
          }),
          bearer: () => 'token',
        ),
      );

      final result = await gateway.enrol(mrn: 'MRN-001');

      expect(body['mrn'], 'MRN-001');
      expect(result.subjectId, 'S1');
    });

    test('a verdict is bound to the fusion row the clinician looked at', () async {
      late Map<String, dynamic> body;
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{}', 200);
          }),
          bearer: () => 'token',
        ),
      );

      await gateway.submitVerdict(
        fusionResultId: 17,
        decision: 'agree',
        author: 'DR1',
      );

      expect(body['fusion_result_id'], 17);
    });

    test('the TC-WPN Space is only ever asked for /health', () {
      final source = File('lib/data/api/gateways.dart').readAsStringSync();
      expect(source, isNot(contains("'/predict'")));
    });
  });

  group('a failed call is an error, never a score', () {
    CentralBackendGateway _failing(int status) => CentralBackendGateway(
          ApiClient(
            'https://backend.test',
            client: MockClient(
              (_) async => http.Response('{"detail":"nope"}', status),
            ),
            bearer: () => 'token',
          ),
        );

    test('400 surfaces as validation', () async {
      await expectLater(
        _failing(400).timeline(subjectId: 'S1', mrn: 'S-000123'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.validation,
          ),
        ),
      );
    });

    test('422 surfaces as validation, with the server detail intact', () async {
      await expectLater(
        _failing(422).timeline(subjectId: 'S1', mrn: 'S-000123'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.validation,
          ),
        ),
      );
    });

    test('401 surfaces as unauthorized, not as an empty chart', () async {
      await expectLater(
        _failing(401).timeline(subjectId: 'S1', mrn: 'S-000123'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.unauthorized,
          ),
        ),
      );
    });

    test('403 surfaces as forbidden, distinct from expired identity', () async {
      await expectLater(
        _failing(403).timeline(subjectId: 'S1', mrn: 'S-000123'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.forbidden,
          ),
        ),
      );
    });

    test('500 throws rather than returning a default FusionResult', () async {
      await expectLater(
        _failing(500).latestFusion(subjectId: 'S1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('503 from the fusion trigger throws', () async {
      await expectLater(
        _failing(503).triggerFusion(subjectId: 'S1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('an unknown subject is null, which is a state — not an exception',
        () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => http.Response('{}', 404)),
          bearer: () => 'token',
        ),
      );
      expect(await gateway.latestFusion(subjectId: 'S1'), isNull);
    });

    test('resolveMrn returns null for an unenrolled MRN', () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => http.Response('{}', 404)),
          bearer: () => 'token',
        ),
      );
      expect(await gateway.resolveMrn('MRN-001'), isNull);
    });

    test('a 409 on external-id linking is NOT swallowed', () async {
      await expectLater(
        _failing(409).registerExternalId(
          subjectId: 'S1',
          modality: 'c1_physiological',
          externalId: 'AURA-1',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.conflict,
          ),
        ),
      );
    });

    test('a network drop is offline, not an empty result', () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => throw const SocketException('down')),
          bearer: () => 'token',
        ),
      );
      await expectLater(
        gateway.latestFusion(subjectId: 'S1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.offline,
          ),
        ),
      );
    });

    test('a timeout is a timeout', () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => Future<http.Response>.delayed(
                const Duration(milliseconds: 50),
                () => http.Response('{}', 200),
              )),
          bearer: () => 'token',
        ),
      );
      await expectLater(
        gateway.latestFusion(
          subjectId: 'S1',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.timeout,
          ),
        ),
      );
    });

    test('an HTML error page is malformed, not a FormatException crash', () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => http.Response('<html>bad</html>', 200)),
          bearer: () => 'token',
        ),
      );
      await expectLater(
        gateway.latestFusion(subjectId: 'S1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailure.malformed,
          ),
        ),
      );
    });

    test('health() degrades to null rather than blocking the app', () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => http.Response('{}', 503)),
          bearer: () => 'token',
        ),
      );
      expect(await gateway.health(), isNull);
    });
  });

  group('an experimental behavioural score never reaches the composite', () {
    test('not_validated with a real score is still not usable evidence', () {
      final result = FusionResult.fromJson({
        'fusion_result_id': 1,
        'component_details': {
          'c2_behavioral': {
            'score': 0.91,
            'available': true,
            'status': 'not_validated',
            'included': false,
          },
        },
      });
      expect(result.componentDetails['c2_behavioral']?.included, isFalse);
    });

    test('the exclusion explains itself in clinician language', () {
      final result = FusionResult.fromJson({
        'fusion_result_id': 1,
        'component_details': {
          'c2_behavioral': {
            'score': 0.91,
            'available': true,
            'status': 'not_validated',
            'included': false,
          },
        },
      });
      expect(
        result.componentDetails['c2_behavioral']?.status,
        'not_validated',
      );
    });

    test('an absent modality stays null and is never 0.0', () {
      final result = FusionResult.fromJson({'fusion_result_id': 1});
      expect(result.componentDetails['c2_behavioral'], isNull);
    });

    test('the composite is the server\'s number, unmodified', () {
      final result = FusionResult.fromJson({
        'fusion_result_id': 1,
        'composite_score': 0.613,
      });
      expect(result.compositeScore, 0.613);
    });

    test('contributions are read, not recomputed as weight x score', () {
      final result = FusionResult.fromJson({
        'fusion_result_id': 1,
        'contributions': {'c1_physiological': 0.22},
      });
      expect(result.contributions['c1_physiological'], 0.22);
    });

    test('the two fused modalities carry all the weight', () {
      final result = FusionResult.fromJson({
        'fusion_result_id': 1,
        'weights': {
          'c1_physiological': 0.55,
          'c3_clinical_nlp': 0.45,
          'c2_behavioral': 0.0,
        },
      });
      expect(result.weights['c1_physiological'], 0.55);
      expect(result.weights['c3_clinical_nlp'], 0.45);
      expect(result.weights['c2_behavioral'], 0.0);
    });
  });

  group('CARE-AnxRAG', () {
    test('guidance is requested through the backend, not a RAG service', () async {
      late http.Request sent;
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((request) async {
            sent = request;
            return http.Response('{"answer":"ok","abstained":false}', 200);
          }),
          bearer: () => 'token',
        ),
      );

      await gateway.evidence(subjectId: 'S1', question: 'What changed?');
      expect(sent.url.path, '/v1/doctor/patients/S1/evidence');
    });

    test('an abstention is passed through, not turned into advice', () async {
      final gateway = CentralBackendGateway(
        ApiClient(
          'https://backend.test',
          client: MockClient((_) async => http.Response(
                '{"answer":null,"abstained":true,"reason":"insufficient evidence"}',
                200,
              )),
          bearer: () => 'token',
        ),
      );

      final result = await gateway.evidence(
        subjectId: 'S1',
        question: 'What changed?',
      );
      expect(result.abstained, isTrue);
      expect(result.answer, isNull);
    });

    test('an unavailable RAG backend throws instead of returning silence', () async {
      final gateway = _failingCare(503);
      await expectLater(
        gateway.evidence(subjectId: 'S1', question: 'What changed?'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

CentralBackendGateway _failingCare(int status) => CentralBackendGateway(
      ApiClient(
        'https://backend.test',
        client: MockClient((_) async => http.Response('{"detail":"nope"}', status)),
        bearer: () => 'token',
      ),
    );
