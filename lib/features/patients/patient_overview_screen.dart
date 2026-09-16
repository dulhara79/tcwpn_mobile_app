import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/session.dart';
import '../../data/repositories/central_backend_repositories.dart';
import '../../domain/contracts/assessment_summary.dart';
import '../../domain/contracts/contract_enums.dart';
import '../../state/async_data_state.dart';
import '../../state/patient_overview_controller.dart';
import 'clinical_notes_screen.dart';
import 'data_quality_screen.dart';
import 'signals_contributions_screen.dart';
import 'timeline_screen.dart';

typedef OpenClinicalNotes = void Function(String subjectId, String localRecordId);

class PatientOverviewScreen extends StatefulWidget {
  final String? displayId;
  final String? localRecordId;
  final PatientOverviewController? controller;
  final String? subjectId;
  final ValueChanged<AssessmentSummary>? onOpenSignalsContributions;
  final ValueChanged<AssessmentSummary>? onOpenDataQuality;
  final ValueChanged<String>? onOpenTimeline;
  final OpenClinicalNotes? onOpenClinicalNotes;

  const PatientOverviewScreen({
    super.key,
    required this.controller,
    this.displayId,
    this.localRecordId,
    this.onOpenSignalsContributions,
    this.onOpenDataQuality,
    this.onOpenTimeline,
    this.onOpenClinicalNotes,
  }) : subjectId = null;

  const PatientOverviewScreen.production({
    super.key,
    required this.subjectId,
    this.displayId,
    this.localRecordId,
    this.onOpenSignalsContributions,
    this.onOpenDataQuality,
    this.onOpenTimeline,
    this.onOpenClinicalNotes,
  }) : controller = null;

  @override
  State<PatientOverviewScreen> createState() => _PatientOverviewScreenState();
}

class _PatientOverviewScreenState extends State<PatientOverviewScreen> {
  late final PatientOverviewController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        PatientOverviewController(
          subjectId: widget.subjectId!,
          repository: CentralBackendAssessmentRepository(),
          authRepository: CentralBackendAuthRepository(),
        );
    if (_ownsController) _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.displayId ?? _controller.subjectId,
                  style: AppTheme.display(size: 16.5)),
              Text(_controller.subjectId,
                  style: AppTheme.data(size: 10.5, color: Ds.inkFaint)),
            ],
          ),
        ),
        body: _body(_controller.state),
      ),
    );
  }

  Widget _body(AsyncDataState<AssessmentSummary> state) {
    if (state.status == AsyncDataStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final assessment = state.data;
    if (assessment == null) {
      final title = switch (state.status) {
        AsyncDataStatus.sessionExpired => 'Session expired',
        AsyncDataStatus.forbidden => 'Patient access unavailable',
        AsyncDataStatus.conflict => 'Assessment changed on the server',
        AsyncDataStatus.offline => 'Assessment unavailable offline',
        _ => 'Assessment unavailable',
      };
      return EmptyState(
        icon: state.status == AsyncDataStatus.offline
            ? Icons.cloud_off_rounded
            : Icons.monitor_heart_outlined,
        title: title,
        body: state.message ??
            'No authoritative current assessment is available for this patient.',
        actionLabel: state.status == AsyncDataStatus.sessionExpired ? null : 'Retry',
        onAction: state.status == AsyncDataStatus.sessionExpired
            ? null
            : () => _controller.load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _controller.load(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s4, Ds.s4, Ds.s10),
        children: [
          _ForecastSection(forecast: assessment.forecast),
          const SizedBox(height: Ds.s6),
          _CurrentAssessmentSection(assessment: assessment),
          const SizedBox(height: Ds.s6),
          _SignalsSection(
            modalities: assessment.modalities,
            onOpenDetails: () => _openSignalsContributions(assessment),
          ),
          const SizedBox(height: Ds.s6),
          _DataQualitySummary(
            assessment: assessment,
            onOpenDetails: () => _openDataQuality(assessment),
          ),
          const SizedBox(height: Ds.s6),
          const SectionLabel('Temporal context & notes'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Timeline is historical backend context. Clinical-note history shown in ClinAnx is device-local until a server read contract is verified.',
                  style: TextStyle(fontSize: 12, color: Ds.inkMuted, height: 1.4),
                ),
                TextButton.icon(
                  onPressed: _openTimeline,
                  icon: const Icon(Icons.timeline_rounded, size: 17),
                  label: const Text('View timeline'),
                ),
                TextButton.icon(
                  onPressed: _openClinicalNotes,
                  icon: const Icon(Icons.note_alt_outlined, size: 17),
                  label: const Text('View clinical notes'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Ds.s6),
          const DecisionSupportNotice(),
        ],
      ),
    );
  }

  void _openSignalsContributions(AssessmentSummary assessment) {
    final callback = widget.onOpenSignalsContributions;
    if (callback != null) {
      callback(assessment);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignalsContributionsScreen(
          assessment: assessment,
          displayId: widget.displayId,
        ),
      ),
    );
  }

  void _openDataQuality(AssessmentSummary assessment) {
    final callback = widget.onOpenDataQuality;
    if (callback != null) {
      callback(assessment);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DataQualityScreen(
          assessment: assessment,
          displayId: widget.displayId,
        ),
      ),
    );
  }

  void _openTimeline() {
    final callback = widget.onOpenTimeline;
    if (callback != null) {
      callback(_controller.subjectId);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimelineScreen.production(
          subjectId: _controller.subjectId,
          displayId: widget.displayId,
        ),
      ),
    );
  }

  void _openClinicalNotes() {
    final localRecordId =
        widget.localRecordId ?? 'canonical-local::${_controller.subjectId}';
    final callback = widget.onOpenClinicalNotes;
    if (callback != null) {
      callback(_controller.subjectId, localRecordId);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicalNotesScreen.production(
          subjectId: _controller.subjectId,
          localRecordId: localRecordId,
          clinicianId: Session.clinicianId ?? '',
          refreshCanonicalAssessment: () =>
              _controller.load(showLoading: false),
          displayId: widget.displayId,
        ),
      ),
    );
  }
}

