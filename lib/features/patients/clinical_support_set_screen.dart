import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/stores.dart';
import '../../domain/models.dart';

/// A transparent clinician-edited support set. These examples are research
/// evidence supplied to TC-WPN; they are never generated secretly or inserted
/// into the authoritative fusion result by the app.
class ClinicalSupportSetScreen extends StatefulWidget {
  final String localRecordId;
  final String clinicianId;

  const ClinicalSupportSetScreen({
    super.key,
    required this.localRecordId,
    required this.clinicianId,
  });

  @override
  State<ClinicalSupportSetScreen> createState() => _ClinicalSupportSetScreenState();
}

class _ClinicalSupportSetScreenState extends State<ClinicalSupportSetScreen> {
  final _text = TextEditingController();
  String _scope = 'patient';
  String _label = 'control';
  DateTime _date = DateTime.now();
  List<SupportNote> _site = const [];
  List<SupportNote> _patient = const [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final site = await RecordStore.loadSiteSupport();
      final patient = await RecordStore.loadSupport(widget.localRecordId);
      if (!mounted) return;
      setState(() {
        _site = site;
        _patient = patient;
        _busy = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        _busy = false;
        _error = 'Support examples could not be loaded from this device.';
      });
    }
  }

  Future<void> _add() async {
    final text = _text.text.trim();
    if (text.isEmpty || text.length > 5000) {
      setState(() => _error = 'Enter a de-identified note (up to 5000 characters).');
      return;
    }
    final note = SupportNote(
      id: const Uuid().v4(),
      text: text,
      label: _label,
      noteDate: _date,
      addedAt: DateTime.now(),
      patientMrn: _scope == 'patient' ? widget.localRecordId : null,
      addedByClinician: widget.clinicianId,
    );
    try {
      if (_scope == 'site') {
        await RecordStore.saveSiteSupport([..._site, note]);
      } else {
        await RecordStore.saveSupport(widget.localRecordId, [..._patient, note]);
      }
      _text.clear();
      await _load();
    } catch (_) {
      if (mounted) setState(() =>
          _error = 'The example was not saved. Please retry.');
    }
  }

  Future<void> _remove(SupportNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove support example?'),
        content: const Text(
          'Removal affects future TC-WPN analyses only. '
          'It cannot change previously stored scores or fusion results.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (note.patientMrn == null) {
        await RecordStore.saveSiteSupport(
            _site.where((n) => n.id != note.id).toList());
      } else {
        await RecordStore.saveSupport(widget.localRecordId,
            _patient.where((n) => n.id != note.id).toList());
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() =>
          _error = 'Could not remove this support example.');
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TC-WPN support examples')),
    body: _busy
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Research support set — visible and editable. Site examples '
                'apply to future analyses of all patients; patient examples '
                'apply only to this record. Labels must reflect reviewed '
                'evidence, not a desired model score. Examples are sent to '
                'the Central Backend during note analysis and may affect TC-WPN. '
                'The authoritative fusion result is never changed locally.',
              ),
            )),
            const SizedBox(height: 12),
            Text('Add a reviewed, de-identified example',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              key: const Key('support-example-text'),
              maxLines: 4,
              maxLength: 5000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Clinical support note',
              ),
            ),
            Wrap(spacing: 12, runSpacing: 8, children: [
              DropdownButton<String>(
                value: _scope,
                items: const [
                  DropdownMenuItem(value: 'patient',
                      child: Text('Patient only')),
                  DropdownMenuItem(value: 'site',
                      child: Text('Site-wide')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _scope = value);
                },
              ),
              DropdownButton<String>(
                value: _label,
                items: const [
                  DropdownMenuItem(value: 'control',
                      child: Text('Control example')),
                  DropdownMenuItem(value: 'anxiety',
                      child: Text('Anxiety example')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _label = value);
                },
              ),
            ]),
            TextButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (date != null && mounted) setState(() => _date = date);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Note date: ${DateFormat('d MMM yyyy').format(_date)}'),
            ),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add support example'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            Text('Effective support set (${_site.length + _patient.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Site-wide and patient-only examples are combined '
              'when a note is next submitted. An empty set may cause '
              'TC-WPN to use its backend default support behavior.'),
            ...[..._site, ..._patient].map((note) => Card(
              child: ListTile(
                title: Text(note.text, maxLines: 5,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${note.patientMrn == null ? 'Site' : 'Patient'} · '
                  '${note.label} · '
                  '${DateFormat('d MMM yyyy').format(note.noteDate)} · '
                  'By ${note.addedByClinician.isEmpty ? 'unknown' : note.addedByClinician}',
                ),
                trailing: IconButton(
                  tooltip: 'Remove support example',
                  onPressed: () => _remove(note),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            )),
            if (_site.isEmpty && _patient.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No curated support examples saved on this device.'),
              ),
          ],
        ),
  );
}
