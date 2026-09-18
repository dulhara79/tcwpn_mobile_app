import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r26_ds012_app/data/api/api_client.dart';
import 'package:r26_ds012_app/data/api/session.dart';
import 'package:r26_ds012_app/data/repositories/central_backend_repositories.dart';
import 'package:r26_ds012_app/domain/contracts/contract_enums.dart';

Map<String, dynamic> assessment(String subjectId) => {
      'subject_id': subjectId,
      'fusion_result_id': 123,
      'current_assessment': {
        'score': 0.58,
        'tier': 'Medium',
        'band': 'AMBER',
      },
      'forecast': {
        'forecast_result_id': 'fcst-123',
        'scope': 'physiological',
        'horizon_minutes': 10,
        'score': 0.84,
        'tier': 'High',
        'escalation_probability': null,
        'escalation_predicted': true,
        'generated_at': '2026-09-18T12:00:00Z',
        'valid_until': '2026-09-18T12:10:00Z',
      },
      'confidence': 0.71,
      'assessment_status': 'complete',
      'modalities': [
        {
          'component_id': 'c1_physiological',
          'score': 0.82,
          'available': true,
          'included_in_fusion': true,
          'status': 'ok',
          'confidence': 0.5,
          'coverage': 0.5,
          'captured_at': '2026-09-18T11:59:00Z',
          'contribution': 0.24,
        },
        {
          'component_id': 'c2_behavioral',
          'score': null,
          'available': false,
          'included_in_fusion': false,
          'status': 'not_validated',
          'confidence': null,
          'coverage': null,
          'captured_at': null,
          'contribution': null,
        },
      ],
      'computed_at': '2026-09-18T12:00:00Z',
      'model_version': 'ragf-v0.4',
    };

void main() {
  tearDown(Session.clear);

  test('validates clinician identity with GET /v1/me', () async {
    Session.set(token: 'test-session', clinicianId: 'DR001');
    final api = ApiClient(
      'https://backend.test',
      bearer: () => 'test-session',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/me');
        return http.Response(
          jsonEncode({
            'principal_type': 'clinician',
            'principal_id': 'principal-1',
            'clinician_id': 'DR001',
            'display_name': 'Clinician One',
            'role': 'clinician',
            'status': 'active',
            'expires_at': '2026-09-19T00:00:00Z',
          }),
          200,
        );
      }),
    );

    await CentralBackendAuthRepository(api).validateCurrentSession();
    expect(Session.clinicianId, 'DR001');
  });

  test('fails closed when server clinician differs from local session', () async {
    Session.set(token: 'test-session', clinicianId: 'DR001');
    final api = ApiClient(
      'https://backend.test',
      bearer: () => 'test-session',
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'principal_type': 'clinician',
              'principal_id': 'principal-2',
              'clinician_id': 'DR002',
              'role': 'clinician',
              'status': 'active',
            }),
            200,
          )),
    );

    await expectLater(
      CentralBackendAuthRepository(api).validateCurrentSession(),
      throwsA(isA<ApiException>().having(
        (error) => error.kind,
        'kind',
        ApiFailure.forbidden,
      )),
    );
  });

  test('latest assessment preserves fusion and physiological forecast identity',
      () async {
    final api = ApiClient(
      'https://backend.test',
      bearer: () => 'test-session',
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/v1/patients/subject-001/assessment/latest',
        );
        return http.Response(jsonEncode(assessment('subject-001')), 200);
      }),
    );

    final result = await CentralBackendAssessmentRepository(api)
        .latestAssessment('subject-001');

    expect(result?.fusionResultId, 123);
    expect(result?.currentAssessment.score, 0.58);
    expect(result?.forecast?.forecastResultId, 'fcst-123');
    expect(result?.forecast?.scope, ForecastScope.physiological);
    expect(
      result?.modalities
          .firstWhere((item) => item.componentId == 'c2_behavioral')
          .isExperimentalExcluded,
      isTrue,
    );
  });

  test('assigned roster keeps patients with no current assessment unavailable',
      () async {
    final api = ApiClient(
      'https://backend.test',
      bearer: () => 'test-session',
      client: MockClient((request) async {
        if (request.url.path == '/v1/clinicians/me/patients') {
          return http.Response(
            jsonEncode({
              'clinician_id': 'DR001',
              'patients': [
                {'subject_id': 'subject-001'},
                {'subject_id': 'subject-002'},
              ],
            }),
            200,
          );
        }
        if (request.url.path ==
            '/v1/patients/subject-001/assessment/latest') {
          return http.Response(jsonEncode(assessment('subject-001')), 200);
        }
        if (request.url.path ==
            '/v1/patients/subject-002/assessment/latest') {
          return http.Response(
            jsonEncode({'detail': 'assessment unavailable'}),
            404,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final patients =
        await CentralBackendPatientRepository(api).assignedPatients();

    expect(patients.map((item) => item.subjectId), [
      'subject-001',
      'subject-002',
    ]);
    expect(patients.first.fusionResultId, 123);
    expect(patients.last.assessmentStatus, AssessmentStatus.unavailable);
    expect(patients.last.currentAssessment, isNull);
  });
}
