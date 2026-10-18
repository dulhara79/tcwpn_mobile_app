import '../../core/config/env.dart';
import '../../domain/repositories/patient_unassignment_repository.dart';
import '../api/api_client.dart';

class CentralBackendPatientUnassignmentRepository
    implements PatientUnassignmentRepository {
  final ApiClient _api;
  CentralBackendPatientUnassignmentRepository([ApiClient? api])
      : _api = api ?? ApiClient(Env.backendBase);

  @override
  Future<void> unassign(String subjectId) async {
    final id = subjectId.trim();
    if (id.isEmpty) {
      throw const ApiException(
        kind: ApiFailure.validation,
        endpoint: 'subject-id',
        detail: 'subject_id is required',
      );
    }
    final path = '/v1/clinicians/me/assignments/${Uri.encodeComponent(id)}';
    final response = await _api.delete(path, timeout: Env.quickTimeout);
    if (response['subject_id'] != id ||
        response['active'] != false) {
      throw ApiException(
        kind: ApiFailure.malformed,
        endpoint: path,
        detail: 'Backend did not confirm the assignment was ended.',
      );
    }
  }
}
