import '../../core/config/env.dart';
import '../../domain/contracts/timeline_entry.dart';
import '../../domain/repositories/timeline_repository.dart';
import '../api/api_client.dart';

class CentralBackendTimelineRepository implements TimelineRepository {
  final ApiClient _api;

  CentralBackendTimelineRepository([ApiClient? api])
      : _api = api ??
            ApiClient(
              Env.backendBase,
              bearer: () => Env.backendToken,
            );

  @override
  Future<List<TimelineEntry>> history(
    String subjectId, {
    int limit = 200,
  }) async {
    try {
      final json = await _api.get(
        '/v1/doctor/patients/${Uri.encodeComponent(subjectId)}/timeline?limit=$limit',
        timeout: Env.quickTimeout,
      );
      final raw = json['trend'];
      if (raw is! List) return const <TimelineEntry>[];
      return raw
          .whereType<Map>()
          .map((value) => TimelineEntry.fromJson(
                Map<String, dynamic>.from(value),
              ))
          .toList(growable: false);
    } on ApiException catch (error) {
      if (error.kind == ApiFailure.notFound) {
        return const <TimelineEntry>[];
      }
      rethrow;
    }
  }
}
