import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:r26_ds012_app/domain/contracts/attention_event.dart';
import 'package:r26_ds012_app/domain/contracts/contract_enums.dart';
import 'package:r26_ds012_app/domain/repositories/attention_event_repository.dart';
import 'package:r26_ds012_app/features/attention_events/attention_event_detail_screen.dart';
import 'package:r26_ds012_app/state/attention_event_detail_controller.dart';

AttentionEvent _event(
  AttentionEventStatus status, {
  String? acknowledgedBy,
  DateTime? acknowledgedAt,
  String? resolvedBy,
  DateTime? resolvedAt,
}) =>
    AttentionEvent(
      id: 'evt-001',
      subjectId: 'subject-001',
      fusionResultId: 123,
      forecastResultId: 'fcst-001',
      eventType: 'acute_escalation_forecast',
      severity: AttentionSeverity.high,
      reason: 'Forecast crossed versioned escalation policy',
      forecastHorizon: 10,
      status: status,
      createdAt: DateTime.utc(2026, 9, 16, 8),
      acknowledgedAt: acknowledgedAt,
      acknowledgedBy: acknowledgedBy,
      resolvedAt: resolvedAt,
      resolvedBy: resolvedBy,
      policyVersion: 'escalation-v1',
    );

class _Events implements AttentionEventRepository {
  AttentionEvent event;
  Completer<AttentionEvent>? acknowledgeCompleter;

  _Events(this.event);

  @override
  Future<AttentionEvent?> eventById(String eventId) async => event;

  @override
  Future<AttentionEvent> acknowledge(String eventId) async {
    final completer = acknowledgeCompleter;
    if (completer != null) return completer.future;
    return event;
  }

  @override
  Future<AttentionEvent> resolve(String eventId) async => event;

  @override
  Future<List<AttentionEvent>> activity({String? subjectId}) async => [event];

  @override
  Future<List<AttentionEvent>> openEvents() async => [event];
}

Future<AttentionEventDetailController> _controller(
  AttentionEvent event, {
  _Events? repository,
}) async {
  final controller = AttentionEventDetailController(
    eventId: event.id,
    repository: repository ?? _Events(event),
  );
  await controller.load();
  return controller;
}

void main() {
  testWidgets('detail shows canonical server identity and provenance',
      (tester) async {
    final controller = await _controller(_event(AttentionEventStatus.open));

    await tester.pumpWidget(
      MaterialApp(home: AttentionEventDetailScreen(controller: controller)),
    );

    expect(find.text('evt-001'), findsWidgets);
    expect(find.text('subject-001'), findsWidgets);
    expect(find.textContaining('Fusion result #123'), findsOneWidget);
    expect(find.textContaining('fcst-001'), findsOneWidget);
    expect(find.textContaining('escalation-v1'), findsOneWidget);
    expect(find.textContaining('10-minute'), findsOneWidget);
    expect(find.textContaining('acute_escalation_forecast'), findsOneWidget);
    expect(find.textContaining('Forecast crossed'), findsOneWidget);
  });

  testWidgets('OPEN shows Acknowledge and no Resolve', (tester) async {
    final controller = await _controller(_event(AttentionEventStatus.open));
    await tester.pumpWidget(
      MaterialApp(home: AttentionEventDetailScreen(controller: controller)),
    );

    expect(find.widgetWithText(OutlinedButton, 'Acknowledge'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Resolve'), findsNothing);
  });

  testWidgets('ACKNOWLEDGED shows Resolve and server acknowledgement provenance',
      (tester) async {
    final controller = await _controller(
      _event(
        AttentionEventStatus.acknowledged,
        acknowledgedBy: 'DR001',
        acknowledgedAt: DateTime.utc(2026, 9, 16, 8, 2),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: AttentionEventDetailScreen(controller: controller)),
    );

    expect(find.widgetWithText(OutlinedButton, 'Resolve'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Acknowledge'), findsNothing);
    expect(find.textContaining('DR001'), findsOneWidget);
  });

  testWidgets('RESOLVED and UNKNOWN expose no mutation action', (tester) async {
    for (final status in [
      AttentionEventStatus.resolved,
      AttentionEventStatus.unknown,
    ]) {
      final controller = await _controller(
        _event(
          status,
          acknowledgedBy: status == AttentionEventStatus.resolved ? 'DR001' : null,
          acknowledgedAt: status == AttentionEventStatus.resolved
              ? DateTime.utc(2026, 9, 16, 8, 2)
              : null,
          resolvedBy: status == AttentionEventStatus.resolved ? 'DR002' : null,
          resolvedAt: status == AttentionEventStatus.resolved
              ? DateTime.utc(2026, 9, 16, 8, 8)
              : null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: AttentionEventDetailScreen(controller: controller)),
      );

      expect(find.widgetWithText(OutlinedButton, 'Acknowledge'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Resolve'), findsNothing);
    }
  });

  testWidgets('mutation action disables while server request is in flight',
      (tester) async {
    final event = _event(AttentionEventStatus.open);
    final repository = _Events(event)
      ..acknowledgeCompleter = Completer<AttentionEvent>();
    final controller = await _controller(event, repository: repository);

    await tester.pumpWidget(
      MaterialApp(home: AttentionEventDetailScreen(controller: controller)),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Acknowledge'));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Acknowledge'),
    );
    expect(button.onPressed, isNull);

    repository.acknowledgeCompleter!.complete(
      _event(
        AttentionEventStatus.acknowledged,
        acknowledgedBy: 'DR001',
        acknowledgedAt: DateTime.utc(2026, 9, 16, 8, 2),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('View patient preserves canonical subject id', (tester) async {
    final controller = await _controller(_event(AttentionEventStatus.open));
    String? openedSubject;

    await tester.pumpWidget(
      MaterialApp(
        home: AttentionEventDetailScreen(
          controller: controller,
          onOpenPatient: (subjectId) => openedSubject = subjectId,
        ),
      ),
    );

    await tester.tap(find.text('View patient'));
    await tester.pump();

    expect(openedSubject, 'subject-001');
  });
}
