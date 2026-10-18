import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r26_ds012_app/data/api/api_client.dart';
import 'package:r26_ds012_app/data/repositories/patient_unassignment_repository.dart';

void main() {
  test('uses authenticated DELETE and canonical subject path', () async {
    final client = ApiClient(
      'https://example.com',
      bearer: () => 'clinician-token',
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path,
            '/v1/clinicians/me/assignments/subject-1');
        expect(request.headers['Authorization'], 'Bearer clinician-token');
        return http.Response(jsonEncode({
          'subject_id': 'subject-1', 'clinician_id': 'DR002',
          'active': false,
        }), 200);
      }),
    );
    await CentralBackendPatientUnassignmentRepository(client)
        .unassign('subject-1');
  });

  test('refuses a response without server confirmation', () async {
    final api = ApiClient('https://example.com',
      bearer: () => 'clinician-token',
      client: MockClient((_) async => http.Response(
        jsonEncode({'subject_id': 'subject-1', 'active': true}), 200)),
    );
    await expectLater(
      CentralBackendPatientUnassignmentRepository(api).unassign('subject-1'),
      throwsA(isA<ApiException>().having(
        (e) => e.kind, 'kind', ApiFailure.malformed)),
    );
  });

  test('does not mask conflict from server', () async {
    final api = ApiClient('https://example.com',
      bearer: () => 'clinician-token',
      client: MockClient((_) async => http.Response(
        '{"detail":"unresolved events"}', 409)),
    );
    await expectLater(
      CentralBackendPatientUnassignmentRepository(api).unassign('subject-1'),
      throwsA(isA<ApiException>().having(
        (e) => e.kind, 'kind', ApiFailure.conflict)),
    );
  });
}
