// Run with: flutter test benchmark/startup_queue_test.dart --reporter expanded
// This measures event-loop latency, not Flutter frame rendering.
import 'dart:async';

import 'package:flutter_execution/flutter_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compare simulated startup actions with and without the queue',
      () async {
    const count = 50;
    Future<void> action() async {
      var value = 0;
      for (var i = 0; i < 20000; i++) {
        value = (value + i) % 1000003;
      }
      if (value == -1) throw StateError('unreachable');
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    Future<List<int>> measure(bool queued) async {
      // This benchmark runs under flutter_test, outside the test/ directory.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await Execution.instance.initialize();
      final stopwatch = Stopwatch()..start();
      final futures = <Future<void>>[];
      for (var i = 0; i < count; i++) {
        futures.add(queued
            ? Execution.instance
                .doOnceOnSession(key: 'job-$i', function: action)
            : action());
      }
      await Future<void>.delayed(Duration.zero);
      final eventLatency = stopwatch.elapsedMicroseconds;
      await Future.wait(futures);
      final total = stopwatch.elapsedMicroseconds;
      await Execution.instance.dispose();
      return [eventLatency, total];
    }

    final baseline = await measure(false);
    late List<int> queued;
    await runZoned(() async {
      queued = await measure(true);
    }, zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}));
    print(
        'count=$count; baseline event/total us=$baseline; queue event/total us=$queued');
  });
}
