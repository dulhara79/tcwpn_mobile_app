import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/p5b_repositories.dart';
import '../../domain/models.dart';
import '../../state/clinical_notes_controller.dart';

class ClinicalNotesScreen extends StatefulWidget {
  final ClinicalNotesController? controller;
  final String? subjectId;
  final String? localRecordId;
  final String? clinicianId;
  final Future<void> Function()? refreshCanonicalAssessment;
  final String? displayId;

  const ClinicalNotesScreen({
    super.key,
    required this.controller,
    this.displayId,
  })  : subjectId = null,
        localRecordId = null,
        clinicianId = null,
        refreshCanonicalAssessment = null;

  const ClinicalNotesScreen.production({
    super.key,
    required this.subjectId,
    required this.localRecordId,
    required this.clinicianId,
    required this.refreshCanonicalAssessment,
    this.displayId,
  }) : controller = null;

  @override
  State<ClinicalNotesScreen> createState() => _ClinicalNotesScreenState();
}

class _ClinicalNotesScreenState extends State<ClinicalNotesScreen> {
  late final ClinicalNotesController _controller;
  late final bool _ownsController;
  final _text = TextEditingController();
  final _noteType = TextEditingController(text: 'Psychiatry note');

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        ClinicalNotesController(
          subjectId: widget.subjectId!,
          localRecordId: widget.localRecordId!,
          clinicianId: widget.clinicianId!,
          repository: LocalCentralBackendClinicalNotesRepository(),
          refreshCanonicalAssessment: widget.refreshCanonicalAssessment!,
        );
    _controller.addListener(_changed);
    if (_ownsController) _controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (_ownsController) _controller.dispose();
    _text.dispose();
    _noteType.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    await _controller.saveDraft(
      text: value,
      noteType: _noteType.text,
    );
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayId == null
            ? 'Clinical notes'
            : '${widget.displayId} · Clinical notes'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This history is device-local ClinAnx data. It is not server-authoritative note history; no server note-history read contract is currently verified.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('clinical-note-text'),
            controller: _text,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Clinical note',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteType,
            decoration: const InputDecoration(
              labelText: 'Note type',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saveDraft,
            child: const Text('Save draft'),
          ),
          if (_controller.message != null) ...[
            const SizedBox(height: 8),
            Text(_controller.message!),
          ],
          const SizedBox(height: 20),
          if (_controller.loading)
            const Center(child: CircularProgressIndicator())
          else if (_controller.notes.isEmpty)
            const Text('No device-local clinical notes yet.')
          else
            ..._controller.notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NoteCard(
                  note: note,
                  submitting: _controller.submittingNoteId == note.id,
                  onSubmit: () => _controller.submit(note.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final ClinicalNote note;
  final bool submitting;
  final VoidCallback onSubmit;

  const _NoteCard({
    required this.note,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final status = switch (note.status) {
      ClinicalNoteStatus.draft => 'Draft',
      ClinicalNoteStatus.analysed => 'Analysed',
      ClinicalNoteStatus.analysisFailed => 'Analysis failed',
    };
    final score = note.result?.calibratedProbability ?? note.result?.riskScore;
    final author = note.clinicianId.trim().isEmpty
        ? 'Author not reported'
        : 'Author: ${note.clinicianId}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.noteType,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(status),
              ],
            ),
            const SizedBox(height: 4),
            Text(DateFormat('d MMM yyyy, HH:mm').format(note.recordedAt)),
            Text(author),
            const SizedBox(height: 8),
            Text(note.text),
            if (note.status != ClinicalNoteStatus.draft) ...[
              const SizedBox(height: 10),
              const Text(
                'Clinical NLP / TC-WPN signal',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(score == null ? 'Not reported' : score.toStringAsFixed(2)),
            ],
            if (note.lastAnalysisError != null) ...[
              const SizedBox(height: 6),
              Text(note.lastAnalysisError!),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: submitting ? null : onSubmit,
              child: Text(
                submitting
                    ? 'Submitting…'
                    : note.status == ClinicalNoteStatus.analysisFailed
                        ? 'Retry analysis'
                        : note.status == ClinicalNoteStatus.analysed
                            ? 'Re-analyse'
                            : 'Analyse note',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
