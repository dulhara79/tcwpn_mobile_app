import 'package:flutter/foundation.dart';

import '../domain/contracts/dashboard_snapshot.dart';
import '../domain/repositories/dashboard_repository.dart';
import 'async_data_state.dart';

class DashboardController extends ChangeNotifier {
  final DashboardRepository repository;

  DashboardController({required this.repository});

  AsyncDataState<DashboardSnapshot> _state =
      const AsyncDataState<DashboardSnapshot>.loading();
  DashboardSnapshot? _lastSuccessful;

  AsyncDataState<DashboardSnapshot> get state => _state;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading || _lastSuccessful == null) {
      _state = const AsyncDataState<DashboardSnapshot>.loading();
      notifyListeners();
    }

    try {
      final snapshot = await repository.loadDashboard();
      _lastSuccessful = snapshot;
      _state = snapshot.isEmpty
          ? const AsyncDataState<DashboardSnapshot>.empty()
          : AsyncDataState<DashboardSnapshot>.data(snapshot);
    } on DashboardOfflineException catch (e) {
      final cached = _lastSuccessful?.asCached();
      _state = AsyncDataState<DashboardSnapshot>.offline(
        cached: cached,
        message: cached == null
            ? e.message
            : 'Offline. Showing the last server-provided dashboard snapshot.',
      );
    } on DashboardUnavailableException catch (e) {
      final cached = _lastSuccessful?.asCached();
      _state = cached == null
          ? AsyncDataState<DashboardSnapshot>.unavailable(message: e.message)
          : AsyncDataState<DashboardSnapshot>.partial(
              cached,
              message:
                  'Assessment service unavailable. Showing the last server-provided dashboard snapshot.',
            );
    } catch (_) {
      _state = const AsyncDataState<DashboardSnapshot>.error(
        message: 'The clinician dashboard could not be loaded.',
      );
    }

    notifyListeners();
  }
}

class DashboardOfflineException implements Exception {
  final String message;
  const DashboardOfflineException([
    this.message = 'Dashboard data is unavailable while offline.',
  ]);
}

class DashboardUnavailableException implements Exception {
  final String message;
  const DashboardUnavailableException([
    this.message = 'Assessment service unavailable.',
  ]);
}
