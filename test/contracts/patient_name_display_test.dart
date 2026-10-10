import 'package:flutter_test/flutter_test.dart';
import 'package:r26_ds012_app/domain/contracts/patient_summary.dart';

Map<String, dynamic> row({String? patientName, String? displayId = 'Patient AB12CD34'}) => {
  'subject_id': 'subject-test',
  'display_id': displayId,
  'patient_name': patientName,
  'assessment_status': 'unavailable',
};

void main() {
  test('assigned-clinician shared name takes priority in roster and details', () {
    final patient = PatientSummary.fromJson(row(patientName: '  Example Name  '));
    expect(patient.clinicianLabel, 'Example Name');
    expect(patient.subjectId, 'subject-test');
    expect(patient.toJson()['patient_name'], '  Example Name  ');
  });

  test('unset or revoked patient name preserves server pseudonym', () {
    expect(PatientSummary.fromJson(row()).clinicianLabel, 'Patient AB12CD34');
    expect(PatientSummary.fromJson(row(patientName: '')).clinicianLabel, 'Patient AB12CD34');
  });

  test('missing labels fall back to canonical opaque ID', () {
    expect(PatientSummary.fromJson(row(displayId: null)).clinicianLabel, 'subject-test');
  });
}