class _ForecastSection extends StatelessWidget {
  final ForecastResult? forecast;
  const _ForecastSection({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final value = forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Acute escalation forecast'),
        Panel(
          child: value == null
              ? const Text('Forecast unavailable',
                  style: TextStyle(color: Ds.inkMuted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.scope == ForecastScope.physiological
                          ? 'Physiological forecast'
                          : 'Forecast scope not reported',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: Ds.s2),
                    Text('${_tier(value.tier)} · ${_score(value.score)}',
                        style: AppTheme.display(size: 24)),
                    if (value.horizonMinutes != null)
                      Text('${value.horizonMinutes}-minute horizon'),
                    if (value.escalationPredicted != null)
                      Text(value.escalationPredicted!
                          ? 'Potential escalation predicted within the forecast horizon.'
                          : 'No escalation flag in the current forecast response.'),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CurrentAssessmentSection extends StatelessWidget {
  final AssessmentSummary assessment;
  const _CurrentAssessmentSection({required this.assessment});

  @override
  Widget build(BuildContext context) {
    final current = assessment.currentAssessment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Current multimodal assessment'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (assessment.assessmentStatus == AssessmentStatus.unavailable ||
                  current.score == null)
                const Text('Assessment unavailable — insufficient current data.')
              else
                Text('${_tier(current.tier)} · ${_score(current.score)}',
                    style: AppTheme.display(size: 24)),
              Text(_assessmentStatus(assessment.assessmentStatus)),
              if (assessment.confidence != null)
                Text('Confidence ${assessment.confidence!.toStringAsFixed(2)}'),
              if (assessment.uncertainty != null)
                Text('Uncertainty ${assessment.uncertainty!.toStringAsFixed(2)}'),
              if (assessment.fusionResultId != null)
                Text('Fusion result #${assessment.fusionResultId}'),
              if (assessment.modelVersion != null)
                Text('Model ${assessment.modelVersion}'),
              if (assessment.computedAt != null)
                Text('Last updated ${DateFormat('d MMM, HH:mm').format(assessment.computedAt!)}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignalsSection extends StatelessWidget {
  static const ids = [
    'c1_physiological',
    'c2_behavioral',
    'c3_clinical_nlp',
    'c4_demographic',
  ];
  final List<ModalityStatus> modalities;
  final VoidCallback onOpenDetails;
  const _SignalsSection({required this.modalities, required this.onOpenDetails});

  @override
  Widget build(BuildContext context) {
    final byId = {for (final m in modalities) m.componentId: m};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Signals'),
        for (final id in ids)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s2),
            child: _SignalCard(id: id, modality: byId[id]),
          ),
        TextButton.icon(
          onPressed: onOpenDetails,
          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
          label: const Text('View signals & contributions'),
        ),
      ],
    );
  }
}

class _SignalCard extends StatelessWidget {
  final String id;
  final ModalityStatus? modality;
  const _SignalCard({required this.id, required this.modality});

  @override
  Widget build(BuildContext context) => Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_signalLabel(id),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(_signalState(id, modality)),
                ],
              ),
            ),
            Text(modality?.score == null
                ? '—'
                : modality!.score!.toStringAsFixed(2)),
          ],
        ),
      );
}

class _DataQualitySummary extends StatelessWidget {
  final AssessmentSummary assessment;
  final VoidCallback onOpenDetails;
  const _DataQualitySummary({required this.assessment, required this.onOpenDetails});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Data quality'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assessment data status: ${_assessmentStatus(assessment.assessmentStatus)}'),
                TextButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View data quality'),
                ),
              ],
            ),
          ),
        ],
      );
}

String _signalLabel(String id) => switch (id) {
      'c1_physiological' => 'Physiological',
      'c2_behavioral' => 'Behavioural',
      'c3_clinical_nlp' => 'Clinical NLP / TC-WPN',
      'c4_demographic' => 'Contextual',
      _ => id,
    };

String _signalState(String id, ModalityStatus? modality) {
  if (id == 'c2_behavioral' &&
      (modality == null || !modality.includedInFusion)) {
    return 'Experimental — not included in fusion';
  }
  if (modality == null) return 'Unavailable';
  return switch (modality.state) {
    ModalityState.ok =>
      modality.includedInFusion ? 'Included in fusion' : 'Available',
    ModalityState.stale => 'Stale',
    ModalityState.unavailable => 'Unavailable',
    ModalityState.buffering => 'Buffering',
    ModalityState.insufficientData => 'Insufficient data',
    ModalityState.poorSignal => 'Poor signal',
    ModalityState.noSupportSet => 'No support set',
    ModalityState.notValidated => 'Not validated',
    ModalityState.error => 'Error',
    ModalityState.unknown => 'Unknown',
  };
}

String _assessmentStatus(AssessmentStatus status) => switch (status) {
      AssessmentStatus.complete => 'Complete assessment',
      AssessmentStatus.partial => 'Partial assessment',
      AssessmentStatus.unavailable => 'Assessment unavailable',
      AssessmentStatus.provisional => 'Provisional assessment',
      AssessmentStatus.unknown => 'Assessment status unknown',
    };

String _tier(RiskTier tier) => switch (tier) {
      RiskTier.low => 'Low',
      RiskTier.medium => 'Medium',
      RiskTier.high => 'High',
      RiskTier.unknown => 'Unknown',
    };

String _score(double? value) => value == null ? '—' : value.toStringAsFixed(2);
