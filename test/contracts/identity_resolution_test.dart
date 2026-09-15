import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:r26_ds012_app/data/api/api_client.dart';
import 'package:r26_ds012_app/data/api/gateways.dart';

const String _base = 'https://backend.test';

void main() {
  test('Aura participant id resolves through the existing backend alias route',
      () async {
    final sent = <http.Request>[];
    final gateway = CentralBackendGateway(
      ApiClient(
        _base,
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('{"subject_id":"subject-aura-001"}', 200);
        }),
        bearer: () => 'test-token',
      ),
    );

    final id = await gateway.resolveAppUserId('P_65DC4002E7863773');

    expect(id, 'subject-aura-001');
    expect(
      sent.single.url.toString(),
      '$_base/v1/subjects/resolve?app_user_id=P_65DC4002E7863773',
    );
    expect(sent.single.method, 'GET');
  });

  test('unknown Aura participant id resolves to null', () async {
    final gateway = CentralBackendGateway(
      ApiClient(
        _base,
        client: MockClient(
          (_) async => http.Response('{"detail":"not found"}', 404),
        ),
        bearer: () => 'test-token',
      ),
    );

    expect(
      await gateway.resolveAppUserId('P_65DC4002E7863773'),
      isNull,
    );
  });

  test('ClinAnx does not depend on the non-existent subjects/attach route', () {
    final gatewaySource =
        File('lib/data/api/gateways.dart').readAsStringSync();
    final controllerSource =
        File('lib/state/controllers.dart').readAsStringSync();

    expect(gatewaySource, isNot(contains('/v1/subjects/attach')));
    expect(controllerSource, isNot(contains('_backend.attach(')));
    expect(controllerSource, contains('resolveAppUserId'));
  });
}
