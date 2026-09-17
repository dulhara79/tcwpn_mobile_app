class PushAttentionMessage {
  const PushAttentionMessage({required this.type, required this.eventId});

  static const String attentionEventType = 'attention_event';

  static const Set<String> _forbiddenKeys = <String>{
    'patient_name',
    'patientname',
    'mrn',
    'patient_mrn',
    'patientmrn',
    'note_text',
    'current_score',
    'forecast_score',
    'fusion_score',
    'composite_score',
    'model_output',
  };

  final String type;
  final String eventId;

  static PushAttentionMessage? tryParse(Map<String, dynamic> data) {
    final normalizedKeys = data.keys.map((key) => key.toLowerCase()).toSet();
    if (normalizedKeys.any(_forbiddenKeys.contains)) return null;

    final type = data['type']?.toString().trim() ?? '';
    final eventId = data['event_id']?.toString().trim() ?? '';
    if (type != attentionEventType || eventId.isEmpty) return null;
    return PushAttentionMessage(type: type, eventId: eventId);
  }
}
