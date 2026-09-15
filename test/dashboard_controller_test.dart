import 'package:flutter_test/flutter_test.dart';

import 'package:r26_ds012_app/domain/contracts/dashboard_snapshot.dart';
import 'package:r26_ds012_app/domain/repositories/dashboard_repository.dart';
import 'package:r26_ds012_app/state/async_data_state.dart';
import 'package:r26_ds012_app/state/dashboard_controller.dart';

class _Repository implements DashboardRepository {
  DashboardSnapshot? value;
  Object? failure;

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    if (failure != null) throw failure!;
    return value!;
  }
}

void main() {
  test('empty server snapshot becomes explicit empty state', () async {
    final repo = _Repository()
      ..value = DashboardSnapshot(
        openEvents: const [],
        assignedPatients: const [],
        fetchedAt: DateTime.utc(2026, 9, 16),
      );
    final controller = DashboardController(repository: repo);

    await controller.load();

    expect(controller.state.status, AsyncDataStatus.empty);
  });

  test('offline refresh preserves cached provenance', () async {
    final repo = _Repository()
      ..value = DashboardSnapshot(
        openEvents: const [],
        assignedPatients: const [],
        fetchedAt: DateTime.utc(2026, 9, 16),
      );
    final controller = DashboardController(repository: repo);
    await controller.load();

    repo.failure = const DashboardOfflineException();
    await controller.load(showLoading: false);

    expect(controller.state.status, AsyncDataStatus.offline);
    expect(controller.state.data, isNotNull);
    expect(controller.state.data!.isFromCache, isTrue);
  });

  test('unavailable source without prior snapshot stays unavailable', () async {
    final repo = _Repository()
      ..failure = const DashboardUnavailableException();
    final controller = DashboardController(repository: repo);

    await controller.load();

    expect(controller.state.status, AsyncDataStatus.unavailable);
    expect(controller.state.data, isNull);
  });
}
