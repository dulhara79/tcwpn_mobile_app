import 'assessment_summary.dart';
import 'contract_enums.dart';
import 'contract_parsing.dart';

class PatientSummary {
  final String subjectId;
  final String? displayId;
  final String? patientName;
  final int? fusionResultId;
  final CurrentAssessment? currentAssessment;
  final ForecastResult? forecast;
  final AssessmentStatus assessmentStatus;
  final DateTime? lastUpdated;
  final int? openEventCount;

  const PatientSummary({
    required this.subjectId,
    required this.displayId,
    this.patientName,
    required this.fusionResultId,
    required this.currentAssessment,
    required this.forecast,
    required this.assessmentStatus,
    required this.lastUpdated,
    required this.openEventCount,
  });

  factory PatientSummary.fromJson(Map<String, dynamic> json) {
    final current = contractMap(json['current'] ?? json['current_assessment']);
    final forecast = contractMap(json['forecast']);
    return PatientSummary(
      subjectId: contractString(json['subject_id']) ?? '',
      displayId: contractString(json['display_id']),
      patientName: contractString(json['patient_name']),
      fusionResultId: contractInt(json['fusion_result_id']),
      currentAssessment:
          current == null ? null : CurrentAssessment.fromJson(current),
      forecast: forecast == null ? null : ForecastResult.fromJson(forecast),
      assessmentStatus: AssessmentStatus.fromWire(json['assessment_status']),
      lastUpdated: contractDateTime(json['last_updated']),
      openEventCount: contractInt(json['open_event_count']),
    );
  }

  /// The patient may revoke this optional name at any time. Fall back to the
  /// backend pseudonym, never to a guessed identity.
  String get clinicianLabel =>
      patientName?.trim().isNotEmpty == true
          ? patientName!.trim()
          : (displayId?.trim().isNotEmpty == true ? displayId! : subjectId);

  Map<String, dynamic> toJson() => {
        'subject_id': subjectId,
        'display_id': displayId,
        'patient_name': patientName,
        'fusion_result_id': fusionResultId,
        'current_assessment': currentAssessment == null
            ? null
            : {
                'score': currentAssessment!.score,
                'tier': currentAssessment!.tier.name,
                'band': currentAssessment!.band,
              },
        'forecast': forecast == null
            ? null
            : {
                'forecast_result_id': forecast!.forecastResultId,
                'scope': forecast!.scope.name,
                'horizon_minutes': forecast!.horizonMinutes,
                'score': forecast!.score,
                'tier': forecast!.tier.name,
                'escalation_probability': forecast!.escalationProbability,
                'escalation_predicted': forecast!.escalationPredicted,
                'generated_at': forecast!.generatedAt?.toUtc().toIso8601String(),
                'valid_until': forecast!.validUntil?.toUtc().toIso8601String(),
              },
        'assessment_status': assessmentStatus.name,
        'last_updated': lastUpdated?.toUtc().toIso8601String(),
        'open_event_count': openEventCount,
      };
}
