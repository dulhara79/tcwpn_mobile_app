import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/session.dart';
import '../../data/local/patient_label_store.dart';
import '../../domain/contracts/attention_event.dart';
import '../../domain/contracts/contract_enums.dart';
import '../../domain/contracts/dashboard_snapshot.dart';
import '../../domain/contracts/patient_summary.dart';
import '../../state/async_data_state.dart';
import '../../state/dashboard_controller.dart';
import '../attention_events/attention_event_detail_screen.dart';
import '../patients/patient_overview_screen.dart';

/// Only the Central Backend supplies clinical status. Optional device-local
/// display labels never enter the network, assessment, or cached dashboard.
class ServerDashboardScreen extends StatefulWidget {
  final DashboardController controller;
  final ValueChanged<PatientSummary>? onOpenPatient;
  final ValueChanged<AttentionEvent>? onOpenEvent;
  final PatientLabelStore? labelStore;

  const ServerDashboardScreen({
    super.key,
    required this.controller,
    this.onOpenPatient,
    this.onOpenEvent,
    this.labelStore,
  });

  @override
  State<ServerDashboardScreen> createState() => _ServerDashboardScreenState();
}

class _ServerDashboardScreenState extends State<ServerDashboardScreen> {
  late final PatientLabelStore _labelStore =
      widget.labelStore ?? const SecurePatientLabelStore();
  final Map<String, String> _labels = {};
  String? _rosterKey;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleLabels);
    _scheduleLabels();
  }

  @override
  void didUpdateWidget(covariant ServerDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleLabels);
      widget.controller.addListener(_scheduleLabels);
      _rosterKey = null;
      _labels.clear();
      _scheduleLabels();
    }
  }

  void _scheduleLabels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshLabels();
    });
  }

  void _refreshLabels() {
    final state = widget.controller.state;
    final snapshot = state.data;
    final clinician = Session.isActive ? Session.clinicianId : null;
    if (snapshot == null || snapshot.isFromCache || clinician == null ||
        clinician.isEmpty || state.status == AsyncDataStatus.forbidden ||
        state.status == AsyncDataStatus.sessionExpired) {
      if (_rosterKey != null || _labels.isNotEmpty) {
        setState(() {
          _rosterKey = null;
          _labels.clear();
        });
      }
      return;
    }

    final ids = snapshot.assignedPatients.map((p) => p.subjectId).toList()
      ..sort();
    final key = '$clinician|${ids.join('|')}';
    if (_rosterKey == key) return;
    _rosterKey = key;
    Future.wait(snapshot.assignedPatients.map((p) async => MapEntry(
          p.subjectId,
          await _labelStore.read(clinicianId: clinician, subjectId: p.subjectId),
        ))).then((entries) {
      if (!mounted || !Session.isActive || Session.clinicianId != clinician ||
          _rosterKey != key || widget.controller.state.data?.isFromCache != false) {
        return;
      }
      setState(() {
        _labels.clear();
        for (final entry in entries) {
          if (entry.value?.trim().isNotEmpty == true) {
            _labels[entry.key] = entry.value!;
          }
        }
      });
    }).catchError((Object _) {
      if (mounted && _rosterKey == key) {
        setState(() {
          _rosterKey = null;
          _labels.clear();
        });
      }
    });
  }

  String _patientLabel(PatientSummary patient, DashboardSnapshot snapshot) {
    if (!snapshot.isFromCache && Session.isActive &&
        _rosterKey?.startsWith('${Session.clinicianId}|') == true) {
      final local = _labels[patient.subjectId];
      if (local != null && local.isNotEmpty) return local;
    }
    return patient.displayId ?? 'Participant ${_shortId(patient.subjectId)}';
  }

  void _openPatient(BuildContext context, PatientSummary patient,
      DashboardSnapshot snapshot) {
    final callback = widget.onOpenPatient;
    if (callback != null) {
      callback(patient);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientOverviewScreen.production(
          subjectId: patient.subjectId,
          displayId: _patientLabel(patient, snapshot),
        ),
      ),
    );
  }

  void _openEvent(BuildContext context, AttentionEvent event) {
    final callback = widget.onOpenEvent;
    if (callback != null) {
      callback(event);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttentionEventDetailScreen.production(eventId: event.id),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleLabels);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        if (state.status == AsyncDataStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final snapshot = state.data;
        if (snapshot == null) {
          return _NoDashboardData(
            status: state.status,
            message: state.message,
            onRetry: widget.controller.load,
          );
        }

        final activeIds = snapshot.openEvents.map((e) => e.subjectId).toSet();
        final patients = [...snapshot.assignedPatients]
          ..sort((a, b) {
            final aAttention = activeIds.contains(a.subjectId) ? 0 : 1;
            final bAttention = activeIds.contains(b.subjectId) ? 0 : 1;
            if (aAttention != bAttention) {
              return aAttention.compareTo(bAttention);
            }
            final tierCompare =
                _priority(a).compareTo(_priority(b));
            if (tierCompare != 0) return tierCompare;
            return _patientLabel(a, snapshot)
                .compareTo(_patientLabel(b, snapshot));
          });
        final assessed = patients.where((p) =>
          p.assessmentStatus != AssessmentStatus.unavailable &&
          p.currentAssessment?.score != null).length;
        final clinicianName = snapshot.clinician?.displayName?.trim();
        final clinician = clinicianName == null || clinicianName.isEmpty
            ? 'Clinician worklist'
            : 'Welcome, $clinicianName';

        return RefreshIndicator(
          onRefresh: () => widget.controller.load(showLoading: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s3, Ds.s4, Ds.s10),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ClinAnx', style: AppTheme.display(size: 28)),
                        const SizedBox(height: 2),
                        Text(clinician, style: const TextStyle(
                            color: Ds.inkMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh dashboard',
                    onPressed: () => widget.controller.load(showLoading: false),
                    icon: const Icon(Icons.refresh_rounded, color: Ds.brand),
                  ),
                ],
              ),
              const SizedBox(height: Ds.s4),
              Container(
                padding: const EdgeInsets.all(Ds.s5),
                decoration: BoxDecoration(
                  color: Ds.brand,
                  borderRadius: BorderRadius.circular(Ds.rLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.monitor_heart_outlined, color: Colors.white70, size: 19),
                        SizedBox(width: Ds.s2),
                        Text('CLINICAL OVERVIEW', style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4)),
                      ],
                    ),
                    const SizedBox(height: Ds.s3),
                    const Text('Your assigned participants',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: Ds.s4),
                    Row(
                      children: [
                        _SummaryMetric(
                            value: '${snapshot.assignedPatients.length}',
                            caption: 'Assigned'),
                        _SummaryMetric(
                            value: snapshot.openEvents.isEmpty
                                ? 'None' : '${snapshot.openEvents.length}',
                            caption: 'Open events'),
                        _SummaryMetric(
                            value: '$assessed / ${patients.length}',
                            caption: 'Assessable'),
                      ],
                    ),
                    const SizedBox(height: Ds.s3),
                    Text(
                      'Current assessment and forecast are separate server-reported results.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.84),
                          fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
              if (state.status == AsyncDataStatus.offline ||
                  snapshot.isFromCache) ...[
                const SizedBox(height: Ds.s4),
                InlineNotice(
                  icon: Icons.cloud_off_rounded,
                  text: state.message ??
                      'Offline: this is a historical dashboard snapshot, not current clinical state.',
                ),
              ] else if (state.status == AsyncDataStatus.partial) ...[
                const SizedBox(height: Ds.s4),
                InlineNotice(
                  icon: Icons.info_outline_rounded,
                  text: state.message ??
                      'Some server dashboard data is temporarily unavailable.',
                ),
              ],
              const SizedBox(height: Ds.s6),
              SectionLabel('Needs attention',
                trailing: snapshot.openEvents.isEmpty
                    ? null : '${snapshot.openEvents.length} open'),
              if (snapshot.openEvents.isEmpty)
                Panel(
                  background: Ds.brandSoft,
                  borderColor: Ds.brandEdge,
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Ds.brand),
                      SizedBox(width: Ds.s3),
                      Expanded(child: Text('No open attention events from the server.',
                          style: TextStyle(color: Ds.inkMuted))),
                    ],
                  ),
                )
              else
                ...snapshot.openEvents.map((event) {
                  PatientSummary? matching;
                  for (final patient in snapshot.assignedPatients) {
                    if (patient.subjectId == event.subjectId) {
                      matching = patient;
                      break;
                    }
                  }
                  final label = matching == null
                      ? 'Assigned participant ${_shortId(event.subjectId)}'
                      : _patientLabel(matching, snapshot);
                  return _AttentionEventCard(event,
                      label: label,
                      onTap: () => _openEvent(context, event));
                }),
              const SizedBox(height: Ds.s6),
              SectionLabel('Assigned patients',
                  trailing: '${patients.length} patients'),
              if (patients.isEmpty)
                const Panel(child: Text(
                  'No assigned patients are available in the current server response.',
                  style: TextStyle(color: Ds.inkMuted),
                ))
              else
                ...patients.map((patient) => _PatientSummaryCard(
                      patient,
                      label: _patientLabel(patient, snapshot),
                      hasAttention: activeIds.contains(patient.subjectId),
                      onTap: () => _openPatient(context, patient, snapshot),
                    )),
              const SizedBox(height: Ds.s5),
              const DecisionSupportNotice(),
            ],
          ),
        );
      },
    );
  }
}

