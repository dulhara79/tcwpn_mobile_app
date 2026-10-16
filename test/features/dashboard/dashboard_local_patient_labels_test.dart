import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:r26_ds012_app/data/api/session.dart';
import 'package:r26_ds012_app/data/local/patient_label_store.dart';
import 'package:r26_ds012_app/domain/contracts/attention_event.dart';
import 'package:r26_ds012_app/domain/contracts/contract_enums.dart';
import 'package:r26_ds012_app/domain/contracts/dashboard_snapshot.dart';
import 'package:r26_ds012_app/domain/contracts/patient_summary.dart';
import 'package:r26_ds012_app/domain/repositories/dashboard_repository.dart';
import 'package:r26_ds012_app/features/dashboard/server_dashboard_screen.dart';
import 'package:r26_ds012_app/state/dashboard_controller.dart';

class _FakeLabels implements PatientLabelStore {
  final labels = <String, String>{};
  String key(String clinician, String subject) => '$clinician|$subject';

  @override
  Future<String?> read({required String clinicianId, required String subjectId}) async =>
      labels[key(clinicianId, subjectId)];

  @override
  Future<void> write({
    required String clinicianId,
    required String subjectId,
    required String label,
  }) async {
    labels[key(clinicianId, subjectId)] = label;
  }

  @override
  Future<void> delete({required String clinicianId, required String subjectId}) async {
    labels.remove(key(clinicianId, subjectId));
  }
}

class _Dashboard implements DashboardRepository {
  final DashboardSnapshot snapshot;
  _Dashboard(this.snapshot);

  @override
  Future<DashboardSnapshot> loadDashboard() async => snapshot;
}

DashboardSnapshot _snapshot({bool cached = false}) => DashboardSnapshot(
  fetchedAt: DateTime.utc(2026, 10, 11),
  isFromCache: cached,
  assignedPatients: const [
    PatientSummary(
      subjectId: 'test-subject',
      displayId: 'Patient ABCD1234',
      fusionResultId: null,
      currentAssessment: null,
      forecast: null,
      assessmentStatus: AssessmentStatus.unavailable,
      lastUpdated: null,
      openEventCount: 1,
    ),
  ],
  openEvents: [
    AttentionEvent(
      id: 'evt-test',
      subjectId: 'test-subject',
      fusionResultId: null,
      forecastResultId: null,
      eventType: 'acute_escalation_forecast',
      severity: AttentionSeverity.high,
      reason: 'Synthetic regression event',
      forecastHorizon: null,
      status: AttentionEventStatus.open,
      createdAt: DateTime.utc(2026, 10, 11),
      acknowledgedAt: null,
      acknowledgedBy: null,
      resolvedAt: null,
      resolvedBy: null,
      policyVersion: 'test-v1',
    ),
  ],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Session.set(token: 'fake-test-session', clinicianId: 'DR001');
  });

  tearDown(Session.clear);

  testWidgets('dashboard patient card and attention card reflect local label changes',
      (tester) async {
    final labels = _FakeLabels();
    final controller = DashboardController(repository: _Dashboard(_snapshot()));
    await controller.load();

    await tester.pumpWidget(MaterialApp(
      home: ServerDashboardScreen(controller: controller, labelStore: labels),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Patient ABCD1234'), findsOneWidget);
    expect(find.text('Patient test-subject'), findsOneWidget);

    await labels.write(
      clinicianId: 'DR001', subjectId: 'test-subject', label: 'Participant A');
    PatientLabelStore.notifyChanged();
    await tester.pumpAndSettle();

    expect(find.text('Participant A'), findsNWidgets(2));
    expect(find.text('Patient ABCD1234'), findsNothing);
    expect(find.text('Patient test-subject'), findsNothing);

    await labels.delete(clinicianId: 'DR001', subjectId: 'test-subject');
    PatientLabelStore.notifyChanged();
    await tester.pumpAndSettle();
    expect(find.text('Patient ABCD1234'), findsOneWidget);
    expect(find.text('Patient test-subject'), findsOneWidget);
  });

  testWidgets('cached roster never exposes local clinician name', (tester) async {
    final labels = _FakeLabels();
    await labels.write(
      clinicianId: 'DR001', subjectId: 'test-subject', label: 'Participant A');
    final controller = DashboardController(
        repository: _Dashboard(_snapshot(cached: true)));
    await controller.load();
    await tester.pumpWidget(MaterialApp(
      home: ServerDashboardScreen(controller: controller, labelStore: labels),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Participant A'), findsNothing);
    expect(find.text('Patient ABCD1234'), findsOneWidget);
  });
}
