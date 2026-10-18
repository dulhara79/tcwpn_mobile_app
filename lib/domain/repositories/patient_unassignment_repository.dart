abstract interface class PatientUnassignmentRepository {
  /// Ends only the authenticated clinician's assignment on the Central Backend.
  /// This must never delete the subject, assessment history or medical records.
  Future<void> unassign(String subjectId);
}