int _priority(PatientSummary patient) {
  if (patient.assessmentStatus == AssessmentStatus.unavailable ||
      patient.currentAssessment?.score == null) return 3;
  return switch (patient.currentAssessment!.tier) {
    RiskTier.high => 0,
    RiskTier.medium => 1,
    RiskTier.low => 2,
    RiskTier.unknown => 3,
  };
}

String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

class _SummaryMetric extends StatelessWidget {
  final String value;
  final String caption;

  const _SummaryMetric({required this.value, required this.caption});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(
          color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(caption, style: const TextStyle(
          color: Colors.white70, fontSize: 11)),
      ],
    ),
  );
}

class _NoDashboardData extends StatelessWidget {
  final AsyncDataStatus status;
  final String? message;
  final Future<void> Function({bool showLoading}) onRetry;

  const _NoDashboardData({
    required this.status,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final title = switch (status) {
      AsyncDataStatus.empty => 'No assigned dashboard items',
      AsyncDataStatus.unavailable => 'Dashboard unavailable',
      AsyncDataStatus.offline => 'Dashboard unavailable offline',
      _ => 'Dashboard could not be loaded',
    };
    return EmptyState(
      icon: status == AsyncDataStatus.offline
          ? Icons.cloud_off_rounded : Icons.dashboard_outlined,
      title: title,
      body: message ?? 'Try again when the Central Backend is available.',
      actionLabel: 'Retry',
      onAction: () => onRetry(showLoading: true),
    );
  }
}

class _AttentionEventCard extends StatelessWidget {
  final AttentionEvent event;
  final String label;
  final VoidCallback onTap;

