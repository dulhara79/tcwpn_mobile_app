import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/session.dart';
import '../../data/local/patient_label_store.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/patient_unassignment_repository.dart';
import '../../domain/repositories/patient_unassignment_repository.dart';
import '../../domain/contracts/contract_enums.dart';
import '../../domain/contracts/dashboard_snapshot.dart';
import '../../domain/contracts/patient_summary.dart';
import '../../domain/repositories/assignment_invite_repository.dart';
import '../../state/async_data_state.dart';
import '../../state/dashboard_controller.dart';
import 'patient_overview_screen.dart';
import 'link_patient_screen.dart';

class PatientsScreen extends StatefulWidget {
  final DashboardController controller;
  final ValueChanged<PatientSummary>? onOpenPatient;
  final AssignmentInviteRepository? inviteRepository;
  final PatientLabelStore? labelStore;
  final PatientUnassignmentRepository? unassignmentRepository;

  const PatientsScreen({
    super.key,
    required this.controller,
    this.onOpenPatient,
    this.inviteRepository,
    this.labelStore,
    this.unassignmentRepository,
  });

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _search = TextEditingController();
  String _query = '';
  RiskTier? _currentTier;
  RiskTier? _forecastTier;
  AssessmentStatus? _assessmentStatus;
  bool _needsAttentionOnly = false;
  late final PatientLabelStore _labelStore =
      widget.labelStore ?? const SecurePatientLabelStore();
  final Map<String, String> _labels = {};
  late final PatientUnassignmentRepository _unassignmentRepository =
      widget.unassignmentRepository ?? CentralBackendPatientUnassignmentRepository();
  String? _removingSubjectId;
  String? _loadedForClinician;
  String? _rosterKey;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onDashboardChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLabels());
  }

  void _onDashboardChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLabels());
  }

  void _refreshLabels() {
    if (!mounted) return;
    final snapshot = widget.controller.state.data;
    final clinician = Session.isActive ? Session.clinicianId : null;
    if (snapshot == null || snapshot.isFromCache ||
        clinician == null || clinician.isEmpty ||
        widget.controller.state.status == AsyncDataStatus.forbidden ||
        widget.controller.state.status == AsyncDataStatus.sessionExpired) {
      if (_labels.isNotEmpty || _loadedForClinician != null) {
        setState(() {
          _labels.clear();
          _loadedForClinician = null;
          _rosterKey = null;
        });
      }
      return;
    }
    final ids = snapshot.assignedPatients.map((p) => p.subjectId).toList()..sort();
    final rosterKey = '$clinician|${ids.join('|')}';
    if (_rosterKey == rosterKey) return;
    _rosterKey = rosterKey;
    _loadedForClinician = clinician;
    Future.wait(snapshot.assignedPatients.map((p) async =>
      MapEntry(p.subjectId, await _labelStore.read(
        clinicianId: clinician, subjectId: p.subjectId,
      )),
    )).then((entries) {
      if (!mounted || !Session.isActive ||
          Session.clinicianId != clinician || _loadedForClinician != clinician || _rosterKey != rosterKey) {
        return;
      }
      setState(() {
        _labels.clear();
        for (final e in entries) {
          if (e.value?.isNotEmpty == true) _labels[e.key] = e.value!;
        }
      });
    }).catchError((Object _) {
      if (mounted && _loadedForClinician == clinician) {
        setState(() {
          _labels.clear();
          _loadedForClinician = null;
          _rosterKey = null;
        });
      }
    });
  }

  String _label(PatientSummary p) =>
      (Session.isActive && Session.clinicianId == _loadedForClinician &&
       widget.controller.state.data?.isFromCache == false
          ? _labels[p.subjectId] : null) ?? p.displayId ?? p.subjectId;

  Future<void> _editLabel(PatientSummary patient) async {
    final clinician = Session.isActive ? Session.clinicianId : null;
    final snapshot = widget.controller.state.data;
    if (clinician == null || snapshot == null || snapshot.isFromCache ||
        !snapshot.assignedPatients.any((p) => p.subjectId == patient.subjectId)) {
      return;
    }
    final field = TextEditingController(text: _labels[patient.subjectId] ?? '');
    final form = GlobalKey<FormState>();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit patient label'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: field,
            maxLength: 80,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Study-safe name or nickname',
              helperText: 'Only on this clinician device',
            ),
            validator: PatientLabelStore.validateLabel,
          ),
        ),
        actions: [
          if (_labels.containsKey(patient.subjectId))
            TextButton(
              onPressed: () => Navigator.pop(ctx, '\u0001REMOVE'),
              child: const Text('Remove label'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() == true) {
                Navigator.pop(ctx, PatientLabelStore.normalizeLabel(field.text));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    field.dispose();
    if (!mounted || action == null || !Session.isActive ||
        Session.clinicianId != clinician ||
        !(widget.controller.state.data?.assignedPatients.any(
           (p) => p.subjectId == patient.subjectId) ?? false)) {
      return;
    }
    try {
      if (action == '\u0001REMOVE') {
        await _labelStore.delete(clinicianId: clinician, subjectId: patient.subjectId);
      } else {
        await _labelStore.write(
          clinicianId: clinician, subjectId: patient.subjectId, label: action);
      }
      if (!mounted || !Session.isActive || Session.clinicianId != clinician) return;
      setState(() {
        if (action == '\u0001REMOVE') {
          _labels.remove(patient.subjectId);
        } else {
          _labels[patient.subjectId] = action;
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save this label securely.'),
        ));
      }
    }
  }

  Future<void> _removePatient(PatientSummary patient) async {
    final clinician = Session.isActive ? Session.clinicianId : null;
    final snapshot = widget.controller.state.data;
    if (_removingSubjectId != null || clinician == null ||
        snapshot == null || snapshot.isFromCache ||
        !snapshot.assignedPatients.any((p) => p.subjectId == patient.subjectId)) {
      return;
    }
    final name = _label(patient);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove from my patients?'),
        content: Text(
          'Remove "$name" from your assigned patient list? '
          'This revokes your access to this patient on the Central Backend. '
          'It does NOT delete the patient, medical records, or assessment history. '
          'To link again, the patient must issue a new invitation. '
          'Unresolved attention events must be handled first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove patient'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !Session.isActive ||
        Session.clinicianId != clinician ||
        widget.controller.state.data?.isFromCache != false ||
        !(widget.controller.state.data?.assignedPatients.any(
          (p) => p.subjectId == patient.subjectId) ?? false)) return;
    setState(() => _removingSubjectId = patient.subjectId);
    try {
      await _unassignmentRepository.unassign(patient.subjectId);
      // This is not a local-only deletion: refresh the server-owned roster.
      if (!mounted || !Session.isActive ||
          Session.clinicianId != clinician) return;
      try {
        await _labelStore.delete(
          clinicianId: clinician, subjectId: patient.subjectId);
        _labels.remove(patient.subjectId);
      } catch (_) {
        // Do not misreport backend success as failure due to local cleanup.
      }
      await widget.controller.load(showLoading: false);
      if (!mounted) return;
      final stillAssigned = widget.controller.state.data?.assignedPatients.any(
        (p) => p.subjectId == patient.subjectId) ?? false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(stillAssigned
          ? 'Assignment ended on the server. Refresh the patient list to confirm.'
          : 'Patient removed from your assignments. Records were retained.'),
      ));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (error.statusCode) {
          404 => 'No active assignment was found. Refresh the patient list.',
          409 => 'Cannot remove this patient while attention events need review.',
          401 => 'Session expired. Sign in again.',
          403 => 'You do not have permission to remove this assignment.',
          _ => error.message,
        }),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not remove this assignment. Please try again.'),
      ));
    } finally {
      if (mounted) setState(() => _removingSubjectId = null);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDashboardChanged);
    _search.dispose();
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
          displayId: _label(patient),
        ),
      ),
    );
  }

  Future<void> _linkPatient() async {
    final subjectId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LinkPatientScreen(repository: widget.inviteRepository),
      ),
    );
    if (!mounted || subjectId == null) return;
    await widget.controller.load(showLoading: false);
    if (!mounted) return;
    final snapshot = widget.controller.state.data;
    final refreshed =
        snapshot != null &&
        !snapshot.isFromCache &&
        snapshot.assignedPatients.any(
          (patient) => patient.subjectId == subjectId,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refreshed ? 'Patient linked. Assigned roster refreshed.' : 'Invitation accepted. The assigned roster could not be refreshed yet.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Patients'),
            actions: [
              IconButton(
                tooltip: 'Link patient with invite',
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: _linkPatient,
              ),
            ],
          ),
          body: _bodyForState(context, state),
        );
      },
    );
  }

  Widget _bodyForState(
    BuildContext context,
    AsyncDataState<DashboardSnapshot> state,
  ) {
    if (state.status == AsyncDataStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final snapshot = widget.controller.state.data;
    if (snapshot == null) {
      final title = switch (state.status) {
        AsyncDataStatus.sessionExpired => 'Session expired',
        AsyncDataStatus.forbidden => 'Patient roster access unavailable',
        AsyncDataStatus.offline => 'Patient roster unavailable offline',
        _ => 'Assigned patients unavailable',
      };
      return EmptyState(
        icon: state.status == AsyncDataStatus.offline
            ? Icons.cloud_off_rounded
            : Icons.folder_shared_outlined,
        title: title,
        body: state.message ?? 'The assignment-scoped patient roster could not be loaded from the Central Backend.',
        actionLabel: state.status == AsyncDataStatus.sessionExpired
            ? null
            : 'Retry',
        onAction: state.status == AsyncDataStatus.sessionExpired
            ? null
            : () => widget.controller.load(),
      );
    }

    final attentionSubjects = snapshot.openEvents
        .map((event) => event.subjectId)
        .toSet();
    final patients = snapshot.assignedPatients
        .where((patient) {
          final query = _query.trim().toLowerCase();
          final matchesQuery =
              query.isEmpty ||
              patient.subjectId.toLowerCase().contains(query) ||
              (patient.displayId ?? '').toLowerCase().contains(query) ||
              _label(patient).toLowerCase().contains(query);
          final matchesAttention =
              !_needsAttentionOnly ||
              attentionSubjects.contains(patient.subjectId);
          final matchesCurrent =
              _currentTier == null ||
              patient.currentAssessment?.tier == _currentTier;
          final matchesForecast =
              _forecastTier == null || patient.forecast?.tier == _forecastTier;
          final matchesStatus =
              _assessmentStatus == null ||
              patient.assessmentStatus == _assessmentStatus;
          return matchesQuery &&
              matchesAttention &&
              matchesCurrent &&
              matchesForecast &&
              matchesStatus;
        })
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () => widget.controller.load(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s4, Ds.s4, Ds.s10),
        children: [
          if (state.status == AsyncDataStatus.offline ||
              snapshot.isFromCache) ...[
            InlineNotice(
              icon: Icons.cloud_off_rounded,
              text: state.message ?? 'Offline. Showing the last server-provided assigned-patient snapshot.',
            ),
            const SizedBox(height: Ds.s4),
          ] else if (state.status == AsyncDataStatus.partial) ...[
            InlineNotice(
              icon: Icons.info_outline_rounded,
              text: state.message ?? 'Some assigned-patient assessment data is temporarily unavailable.',
            ),
            const SizedBox(height: Ds.s4),
          ],
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search assigned patient',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
            ),
          ),
          const SizedBox(height: Ds.s3),
          Wrap(
            spacing: Ds.s2,
            runSpacing: Ds.s2,
            children: [
              FilterChip(
                label: const Text('Needs attention'),
                selected: _needsAttentionOnly,
                onSelected: (selected) =>
                    setState(() => _needsAttentionOnly = selected),
              ),
              _enumMenu<RiskTier>(
                label: 'Current',
                value: _currentTier,
                values: const [RiskTier.low, RiskTier.medium, RiskTier.high],
                text: _tierLabel,
                onChanged: (value) => setState(() => _currentTier = value),
              ),
              _enumMenu<RiskTier>(
                label: 'Forecast',
                value: _forecastTier,
                values: const [RiskTier.low, RiskTier.medium, RiskTier.high],
                text: _tierLabel,
                onChanged: (value) => setState(() => _forecastTier = value),
              ),
              _enumMenu<AssessmentStatus>(
                label: 'Availability',
                value: _assessmentStatus,
                values: const [
                  AssessmentStatus.complete,
                  AssessmentStatus.partial,
                  AssessmentStatus.unavailable,
                ],
                text: _assessmentLabel,
                onChanged: (value) => setState(() => _assessmentStatus = value),
              ),
            ],
          ),
          const SizedBox(height: Ds.s5),
          Row(
            children: [
              const Expanded(child: SectionLabel('Assigned patients')),
              Text(
                '${patients.length} of ${snapshot.assignedPatients.length}',
                style: AppTheme.data(size: 11.5, color: Ds.inkFaint),
              ),
            ],
          ),
          if (patients.isEmpty)
            const Panel(
              child: Text(
                'No assigned patients match the current filters.',
                style: TextStyle(color: Ds.inkMuted),
              ),
            )
          else
            for (final patient in patients)
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.s3),
                child: _AssignedPatientCard(
                  patient: patient,
                  label: _label(patient),
                  onEdit: Session.isActive && !snapshot.isFromCache &&
                          Session.clinicianId == _loadedForClinician
                      ? () => _editLabel(patient)
                      : null,
                  onRemove: Session.isActive && !snapshot.isFromCache &&
                          _removingSubjectId == null
                      ? () => _removePatient(patient)
                      : null,
                  removing: _removingSubjectId == patient.subjectId,
                  hasOpenAttention: attentionSubjects.contains(
                    patient.subjectId,
                  ),
                  onTap: () => _openPatient(context, patient),
                ),
              ),
          const SizedBox(height: Ds.s4),
          const DecisionSupportNotice(),
        ],
      ),
    );
  }

  Widget _enumMenu<T>({
    required String label,
    required T? value,
    required List<T> values,
    required String Function(T value) text,
    required ValueChanged<T?> onChanged,
  }) {
    return PopupMenuButton<T?>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        PopupMenuItem<T?>(value: null, child: Text('All $label')),
        ...values.map(
          (item) => PopupMenuItem<T?>(value: item, child: Text(text(item))),
        ),
      ],
      child: Chip(
        avatar: const Icon(Icons.filter_list_rounded, size: 16),
        label: Text(value == null ? label : '$label: ${text(value)}'),
      ),
    );
  }
}

