import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/session.dart';
import '../../data/local/patient_label_store.dart';
import '../../domain/contracts/attention_event.dart';
import '../../domain/contracts/contract_enums.dart';
import '../../domain/contracts/patient_summary.dart';
import '../../state/async_data_state.dart';
import '../../state/dashboard_controller.dart';
import '../attention_events/attention_event_detail_screen.dart';
import '../patients/patient_overview_screen.dart';

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
  late final PatientLabelStore _labelsStore =
      widget.labelStore ?? const SecurePatientLabelStore();
  final Map<String, String> _labels = {};
  String? _scope;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleReload);
    PatientLabelStore.changes.addListener(_scheduleReload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void didUpdateWidget(covariant ServerDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleReload);
      widget.controller.addListener(_scheduleReload);
      _scheduleReload();
    }
  }

  void _scheduleReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final generation = ++_generation;
    final state = widget.controller.state;
    final snapshot = state.data;
    final clinician = Session.isActive ? Session.clinicianId : null;
    final allowed = clinician != null && clinician.isNotEmpty &&
        snapshot != null && !snapshot.isFromCache &&
        state.status != AsyncDataStatus.offline &&
        state.status != AsyncDataStatus.sessionExpired &&
        state.status != AsyncDataStatus.forbidden &&
        state.status != AsyncDataStatus.conflict;

    if (!allowed) {
      if (_labels.isNotEmpty || _scope != null) {
        setState(() { _labels.clear(); _scope = null; });
      }
      return;
    }
    try {
      final entries = await Future.wait(
        snapshot.assignedPatients.map((patient) async => MapEntry(
          patient.subjectId,
          await _labelsStore.read(
            clinicianId: clinician,
            subjectId: patient.subjectId,
          ),
        )),
      );
      if (!mounted || generation != _generation || !Session.isActive ||
          Session.clinicianId != clinician ||
          widget.controller.state.data?.isFromCache != false) return;
      setState(() {
        _scope = clinician;
        _labels.clear();
        for (final e in entries) {
          if (e.value?.isNotEmpty == true) _labels[e.key] = e.value!;
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() { _labels.clear(); _scope = null; });
      }
    }
  }

  String _label(String subjectId, String fallback) {
    if (!Session.isActive || Session.clinicianId != _scope ||
        widget.controller.state.data?.isFromCache != false) return fallback;
    return _labels[subjectId] ?? fallback;
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_scheduleReload);
    PatientLabelStore.changes.removeListener(_scheduleReload);
    super.dispose();
  }

  void _openPatient(BuildContext context, PatientSummary patient) {
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
          displayId: _label(patient.subjectId, patient.displayId ?? patient.subjectId),
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

        return RefreshIndicator(
          onRefresh: () => widget.controller.load(showLoading: false),
          child: ListView(
            padding: const EdgeInsets.all(Ds.s4),
            children: [
              Text('Dashboard', style: AppTheme.display(size: 26)),
              const SizedBox(height: Ds.s2),
              Text(
                'Server-backed clinician worklist · ${snapshot.assignedPatients.length} assigned',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Ds.inkMuted,
                    ),
              ),
              if (state.status == AsyncDataStatus.offline ||
                  snapshot.isFromCache) ...[
                const SizedBox(height: Ds.s4),
                InlineNotice(
                  icon: Icons.cloud_off_rounded,
                  text: state.message ??
                      'Offline. Showing the last server-provided dashboard snapshot.',
                ),
              ] else if (state.status == AsyncDataStatus.partial) ...[
                const SizedBox(height: Ds.s4),
                InlineNotice(
                  icon: Icons.info_outline_rounded,
                  text: state.message ??
                      'Some dashboard data is temporarily unavailable.',
                ),
              ],
              const SizedBox(height: Ds.s6),
              const SectionLabel('Needs attention'),
              if (snapshot.openEvents.isEmpty)
                const Panel(
                  child: Text(
                    'No open attention events from the server.',
                    style: TextStyle(color: Ds.inkMuted),
                  ),
                )
              else
                ...snapshot.openEvents.map(
                  (event) => _AttentionEventCard(
                    event,
                    patientLabel: _label(event.subjectId, 'Patient ${event.subjectId}'),
                    onTap: () => _openEvent(context, event),
                  ),
                ),
              const SizedBox(height: Ds.s6),
              const SectionLabel('Assigned patients'),
              if (snapshot.assignedPatients.isEmpty)
                const Panel(
                  child: Text(
                    'No assigned patients are available in the current server response.',
                    style: TextStyle(color: Ds.inkMuted),
                  ),
                )
              else
                ...snapshot.assignedPatients.map(
                  (patient) => _PatientSummaryCard(
                    patient,
                    displayLabel: _label(patient.subjectId, patient.displayId ?? patient.subjectId),
                    onTap: () => _openPatient(context, patient),
                  ),
                ),
              const SizedBox(height: Ds.s6),
              const DecisionSupportNotice(),
            ],
          ),
        );
      },
    );
  }
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
    final body = message ??
        (status == AsyncDataStatus.empty
            ? 'The server returned no open attention events or assigned patients.'
            : 'Try again when the backend is available.');

    return EmptyState(
      icon: status == AsyncDataStatus.offline
          ? Icons.cloud_off_rounded
          : Icons.dashboard_outlined,
      title: title,
      body: body,
      actionLabel: 'Retry',
      onAction: () => onRetry(showLoading: true),
    );
  }
}

