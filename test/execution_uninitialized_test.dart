import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('querying before initialization throws for every scope', () {
    for (final scope in ExecutionScope.values) {
      expect(
          () => Execution.instance
              .hasExecuted(key: 'uninitialized', scope: scope),
          throwsStateError);
    }
  });
}