class _AssignedPatientCard extends StatelessWidget {
  final PatientSummary patient;
  final String label;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool removing;
  final bool hasOpenAttention;
  final VoidCallback onTap;

  const _AssignedPatientCard({
    required this.patient,
    required this.label,
    required this.onEdit,
    required this.onRemove,
    required this.removing,
    required this.hasOpenAttention,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final current = patient.currentAssessment;
    final unavailable =
        patient.assessmentStatus == AssessmentStatus.unavailable ||
        current == null ||
        current.score == null;

    return Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ds.ink,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit patient label',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
              if (removing)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onRemove != null)
                IconButton(
                  tooltip: 'Remove patient from my list',
                  onPressed: onRemove,
                  icon: const Icon(Icons.person_remove_outlined,
                    size: 19, color: Ds.red),
                ),
              if (hasOpenAttention)
                const Text(
                  'OPEN attention event',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Ds.amber,
                  ),
                ),
            ],
          ),
          if (patient.displayId != null) ...[
            const SizedBox(height: Ds.s1),
            Text(
              patient.subjectId,
              style: AppTheme.data(size: 10.5, color: Ds.inkFaint),
            ),
          ],
          const SizedBox(height: Ds.s3),
          if (unavailable)
            const Text(
              'Current assessment: unavailable',
              style: TextStyle(fontWeight: FontWeight.w600, color: Ds.inkMuted),
            )
          else
            Text(
              'Current multimodal assessment: ${_tierLabel(current.tier)} · ${_scoreLabel(current.score)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: Ds.s1),
          Text(
            _assessmentLabel(patient.assessmentStatus),
            style: const TextStyle(fontSize: 12, color: Ds.inkMuted),
          ),
          const SizedBox(height: Ds.s3),
          if (patient.forecast == null)
            const Text(
              'Near-term forecast: unavailable',
              style: TextStyle(fontSize: 12.5, color: Ds.inkMuted),
            )
          else ...[
            Text(
              '${_forecastLabel(patient.forecast!.scope)}: ${_tierLabel(patient.forecast!.tier)} · ${_scoreLabel(patient.forecast!.score)}',
              style: const TextStyle(fontSize: 12.5, color: Ds.ink),
            ),
            if (patient.forecast!.horizonMinutes != null)
              Text(
                'Forecast horizon ${patient.forecast!.horizonMinutes} min',
                style: const TextStyle(fontSize: 11.5, color: Ds.inkMuted),
              ),
          ],
          if (patient.fusionResultId != null ||
              patient.lastUpdated != null) ...[
            const SizedBox(height: Ds.s3),
            Wrap(
              spacing: Ds.s4,
              runSpacing: Ds.s1,
              children: [
                if (patient.fusionResultId != null)
                  Text(
                    'Fusion result #${patient.fusionResultId}',
                    style: const TextStyle(fontSize: 11, color: Ds.inkFaint),
                  ),
                if (patient.lastUpdated != null)
                  Text(
                    'Updated ${DateFormat('d MMM y, HH:mm').format(patient.lastUpdated!.toLocal())}',
                    style: const TextStyle(fontSize: 11, color: Ds.inkFaint),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _tierLabel(RiskTier tier) => switch (tier) {
  RiskTier.low => 'Low',
  RiskTier.medium => 'Medium',
  RiskTier.high => 'High',
  RiskTier.unknown => 'Unknown',
};

String _assessmentLabel(AssessmentStatus status) => switch (status) {
  AssessmentStatus.complete => 'Complete assessment',
  AssessmentStatus.partial => 'Partial assessment',
  AssessmentStatus.unavailable =>
    'Assessment unavailable — insufficient current data',
  AssessmentStatus.unknown => 'Assessment status unknown',
};

String _forecastLabel(ForecastScope scope) => switch (scope) {
  ForecastScope.physiological => 'Near-term physiological forecast',
  ForecastScope.multimodal => 'Multimodal forecast',
  ForecastScope.unknown => 'Forecast scope unavailable',
};

String _scoreLabel(double? score) =>
    score == null ? '—' : score.toStringAsFixed(2);