  const _AttentionEventCard(this.event,
      {required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Ds.s3),
    child: Panel(
      onTap: onTap,
      borderColor: Ds.amber.withValues(alpha: .45),
      background: Ds.amberSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notification_important_outlined,
                size: 20, color: Ds.amber),
            const SizedBox(width: Ds.s2),
            const Expanded(child: Text('Review attention event',
                style: TextStyle(fontWeight: FontWeight.w700, color: Ds.ink))),
            const Icon(Icons.chevron_right_rounded, color: Ds.inkMuted),
          ]),
          const SizedBox(height: Ds.s2),
          Text(label, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: Ds.s1),
          Text(event.reason?.trim().isNotEmpty == true
              ? event.reason! : 'Review this server-generated event.',
              style: const TextStyle(fontSize: 12, color: Ds.inkMuted)),
          const SizedBox(height: Ds.s2),
          Text('${_eventStatusLabel(event.status)} · ${event.id}',
              style: AppTheme.data(size: 10.5, color: Ds.inkMuted)),
          if (event.forecastHorizon != null)
            Text('Forecast horizon: ${event.forecastHorizon} min',
                style: const TextStyle(fontSize: 11, color: Ds.inkMuted)),
        ],
      ),
    ),
  );
}

class _PatientSummaryCard extends StatelessWidget {
  final PatientSummary patient;
  final String label;
  final bool hasAttention;
  final VoidCallback onTap;