class _AttentionEventCard extends StatelessWidget {
  final AttentionEvent event;
  final String patientLabel;
  final VoidCallback onTap;

  const _AttentionEventCard(this.event, {required this.onTap, required this.patientLabel});

  @override
  Widget build(BuildContext context) {
    final reason = event.reason?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s3),
      child: Panel(
        onTap: onTap,
        borderColor: Ds.amber.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.priority_high_rounded, size: 18, color: Ds.amber),
                const SizedBox(width: Ds.s2),
                Expanded(
                  child: Text(
                    event.id,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Ds.ink,
                    ),
                  ),
                ),
                Text(
                  _eventStatusLabel(event.status),
                  style: AppTheme.data(size: 11, color: Ds.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: Ds.s2),
            Text(
              patientLabel,
              style: const TextStyle(fontSize: 13, color: Ds.inkMuted),
            ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: Ds.s2),
              Text(reason, style: const TextStyle(fontSize: 13, color: Ds.ink)),
            ],
            if (event.forecastHorizon != null) ...[
              const SizedBox(height: Ds.s2),
              Text(
                'Near-term forecast horizon: ${event.forecastHorizon} min',
                style: const TextStyle(fontSize: 12, color: Ds.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatientSummaryCard extends StatelessWidget {
  final PatientSummary patient;
  final String displayLabel;
  final VoidCallback onTap;

  const _PatientSummaryCard(
    this.patient, {
    required this.onTap,
    required this.displayLabel,
  });

  @override
  Widget build(BuildContext context) {
    final unavailable = patient.assessmentStatus == AssessmentStatus.unavailable ||
        patient.currentAssessment == null ||
        patient.currentAssessment!.score == null;
    final partial = patient.assessmentStatus == AssessmentStatus.partial;

    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s3),
      child: Panel(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Ds.ink,
                    ),
                  ),
                ),
                if (patient.openEventCount != null && patient.openEventCount! > 0)
                  Text(
                    '${patient.openEventCount} open',
                    style: AppTheme.data(size: 11, color: Ds.amber),
                  ),
              ],
            ),
            if (patient.fusionResultId != null) ...[
              const SizedBox(height: Ds.s1),
              Text(
                'Fusion result #${patient.fusionResultId}',
                style: const TextStyle(fontSize: 11.5, color: Ds.inkFaint),
              ),
            ],
            const SizedBox(height: Ds.s3),
            if (unavailable)
              const Text(
                'Assessment unavailable',
                style: TextStyle(fontWeight: FontWeight.w600, color: Ds.inkMuted),
              )
            else ...[
              Text(
                'Current assessment · ${_tierLabel(patient.currentAssessment!.tier)}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Ds.ink),
              ),
              if (partial) ...[
                const SizedBox(height: Ds.s1),
                const Text(
                  'Partial assessment',
                  style: TextStyle(fontSize: 12, color: Ds.inkMuted),
                ),
              ],
            ],
            if (patient.forecast != null) ...[
              const SizedBox(height: Ds.s3),
              Text(
                '${_forecastLabel(patient.forecast!.scope)} · ${_tierLabel(patient.forecast!.tier)}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Ds.ink),
              ),
              if (patient.forecast!.horizonMinutes != null) ...[
                const SizedBox(height: Ds.s1),
                Text(
                  'Horizon ${patient.forecast!.horizonMinutes} min',
                  style: const TextStyle(fontSize: 12, color: Ds.inkMuted),
                ),
              ],
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
