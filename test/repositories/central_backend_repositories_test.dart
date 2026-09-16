import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r26_ds012_app/data/api/api_client.dart';
import 'package:r26_ds012_app/data/repositories/central_backend_repositories.dart';

void main() {
  ApiClient noNetworkApi() => ApiClient(
        'https://backend.test',
        client: MockClient((request) async {
          fail('Unverified target adapter attempted network call: ${request.url}');
          return http.Response('{}', 500);
        }),
        bearer: () => 'clinician-jwt',
      );

  test('auth target adapter remains blocked until backend contract is verified',
      () async {
    await expectLater(
      CentralBackendAuthRepository(noNetworkApi()).validateCurrentSession(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiFailure.notConfigured,
        ),
      ),
    );
  });

  test('dashboard target adapter remains blocked until backend contract is verified',
      () async {
    await expectLater(
      CentralBackendDashboardRepository(noNetworkApi()).loadDashboard(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiFailure.notConfigured,
        ),
      ),
    );
  });

  test('latest assessment target adapter remains blocked until backend contract is verified',
      () async {
    await expectLater(
      CentralBackendAssessmentRepository(noNetworkApi())
          .latestAssessment('subject-001'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiFailure.notConfigured,
        ),
      ),
    );
  });
}
