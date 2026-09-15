import 'attention_event.dart';
import 'patient_summary.dart';

class DashboardSnapshot {
  final List<AttentionEvent> openEvents;
  final List<PatientSummary> assignedPatients;
  final DateTime fetchedAt;
  final bool isFromCache;

  const DashboardSnapshot({
    required this.openEvents,
    required this.assignedPatients,
    required this.fetchedAt,
    this.isFromCache = false,
  });

  bool get isEmpty => openEvents.isEmpty && assignedPatients.isEmpty;

  DashboardSnapshot asCached() => DashboardSnapshot(
        openEvents: openEvents,
        assignedPatients: assignedPatients,
        fetchedAt: fetchedAt,
        isFromCache: true,
      );
}