  const _PatientSummaryCard(this.patient, {
    required this.label,
    required this.hasAttention,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final current = patient.currentAssessment;
    final unavailable = patient.assessmentStatus == AssessmentStatus.unavailable ||
        current == null || current.score == null;
    final partial = patient.assessmentStatus == AssessmentStatus.partial;
    final tier = unavailable ? RiskTier.unknown : current.tier;
    final statusColor = switch (tier) {
      RiskTier.high => Ds.red,
      RiskTier.medium => Ds.amber,
      RiskTier.low => Ds.green,
      RiskTier.unknown => Ds.inkMuted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s3),
      child: Panel(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 5, height: 39,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(Ds.rPill))),
              const SizedBox(width: Ds.s3),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: Ds.ink)),
                  if (patient.lastUpdated != null)
                    Text('Updated ${DateFormat('d MMM, HH:mm').format(patient.lastUpdated!.toLocal())}',
                        style: const TextStyle(fontSize: 11, color: Ds.inkFaint)),
                ],
              )),
              const Icon(Icons.chevron_right_rounded, color: Ds.inkFaint),
            ]),
            const SizedBox(height: Ds.s3),
            if (unavailable)
              const Text('Assessment unavailable — insufficient current data',
                  style: TextStyle(color: Ds.inkMuted, fontWeight: FontWeight.w600))
            else
              Row(children: [
                Expanded(child: Text(
                    'Current assessment · ${_tierLabel(tier)}',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(current.score!.toStringAsFixed(2),
                    style: AppTheme.data(size: 17, weight: FontWeight.w700,
                        color: statusColor)),
              ]),
            if (partial) ...[
              const SizedBox(height: Ds.s1),
              const Text('Partial assessment · verify data quality',
                  style: TextStyle(fontSize: 11.5, color: Ds.amber)),
            ],
            const SizedBox(height: Ds.s2),
            if (patient.forecast == null)
              const Text('Near-term forecast unavailable',
                  style: TextStyle(fontSize: 12, color: Ds.inkMuted))
            else
              Text(
                '${_forecastLabel(patient.forecast!.scope)} · '
                '${_tierLabel(patient.forecast!.tier)}'
                '${patient.forecast!.score == null ? '' : ' · ${patient.forecast!.score!.toStringAsFixed(2)}'}',
                style: const TextStyle(fontSize: 12, color: Ds.inkMuted),
              ),
            if (hasAttention) ...[
              const SizedBox(height: Ds.s2),
              const Text('OPEN attention event · review required',
                style: TextStyle(fontSize: 11.5, color: Ds.amber,
                    fontWeight: FontWeight.w700)),
            ],
            if (patient.fusionResultId != null) ...[
              const SizedBox(height: Ds.s2),
              Text('Fusion result #${patient.fusionResultId}',
                style: AppTheme.data(size: 10, color: Ds.inkFaint)),
            ],
          ],
        ),
      ),
    );
  }
}

String _forecastLabel(ForecastScope scope) => switch (scope) {
  ForecastScope.physiological => 'Near-term physiological forecast',
  ForecastScope.multimodal => 'Near-term multimodal forecast',
  ForecastScope.unknown => 'Near-term forecast',
};

String _tierLabel(RiskTier tier) => switch (tier) {
  RiskTier.low => 'Low',
  RiskTier.medium => 'Medium',
  RiskTier.high => 'High',
  RiskTier.unknown => 'Unknown',
};

String _eventStatusLabel(AttentionEventStatus status) => switch (status) {
  AttentionEventStatus.open => 'OPEN',
  AttentionEventStatus.acknowledged => 'ACKNOWLEDGED',
  AttentionEventStatus.resolved => 'RESOLVED',
  AttentionEventStatus.unknown => 'UNKNOWN',
};
